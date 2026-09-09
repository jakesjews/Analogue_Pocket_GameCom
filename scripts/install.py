#!/usr/bin/env python3
"""Install the built core and optional local assets without replacing saves."""
from pathlib import Path
import argparse
import hashlib
import shutil
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def write_new_verified(dest, content):
    if dest.exists():
        return
    dest.write_bytes(content)
    if hashlib.sha256(dest.read_bytes()).digest() != hashlib.sha256(content).digest():
        raise SystemExit(f"Verification failed: {dest}")


def install():
    parser = argparse.ArgumentParser()
    parser.add_argument("volume", type=Path)
    parser.add_argument("--assets", type=Path)
    args = parser.parse_args()
    if not (args.volume / "Cores").is_dir() or not (args.volume / "Assets").is_dir():
        raise SystemExit("Not an existing Pocket SD card")
    release = ROOT / "release"
    if not (release / "build.json").exists():
        raise SystemExit("Build and package first")
    backup_root = ROOT / "build/sd-backup" / str(time.time_ns())
    for group in ("Cores", "Platforms"):
        for source in (release / group).rglob("*"):
            if not source.is_file():
                continue
            dest = args.volume / source.relative_to(release)
            dest.parent.mkdir(parents=True, exist_ok=True)
            if dest.exists() and source.read_bytes() != dest.read_bytes():
                backup = backup_root / dest.relative_to(args.volume)
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(dest, backup)
            shutil.copyfile(source, dest)
            if hashlib.sha256(source.read_bytes()).digest() != hashlib.sha256(dest.read_bytes()).digest():
                raise SystemExit(f"Verification failed: {dest}")
    assets = args.volume / "Assets/gamecom/common"
    assets.mkdir(parents=True, exist_ok=True)
    if args.assets:
        bios = args.assets / "boot.rom"
        if bios.stat().st_size != 262144:
            raise SystemExit("BIOS must be exactly 262144 bytes")
        if not (assets / "boot.rom").exists():
            write_new_verified(assets / "boot.rom", bios.read_bytes())
        with zipfile.ZipFile(args.assets / "ROMS.zip") as archive:
            for member in archive.infolist():
                name = Path(member.filename).name
                if name.lower().endswith(".tgc") and not name.startswith("[BIOS]"):
                    dest = assets / name
                    if not dest.exists():
                        write_new_verified(dest, archive.read(member))
        # APF nonvolatile files live under Saves, mirroring the asset location.
        # Preserve an existing console save across all subsequent installations.
        save = args.volume / "Saves/gamecom/common/gamecom.sav"
        save.parent.mkdir(parents=True, exist_ok=True)
        if not save.exists():
            source = args.assets / "memory.sav"
            if not source.exists():
                source = args.assets / "boot1.vhd"
            if source.stat().st_size != 8192:
                raise SystemExit("Console save must be exactly 8192 bytes")
            write_new_verified(save, source.read_bytes())
    print(f"Installed and verified {args.volume / 'Cores/jacob.GameCom'}")


if __name__ == "__main__":
    install()
