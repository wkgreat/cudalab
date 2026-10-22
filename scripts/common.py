"""Shared helpers for the scripts in this directory.

Everything machine specific is detected at run time: pixi supplies CMake, Ninja,
clangd and the CUDA toolkit on both platforms (and gcc on Linux, plus the MSVC
toolchain on Windows), the Windows SDK comes from its registry entry and the
GPU architecture from nvidia-smi.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

SOURCE_SUFFIXES = {'.cu', '.cpp', '.cxx', '.cc'}
HEADER_SUFFIXES = {'.h', '.cuh', '.hpp', '.hxx'}

# Keep our own messages in step with the native tools writing straight to the
# console when stdout is a pipe (a task runner, a log file).
sys.stdout.reconfigure(line_buffering=True)

_USE_COLOR = sys.stdout.isatty()


def _paint(code: str, text: str) -> str:
    return f'\033[{code}m{text}\033[0m' if _USE_COLOR else text


def step(message: str) -> None:
    print(_paint('36', f'==> {message}'))


def success(message: str) -> None:
    print(_paint('32', f'==> {message}'))


def warn(message: str) -> None:
    print(_paint('33', f'==> {message}'))


def detail(message: str) -> None:
    print(_paint('90', message))


def error(message: str) -> None:
    print(_paint('31', message), file=sys.stderr)


def is_windows() -> bool:
    return os.name == 'nt'


def run_native(arguments: list) -> int:
    """Run a command with inherited stdio and return its exit code."""
    return subprocess.run([str(argument) for argument in arguments]).returncode


# ---------------------------------------------------------------------------
# demos
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Demo:
    name: str
    directory: Path
    sources: tuple

    @property
    def has_cuda(self) -> bool:
        return any(source.suffix == '.cu' for source in self.sources)


def get_demos(repo_root=None) -> list:
    """Every demo under src/demos that has sources, sorted by name."""
    repo_root = Path(repo_root or REPO_ROOT)
    demos_dir = repo_root / 'src' / 'demos'
    if not demos_dir.is_dir():
        raise RuntimeError(f'demo directory not found: {demos_dir}')

    demos = []
    for directory in sorted((entry for entry in demos_dir.iterdir() if entry.is_dir()),
                            key=lambda entry: entry.name):
        sources = tuple(sorted(
            (entry for entry in directory.iterdir()
             if entry.is_file() and entry.suffix in SOURCE_SUFFIXES),
            key=lambda entry: entry.name))
        if sources:
            demos.append(Demo(directory.name, directory, sources))

    return demos


def select_demos(demos: list, name: str = '') -> list:
    """Filter a demo list by name; an empty name selects everything."""
    if not name:
        return demos

    match = [demo for demo in demos if demo.name == name]
    if not match:
        available = ', '.join(demo.name for demo in demos)
        raise RuntimeError(f"demo '{name}' not found. Available demos: {available}")

    return match


# ---------------------------------------------------------------------------
# detected machine paths
# ---------------------------------------------------------------------------

def get_host_compiler() -> str:
    """cl.exe on PATH, which is what nvcc uses as its host compiler on Windows."""
    return shutil.which('cl.exe') or ''


def get_ucrt_include() -> str:
    """Windows SDK UCRT include directory, taken from the SDK's registry entry."""
    if not is_windows():
        return ''

    import winreg

    key_path = r'Microsoft\Microsoft SDKs\Windows\v10.0'
    sdk_root = ''
    for hive in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
        for prefix in (r'SOFTWARE\Wow6432Node', r'SOFTWARE'):
            try:
                with winreg.OpenKey(hive, prefix + '\\' + key_path) as key:
                    value, _ = winreg.QueryValueEx(key, 'InstallationFolder')
            except OSError:
                continue
            if value and Path(value).is_dir():
                sdk_root = value
                break
        if sdk_root:
            break

    if not sdk_root:
        sdk_root = Path(os.environ.get('ProgramFiles(x86)', r'C:\Program Files (x86)')) / 'Windows Kits' / '10'

    include_root = Path(sdk_root) / 'Include'
    if not include_root.is_dir():
        return ''

    for version in sorted(include_root.iterdir(), key=lambda entry: entry.name, reverse=True):
        ucrt = version / 'ucrt'
        if ucrt.is_dir():
            return ucrt.as_posix()

    return ''


def get_cuda_root() -> str:
    """The toolkit in use: nvcc on PATH first, then CUDA_PATH/CUDA_HOME, then /usr/local/cuda."""
    candidates = []

    nvcc = shutil.which('nvcc')
    if nvcc:
        candidates.append(Path(nvcc).resolve().parent.parent)
    for variable in ('CUDA_PATH', 'CUDA_HOME'):
        value = os.environ.get(variable)
        if value:
            candidates.append(Path(value))
    candidates.append(Path('/usr/local/cuda'))

    for candidate in candidates:
        if candidate.is_dir():
            return candidate.as_posix()

    return ''


def get_min_cuda_version(repo_root=None) -> str:
    """Minimum CUDA version, read from the pixi.toml constraint so it lives in one place."""
    pixi_toml = Path(repo_root or REPO_ROOT) / 'pixi.toml'
    if not pixi_toml.is_file():
        raise RuntimeError(f"pixi.toml not found under '{pixi_toml.parent}'; cannot read the minimum CUDA version.")

    # e.g. cuda-toolkit = ">=13.3,<14"
    text = pixi_toml.read_text(encoding='utf-8')
    match = re.search(r'cuda-toolkit\s*=\s*"[^"]*?>=\s*([0-9]+(?:\.[0-9]+)*)', text)
    if not match:
        raise RuntimeError("no '>=<version>' constraint found for cuda-toolkit in pixi.toml.")

    return match.group(1)


def get_cuda_version(cuda_root) -> str:
    """Version of an installed toolkit: version.json first, nvcc --version as the fallback."""
    root = Path(cuda_root)

    version_json = root / 'version.json'
    if version_json.is_file():
        try:
            version = json.loads(version_json.read_text(encoding='utf-8')).get('cuda', {}).get('version', '')
            if version:
                return version
        except (OSError, ValueError):
            pass

    nvcc = root / 'bin' / ('nvcc.exe' if is_windows() else 'nvcc')
    if nvcc.is_file():
        try:
            output = subprocess.run([str(nvcc), '--version'],
                                    capture_output=True, text=True).stdout
        except OSError:
            output = ''
        match = re.search(r'release\s+([0-9]+\.[0-9]+)', output)
        if match:
            return match.group(1)

    return ''


def _version_tuple(text: str) -> tuple:
    return tuple(int(part) for part in re.findall(r'[0-9]+', text))


def assert_cuda_version(repo_root=None, cuda_root=None) -> None:
    """Fail fast when the toolkit the build will use is older than pixi.toml allows."""
    if cuda_root is None:
        cuda_root = get_cuda_root()
    if not cuda_root:
        return

    minimum = _version_tuple(get_min_cuda_version(repo_root))
    found = get_cuda_version(cuda_root)
    if not found:
        raise RuntimeError(f"cannot determine the CUDA toolkit version at '{cuda_root}' (no version.json and no nvcc).")

    if _version_tuple(found) < minimum:
        raise RuntimeError(
            f"CUDA toolkit {found} at '{cuda_root}' is older than the required minimum "
            f"{'.'.join(str(part) for part in minimum)} (declared in pixi.toml). "
            'Run through pixi (pixi run ...) so its CUDA toolkit is on PATH.')


# ---------------------------------------------------------------------------
# build tree helpers
# ---------------------------------------------------------------------------

def load_presets(repo_root=None) -> dict:
    presets_path = Path(repo_root or REPO_ROOT) / 'CMakePresets.json'
    return json.loads(presets_path.read_text(encoding='utf-8'))


def resolve_build_dir(preset: str = 'ninja-debug', repo_root=None) -> Path:
    """Read a configure preset's binary directory from CMakePresets.json."""
    repo_root = Path(repo_root or REPO_ROOT)
    for entry in load_presets(repo_root).get('configurePresets', []):
        if entry.get('name') == preset:
            binary_dir = entry.get('binaryDir', '')
            return Path(binary_dir.replace('${sourceDir}', str(repo_root)))

    raise RuntimeError(f"configure preset '{preset}' is not defined in CMakePresets.json")


def executable_name(demo_name: str) -> str:
    return f'{demo_name}.exe' if is_windows() else demo_name


def get_built_executables(build_dir, demos=()) -> list:
    """Every demo executable present in a build directory, restricted to the given demos."""
    build_dir = Path(build_dir)
    if not build_dir.is_dir():
        raise RuntimeError(f'build directory not found: {build_dir} (build the demos first)')

    names = {demo.name for demo in demos}
    found = []
    for entry in sorted(build_dir.iterdir(), key=lambda item: item.name):
        if not entry.is_file():
            continue
        if is_windows():
            if entry.suffix.lower() != '.exe':
                continue
        elif entry.stem in {'build', 'rules'} or entry.suffix:
            # Ninja's own files and anything with an extension is not a demo.
            continue
        if names and entry.stem not in names:
            continue
        if not is_windows() and not os.access(entry, os.X_OK):
            continue
        found.append(entry)

    return found


# ---------------------------------------------------------------------------
# clangd compile database
# ---------------------------------------------------------------------------

def split_command_line(command: str) -> list:
    """Split a command line into arguments, honouring double quotes."""
    tokens = []
    current = []
    in_quotes = False

    for character in command:
        if character == '"':
            in_quotes = not in_quotes
            continue
        if not in_quotes and character.isspace():
            if current:
                tokens.append(''.join(current))
                current.clear()
            continue
        current.append(character)

    if current:
        tokens.append(''.join(current))

    return tokens


def get_command_flags(command: str) -> tuple:
    """Include directories, preprocessor defines and debug flag from a CMake command line."""
    tokens = split_command_line(command)
    includes = []
    defines = []

    index = 0
    while index < len(tokens):
        token = tokens[index]
        following = tokens[index + 1] if index + 1 < len(tokens) else None

        if token in ('-I', '/I', '-isystem', '-imsvc'):
            if following is not None:
                includes.append(following)
                index += 1
        elif token in ('-D', '/D'):
            if following is not None:
                defines.append(following)
                index += 1
        elif token.startswith('-external:I') or token.startswith('/external:I'):
            includes.append(token[len('-external:I'):])
        elif token.startswith('-isystem'):
            includes.append(token[len('-isystem'):])
        elif token.startswith(('-I', '/I')):
            includes.append(token[2:])
        elif token.startswith(('-D', '/D')) and len(token) > 2 and (token[2].isupper() or token[2] == '_'):
            defines.append(token[2:])

        index += 1

    # /MDd and -MDd imply _DEBUG for the MSVC headers.
    debug = '-MDd' in tokens or '/MDd' in tokens

    return includes, defines, debug


def detect_gpu_arch(default: str = '120') -> str:
    """Compute capability compiled for, from nvidia-smi."""
    try:
        output = subprocess.run(['nvidia-smi', '--query-gpu=compute_cap', '--format=csv,noheader'],
                                capture_output=True, text=True).stdout
    except OSError:
        return default

    first = output.strip().splitlines()[0].strip() if output.strip() else ''
    match = re.match(r'^([0-9]+)\.([0-9]+)$', first)
    return f'{match.group(1)}{match.group(2)}' if match else default


def write_clang_database(repo_root=None, build_dir=None, preset: str = 'ninja-debug') -> int:
    """Render a clang-native compile_commands.json covering every source and header."""
    repo_root = Path(repo_root or REPO_ROOT)
    if build_dir is None:
        build_dir = resolve_build_dir(preset, repo_root)
    build_dir = Path(build_dir)

    cmake_db = build_dir / 'compile_commands.json'
    if not cmake_db.is_file():
        raise RuntimeError(f"compile_commands.json not found in '{build_dir}'; configure the project first.")

    cuda_root = get_cuda_root()
    ucrt = get_ucrt_include()

    # System include directories clangd cannot discover by itself.
    system_include_dirs = []
    if ucrt:
        system_include_dirs.append(ucrt)
    if cuda_root:
        system_include_dirs += [f'{cuda_root}/include', f'{cuda_root}/include/cccl']

    managed = {directory.lower() for directory in system_include_dirs}
    system_includes = []
    for directory in system_include_dirs:
        system_includes += ['-isystem', directory]

    arch = detect_gpu_arch()
    cuda_flags = ['-x', 'cuda']
    if cuda_root:
        cuda_flags.append(f'--cuda-path={cuda_root}')
    cuda_flags += [f'--cuda-gpu-arch=sm_{arch}', '-Wno-unknown-cuda-version']

    directory_slash = build_dir.as_posix()
    entries = []
    by_file = {}

    for item in json.loads(cmake_db.read_text(encoding='utf-8')):
        file = item['file'].replace('\\', '/')
        includes, defines, debug = get_command_flags(item.get('command', ''))
        is_cuda = file.endswith('.cu')

        arguments = ['clang++']
        arguments += cuda_flags if is_cuda else ['-x', 'c++']
        arguments += ['-std=c++17']
        arguments += system_includes
        for include in includes:
            normalized = include.replace('\\', '/')
            if normalized.lower() not in managed:
                arguments += ['-I', normalized]
        if debug:
            arguments.append('-D_DEBUG')
        for define in defines:
            arguments.append(f'-D{define}')
        arguments += ['-c', file]

        entry = {'directory': directory_slash, 'file': file, 'arguments': arguments}
        entries.append(entry)
        by_file[file.lower()] = entry

    if not entries:
        raise RuntimeError(f"no translation units found in '{cmake_db}'.")

    # Give every header an explicit entry, so clangd never has to guess one from
    # a neighbouring source. Headers are parsed as CUDA, which accepts plain C++ too.
    src_root = repo_root / 'src'
    headers = sorted((path for path in src_root.rglob('*')
                      if path.is_file() and path.suffix in HEADER_SUFFIXES), key=lambda path: path.as_posix())
    for header in headers:
        file = header.as_posix()
        if file.lower() in by_file:
            continue

        # Model the header on the source that shares its name, else on a source in
        # the same directory, else on any source at all.
        donor = next((entry for entry in entries
                      if Path(entry['file']).stem == header.stem), None)
        if donor is None:
            donor = next((entry for entry in entries
                          if Path(entry['file']).parent == header.parent), None)
        if donor is None:
            donor = entries[0]

        header_includes = []
        header_defines = []
        donor_arguments = donor['arguments']
        index = 0
        while index < len(donor_arguments):
            token = donor_arguments[index]
            if token == '-I' and index + 1 < len(donor_arguments):
                header_includes.append(donor_arguments[index + 1])
                index += 1
            elif token == '-D_DEBUG' or token.startswith('-D'):
                header_defines.append(token)
            index += 1

        arguments = ['clang++'] + cuda_flags + ['-std=c++17'] + system_includes
        for include in header_includes:
            arguments += ['-I', include]
        arguments += header_defines
        arguments += ['-c', file]

        entries.append({'directory': directory_slash, 'file': file, 'arguments': arguments})

    output = repo_root / 'compile_commands.json'
    output.write_text(json.dumps(entries, indent=2), encoding='utf-8')

    return len(entries)
