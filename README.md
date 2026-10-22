# cudalab

CUDA 实验项目。一个 demo 一个目录，每个 demo 编译成一个独立的可执行 target，统一用 CMake 构建。

## 新机器环境配置

### Windows

1. 安装 pixi：`winget install prefix-dev.pixi`
2. 安装 Visual Studio 2026（勾选「使用 C++ 的桌面开发」）；只有 VS 2022 也行 —— nvcc 需要它的 `cl.exe` 主机编译器
3. 克隆本仓库并进入仓库目录
4. `pixi install` —— cmake / ninja / clangd / CUDA 都由 pixi 提供，不用单独装 CUDA Toolkit
5. `pixi run build-debug`
6. `pixi run test`
7. 想单独刷新 clangd 编译库：`pixi run env`（需先构建过一次）

不需要任何机器配置文件：MSVC、Windows SDK 和 GPU 架构都在构建时探测。

Catch2、fmt、OpenCL 也由 pixi 安装，不需要 vcpkg。

### Linux

1. 安装 pixi：`curl -fsSL https://pixi.sh/install.sh | bash`
2. 克隆本仓库并进入仓库目录
3. `pixi install`
4. `pixi run build`
5. `pixi run test`
6. 单独刷新 clangd 编译库：`pixi run env`（需先配置过一次）

Catch2、fmt、OpenCL 也由 pixi 安装，不需要 vcpkg。

### VS Code

1. 安装扩展：`llvm-vs-code-extensions.vscode-clangd`、`ms-vscode.cpptools`、`ms-vscode.cmake-tools`
2. 先构建一次，生成 clangd 编译库（仓库根目录的 `compile_commands.json`）
3. 改过 `.vscode/settings.json` 的 clangd 开关后：`Ctrl+Shift+P` → `Developer: Reload Window`

## 构建与测试

1. `pixi run build` —— 全部 demo
2. `pixi run test` —— 全部测试
3. `pixi run clean` —— 干净重建
4. `cmake --build --preset ninja-debug --target demo_add_one` —— 单个 demo

## 机器相关细节

1. 见 [`docs/setup.md`](docs/setup.md)
