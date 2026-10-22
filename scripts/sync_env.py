#!/usr/bin/env python3
"""Regenerate the clangd compile database.

There is no machine config file: pixi supplies CMake, Ninja, clangd, the CUDA
toolkit (both platforms, and gcc on Linux) and the MSVC toolchain on Windows, the
Windows SDK is detected at run time, and the GPU's architecture comes from
nvidia-smi. This script only re-renders the clangd database from the build tree.

Usage:
    pixi run env
    python scripts/sync_env.py
    python scripts/sync_env.py --preset ninja-release
"""

from __future__ import annotations

import argparse
import sys

import common


def parse_arguments(argv=None):
    parser = argparse.ArgumentParser(description='Regenerate the clangd compile database.')
    parser.add_argument('--preset', default='ninja-debug',
                        help='which build tree holds CMake compile_commands.json')
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_arguments(argv)
    repo_root = common.REPO_ROOT

    common.assert_cuda_version(repo_root)

    print()
    common.step('detected toolchain')
    print(f'    CUDA toolkit : {common.get_cuda_root()}')
    if common.is_windows():
        print(f'    MSVC         : {common.get_host_compiler()}')
        print(f'    Windows SDK  : {common.get_ucrt_include()}')

    # --- clangd's compile database ---------------------------------------------
    # It is rendered from CMake's own database, so it has to wait for a configure.
    build_dir = common.resolve_build_dir(args.preset, repo_root)
    if not (build_dir / 'compile_commands.json').is_file():
        print()
        common.warn(f'no build tree at {build_dir} yet')
        common.warn(f'configure first: pixi run build ({args.preset})')
        return 0

    entry_count = common.write_clang_database(repo_root, build_dir)

    print()
    common.success(f'clangd database: {entry_count} entries (sources + headers)')
    print(f'    {repo_root / "compile_commands.json"}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError) as error:
        common.error(str(error))
        sys.exit(1)
