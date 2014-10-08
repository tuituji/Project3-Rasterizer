编译环境搭建

当前环境为windows + cuda 4.2。
1. Visual Studio 2010中打开sln文件，右键 项目-》 生成自定义...-》勾选cuda 4.2
2. 项目-》xxx属性-》C/C++-》常规-》附加包含目录
	$(NVSDKCOMPUTE_ROOT)/C/common/inc
	$(CUDA_INC_PATH)
   项目-》xxx属性-》CUDA C/C++-》常规-》附加包含目录
	$(NVSDKCOMPUTE_ROOT)/C/common/inc
	$(CUDA_INC_PATH)
3. 将Project0中的glew32.dll拷贝到Debug目录下面（生成exe文件的目录）
4. 将shaders目录拷贝到Debug目录下面。
5. 添加了几个简单的场景文件

添加cuPrintf
参见cuda SDK simplePrintf