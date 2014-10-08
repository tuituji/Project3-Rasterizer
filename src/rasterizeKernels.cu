// CIS565 CUDA Rasterizer: A simple rasterization pipeline for Patrick Cozzi's CIS565: GPU Computing at the University of Pennsylvania
// Written by Yining Karl Li, Copyright (c) 2012 University of Pennsylvania

#include <stdio.h>
#include <cuda.h>
#include <cmath>
#include <cutil_math.h>
#include <thrust/random.h>
#include "rasterizeKernels.h"
#include "rasterizeTools.h"
#include "cuPrintf.cu"

glm::vec3* framebuffer;
fragment* depthbuffer;
float* device_vbo;
float* device_cbo;
int* device_ibo;
triangle* primitives;



__device__ void printPoint(glm::vec4 p)
{
	cuPrintf("(%f, %f, %f, %f)\n", p.x, p.y, p.z, p.w);
}
__device__ void printPoint(glm::vec3 p)
{
	cuPrintf("(%f, %f, %f)\n", p.x, p.y, p.z);
}

__device__ void printTri(triangle tri)
{
	cuPrintf("0: (%f %f %f, %d %d %d)\n", tri.p0.x, tri.p0.y, tri.p0.z, tri.c0.x, tri.c0.y,tri.c0.z);
	cuPrintf("1: (%f %f %f, %d %d %d)\n", tri.p1.x, tri.p1.y, tri.p1.z, tri.c1.x, tri.c1.y,tri.c1.z);
	cuPrintf("2: (%f %f %f, %d %d %d)\n", tri.p2.x, tri.p2.y, tri.p2.z, tri.c2.x, tri.c2.y,tri.c2.z);
}

void checkCUDAError(const char *msg) {
  cudaError_t err = cudaGetLastError();
  if( cudaSuccess != err) {
    fprintf(stderr, "Cuda error: %s: %s.\n", msg, cudaGetErrorString( err) ); 
    exit(EXIT_FAILURE); 
  }
} 

//Handy dandy little hashing function that provides seeds for random number generation
__host__ __device__ unsigned int hash(unsigned int a){
    a = (a+0x7ed55d16) + (a<<12);
    a = (a^0xc761c23c) ^ (a>>19);
    a = (a+0x165667b1) + (a<<5);
    a = (a+0xd3a2646c) ^ (a<<9);
    a = (a+0xfd7046c5) + (a<<3);
    a = (a^0xb55a4f09) ^ (a>>16);
    return a;
}

//Writes a given fragment to a fragment buffer at a given location
__host__ __device__ void writeToDepthbuffer(int x, int y, fragment frag, fragment* depthbuffer, glm::vec2 resolution){
  if(x<resolution.x && y<resolution.y){
    int index = (y*resolution.x) + x;
    depthbuffer[index] = frag;
  }
}

//Reads a fragment from a given location in a fragment buffer
__host__ __device__ fragment getFromDepthbuffer(int x, int y, fragment* depthbuffer, glm::vec2 resolution){
  if(x<resolution.x && y<resolution.y){
    int index = (y*resolution.x) + x;
    return depthbuffer[index];
  }else{
    fragment f;
    return f;
  }
}

//Writes a given pixel to a pixel buffer at a given location
__host__ __device__ void writeToFramebuffer(int x, int y, glm::vec3 value, glm::vec3* framebuffer, glm::vec2 resolution){
  if(x<resolution.x && y<resolution.y){
    int index = (y*resolution.x) + x;
    framebuffer[index] = value;
  }
}

//Reads a pixel from a pixel buffer at a given location
__host__ __device__ glm::vec3 getFromFramebuffer(int x, int y, glm::vec3* framebuffer, glm::vec2 resolution){
  if(x<resolution.x && y<resolution.y){
    int index = (y*resolution.x) + x;
    return framebuffer[index];
  }else{
    return glm::vec3(0,0,0);
  }
}

//Kernel that clears a given pixel buffer with a given color
__global__ void clearImage(glm::vec2 resolution, glm::vec3* image, glm::vec3 color){
    int x = (blockIdx.x * blockDim.x) + threadIdx.x;
    int y = (blockIdx.y * blockDim.y) + threadIdx.y;
    int index = x + (y * resolution.x);
    if(x<=resolution.x && y<=resolution.y){
      image[index] = color;
    }
}

//Kernel that clears a given fragment buffer with a given fragment
__global__ void clearDepthBuffer(glm::vec2 resolution, fragment* buffer, fragment frag){
    int x = (blockIdx.x * blockDim.x) + threadIdx.x;
    int y = (blockIdx.y * blockDim.y) + threadIdx.y;
    int index = x + (y * resolution.x);
    if(x<=resolution.x && y<=resolution.y){
      fragment f = frag;
      f.position.x = x;
      f.position.y = y;
      buffer[index] = f;
    }
}

//Kernel that writes the image to the OpenGL PBO directly. 
__global__ void sendImageToPBO(uchar4* PBOpos, glm::vec2 resolution, glm::vec3* image){
  
  int x = (blockIdx.x * blockDim.x) + threadIdx.x;
  int y = (blockIdx.y * blockDim.y) + threadIdx.y;
  int index = x + (y * resolution.x);
  
  if(x<=resolution.x && y<=resolution.y){

      glm::vec3 color;      
      color.x = image[index].x*255.0;
      color.y = image[index].y*255.0;
      color.z = image[index].z*255.0;

      if(color.x>255){
        color.x = 255;
      }

      if(color.y>255){
        color.y = 255;
      }

      if(color.z>255){
        color.z = 255;
      }
      
      // Each thread writes one pixel location in the texture (textel)
      PBOpos[index].w = 0;
      PBOpos[index].x = color.x;     
      PBOpos[index].y = color.y;
      PBOpos[index].z = color.z;
  }
}

//TODO: Implement a vertex shader
__global__ void vertexShadeKernel(float* vbo, int vbosize){
  int index = (blockIdx.x * blockDim.x) + threadIdx.x;
  if(index<vbosize/3){
  }
}

//TODO: Implement primative assembly
__global__ void primitiveAssemblyKernel(float* vbo, int vbosize, float* cbo, int cbosize, int* ibo, int ibosize, triangle* primitives){
  int index = (blockIdx.x * blockDim.x) + threadIdx.x;
  int primitivesCount = ibosize/3;
  if(index<primitivesCount){
    int index0 = ibo[index * 3];
    int index1 = ibo[index * 3 + 1];
    int index2 = ibo[index * 3 + 2];

    primitives[index].p0 = glm::vec3(vbo[index0 * 3], vbo[index0 * 3 + 1], vbo[index0 * 3 + 2]);
    primitives[index].p1 = glm::vec3(vbo[index1 * 3], vbo[index1 * 3 + 1], vbo[index1 * 3 + 2]);
    primitives[index].p2 = glm::vec3(vbo[index2 * 3], vbo[index2 * 3 + 1], vbo[index2 * 3 + 2]);

    primitives[index].c0 = glm::vec3(cbo[index0 * 3], cbo[index0 * 3 + 1], cbo[index0 * 3 + 2]);
    primitives[index].c1 = glm::vec3(cbo[index1 * 3], cbo[index1 * 3 + 1], cbo[index1 * 3 + 2]);
    primitives[index].c2 = glm::vec3(cbo[index2 * 3], cbo[index2 * 3 + 1], cbo[index2 * 3 + 2]);
  }
}


//Converts a triangle from clip space to a screen resolution mapped space 
//From (-1:1,-1:1,-1:1) to (0:w, 0:h, 0:1)
__host__ __device__ void transTri2Screen(triangle &tri, glm::vec2 res)
{
	//Scale and shift x
	tri.p0.x = (tri.p0.x + 1.0) * 0.5f * res.x;
	tri.p1.x = (tri.p1.x + 1.0) * 0.5f * res.x;
	tri.p2.x = (tri.p2.x + 1.0) * 0.5f * res.x;

	//Scale and shift y
	tri.p0.y = (-tri.p0.y + 1.0) * 0.5f * res.y;
	tri.p1.y = (-tri.p1.y + 1.0) * 0.5f * res.y;
	tri.p2.y = (-tri.p2.y + 1.0) * 0.5f * res.y;

	//Scale and shift z
	tri.p0.z = (tri.p0.z + 1.0) * 0.5f;
	tri.p1.z = (tri.p1.z + 1.0) * 0.5f;
	tri.p2.z = (tri.p2.z + 1.0) * 0.5f;
}

//TODO: Implement a rasterization method, such as scanline.
__global__ void rasterizationKernel(triangle* primitives, int primitivesCount, fragment* depthbuffer, glm::vec2 resolution){
  int index = (blockIdx.x * blockDim.x) + threadIdx.x;
  if(index<primitivesCount){
    triangle tri = primitives[index];
	transTri2Screen(tri, resolution);
	glm::vec3 minBox, maxBox;
	getAABBForTriangle(tri, minBox, maxBox);
	int minX = glm::max(glm::floor(minBox.x), 0.0f);
    int minY = glm::max(glm::floor(minBox.y), 0.0f);
    int maxX = glm::min(glm::ceil(maxBox.x), resolution.x);
    int maxY = glm::min(glm::ceil(maxBox.y), resolution.y);
	cuPrintf("In raster %d %d %d %d\n", minX, maxX, minY, maxY);
	int x, y;
    for (x = minX; x < maxX; ++x) {
      for (y = minY; y < maxY; ++y) {
	    glm::vec3 bCoord = calculateBarycentricCoordinate(tri, glm::vec2(x, y));
		if (!isBarycentricCoordInBounds(bCoord)) {
		  continue;
		}
			
		fragment frag;// use pointer mainly for the lock
		frag = getFromDepthbuffer(x, y, depthbuffer, resolution);

		glm::vec3 pos = bCoord.x * tri.p0 + bCoord.y * tri.p1 + bCoord.z * tri.p2;
		if ( pos.z < frag.position.z) {
			continue;
		}
		frag.color = bCoord.x * tri.c0 + bCoord.y * tri.c1 + bCoord.z * tri.c2;
		frag.position = pos; //bCoord.x * tri.p0 + bCoord.y * tri.p1 + bCoord.z * tri.p2;
		// now i do not lock it, so the result is not ok
		writeToDepthbuffer(x, y, frag, depthbuffer, resolution);
	  }
	}
  }
}

//TODO: Implement a fragment shader
__global__ void fragmentShadeKernel(fragment* depthbuffer, glm::vec2 resolution){
  int x = (blockIdx.x * blockDim.x) + threadIdx.x;
  int y = (blockIdx.y * blockDim.y) + threadIdx.y;
  int index = x + (y * resolution.x);
  if(x<=resolution.x && y<=resolution.y){
  }
}

//Writes fragment colors to the framebuffer
__global__ void render(glm::vec2 resolution, fragment* depthbuffer, glm::vec3* framebuffer){

  int x = (blockIdx.x * blockDim.x) + threadIdx.x;
  int y = (blockIdx.y * blockDim.y) + threadIdx.y;
  int index = x + (y * resolution.x);

  if(x<=resolution.x && y<=resolution.y){
    framebuffer[index] = depthbuffer[index].color;
  }
}

// Wrapper for the __global__ call that sets up the kernel calls and does a ton of memory management
void cudaRasterizeCore(uchar4* PBOpos, glm::vec2 resolution, float frame, float* vbo, int vbosize, float* cbo, int cbosize, int* ibo, int ibosize){

  // set up crucial magic
  int tileSize = 8;
  dim3 threadsPerBlock(tileSize, tileSize);
  dim3 fullBlocksPerGrid((int)ceil(float(resolution.x)/float(tileSize)), (int)ceil(float(resolution.y)/float(tileSize)));

  //set up framebuffer
  framebuffer = NULL;
  cudaMalloc((void**)&framebuffer, (int)resolution.x*(int)resolution.y*sizeof(glm::vec3));
  
  //set up depthbuffer
  depthbuffer = NULL;
  cudaMalloc((void**)&depthbuffer, (int)resolution.x*(int)resolution.y*sizeof(fragment));

  //kernel launches to black out accumulated/unaccumlated pixel buffers and clear our scattering states
  clearImage<<<fullBlocksPerGrid, threadsPerBlock>>>(resolution, framebuffer, glm::vec3(0,0,0));
  
  fragment frag;
  frag.color = glm::vec3(0,0,0);
  frag.normal = glm::vec3(0,0,0);
  frag.position = glm::vec3(0,0,-10000);
  clearDepthBuffer<<<fullBlocksPerGrid, threadsPerBlock>>>(resolution, depthbuffer,frag);

  //------------------------------
  //memory stuff
  //------------------------------
  primitives = NULL;
  cudaMalloc((void**)&primitives, (ibosize/3)*sizeof(triangle));

  device_ibo = NULL;
  cudaMalloc((void**)&device_ibo, ibosize*sizeof(int));
  cudaMemcpy( device_ibo, ibo, ibosize*sizeof(int), cudaMemcpyHostToDevice);

  device_vbo = NULL;
  cudaMalloc((void**)&device_vbo, vbosize*sizeof(float));
  cudaMemcpy( device_vbo, vbo, vbosize*sizeof(float), cudaMemcpyHostToDevice);

  device_cbo = NULL;
  cudaMalloc((void**)&device_cbo, cbosize*sizeof(float));
  cudaMemcpy( device_cbo, cbo, cbosize*sizeof(float), cudaMemcpyHostToDevice);

  tileSize = 32;
  int primitiveBlocks = ceil(((float)vbosize/3)/((float)tileSize));

  //------------------------------
  //vertex shader
  //------------------------------
  vertexShadeKernel<<<primitiveBlocks, tileSize>>>(device_vbo, vbosize);

  cudaDeviceSynchronize();
  //------------------------------
  //primitive assembly
  //------------------------------
  primitiveBlocks = ceil(((float)ibosize/3)/((float)tileSize));
  primitiveAssemblyKernel<<<primitiveBlocks, tileSize>>>(device_vbo, vbosize, device_cbo, cbosize, device_ibo, ibosize, primitives);

  cudaDeviceSynchronize();
  //------------------------------
  //rasterization
  //------------------------------
  rasterizationKernel<<<primitiveBlocks, tileSize>>>(primitives, ibosize/3, depthbuffer, resolution);

  cudaDeviceSynchronize();
  //------------------------------
  //fragment shader
  //------------------------------
  fragmentShadeKernel<<<fullBlocksPerGrid, threadsPerBlock>>>(depthbuffer, resolution);

  cudaDeviceSynchronize();
  //------------------------------
  //write fragments to framebuffer
  //------------------------------
  render<<<fullBlocksPerGrid, threadsPerBlock>>>(resolution, depthbuffer, framebuffer);
  sendImageToPBO<<<fullBlocksPerGrid, threadsPerBlock>>>(PBOpos, resolution, framebuffer);

  cudaDeviceSynchronize();

  kernelCleanup();

  checkCUDAError("Kernel failed!");
}

void kernelCleanup(){
  cudaFree( primitives );
  cudaFree( device_vbo );
  cudaFree( device_cbo );
  cudaFree( device_ibo );
  cudaFree( framebuffer );
  cudaFree( depthbuffer );
}

