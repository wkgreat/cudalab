# cudalab

CUDA 实验项目。一个 demo 一个目录，每个 demo 编译成一个独立的可执行 target，统一用 CMake 构建。

## 新机器环境配置

### Windows

1. 安装 pixi：`winget install prefix-dev.pixi`
2. 安装 Visual Studio 2026（勾选「使用 C++ 的桌面开发」）；只有 VS 2022 也行
3. 安装 CUDA Toolkit
4. 克隆本仓库并进入仓库目录
5. `pixi install`
6. `pixi run build-debug`（首次会自动探测本机并生成 `env.json`）
7. `pixi run test`
8. 路径探测不准时：`pixi run env`，然后重新 `pixi run build`

vcpkg 用系统里已有的安装；Windows 上没装时用 Visual Studio 自带的（见 `docs/setup.md`）。

### Linux

1. 安装 pixi：`curl -fsSL https://pixi.sh/install.sh | bash`
2. 克隆本仓库并进入仓库目录
3. `pixi install`
4. `pixi run build`
5. `pixi run test`
6. 单独刷新 clangd 编译库：`pixi run env`（需先配置过一次）

vcpkg 用系统里已有的安装（`VCPKG_ROOT` 或 PATH 上的 `vcpkg`），见 `docs/setup.md`。

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
