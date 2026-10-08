# cudalab

CUDA 实验项目。以 demo 为单位组织：**一个 demo 一个目录，每个 demo 编译成一个独立的可执行 target**，统一用 CMake 构建。

## 目录结构

```
cudalab/
├─ CMakeLists.txt            自动发现 src/demos/*，每个目录生成同名可执行 target
├─ CMakePresets.json         ninja-debug / ninja-release 构建预设
├─ env.json                  本机路径配置（用法见 docs/setup.md）
├─ docs/setup.md             开发环境搭建、IntelliSense、调试与排错
├─ src/common/               跨 demo 共享代码 → 静态库 cudalab_common
├─ src/demos/<demo>/         一个目录 = 一个可执行 target
├─ scripts/                  构建 / 运行 / 性能分析脚本
└─ .vscode/                  构建任务与调试配置
```

## 构建与运行

需要 CMake 3.24+、Ninja、CUDA Toolkit 和 MSVC（Windows 上 nvcc 需要 `cl.exe` 作主机编译器）。

```powershell
cmake --preset ninja-debug
cmake --build --preset ninja-debug
```

`scripts/` 下的脚本封装了同样的流程，并负责准备好编译环境：

```powershell
.\scripts\build-cmake.ps1                          # 配置 + 构建全部 demo
.\scripts\build-cmake.ps1 -Preset ninja-release    # Release
.\scripts\build-cmake.ps1 -Demo demo_add_one -Run  # 只构建并运行一个 demo
.\scripts\run-demos.ps1                            # 运行已构建的 demo，汇总结果
```

产物位于 `build/<preset>/<demo>.exe`。

## 新增 demo

1. 建目录 `src/demos/demo_xxx/`；
2. 放入 `.cu` / `.cpp` 源文件，头文件放同一目录即可直接 `#include "xxx.h"`；
3. 重新构建 —— 会自动出现 target `demo_xxx`，**不需要修改 CMakeLists.txt**。

只构建其中几个：

```powershell
cmake --preset ninja-debug -DCUDALAB_DEMOS="demo_add_one;demo_xxx"
```

## 约定

| 规则 | 说明 |
| --- | --- |
| 一个目录一个 target | `src/demos/<name>/` → 可执行 target `<name>`（target 名 = 目录名） |
| 源文件 | 该目录下的 `*.cu` / `*.cpp` / `*.cxx` / `*.cc`；目录本身加入 include 路径 |
| CUDA 链接 | 目录里出现 `.cu` 才链接 `CUDA::cudart`，纯 C++ demo 不引入 CUDA 运行时 |
| 共享代码 | `src/common/` → 静态库 `cudalab_common`，所有 demo 都链接它 |
| 空目录 | 没有源文件的 demo 目录会被跳过并提示，不影响其他 demo 构建 |

## 共享库 API

```cpp
// src/common/random.h  ——  namespace cudalab::common
int *randomInt(size_t n);                              // 全 int 范围
int *randomInt(size_t n, int minValue, int maxValue);  // [minValue, maxValue] 闭区间
void seedRandom(unsigned int seed);                    // 重置种子，便于复现
```

返回 `new int[n]`，调用方用 `delete[]` 释放；`n == 0` 返回可安全 delete 的非空指针；
`minValue > maxValue` 抛 `std::invalid_argument`。

## 开发环境

构建环境准备、`env.json`、clangd IntelliSense、kernel 调试与性能分析的说明见
[docs/setup.md](docs/setup.md)。
