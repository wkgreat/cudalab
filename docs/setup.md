# 开发环境说明

本文档记录**机器相关**的环境细节、配置原理和踩过的坑。README 只做项目通用说明，
凡是与具体机器、具体版本、具体路径有关的内容都放在这里。

## 0. 工具链：pixi

`pixi.toml` 锁定 cmake / ninja / clangd / **python** / **CUDA** 的版本，两个平台都装
CUDA（Windows 上不再用系统安装的那份），Linux 上还有 gcc：

```bash
pixi install
pixi run build     # 配置 + 编译全部 demo
pixi run test      # ctest --preset ninja-release
pixi run env       # 重新生成 clangd 数据库
```

pixi 取代了旧文档里“手工装 CMake / Ninja / clangd / CUDA”的步骤。Windows 上
`pixi.toml` 用 `vs2026_win-64` 激活主机编译器（`cl.exe` + `INCLUDE`/`LIB` 直接进
pixi 环境），脚本不再自己调 `vcvars64.bat`（见 §1）。Catch2、fmt、OpenCL 也由
pixi 直接提供，不再需要 vcpkg（§12）。

## 1. 本机实测环境

| 组件 | 版本 / 路径 |
| --- | --- |
| GPU | NVIDIA GeForce RTX 5060 Ti，计算能力 **sm_120**（12.0），16 GB |
| 驱动 | 617.42 |
| CUDA Toolkit | 由 **pixi** 提供（`cuda-toolkit >=13.3,<14`，本机解析到 **13.4.1**）；系统安装的 13.2 不再使用 |
| 主机编译器 | MSVC **14.51.36231**（Visual Studio Community **2026** / VS 18，由 pixi 的 `vs2026_win-64` 激活到环境中） |
| CMake | 由 **pixi** 提供（`pixi.toml` 锁定版本），生成器 **Ninja** |
| clangd | 由 **pixi** 提供（`clang-tools`） |
| Windows SDK | 10.0.26100.0 |
| Shell / 脚本运行时 | 构建与辅助脚本统一用 **pixi 的 Python**（`scripts/*.py`），不再依赖 PowerShell |

这些值都不写死在配置里：工具链的**版本**由 `pixi.toml` 锁定，其余**全部运行时探测**
（见 §2），仓库里没有任何机器配置文件。

## 2. 没有机器配置文件

以前仓库根目录有个 `env.json` 承载本机的 CUDA / MSVC / Windows SDK 路径，**已删除**。
现在两样都能在运行时探测出来，另一部分由 pixi 提供：

| 值 | 来源 |
| --- | --- |
| cmake / ninja / clangd / python / CUDA（两平台） | `pixi.toml` 锁定，`pixi install` 装好 |
| GPU 架构 | CMake 的 `native` 自动探测 |
| MSVC 工具链（`cl.exe`、`INCLUDE`、`LIB`） | pixi 的 `vs2026_win-64` 激活脚本写进环境，构建脚本直接用 PATH 上的 `cl.exe` |
| Windows SDK UCRT 目录 | 注册表 `Microsoft SDKs\Windows\v10.0\InstallationFolder` 下最新版本 |
| CUDA 版本校验 | `scripts/common.py` 从 `pixi.toml` 的 `cuda-toolkit` 约束读最低版本，实际 nvcc 低于它直接报错 |

`scripts/sync_env.py` 现在只做一件事：**重新渲染 clangd 的 `compile_commands.json`**。
`compile_commands.json` 是生成物，已被 git 忽略。

### 为什么不把机器路径写进配置文件

- **`.clangd` 引用不了变量。** 它是 YAML，没有任何变量替换或 include 机制。
- **VS Code 只能算半个。** `${env:VAR}` 取的是 **VS Code 进程启动瞬间**的环境变量，
  意味着新机器必须先设系统环境变量再启动 VS Code，改一次还要重启一次，不可靠。

所以走的是**渲染**路线：**机器路径只进"生成物"，不进"配置文件"**。

- `.clangd` **已删除** —— 它原本要写 CUDA 路径、SDK 版本、GPU 架构，现在这些由
  `scripts/common.py` 从探测到的工具链和 `nvidia-smi` 渲染进 `compile_commands.json`；
- `.vscode/c_cpp_properties.json` **已删除**（原本写死 cl.exe 和 CUDA include，
  而且 cpptools 的 IntelliSense 本来就关着）；
- `.vscode/settings.json` 里的 `cmake.cmakePath`、`C_Cpp.default.compilerPath`、
  `C_Cpp.default.includePath` **已删除** —— 构建任务调用脚本，脚本自己找 CMake；
- `CMakePresets.json` 里的 `CMAKE_CUDA_ARCHITECTURES` **已改为 CMake 的 `native`
  自动探测**（命令行 `-DCMAKE_CUDA_ARCHITECTURES=...` 仍可覆盖）。

净结果：仓库里没有任何机器路径或机器配置文件，`.clangd` 不存在。

## 3. 换一台机器

**什么都不用改。**

```bash
pixi install       # 装 cmake / ninja / clangd / CUDA
pixi run build     # 配置 + 编译
```

MSVC、Windows SDK、GPU 架构都在构建时现探测，没有文件要刷新。只改了探测相关的东西
（或没重新构建但想更新 IntelliSense）时：

```bash
python scripts/sync_env.py         # 只重新生成 clangd 数据库（需在 pixi 环境里）
```

Catch2 / fmt / OpenCL 同样来自 pixi，`pixi install` 之后就能直接构建（§12）。

## 4. 构建脚本与执行顺序

`scripts/build_cmake.py` 的顺序固定为 **配置 → 生成 clangd 编译库 → 编译**。
中间那步往前放是有意的：代码编译不过的时候，恰恰最需要 IntelliSense。

脚本本身是 Python，由 `pixi.toml` 里的 `python` 提供运行时，`pixi run ...` 直接可用。

脚本不再调用 `vcvars64.bat`：pixi 的 `vs2026_win-64` 激活时已经把 `cl.exe`、`INCLUDE`、
`LIB` 放进环境，Ninja 和 nvcc 直接就能用。所以脚本必须在 pixi 环境里跑（`pixi run ...`
或 `pixi shell`），不在 pixi 里会明确报错说找不到 `cl.exe` / `cmake`。

CMake 只从 **PATH** 找，也就是 `pixi.toml` 锁定的那个，不再回退到 VS 自带的副本。

如果提示“未对文件进行数字签名”，在命令前加 `-ExecutionPolicy Bypass`
（VS Code 里的任务已经带了该参数）。

## 5. clangd IntelliSense

**clangd 是 IntelliSense 引擎**，C/C++ 扩展的 IntelliSense 已在工作区里关掉
（`C_Cpp.intelliSenseEngine: disabled`），否则两套诊断会在同一个文件上互相打架；
C/C++ 扩展保留是为了它提供的 `cppvsdbg` 调试器（`launch.json` 在用）。

### 为什么不直接用 CMake 的 compile_commands.json

CMake 导出的那份里，`.cu` 条目是 **nvcc** 命令行、`.cpp` 条目是 **cl.exe** 命令行，
clangd 都用不了；更麻烦的是**头文件不参与编译**，数据库里根本没有它的条目，
clangd 只能拿邻近源文件的命令顶替。这些坑原先靠一个 `.clangd` 文件打补丁，
现在改成**渲染**：

```
CMake 的 compile_commands.json（build/<preset>/，权威）
        + PATH 上的 nvcc（CUDA 路径）+ 探测到的 Windows SDK 路径 + nvidia-smi（架构）
                ↓  scripts/common.py / write_clang_database
仓库根的 compile_commands.json（clang 方言，源码 + 头文件全覆盖）
```

clangd 会自动在源文件的上级目录找到根目录那份，**不需要任何配置文件**。
每条命令都是干净的 clang 方言：统一 `clang++` 驱动，`.cu` 与头文件用
`-x cuda --cuda-path=<env> --cuda-gpu-arch=sm_<env>`，`.cpp` 用 `-x c++`，
并补上 clangd 自己探测不到的 Windows SDK UCRT 目录。

这么做顺带解决了三个此前反复踩的问题：

1. **头文件没有条目** —— 现在每个头文件都有一条显式记录，按同名源文件建模
   （找不到就按同目录，再找不到就任取一个），不再依赖 clangd 的猜测；
2. **驱动模式冲突** —— 不再“覆盖驱动”。原先给 `.cu` 加 `Compiler: clang++` 看着自然，
   但头文件继承到的命令可能是 cl.exe 风格，一换驱动 `/Zi /FS /TP -MDd` 全变非法参数；
3. **`Remove` 删不干净** —— 原先列了 22 条要删的开关，实测只有一部分生效，
   `-MDd`、`/Zi`、`/FS` 仍留在命令行里报 `unknown argument`。现在命令是重新生成的，
   根本不依赖删除。

### 验证

```bash
clangd --check=src/demos/demo_add_one/add_one.cu
```

`clangd` 由 pixi 提供（`pixi.toml` 里的 `clang-tools`），所以先 `pixi shell` 或
`pixi run` 一下，PATH 上就是它。期望输出 `All checks completed, 0 errors`。

编译库由构建脚本自动刷新；改了探测相关的东西又不想重新构建时，跑
`pixi run env`（即 `scripts/sync_env.py`）或 VS Code 里的 **env: refresh clangd database** 任务。

改了 `.vscode/settings.json` 里的 clangd 开关后需要
`Ctrl+Shift+P` → **Developer: Reload Window**。

## 6. 为什么还离不开 MSVC

Windows 上 **nvcc 必须有一个主机编译器，只能用 `cl.exe`**，没有替代品。
这份编译器由 pixi 的 `vs2026_win-64` 包激活：激活时把 `cl.exe` 放进 PATH、
`INCLUDE`/`LIB` 指向 MSVC 与 Windows SDK，构建脚本直接用，不需要 `vcvars64.bat`。
（这个包本身链接的是机器上已装的 VS 2026，所以机器仍需装一次 VS 的 C++ 工作负载；
它解决的是“不用手工配环境变量”，不是“不用装 VS”。）
这不影响“只用 CMake 构建”：构建系统是 CMake、生成器是 Ninja，
`cl.exe` 只是 CUDA 工具链的主机编译器；项目里没有 Visual Studio 生成器
（MSBuild / `.slnx`），也没有直接调 nvcc 的构建路径。

## 7. 调试

Windows 上**不能单步调试 kernel**：CUDA-GDB 只有 Linux 版，
`nvidia.nsight-vscode-edition` 扩展只提供 `cuda-gdb` / `cuda-gdbserver`，都依赖 cuda-gdb。

`launch.json` 用 `cppvsdbg` 调**主机代码**：可以在 `main()`、CUDA 运行时调用、
以及启动函数里下断点看启动配置，但进不了 kernel。替代手段：

1. kernel 内直接 `printf`（sm_120 支持）；
2. WSL2 + cuda-gdb，`launch.json` 底部留了注释示例；
3. 项目不生成 Visual Studio 解决方案；要用 Nsight Visual Studio Edition 调 kernel，
   需要自己加一个 Visual Studio 生成器预设。

## 8. 性能分析

```bash
python scripts/profile.py                              # Nsight Compute，默认第一个 demo
python scripts/profile.py --demo demo_add_one --set full
python scripts/profile.py --tool systems               # Nsight Systems 时间线
```

脚本会先找 PATH 上的 `ncu` / `nsys`，再自动扫
`C:\Program Files\NVIDIA Corporation\Nsight ...`（Windows）或 `/opt/nvidia`（Linux）
（这一步是动态扫描，所以不写进任何配置）。

实测注意事项：

- **Nsight Compute 需要权限**：会报 `ERR_NVGPUCTRPERM`。用管理员终端运行，或在
  NVIDIA 控制面板 → 桌面/开发者 → 管理 GPU 性能计数器里允许所有用户访问。
- **Nsight Systems 未采到 CUDA 数据**：报告能生成，但 `nsys stats` 报
  `does not contain CUDA kernel data`，`nsys` 退出码 `-529697949`（0xE06D7363）。
  怀疑是搭建时所用受限 shell 阻止了注入 DLL，**建议在普通终端里再试一次**确认。

## 9. 常见问题

- **clangd 报一堆 `crtdbg.h` / `std::printf` 找不到**：`compile_commands.json` 过期了，
  跑一次 `pixi run build` 或 `pixi run env`。
- **clangd 在 `.cu` 里报 `blockIdx` 未声明**：同上，编译库里该文件没走 CUDA 分支，
  检查 pixi 环境里的 nvcc（`pixi run` 后 `where nvcc`），以及 `nvidia-smi` 能不能报出架构。
- **改了 `CMAKE_CUDA_ARCHITECTURES` 但构建没反应**：它是 cache 变量，改架构要用
  `pixi run clean` 重建（或删掉 `build/<preset>`）。默认的 `native`
  不需要手工改。
- **VS Code 里 clangd 用的不是 pixi 那份**：clangd 扩展默认用它自己下载的二进制。
  想统一，把 `clangd.path` 指到 pixi 环境里的 clangd（`pixi shell` 后 `where clangd`）。
- **`--clean` 删不掉 build 目录**：编辑器/调试器会占用该目录，脚本会自动回退到
  `cmake --fresh`（清配置缓存并全量重编），效果一样。
- **找不到 `python` / `cmake` / `cl.exe`**：脚本要在 pixi 环境里跑，
  用 `pixi run ...`，或者先 `pixi shell` 再跑 `python scripts/...`。
- **MSVC 报 `warning C4068: unknown pragma`**：头文件里写了 `#pragma one`，
  应为 `#pragma once`。

## 10. 实测结果

| 项目 | 结果 |
| --- | --- |
| `ninja-debug` 构建并运行 `demo_add_one` | ✅ 无警告，`PASS`，1,048,576 个元素全对，0.259 ms |
| `ninja-release` 构建 `demo_add_one` | ✅ 无警告，`PASS`，0.158 ms（53.2 GB/s 有效带宽） |
| `demo_bitonic_sort` | ✅ 已能编译链接运行（实现进行中） |
| `randomInt` 行为验证（`/W4` + 9 项断言） | ✅ 范围、端点包含、可复现、调用推进、`n == 0`、退化区间、非法区间抛异常 全部通过 |
| `clangd --check` 全部 8 个条目 | ✅ 8/8 `0 errors`，且**不使用 `.clangd`** |
| **模拟新机器**：删掉编译库 + build 目录后构建 | ✅ 一条命令完成探测、重建、生成编译库、`PASS` |
| `cudalab_tests`（pixi 装的 Catch2，`ctest --preset ninja-debug`） | ✅ 8/8 通过（`randomInt` 6 项 + `perf::Clock` 2 项） |
| `demo_bitonic_sort_test`（CPU/CUDA、升/降序、2 的幂与非 2 的幂、5 种输入形态，对比 `std::sort`） | ✅ 5 个 test case、4712 条断言全过（`ctest` 合计 13/13） |

## 11. 一个必须记住的 CMake 坑

`CMAKE_CUDA_ARCHITECTURES` 必须在 **`project()` 之前**设置：

```cmake
set(CMAKE_CUDA_ARCHITECTURES "${CUDALAB_CUDA_ARCH}" CACHE STRING "...")
project(cudalab ... LANGUAGES CXX CUDA)
```

原因：启用 CUDA 语言时 CMake 会自己往这个 cache 变量里塞一个默认值，
之后再 `if(NOT DEFINED CMAKE_CUDA_ARCHITECTURES)` 就永远不成立，
会静默按错误架构编译 —— 实测踩过：写 86，cache 里却是 75。

现在的默认值是 **`native`**（CMake 3.24+）：CMake 在配置阶段直接问当前 GPU，
所以不用再手工维护架构。命令行 `-DCMAKE_CUDA_ARCHITECTURES=...` 依然能覆盖它。

放在 `project()` 之前是安全的：设置 cache 变量不会覆盖已存在的值，
所以命令行 `-DCMAKE_CUDA_ARCHITECTURES=...` 仍然优先。

## 12. 依赖与 Catch2 单元测试

Catch2、fmt、OpenCL 全部由 pixi 提供，写在 `pixi.toml` 的 `[dependencies]` 里：

| 包 | 用途 |
| --- | --- |
| `catch2`（钉在 3.15.x） | 单元测试框架（`Catch2::Catch2WithMain`） |
| `fmt` | 格式化（`fmt::fmt`） |
| `opencl-headers` + `khronos-opencl-icd-loader`（Linux 用 `ocl-icd`） | OpenCL 头文件与 ICD loader（`OpenCL::OpenCL`） |

> Catch2 3.16.1 的 `catch_discover_tests` 会把 `EXTRA_ARGS` 当成单个参数传给测试，
> 结果为 `Unrecognised token: --benchmark-samples;20;...`；这里钉到 3.15.3。

> **Linux OpenCL 坑**：pixi 的 `cuda-opencl` 会在环境里放一个 `etc/OpenCL/vendors/cuda.icd`，
> ocl-icd 把它当 ICD 加载会失败（缺 `clIcdGetPlatformIDsKHR`），平台数直接变 0。
> `pixi.toml` 已用 `[target.linux-64.activation.env]` 把 `OCL_ICD_VENDORS` 指向
> `/etc/OpenCL/vendors/nvidia.icd`，只加载 NVIDIA ICD，也绕开了 `gf.icd` 的退出崩溃。

pixi 把这些包装进当前环境（`CONDA_PREFIX`），`CMakeLists.txt` 在 `project()` 之前
把 `CONDA_PREFIX`（Windows 还有 `CONDA_PREFIX/Library`）加入 `CMAKE_PREFIX_PATH`，
因此 `find_package(... CONFIG REQUIRED)` 直接命中，不需要 `CMAKE_TOOLCHAIN_FILE`，
也不需要 vcpkg。

> **坑**：`CMAKE_PREFIX_PATH` 只在当前环境里有效。已有的 `build/<preset>` 如果是
> 在 vcpkg 时代配置的，cache 里可能还留着 `CMAKE_TOOLCHAIN_FILE=...vcpkg...`；
> `scripts/build_cmake.py` 检测到会自动 `cmake --fresh` 重配。其它情况删掉
> `build/<preset>` 重新配置即可 —— 构建目录本来就是可再生产物。

### 测试怎么组织

测试放两个地方，CMake 都会自动发现：

| 位置 | 生成的 target | 参与编译的源文件 |
| --- | --- | --- |
| `tests/*.cpp` | `cudalab_tests` | 该目录下全部 `.cpp` |
| `src/demos/<demo>/test*.cpp` | `<demo>_test` | 该 demo 目录里除 `main.*`、`test*` 以外的源文件 + `test*` |

约定：demo 目录里 **`main.*` 是驱动，`test*.cpp` 是 Catch2 测试，其余是待测实现**。
测试 target 复用实现源文件（如 `bitonic_sort.cu`），但不含 `main.*` —— 它的 `main()`
由 `Catch2::Catch2WithMain` 提供，这样 demo 可执行文件和测试各有一个 main，互不冲突。

- 每个 Catch2 `TEST_CASE` 由 `catch_discover_tests` 注册成一个 CTest 用例（用 `DISCOVERY_MODE PRE_TEST`，见下）；
- 加测试 = 往 `tests/` 或某个 demo 目录放一个 `.cpp`，不用改 `CMakeLists.txt`；
- 两者都链接 `cudalab_common`，顺带拿到 `src/` 头文件路径（可以写
  `#include "common/random.h"`）；
- `-DCUDALAB_BUILD_TESTS=OFF` 关闭全部测试。

> **VS Code Test 集成的坑**：CMake Tools 跑测试前编译的是**当前选中的 target**
> （通常是某个 demo 驱动，比如 `demo_bitonic_sort`），**不会**去编译 `<demo>_test`。
> 用默认的 `POST_BUILD` 发现模式时，CTest 里会一直留着一条
> `<demo>_test_NOT_BUILT-<hash>` 占位用例，`ctest` 直接报
> `Could not find executable`。这里做了两件事兜住它：
>
> 1. `catch_discover_tests(... DISCOVERY_MODE PRE_TEST)` —— 测试列表在 ctest 启动时
>    才发现（而不是编译期），只要测试可执行文件在磁盘上就行；
> 2. 一个聚合 target `cudalab_build_tests` 依赖**全部** `<demo>_test`，并让每个 demo 驱动
>    都依赖它 —— 因为 `ctest` 跑的是全部测试二进制，而 IDE 只编译「当前选中的那个」；
>    这样 `cmake --build --target <任意 demo>` 都会把所有测试二进制一起编出来。

```bash
cmake --preset ninja-debug
cmake --build --preset ninja-debug --target demo_bitonic_sort_test
ctest --preset ninja-debug
```

`CMakePresets.json` 里补了对应的 `testPresets`：`--output-on-failure` 已打开，输出保持 ctest 默认 —— 每个用例一行 `Test #k … Passed/Failed`，只有失败用例才回显完整输出。

顶层 `CMakeLists.txt` 里调了 `include(CTest)`，它会生成 `DartConfiguration.tcl`。
这一步不能省：裸 `ctest` 用不到它，但 **`ctest -T test`（VS Code CMake Tools 的
Test 集成走的就是这个模式）会读它**，缺了就直接报
`Cannot find file: .../DartConfiguration.tcl`。`include(CTest)` 还顺带定义了标准的
`BUILD_TESTING`，所以测试要同时满足 `BUILD_TESTING` 和 `CUDALAB_BUILD_TESTS`
（默认都为 ON）；`-DBUILD_TESTING=OFF` 或 `-DCUDALAB_BUILD_TESTS=OFF` 都能关掉。

### 性能测试

`demo_bitonic_sort/test.cpp` 用 Catch2 的 `BENCHMARK` 量了 CPU / GPU 的排序耗时，标签是
普通的 `[benchmark]`（**不是** Catch2 那个会隐藏用例的 `[!benchmark]`），所以它和别的
用例一样会随 `ctest` 一起跑。两个 `BENCHMARK` 用**同一个 `n`**（`test.cpp` 里的
`kN = 1 << 18`，即 262,144），CPU / GPU 两行是同一问题、可直接对比；想看更大规模的数字
就改这个常量。

### 测试输出

测试用 Catch2 原生的 `console` reporter，`ctest --preset ninja-debug` 的输出就是 Catch2 / CTest
的默认形态：每个用例一行结果、末尾一段汇总，只有失败用例才回显完整输出。

直接跑二进制时，`console` reporter **不会**逐条列出通过的用例（只有产生输出或失败的用例才有
用例名，所以默认只会看到 benchmark 那条 + 末尾汇总）。想看「一行一个用例、benchmark 均值附在
行尾」的紧凑输出，用仓库自带的 `oneline` reporter（`include/cudalab/oneline_reporter.hpp`，
`CATCH_REGISTER_REPORTER` 注册，默认不启用）：

```bash
./build/ninja-debug/demo_bitonic_sort_test --reporter oneline
```

```
both implementations sort a size that is not a power of two PASS
bitonic sort performance ...................................PASS
    bitonicSortInt (CPU, n=262144)      96.455 ms
    cudaBitonicSortInt (GPU, n=262144)  1.813 ms
...

-------------------------------------------------------------------------------
benchmark results
-------------------------------------------------------------------------------
benchmark name                           samples  iters      est run         mean     low mean    high mean      std dev  low std dev high std dev
bitonicSortInt (CPU, n=262144)                 5      1   485.510 ms    96.455 ms    96.142 ms    96.996 ms     472.8 us     140.5 us     646.2 us
cudaBitonicSortInt (GPU, n=262144)             5      1     9.035 ms     1.813 ms     1.784 ms     1.893 ms      54.8 us       1.9 us      70.2 us
```

用例行的 benchmark 均值**换行**缩进在下方；整套跑完后，末尾统一打印完整的性能表
（samples / iters / est run / mean / low mean / high mean / std dev / low & high std dev）。

这是**可选**的：`ctest` 与默认运行仍用 `console`。想让 `ctest` 也走 oneline，把
`catch_discover_tests(...)` 的 `EXTRA_ARGS` 加上 `--reporter oneline` 即可。

想看 `BENCHMARK` 打印的完整计时表，绕过 ctest 直接跑二进制：

```bash
./build/ninja-release/demo_bitonic_sort_test "[benchmark]"
./build/ninja-release/demo_bitonic_sort_test "[benchmark]" --benchmark-samples 100
```

采样数：CTest 里跑时由 CMake 传了 `--benchmark-samples 20 --benchmark-resamples 1000`，
让计时表不至于拖慢整套测试；直接跑二进制则是 Catch2 默认的 100 次。

Debug 构建的数字没有参考价值（只带 `-g`、不优化），量性能请用 `ninja-release`。
