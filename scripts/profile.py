#!/usr/bin/env python3
"""Profile a demo executable with Nsight Compute or Nsight Systems.

Neither tool is on PATH in a normal shell: the CUDA toolkit installer puts them
under "C:\\Program Files\\NVIDIA Corporation\\Nsight ..." on Windows and under
/opt/nvidia on Linux. This script finds them and runs the tool against an
executable produced by the CMake build.

Usage:
    python scripts/profile.py
    python scripts/profile.py --demo demo_add_one
    python scripts/profile.py --preset ninja-release
    python scripts/profile.py --tool systems
    python scripts/profile.py --set full
    python scripts/profile.py --exe build/ninja-debug/demo_add_one.exe
"""

from __future__ import annotations

import argparse
import os
import shutil
import sys
from datetime import datetime
from pathlib import Path

import common


def parse_arguments(argv=None):
    parser = argparse.ArgumentParser(description='Profile a demo executable with Nsight.')
    parser.add_argument('--tool', choices=('compute', 'systems'), default='compute',
                        help='which Nsight tool to run (default: compute)')
    parser.add_argument('--demo', default='',
                        help='demo to profile; empty picks the first demo under src/demos')
    parser.add_argument('--preset', default='ninja-debug',
                        help='which CMake build tree holds the executable')
    parser.add_argument('--exe', default='',
                        help='explicit executable path, relative to the repository root unless absolute')
    parser.add_argument('--set', dest='section', default='detailed',
                        help='Nsight Compute section set: basic, detailed, full, or a section name')
    parser.add_argument('--out-dir', default='profiles', help='directory for the report files')
    return parser.parse_args(argv)


def find_tool(tool: str) -> str:
    """Locate ncu/nsys: PATH first, then the usual Nsight install directories."""
    name = 'ncu' if tool == 'compute' else 'nsys'
    executable = f'{name}.exe' if common.is_windows() else name

    found = shutil.which(executable)
    if found:
        return found

    pattern = 'Nsight Compute*' if tool == 'compute' else 'Nsight Systems*'
    roots = []
    if common.is_windows():
        roots.append(Path(os.environ.get('ProgramFiles', r'C:\Program Files')) / 'NVIDIA Corporation')
    else:
        roots += [Path('/opt/nvidia'), Path('/usr/local')]

    for root in roots:
        if not root.is_dir():
            continue
        for directory in sorted(root.glob(pattern)):
            for candidate in directory.rglob(executable):
                return str(candidate)

    raise RuntimeError(f"{executable} not found on PATH or under {', '.join(str(root) for root in roots)}; "
                       'install Nsight Compute / Nsight Systems.')


def main(argv=None) -> int:
    args = parse_arguments(argv)
    repo_root = common.REPO_ROOT

    # --- Resolve the executable -------------------------------------------------
    if args.exe:
        exe_path = Path(args.exe)
        if not exe_path.is_absolute():
            exe_path = repo_root / exe_path
    else:
        demos = common.get_demos(repo_root)
        if not demos:
            raise RuntimeError(f'no demos with sources found under {repo_root / "src" / "demos"}')
        selected = common.select_demos(demos, args.demo)[0]
        exe_path = common.resolve_build_dir(args.preset, repo_root) / common.executable_name(selected.name)

    if not exe_path.is_file():
        raise RuntimeError(f'executable not found: {exe_path} '
                           f'(build it first, e.g. python scripts/build_cmake.py --preset {args.preset})')

    out_path = repo_root / args.out_dir
    out_path.mkdir(parents=True, exist_ok=True)

    # --- Locate the requested profiler ------------------------------------------
    tool_path = find_tool(args.tool)
    stamp = datetime.now().strftime('%Y%m%d-%H%M%S')
    base_name = exe_path.stem

    if args.tool == 'compute':
        report = out_path / f'{base_name}-ncu-{stamp}'
        common.step(f'{Path(tool_path).name} --set {args.section}  -> {report}.ncu-rep')
        exit_code = common.run_native([tool_path, '--set', args.section, '--launch-count', '1',
                                       '--export', report, '--force-overwrite', exe_path])
    else:
        report = out_path / f'{base_name}-nsys-{stamp}'
        common.step(f'{Path(tool_path).name} profile  -> {report}.nsys-rep')
        exit_code = common.run_native([tool_path, 'profile', '--force-overwrite', 'true',
                                       '--output', report, exe_path])
        if exit_code == 0:
            common.step(f'{Path(tool_path).name} stats')
            exit_code = common.run_native([tool_path, 'stats', f'{report}.nsys-rep'])

    if exit_code != 0:
        raise RuntimeError(f'{Path(tool_path).name} exited with code {exit_code}')

    common.success(f'report written to {out_path}')
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (RuntimeError, OSError, ValueError) as error:
        common.error(str(error))
        sys.exit(1)
