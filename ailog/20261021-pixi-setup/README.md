# 2026-10-21 pixi 环境配置复盘：vcpkg 交还给系统

## 1. 目标

- pixi 不再管理 vcpkg 程序本身，改用机器上已有的 vcpkg
- Windows 上即使没单独装 vcpkg，也能用 Visual Studio 自带的
- 唯一入口 `pixi run build-release` 必须成功
- 多台 Windows / Linux 机器只靠 pixi 配置就能切换，不能出现写死的机器路径

## 2. 最终方案

### 2.1 vcpkg 目录解析顺序

`CMakeLists.txt:40-121`，在 `project()` 之前按顺序取第一个包含
`scripts/buildsystems/vcpkg.cmake` 的目录：

1. `env.json` 的 `vcpkg.root`（显式覆盖，可选）
2. 环境变量 `VCPKG_ROOT`（vcpkg 自己的约定）
3. PATH 上的 `vcpkg`（取可执行文件所在目录，`file(REAL_PATH)` 先解符号链接）
4. Windows：`C:/vcpkg`
5. Windows：Visual Studio 自带的 `VC/vcpkg`（用 vswhere 定位）

命中后写入 `CMAKE_TOOLCHAIN_FILE`（`FORCE`），vcpkg 进入 manifest 模式，
把 catch2 / fmt / opencl 装到 `build/<preset>/vcpkg_installed/`。
一个都找不到只打印一条 STATUS，项目照常构建，单元测试关闭。

### 2.2 旧 build tree 自愈

CMake 只在 build tree 首次 configure 时读 `CMAKE_TOOLCHAIN_FILE`，
以前指向仓库内 `.vcpkg/` 的缓存会一直生效。两处兜底：

- `CMakeLists.txt:107-118`：缓存里匹配到 `.vcpkg/` 就 `FORCE` 换成当前检测结果
- `scripts/build-cmake.ps1:70-80`：检测到缓存仍指向 `.vcpkg/` 时自动 `cmake --fresh`

### 2.3 env.json 跨机器失效保护

`scripts/common.ps1:270-281`：读到的 `env.json` 现在会逐个 `Test-Path` 校验。
别的机器带过来的路径解析没问题但指向不存在，以前会静默失败，现在会打印提示并重新探测。

## 3. 变更清单

| 文件 | 改动 |
| --- | --- |
| `CMakeLists.txt` | 重写 vcpkg 解析（5 步候选 + vswhere + 失效缓存替换） |
| `scripts/build-cmake.ps1` | 老构建目录自动 `--fresh` |
| `scripts/common.ps1` | `env.json` 路径存在性校验 |
| `scripts/setup-vcpkg.ps1` | 删除（pixi 管 vcpkg 的引导脚本，已废弃） |
| `.gitignore` | 更新 `.vcpkg/` 注释；新增 `temp/` |
| `README.md` | 去掉 Windows/Linux 的 `pixi run vcpkg` 步骤 |
| `docs/setup.md` | §12 重写 vcpkg 来源说明；修正 `vcpkg.json` 依赖列表（补 fmt） |
| `env.windows-sampe.json` | `vcpkg.root` 注释改为新的回退顺序 |
| `env.json` | 本机 CUDA / MSVC 路径刷新为新机器实际值 |

`pixi.toml` 本来就没有 vcpkg 任务，未改动。

## 4. 验证结果

```
pixi run build-release      -> exit 0
  vcpkg: catch2 3.15.3 / fmt 12.2.0#1 / opencl 2024.10.24#1 安装成功
  cmake: 3 个 demo target + 3 个 test target 配置完成
  build: 27 步全部完成，demo_add_one / demo_bitonic_sort / demo_cum_prod 生成
demo_add_one.exe            -> PASS (1048576 元素 +1，误差 0)
```

## 5. 踩坑复盘

### 5.1 CMake 里直接引用 `ProgramFiles(x86)` 会语法错误

`$ENV{ProgramFiles(x86)}` 的括号让 CMake 解析失败。改成
`find_program(CUDALAB_VSWHERE_EXECUTABLE NAMES vswhere.exe HINTS ...)`，
绕开括号，也不再依赖具体盘符。

### 5.2 vswhere 要带 `-products *`

只查默认产品会漏掉 BuildTools / Preview 安装。同时限制了
`-requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64`，保证找到的是
真有 C++ 工具链、因而连带 vcpkg 的那份。

### 5.3 缓存优先级：`FORCE` 只在需要时用

无条件 `FORCE` 会覆盖用户在命令行传的 `-DCMAKE_TOOLCHAIN_FILE=...`。
现在的条件是两个：缓存为空，或缓存指向已废弃的 `.vcpkg/`。

### 5.4 沙箱内 `git init` 报 permission denied（本次最大的坑）

现象：VS 的 vcpkg 在手动命令行里能正常解析 baseline，但由 CMake（在 pixi
环境里）拉起时就失败：

```
Fetching registry information from https://github.com/microsoft/vcpkg (HEAD)...
catch2 does not exist
...
error: could not lock config file .../registries/git/.git/config: Permission denied
```

排查过程：

1. `-DVCPKG_INSTALL_OPTIONS=--debug` 定位到失败的具体命令是
   `git --git-dir=... init`，返回 128
2. 在 PowerShell 里手动执行同一条命令返回 0，排除 git 本身
3. 用 `--debug-env` 对比"CMake 拉起"和"手动运行"两份环境变量，无实质差异
4. 写了一个 C 版 git 包装器放到 PATH 前面，记录每次调用的参数、cwd、退出码，
   并把子进程 stderr 抓到文件 —— 确认 stderr 就是 `Permission denied`，
   且 `CreateFileW` 建锁文件返回 error 5
5. 同一份包装器放到 `%TEMP%` 下运行却成功，`LockTest-Err: 0`

结论：与项目代码无关。Trae CLI 的沙箱给 `CodexSandboxUsers` 在
`C:\Users\pc\AppData\Local\vcpkg\registries\git\.git` 上只有 `(RX)`，
而"从工作区路径启动的进程"受这层限制；用户自己的正常终端不受影响。

绕过办法（仅用于本地验证，不写进项目）：把 `LOCALAPPDATA` 指到
`temp\vcpkg-appdata`，让 vcpkg 的注册表缓存落在工作区内。

### 5.5 沙箱内 `cl.exe` 报 D8050

同样的 ACL 限制让 MSVC 无法写 `TEMP`，报
`cannot execute 'c1xx.dll': failed to get command line into debug records`
（vcpkg 编译 catch2 时触发）。验证时把 `TMP`/`TEMP` 也指到 `temp\tmp` 即可。
正常终端不会出现。

### 5.6 vcpkg 首次运行要联网拉注册表

即使本地已有 `.git` 缓存，vcpkg 仍会 `fetch --update-shallow` 拉
`microsoft/vcpkg` 的 HEAD。离线环境需要提前预热缓存。

## 6. 多机器切换

### Windows

只需装 pixi + Visual Studio（C++ 桌面开发）+ CUDA Toolkit：

```
pixi install
pixi run build-debug     # 首次自动探测并生成 env.json
pixi run test
```

vcpkg 不用单独准备：VS 自带的那份会自动被找到。想固定某个 vcpkg 时，
在 `env.json` 写 `"vcpkg": { "root": "..." }`。

### Linux

```
pixi install
pixi run build
pixi run test
```

vcpkg 通过 `VCPKG_ROOT` 或 PATH 提供；不需要 `env.json`。

### 换机器时的判断

- 输出 `cudalab: vcpkg -> <路径>`：用的是哪份 vcpkg
- 输出 `cudalab: no vcpkg installation found`：退回无 vcpkg 构建，测试关闭
- 输出 `env.json is incomplete or points at paths that do not exist`：自动重探测

## 7. 遗留与建议

1. 仓库根目录的 `.vcpkg/`（旧 pixi 管理的 checkout，约 30 项）和
   `vcpkg_installed/` 都已是 git 忽略产物，确认不再需要后可手动删除，省磁盘
2. `src/demos/demo_bitonic_sort/main.cpp:75-76` 的 `printf("%ld")` 与
   `std::chrono` 的 `_Rep`(`__int64`) 类型不匹配，有 `C4477` 告警，建议改 `%lld`
3. 如果以后想让 Linux 也统一由 pixi 提供 vcpkg，可在 `pixi.toml` 的
   `linux-64.dependencies` 里加 vcpkg —— 但当前设计是"系统自带"，不推荐回退

## 8. 命令速查

```powershell
pixi run build               # = build-release
pixi run build-debug
pixi run clean
pixi run test
pixi run env                 # 重新探测并刷新 env.json

# 排查 vcpkg 用了哪份、走了什么命令
cmake --preset ninja-release -DVCPKG_INSTALL_OPTIONS=--debug

# 只想看依赖解析结果
vcpkg install --dry-run --triplet x64-windows `
  --x-manifest-root=. --x-install-root=build/ninja-release/vcpkg_installed
```
