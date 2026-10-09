"""Compare a recorded tree with the SHA-256 list of the Mac goldens, file by file.

    python tools/compare.py <reference.sha256[.gz]> <tree> <out>

Writes <out>/report.json and <out>/report.md, and copies every file that differs or is
not in the reference to <out>/files/. Provenance files (manifest.json, SHA256SUMS, .count)
are not compared. Exit status 1 when anything differs.
"""
import gzip
import hashlib
import json
import shutil
import sys
from pathlib import Path

SKIP = {"manifest.json", "SHA256SUMS"}


def main():
    ref_path, tree, out = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
    opener = gzip.open if ref_path.suffix == ".gz" else open
    with opener(ref_path, "rt", encoding="utf-8") as f:
        ref = {p: h for h, p in (line.rstrip("\n").split("  ", 1) for line in f)}
    got = {}
    for p in sorted(tree.rglob("*")):
        rel = p.relative_to(tree).as_posix()
        if p.is_file() and rel not in SKIP and p.name != ".count":
            got[rel] = hashlib.sha256(p.read_bytes()).hexdigest()
    same = [p for p in ref if got.get(p) == ref[p]]
    differ = sorted(p for p in ref if p in got and got[p] != ref[p])
    missing = sorted(p for p in ref if p not in got)
    extra = sorted(p for p in got if p not in ref)
    for p in differ + extra:
        dst = out / "files" / p
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(tree / p, dst)
    out.mkdir(parents=True, exist_ok=True)
    rep = {"reference": ref_path.name, "files": len(ref), "identical": len(same),
           "differ": differ, "missing": missing, "extra": extra}
    (out / "report.json").write_text(json.dumps(rep, indent=1) + "\n", encoding="utf-8")
    md = [f"# {ref_path.name}", "",
          f"{len(same)} of {len(ref)} files bit-identical to the Mac goldens; "
          f"{len(differ)} differ, {len(missing)} missing, {len(extra)} not in the reference.", ""]
    for name, rows in (("Differ", differ), ("Missing", missing), ("Not in the reference", extra)):
        if rows:
            md += [f"## {name}", ""] + [f"- `{p}`" for p in rows[:500]] + [""]
    (out / "report.md").write_text("\n".join(md), encoding="utf-8")
    print(md[2])
    sys.exit(1 if differ or missing or extra else 0)


if __name__ == "__main__":
    main()
