#!/usr/bin/env python3
"""Run the demo executables that have already been built.

Each demo is self-checking: it prints PASS/FAIL and returns a non-zero exit code
when the GPU result is wrong, so this script doubles as a smoke test.

Usage:
    python scripts/run_demos.py
    python scripts/run_demos.py --preset ninja-release
    python scripts/run_demos.py --demo demo_add_one
"""

from __future__ import annotations

import argparse
import sys

import common


def parse_arguments(argv=None):
    parser = argparse.ArgumentParser(description='Run the demo executables that are already built.')
    parser.add_argument('--preset', default='ninja-debug',
                        help='configure preset whose build tree holds the executables')
    parser.add_argument('--demo', default='',
                        help='demo directory name to run; empty runs every built demo')
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_arguments(argv)
    repo_root = common.REPO_ROOT

    build_dir = common.resolve_build_dir(args.preset, repo_root)
    demos = common.select_demos(common.get_demos(repo_root), args.demo)
    executables = common.get_built_executables(build_dir, demos)

    if not executables:
        raise RuntimeError(f"no built demo executable found under '{build_dir}'. "
                           f'Build them first, e.g. python scripts/build_cmake.py --preset {args.preset}')

    # --- Run each demo and collect its exit code -------------------------------
    results = []
    for executable in executables:
        print()
        common.step(executable.name)
        results.append((executable.stem, common.run_native([executable])))

    # --- Summary ---------------------------------------------------------------
    print()
    common.step(f'results from {build_dir}')
    width = max(len(name) for name, _ in results)
    for name, code in results:
        print(f'    {name.ljust(width)}  exit {code}  {"PASS" if code == 0 else "FAIL"}')

    failed = [name for name, code in results if code != 0]
    if failed:
        common.error(f"==> FAILED: {', '.join(failed)}")
        return 1

    common.success(f'all {len(results)} demo(s) passed')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError) as error:
        common.error(str(error))
        sys.exit(1)
