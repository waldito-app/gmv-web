#!/usr/bin/env python3
"""Offline editorial renderer. Requires Poppler pdftoppm and Pillow.
Never run inside the public site directory; no network or credentials needed.
"""
import argparse
import json
import shutil
import subprocess
import tempfile
import uuid
from pathlib import Path
from PIL import Image

def render(source, destination, book_id, dpi=144, quality=82):
    book_id = str(uuid.UUID(book_id))
    source = Path(source).resolve(strict=True)
    destination = Path(destination).resolve()
    if destination.exists():
        raise FileExistsError("Use a new private output directory")
    if not 72 <= dpi <= 240 or not 1 <= quality <= 95:
        raise ValueError("Invalid rendering settings")
    if not shutil.which("pdftoppm"):
        raise RuntimeError("Install Poppler locally")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
        root = Path(temp)
        stage = root / "output"
        pages = stage / book_id
        pages.mkdir(parents=True)
        subprocess.run(["pdftoppm", "-r", str(dpi), "-png", str(source),
                        str(root / "page")], check=True)
        files = sorted(root.glob("page-*.png"),
                       key=lambda p: int(p.stem.rsplit("-", 1)[1]))
        if not files:
            raise ValueError("No pages rendered")
        rows = []
        for i, path in enumerate(files, 1):
            if int(path.stem.rsplit("-", 1)[1]) != i:
                raise ValueError("Non-contiguous PDF pages")
            target = pages / f"{i}.webp"
            with Image.open(path) as img:
                img = img.convert("RGB")
                img.save(target, "WEBP", quality=quality, method=4)
                width, height = img.size
            with Image.open(target) as check:
                check.verify()
            rows.append(dict(book_id=book_id, ordinal=i,
                             object_name=f"{book_id}/{i}.webp",
                             width_px=width, height_px=height))
        (stage / "manifest.json").write_text(
            json.dumps(rows, indent=2), encoding="utf-8")
        total = sum(p.stat().st_size for p in pages.iterdir())
        stage.rename(destination)
    return {"pages": len(rows), "bytes": total, "first_page": 1,
            "last_page": len(rows)}

if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("pdf")
    p.add_argument("output")
    p.add_argument("book_id")
    p.add_argument("--dpi", type=int, default=144)
    p.add_argument("--quality", type=int, default=82)
    a = p.parse_args()
    print(json.dumps(render(a.pdf, a.output, a.book_id, a.dpi, a.quality)))
