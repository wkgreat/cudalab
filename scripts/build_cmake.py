#!/usr/bin/env python3
"""Configure and build the demos with CMake.

This is the only build path for the project. Every demo under src/demos is one
executable target; this script drives CMake for all of them, or for a single one
with --demo.

Ninja needs cl.exe on PATH (nvcc uses MSVC as its host compiler on Windows), and
pixi's VS package puts it there together with INCLUDE/LIB and the pinned CUDA
toolkit. Run the script through pixi (``pixi run build``) so that environment is
active; it does not import the MSVC environment itself.

Usage:
    python scripts/build_cmake.py
    python scripts/build_cmake.py --preset ninja-release
    python scripts/build_cmake.py --demo demo_add_one --run
    python scripts/build_cmake.py --clean
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import sys

import common


VCPKG_TOOLCHAIN_PATTERN = r'^CMAKE_TOOLCHAIN_FILE[^=]*=.*vcpkg'


def parse_arguments(argv=None):
    parser = argparse.ArgumentParser(description='Configure and build the demos with CMake.')
    parser.add_argument('--preset', default='ninja-debug',
                        help='configure preset from CMakePresets.json (default: ninja-debug)')
    parser.add_argument('--demo', default='',
                        help='demo directory name to build; empty builds every demo target')
    parser.add_argument('--build-preset', default='',
                        help='build preset name; defaults to the configure preset name')
    parser.add_argument('--clean', action='store_true',
                        help="delete the preset's binary directory before configuring")
    parser.add_argument('--run', action='store_true',
                        help='run every built demo executable when the build succeeds')
    return parser.parse_args(argv)


def configure_arguments(preset: str, fresh: bool) -> list:
    arguments = ['--preset', preset]
    if fresh:
        arguments.append('--fresh')
    return arguments


def same_path(left: str, right: str) -> bool:
    return os.path.normcase(os.path.realpath(left)) == os.path.normcase(os.path.realpath(right))


def cached_cuda_compiler(cache_text: str) -> str:
    """The cached CMAKE_CUDA_COMPILER when it is not the nvcc currently on PATH."""
    for line in cache_text.splitlines():
        if line.startswith('CMAKE_CUDA_COMPILER:'):
            cached = line.split('=', 1)[1].strip()
            nvcc = shutil.which('nvcc')
            if cached and nvcc and not same_path(cached, nvcc):
                return cached
            return ''
    return ''


def main(argv=None) -> int:
    args = parse_arguments(argv)
    repo_root = common.REPO_ROOT

    cuda_root = common.get_cuda_root()
    common.assert_cuda_version(repo_root, cuda_root)

    # pixi pins CMake, so PATH is the only source; running outside pixi is an
    # error rather than a reason to fall back to some other installation.
    cmake = shutil.which('cmake')
    if not cmake:
        raise RuntimeError('cmake not found on PATH; run this through pixi (pixi run build) '
                           'so the pinned toolchain is active.')

    # nvcc needs cl.exe as its host compiler on Windows, and Ninja needs it on PATH.
    if common.is_windows() and not common.get_host_compiler():
        raise RuntimeError('cl.exe not found on PATH; run this through pixi (pixi run build) '
                           'so its VS package is active.')

    presets = common.load_presets(repo_root)
    preset_names = [entry.get('name') for entry in presets.get('configurePresets', [])]
    if args.preset not in preset_names:
        raise RuntimeError(f"configure preset '{args.preset}' is not defined in CMakePresets.json. "
                           f"Available: {', '.join(preset_names)}")

    build_preset = args.build_preset or args.preset

    use_fresh = False
    configure_dir = common.resolve_build_dir(args.preset, repo_root)
    cache_file = configure_dir / 'CMakeCache.txt'

    # A build tree configured in the vcpkg era keeps that toolchain in its cache
    # forever. Reconfigure from scratch so the tree uses the pixi packages instead.
    if not args.clean and cache_file.is_file():
        cache_text = cache_file.read_text(encoding='utf-8', errors='ignore')
        if any(re.search(VCPKG_TOOLCHAIN_PATTERN, line) for line in cache_text.splitlines()):
            common.warn('build tree still points at deleted vcpkg; reconfiguring from scratch')
            use_fresh = True
        else:
            cached_nvcc = cached_cuda_compiler(cache_text)
            if cached_nvcc:
                common.warn(f'build tree was configured with {cached_nvcc}; '
                            f'reconfiguring from scratch with {shutil.which("nvcc")}')
                use_fresh = True

    if args.clean and configure_dir.is_dir():
        try:
            shutil.rmtree(configure_dir)
            common.warn(f'removed {configure_dir}')
        except OSError as exc:
            # A running editor, debugger or indexer can hold the directory open.
            # 'cmake --fresh' gives the same from-scratch configure without
            # deleting it.
            common.warn(f'could not remove {configure_dir}')
            common.detail(f'    ({exc})')
            common.warn('falling back to cmake --fresh')
            use_fresh = True

    # --- Drop the generator variables the pixi VS package leaks -----------------
    # Activating vs2026_win-64 sets CMAKE_GENERATOR to the Visual Studio generator
    # along with CMAKE_GENERATOR_PLATFORM=x64 and a toolset. This project builds
    # with Ninja, and a leftover platform makes CMake refuse with "Generator
    # Ninja does not support platform specification". Clearing them here keeps
    # the preset's generator the only one in play; the child cmake inherits this
    # process environment.
    for leaked in ('CMAKE_GENERATOR', 'CMAKE_GENERATOR_PLATFORM', 'CMAKE_GENERATOR_TOOLSET'):
        os.environ.pop(leaked, None)

    # --- Configure --------------------------------------------------------------
    common.step(f"cmake{' --fresh' if use_fresh else ''} --preset {args.preset}")
    configure_exit = common.run_native([cmake] + configure_arguments(args.preset, use_fresh))
    if configure_exit != 0:
        raise RuntimeError(f'CMake configure failed with exit code {configure_exit}')

    # --- Refresh the compilation database clangd reads --------------------------
    # Done before the build on purpose: editing code that does not compile yet is
    # exactly when IntelliSense matters. A failure here must not fail the build.
    try:
        entry_count = common.write_clang_database(repo_root, configure_dir)
        common.detail(f"==> clangd database: {entry_count} entries -> {repo_root / 'compile_commands.json'}")
    except (RuntimeError, OSError, ValueError) as exc:
        common.warn(f'clangd database not refreshed: {exc}')

    # --- Build ------------------------------------------------------------------
    build_arguments = ['--build', '--preset', build_preset]
    if args.demo:
        build_arguments += ['--target', args.demo]

    common.step(f"cmake {' '.join(build_arguments)}")
    build_exit = common.run_native([cmake] + build_arguments)
    if build_exit != 0:
        raise RuntimeError(f'CMake build failed with exit code {build_exit}')

    demos = common.select_demos(common.get_demos(repo_root), args.demo)
    executables = common.get_built_executables(configure_dir, demos)
    if not executables:
        raise RuntimeError(f"build succeeded but no demo executable was found under '{configure_dir}'.")

    for executable in executables:
        common.success(f'built {executable}')

    # --- Run --------------------------------------------------------------------
    if args.run:
        failed = []
        for executable in executables:
            common.step(f'running {executable.name}')
            if common.run_native([executable]) != 0:
                failed.append(executable.stem)

        if failed:
            common.error(f"==> run failures: {', '.join(failed)}")
            return 1

    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError) as error:
        common.error(str(error))
        sys.exit(1)
