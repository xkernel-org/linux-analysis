#!/usr/bin/env python3

"""
Run the analysis for all <input-dir>/*/*.input.txt files in parallel
"""

import os
import sys
import glob
import subprocess
import argparse
from pathlib import Path
from datetime import datetime
from multiprocessing import Pool, cpu_count
from typing import Tuple, Optional

def log_info(msg: str):
    """Print info message"""
    print(f"[INFO] {msg}")

def log_success(msg: str):
    """Print success message"""
    print(f"[SUCCESS] {msg}")

def log_error(msg: str):
    """Print error message"""
    print(f"[ERROR] {msg}", file=sys.stderr)

def log_warning(msg: str):
    """Print warning message"""
    print(f"[WARNING] {msg}")

def check_prerequisites(kernel_dir: Path) -> bool:
    """Check if all prerequisites are met"""
    if not kernel_dir.exists():
        log_error(f"KERNEL_DIR does not exist: {kernel_dir}")
        return False
    return True

def parse_input_file(input_file: Path) -> dict:
    """Parse the input file to extract variables"""
    variables = {}
    with open(input_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('#'):
                continue
            if '=' in line:
                # Simple parsing for bash variable assignments
                key, value = line.split('=', 1)
                # Remove inline comments (everything after #)
                if '#' in value:
                    value = value.split('#', 1)[0]
                # Remove quotes if present
                value = value.strip().strip('"').strip("'")
                variables[key] = value
    return variables

def process_input_file(args: Tuple[Path, int, int, str, dict]) -> Tuple[str, bool, Optional[str]]:
    """
    Process a single input file

    Args:
        args: Tuple of (input_file, current_index, total, date_start, config)

    Returns:
        Tuple of (input_file_str, success, error_message)
    """
    input_file, current, total, date_start, config = args

    kernel_dir = Path(config['kernel_dir'])

    interproc = config['interproc']
    upward_interproc = config['upward_interproc']
    indirect_call = config['indirect_call']
    # whole_kernel = config['whole_kernel']

    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    log_info(f"[{current}/{total}] {input_file}, {date_start} -> {now}")

    try:
        # Parse input file
        variables = parse_input_file(input_file)

        source_file = variables.get('SOURCE_FILE', '')
        function_name = variables.get('FUNCTION_NAME', '')
        source_op = variables.get('SOURCE_OP', '')
        constant_value = variables.get('CONSTANT_VALUE', '')
        occurrence = variables.get('OCCURENCE', '')

        # Setup output files
        output_file = input_file.parent / f"{input_file.stem.replace('.input', '')}.output.txt"
        time_statistics = input_file.parent / f"{input_file.stem.replace('.input', '')}.time.txt"

        # Skip if output file already exists
        if output_file.exists():
            log_info(f"[{current}/{total}] Skipping {input_file} - output already exists")
            return (str(input_file), True, None)

        # Setup bitcode files
        source_path = Path(source_file)
        # obj_file = source_path.with_suffix('.o')
        # bc_file = source_path.with_suffix('.bc')
        ll_file = source_path.with_suffix('.ll')
        vmlinux_bc = kernel_dir / 'vmlinux-xk-dataset.bc'

        # Compile if not using whole kernel
        # if not whole_kernel:
        #     os.chdir(kernel_dir)
        #     if obj_file.exists():
        #         obj_file.unlink()
        #
        #     make_cmd = [
        #         'make',
        #         'CC=wllvm',
        #         'AR=llvm-ar',
        #         'HOSTCC=clang',
        #         str(obj_file)
        #     ]
        #     subprocess.run(make_cmd, check=True, capture_output=True)
        #
        #     extract_cmd = ['extract-bc', str(obj_file), '-o', str(bc_file)]
        #     subprocess.run(extract_cmd, check=True, capture_output=True)
        #
        #     llvm_dis_cmd = ['llvm-dis', str(bc_file), '-o', str(ll_file)]
        #     subprocess.run(llvm_dis_cmd, check=True, capture_output=True)

        # Determine input BC file
        # if whole_kernel:
        #     input_bc_file = vmlinux_bc
        # else:
        #     input_bc_file = kernel_dir / bc_file

        input_bc_file = vmlinux_bc

        # Build the opt command
        pass_args = f"{function_name};{source_op};{constant_value};false;{interproc};{indirect_call};{upward_interproc};{occurrence};true"
        opt_cmd = [
            '/usr/bin/time', '-o', str(time_statistics), '-v',
            'opt',
            f'-load-pass-plugin={config["plugin"]}',
            f'-passes=taint-tracker<{pass_args}>',
            '-disable-output',
            str(input_bc_file)
        ]

        # Run the analysis
        with open(output_file, 'w') as out_f:
            result = subprocess.run(
                opt_cmd,
                stdout=out_f,
                stderr=subprocess.STDOUT,
                cwd=config['cwd']
            )

            # Append additional info
            out_f.write(f"\n{kernel_dir / ll_file}\n")
            out_f.write(f"{kernel_dir / source_file}\n")

        if result.returncode != 0:
            return (str(input_file), False, f"opt command failed with exit code {result.returncode}")

        now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        log_success(f"[{current}/{total}] Completed {input_file} at {now}")
        return (str(input_file), True, None)

    except Exception as e:
        return (str(input_file), False, str(e))

def main():
    repo_root = Path(__file__).resolve().parents[1]
    default_dataset = repo_root / 'dataset'
    default_plugin = repo_root / 'passes' / 'build' / 'libTaintTrackerPass.so'

    parser = argparse.ArgumentParser(
        description='Run kernel analysis in parallel on multiple input files'
    )
    parser.add_argument(
        '-j', '--jobs',
        type=int,
        default=50,
        help=f'Number of parallel jobs (default: 50)'
    )
    parser.add_argument(
        '--linux-wllvm',
        type=str,
        default=os.environ.get('LINUX_WLLVM'),
        help='wllvm tree containing vmlinux-xk-dataset.bc (default: $LINUX_WLLVM)'
    )
    # Kept for backward compatibility; --linux-wllvm is preferred.
    parser.add_argument(
        '--kernel-dir',
        type=str,
        default=None,
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        '--input-dir',
        type=str,
        default=str(default_dataset),
        help=f'dataset/ root containing <name>/*.input.txt (default: {default_dataset})'
    )
    parser.add_argument(
        '--plugin',
        type=str,
        default=str(default_plugin),
        help=f'libTaintTrackerPass.so (default: {default_plugin})'
    )
    parser.add_argument(
        '--no-interproc',
        action='store_true',
        help='Disable interprocedural analysis'
    )
    parser.add_argument(
        '--no-upward-interproc',
        action='store_true',
        help='Disable upward interprocedural analysis'
    )
    parser.add_argument(
        '--no-indirect-call',
        action='store_true',
        help='Disable indirect call analysis'
    )

    args = parser.parse_args()

    if args.kernel_dir and not args.linux_wllvm:
        args.linux_wllvm = args.kernel_dir
    if not args.linux_wllvm:
        parser.error("--linux-wllvm is required (or set $LINUX_WLLVM)")
    if not os.path.exists(args.plugin):
        parser.error(f"plugin not found: {args.plugin}\n"
                     f"Build it: cmake -S {repo_root}/passes -B {repo_root}/passes/build && "
                     f"cmake --build {repo_root}/passes/build")

    kernel_dir = Path(args.linux_wllvm)

    input_dir = Path(args.input_dir)

    # Check prerequisites
    if not check_prerequisites(kernel_dir):
        return 1

    # Find all input files
    input_pattern = f'{input_dir}/*/*.input.txt'
    input_files = sorted(glob.glob(input_pattern))

    if not input_files:
        log_error(f"No input files found matching {input_pattern}")
        return 1

    total = len(input_files)
    log_info(f"Found {total} input files to process")
    log_info(f"Using {args.jobs} parallel jobs")

    # Configuration
    config = {
        'kernel_dir': str(kernel_dir),
        'plugin': args.plugin,
        'interproc': 'true' if not args.no_interproc else 'false',
        'upward_interproc': 'true' if not args.no_upward_interproc else 'false',
        'indirect_call': 'true' if not args.no_indirect_call else 'false',
        'cwd': os.getcwd()
    }

    date_start = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    print(f"\nStarting parallel processing at {date_start}\n")

    # Prepare arguments for each job
    job_args = [
        (Path(input_file), idx + 1, total, date_start, config)
        for idx, input_file in enumerate(input_files)
    ]

    # Process in parallel
    results = []
    failed = []

    with Pool(processes=args.jobs) as pool:
        for result in pool.imap_unordered(process_input_file, job_args):
            results.append(result)
            input_file, success, error_msg = result
            if not success:
                failed.append((input_file, error_msg))

    date_end = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    # Print summary
    print(f"\n{'=' * 80}")
    print(f"All jobs completed!")
    print(f"Started:  {date_start}")
    print(f"Finished: {date_end}")
    print()

    success_count = len(results) - len(failed)

    if failed:
        log_warning("Failed jobs:")
        for input_file, error_msg in failed:
            print(f"  {input_file}")
            if error_msg:
                print(f"    {error_msg}")

    print()
    print(f"Summary: {success_count} succeeded, {len(failed)} failed out of {total} total")
    print('=' * 80)

    return 1 if failed else 0

if __name__ == '__main__':
    sys.exit(main())
