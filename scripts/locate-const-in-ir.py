#!/usr/bin/env python3
"""
Phase B: locate the IR occurrence of a perf-const.

For one tunable name, reads dataset/<TUNABLE>/mutation.toml and produces
dataset/<TUNABLE>/<idx>.input.txt for each [[mutation]] entry.

Mechanism:
  1. wllvm-build the source file -> origin .ll
  2. sed-mutate the definition header, wllvm-build again -> mutated .ll
  3. diff the .ll files; the changed instruction names the (function,
     opcode, value, occurrence) tuple consumed by ss-analysis.

Requires $LINUX_WLLVM to be configured (run scripts/build-with-wllvm.sh
first; the build does not need to have completed past `make olddefconfig`).
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DATASET_DIR = REPO_ROOT / "dataset"


def run(cmd, cwd=None, check=True, capture=False):
    print(f"$ {' '.join(str(c) for c in cmd)}", file=sys.stderr)
    return subprocess.run(
        cmd, cwd=cwd, check=check,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
    )


def build_obj_to_ll(kdir: Path, source_file: str) -> Path:
    """Build <source_file> with wllvm; return the .ll path (in kdir)."""
    src = Path(source_file)
    obj = src.with_suffix(".o")
    bc = src.with_suffix(".bc")
    ll = src.with_suffix(".ll")

    (kdir / obj).unlink(missing_ok=True)
    run(["make", "CC=wllvm", "AR=llvm-ar", "HOSTCC=clang", str(obj)], cwd=kdir)
    run(["extract-bc", str(obj), "-o", str(bc)], cwd=kdir)
    run(["llvm-dis", str(bc), "-o", str(ll)], cwd=kdir)
    return kdir / ll


def diff_ll(origin: Path, mutated: Path) -> str:
    """Diff two .ll files, ignoring metadata noise (!N nodes, #dbg_value).

    Returns the raw `diff` output (mode `-` non-unified)."""
    def filtered(path):
        with open(path) as f:
            for line in f:
                s = line.rstrip("\n")
                if re.match(r"^![0-9]", s.lstrip()):
                    continue
                if "#dbg_value" in s:
                    continue
                yield s + "\n\n"

    a = "".join(filtered(origin))
    b = "".join(filtered(mutated))

    proc = subprocess.run(
        ["diff", "-", "/dev/stdin"], input=a, text=True, capture_output=True,
    )
    # `diff` exits 1 when files differ — that's the expected case
    if proc.returncode > 1:
        raise RuntimeError(f"diff failed: {proc.stderr}")

    # The above is inconvenient (can't pass two stdins). Use temp files.
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".a") as fa, \
         tempfile.NamedTemporaryFile("w", suffix=".b") as fb:
        fa.write(a); fa.flush()
        fb.write(b); fb.flush()
        proc = subprocess.run(
            ["diff", fa.name, fb.name], text=True, capture_output=True,
        )
        if proc.returncode > 1:
            raise RuntimeError(f"diff failed: {proc.stderr}")
        return proc.stdout


_FUNC_RE = re.compile(r"define\s+[^@]*@([a-zA-Z0-9_.]+)\s*\(")


def find_function_for_instruction(ll_path: Path, instruction: str) -> str | None:
    """Walk the .ll file; return the function whose body contains the line."""
    var_match = re.match(r"^\s*(%\d+)\s*=", instruction)
    needle = f"{var_match.group(1)} =" if var_match else " ".join(instruction.split()[:3])

    current = None
    with open(ll_path) as f:
        for line in f:
            m = _FUNC_RE.search(line)
            if m:
                current = m.group(1)
            if needle in line and instruction.strip() in line:
                return current
    return None


def extract_opcode(instruction: str) -> str | None:
    m = re.search(r"%\d+\s*=\s*(?:tail\s+)?(call)", instruction)
    if m:
        return m.group(1)
    m = re.search(r"%\d+\s*=\s*(\w+)", instruction)
    if m:
        return m.group(1)
    m = re.match(r"^\s*(\w+)", instruction)
    if m:
        return m.group(1)
    return None


_VAL_RE = re.compile(r"(?:,|\s)\s*(-?\d+)\s*(?:[,)]|$)")


def parse_diff(diff_output: str):
    """Yield (instruction, old_value, new_value) for each `NcM` block."""
    lines = diff_output.splitlines()
    i = 0
    while i < len(lines):
        if re.match(r"^\d+(?:,\d+)?c\d+(?:,\d+)?$", lines[i].strip()):
            i += 1
            old, new = None, None
            while i < len(lines) and lines[i].startswith("<"):
                old = lines[i][1:].strip()
                i += 1
            if i < len(lines) and lines[i].strip() == "---":
                i += 1
            while i < len(lines) and lines[i].startswith(">"):
                new = lines[i][1:].strip()
                i += 1
            if old and new:
                om = _VAL_RE.search(old)
                nm = _VAL_RE.search(new)
                if om and nm:
                    yield old, om.group(1), nm.group(1)
            continue
        i += 1


def occurrence_of(ll_path: Path, function: str, instruction: str) -> int:
    """How many times does `instruction` (after var renumbering) appear in
    `function`? For now we use the trailing-tokens hash: drop the `%N =`
    prefix and the trailing !dbg metadata, then count exact matches inside
    the function body."""
    body_pat = re.sub(r"^\s*%\d+\s*=\s*", "", instruction)
    body_pat = re.sub(r",?\s*!dbg .*$", "", body_pat).strip()

    in_fn = False
    count = 0
    matched_index = 0
    saw = 0
    with open(ll_path) as f:
        for line in f:
            m = _FUNC_RE.search(line)
            if m:
                in_fn = (m.group(1) == function)
                continue
            if not in_fn:
                continue
            if line.startswith("}"):
                in_fn = False
                continue
            stripped = re.sub(r"^\s*%\d+\s*=\s*", "", line.rstrip("\n"))
            stripped = re.sub(r",?\s*!dbg .*$", "", stripped).strip()
            if stripped == body_pat:
                count += 1
                if instruction.strip() in line:
                    matched_index = count
    # If the exact instruction matched once, occurrence is its index; otherwise 1
    return matched_index if matched_index else 1


def write_input(out_path: Path, *, source_file: str, function: str,
                opcode: str, value: str, occurrence: int) -> None:
    text = (
        f"SOURCE_FILE={source_file}\n"
        f"FUNCTION_NAME={function}\n"
        f'SOURCE_OP="{opcode}"\n'
        f"CONSTANT_VALUE={value}\n"
        f"OCCURENCE={occurrence}\n"
    )
    out_path.write_text(text)
    print(f"wrote {out_path}", file=sys.stderr)
    print(text, file=sys.stderr)


def process_mutation(kdir: Path, tunable_dir: Path, m: dict) -> None:
    idx = m["index"]
    source_file = m["source_file"]
    defn = m["definition_source_file"]
    sed_pattern = m["sed_pattern"]

    print(f"\n=== {tunable_dir.name} mutation #{idx}: {source_file} ===",
          file=sys.stderr)

    # 1. Build origin
    ll = build_obj_to_ll(kdir, source_file)
    ll_origin = ll.with_suffix(".ll.origin")
    shutil.move(str(ll), str(ll_origin))

    # 2. Mutate definition file
    defn_path = kdir / defn
    backup = defn_path.with_suffix(defn_path.suffix + ".bak")
    shutil.copy2(defn_path, backup)
    try:
        run(["sed", "-i", sed_pattern, str(defn_path)])
        # Confirm the sed actually changed something
        if subprocess.run(["diff", "-q", str(backup), str(defn_path)],
                          capture_output=True).returncode == 0:
            raise RuntimeError(
                f"sed_pattern matched nothing in {defn}: {sed_pattern!r}")

        # 3. Build mutated
        ll_m = build_obj_to_ll(kdir, source_file)
        ll_mutated = ll_m.with_suffix(".ll.mutated")
        shutil.move(str(ll_m), str(ll_mutated))
    finally:
        shutil.move(str(backup), str(defn_path))

    # 4. Diff and parse
    diff_text = diff_ll(ll_origin, ll_mutated)
    instructions = list(parse_diff(diff_text))
    if not instructions:
        raise RuntimeError(f"no value-changing diff hunks for {source_file}")

    # 5. Pick the first hunk; emit input.txt
    instruction, old_val, _new_val = instructions[0]
    function = find_function_for_instruction(ll_origin, instruction) or "UNKNOWN"
    opcode = extract_opcode(instruction) or "UNKNOWN"
    occ = occurrence_of(ll_origin, function, instruction)

    write_input(
        tunable_dir / f"{idx}.input.txt",
        source_file=source_file,
        function=function,
        opcode=opcode,
        value=old_val,
        occurrence=occ,
    )

    if len(instructions) > 1:
        print(f"note: {len(instructions)} hunks total; emitted only #1",
              file=sys.stderr)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("tunable", help="Tunable name, e.g. BLK_MAX_REQUEST_COUNT")
    ap.add_argument("--kdir", default=os.environ.get("LINUX_WLLVM"),
                    help="wllvm kernel tree (defaults to $LINUX_WLLVM)")
    args = ap.parse_args()

    if not args.kdir:
        ap.error("set $LINUX_WLLVM or pass --kdir")
    kdir = Path(args.kdir).expanduser().resolve()
    if not (kdir / ".config").exists():
        ap.error(f"{kdir}/.config missing — run scripts/build-with-wllvm.sh first")

    tunable_dir = DATASET_DIR / args.tunable
    spec = tunable_dir / "mutation.toml"
    if not spec.exists():
        ap.error(f"{spec} not found")

    with open(spec, "rb") as f:
        cfg = tomllib.load(f)

    for m in cfg.get("mutation", []):
        process_mutation(kdir, tunable_dir, m)


if __name__ == "__main__":
    main()
