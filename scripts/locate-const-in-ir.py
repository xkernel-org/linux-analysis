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


def _normalize_ir(s: str) -> str:
    """Strip leading SSA result name, trailing !dbg metadata, and normalize
    all `%N` operand names to `%X` so two structurally identical
    instructions compare equal regardless of register numbering."""
    s = re.sub(r"^\s*%\d+\s*=\s*", "", s)
    s = re.sub(r",?\s*!dbg .*$", "", s)
    s = re.sub(r"%\d+", "%X", s)
    return s.strip()


def locate(ll_path: Path, instruction: str) -> tuple[str | None, int]:
    """Return (function, occurrence) for `instruction` in `ll_path`.

    Occurrence is the 1-based index of the matching line among all lines
    in the same function whose normalized form equals the instruction's
    normalized form. The diff's `<` line is a verbatim copy, so its exact
    text (including unique `%N` and `!dbg !N`) matches exactly one .ll
    line — that pin determines which occurrence we are."""
    exact = instruction.strip()
    body = _normalize_ir(instruction)

    current = None
    count_in_fn = 0
    found_fn = None
    found_idx = 0
    with open(ll_path) as f:
        for line in f:
            m = _FUNC_RE.search(line)
            if m:
                current = m.group(1)
                count_in_fn = 0
                continue
            if line.startswith("}"):
                current = None
                continue
            if _normalize_ir(line.rstrip("\n")) == body:
                count_in_fn += 1
                if line.strip() == exact and found_fn is None:
                    found_fn = current
                    found_idx = count_in_fn
    return found_fn, (found_idx if found_idx else 1)


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


def changed_int(old_line: str, new_line: str):
    """Token-level diff: find the one integer token that changed.

    Returns (old_value_str, new_value_str) or (None, None).
    """
    import difflib
    a = old_line.split()
    b = new_line.split()
    sm = difflib.SequenceMatcher(a=a, b=b, autojunk=False)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag != "replace":
            continue
        # Pair up replaced tokens; find one whose stripped-of-punctuation
        # form is a different integer.
        for k in range(min(i2 - i1, j2 - j1)):
            ot, nt = a[i1 + k], b[j1 + k]
            om = re.search(r"-?\d+", ot)
            nm = re.search(r"-?\d+", nt)
            if om and nm and om.group() != nm.group():
                return om.group(), nm.group()
    return None, None


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
                ov, nv = changed_int(old, new)
                if ov is not None and nv is not None:
                    yield old, ov, nv
            continue
        i += 1




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


def process_mutation(kdir: Path, tunable_dir: Path, m: dict, start_idx: int) -> int:
    """Run one mutation; emit one input.txt per diff hunk.

    Returns the next free index for downstream callers."""
    source_file = m["source_file"]
    defn = m["definition_source_file"]
    sed_pattern = m["sed_pattern"]

    print(f"\n=== {tunable_dir.name}: {source_file} (mutate {defn}) ===",
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

    # 4. Diff and parse all hunks
    diff_text = diff_ll(ll_origin, ll_mutated)
    instructions = list(parse_diff(diff_text))
    if not instructions:
        raise RuntimeError(f"no value-changing diff hunks for {source_file}")

    # 5. Emit one input.txt per hunk
    idx = start_idx
    for instruction, old_val, _new_val in instructions:
        function, occ = locate(ll_origin, instruction)
        opcode = extract_opcode(instruction) or "UNKNOWN"

        write_input(
            tunable_dir / f"{idx}.input.txt",
            source_file=source_file,
            function=function or "UNKNOWN",
            opcode=opcode,
            value=old_val,
            occurrence=occ,
        )
        idx += 1
    return idx


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

    # Clear previously-generated input.txt files (stale numbering otherwise)
    for p in tunable_dir.glob("*.input.txt"):
        p.unlink()

    next_idx = 1
    for m in cfg.get("mutation", []):
        next_idx = process_mutation(kdir, tunable_dir, m, next_idx)


if __name__ == "__main__":
    main()
