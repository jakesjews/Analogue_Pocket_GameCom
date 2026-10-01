#!/usr/bin/env python3
"""Create an SD-ready release using only a successful current Quartus build."""
from pathlib import Path
import hashlib
import json
import re
import shutil
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CORE = "jacob.GameCom"


def source_digest():
    digest = hashlib.sha256()
    root = ROOT / "src/fpga"
    for path in sorted(root.rglob("*")):
        if path.suffix not in {".v", ".sv", ".vhd", ".qsf", ".qip", ".sdc", ".hex"}:
            continue
        if any(part in {"db", "incremental_db", "output_files"} for part in path.relative_to(root).parts):
            continue
        digest.update(str(path.relative_to(root)).encode())
        digest.update(path.read_bytes())
    return digest.hexdigest()


def package():
    metadata = json.loads((ROOT / "core.json").read_text())["core"]["metadata"]
    # Pocket derives the core's load path from these fields, even if its menu
    # discovered core.json under a different folder. Catch that before shipping.
    for field in ("author", "shortname"):
        value = metadata[field]
        if not value or len(value) > 31 or any(c in value for c in '/\\:*?"<>|'):
            raise SystemExit(f"Invalid filesystem name in core metadata: {field}")
    identity = f"{metadata['author']}.{metadata['shortname']}"
    if identity != CORE:
        raise SystemExit(f"Core metadata resolves to {identity}, but package folder is {CORE}")
    expected = ROOT / "build/source-at-build-start.sha256"
    if not expected.exists() or expected.read_text().strip() != source_digest():
        raise SystemExit("Source changed during compilation; rebuild before packaging")
    out = ROOT / "src/fpga/output_files"
    summary = (out / "ap_core.flow.rpt").read_text(errors="replace")
    if "Flow Status" not in summary or "Successful -" not in summary:
        raise SystemExit("Refusing to package: Quartus flow was not successful")
    fit = (out / "ap_core.fit.summary").read_text(errors="replace")
    if "Fitter Status : Successful -" not in fit:
        raise SystemExit("Refusing to package: Quartus fitter was not successful")
    timing = (out / "ap_core.sta.summary").read_text(errors="replace")
    slacks = [float(n) for n in re.findall(r"Slack\s*:\s*(-?\d+(?:\.\d+)?)", timing)]
    if not slacks or min(slacks) < 0:
        raise SystemExit("Refusing to package: timing requirements were not met")
    rbf = out / "ap_core.rbf"
    # A stale template binary must never be shipped after a failed compile.
    if rbf.stat().st_mtime < max(p.stat().st_mtime for p in (ROOT / "src/fpga").rglob("*")
                               if p.suffix in {".v", ".sv", ".vhd", ".qsf", ".qip", ".sdc"}
                               and "/db/" not in str(p) and "/incremental_db/" not in str(p)):
        raise SystemExit("Bitstream predates source edits; rebuild first")
    # Users unzip the release onto the SD card root, so everything lives under
    # Cores, Platforms or Assets. Rebuild it from scratch so no stale file
    # from an earlier layout survives.
    release = ROOT / "release"
    shutil.rmtree(release, ignore_errors=True)
    target = release / "Cores" / CORE
    target.mkdir(parents=True)
    table = bytes(int(f"{n:08b}"[::-1], 2) for n in range(256))
    reversed_rbf = rbf.read_bytes().translate(table)
    (target / "bitstream.rbf_r").write_bytes(reversed_rbf)
    (ROOT / "output/bitstream.rbf_r").write_bytes(reversed_rbf)
    for name in ("core", "audio", "video", "input", "data", "variants"):
        source = ROOT / f"{name}.json"
        json.loads(source.read_text())
        shutil.copy2(source, target / source.name)
    shutil.copy2(ROOT / "interact.json", target / "interact.json")
    for name in ("info.txt", "LICENSE", "README.md"):
        shutil.copy2(ROOT / name, target / name)
    shutil.copy2(ROOT / "dist/icon.bin", target / "icon.bin")
    (release / "Platforms/_images").mkdir(parents=True)
    shutil.copy2(ROOT / "dist/platforms/gamecom.json", release / "Platforms/gamecom.json")
    shutil.copy2(ROOT / "dist/platforms/_images/gamecom.bin", release / "Platforms/_images/gamecom.bin")
    (release / "Assets/gamecom/common").mkdir(parents=True)
    manifest = {"core": CORE, "version": metadata["version"],
                "upstream": "96ed90ec865302d5eb5a0aa8336844dbfb4a5342",
                "source_sha256": source_digest(),
                "sof_sha256": hashlib.sha256((out / "ap_core.sof").read_bytes()).hexdigest(),
                "rbf_sha256": hashlib.sha256(rbf.read_bytes()).hexdigest(),
                "rbf_r_sha256": hashlib.sha256(reversed_rbf).hexdigest()}
    (target / "build.json").write_text(json.dumps(manifest, indent=2) + "\n")
    archive = ROOT / "build" / f"{CORE}_{metadata['version']}.zip"
    with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as z:
        # Directories are stored too, so the empty BIOS folder is created.
        for p in sorted(release.rglob("*")):
            z.write(p, p.relative_to(release))
    print(f"Packaged {target}; {archive}")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    import sys
    if "--record-sources" in sys.argv:
        (ROOT / "build/source-at-build-start.sha256").write_text(source_digest() + "\n")
    else:
        package()
