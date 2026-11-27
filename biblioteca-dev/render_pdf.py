#!/usr/bin/env python3
"""Offline editorial renderer. Requires Poppler pdftoppm and Pillow.
Never run inside the public site directory; no network or credentials needed.
"""
import argparse
import json
import os
import re
import time
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
    repo = Path(__file__).resolve().parents[1]
    if any(p == repo or repo in p.parents for p in (source, destination)):
        raise ValueError("Keep PDF and rendered pages outside the repository")
    if not source.is_file():
        raise ValueError("Expected a regular PDF file")
    if destination.exists():
        raise FileExistsError("Use a new private output directory")
    if not 72 <= dpi <= 240 or not 1 <= quality <= 95:
        raise ValueError("Invalid rendering settings")
    if not all(shutil.which(x) for x in ("pdftoppm", "pdfinfo")):
        raise RuntimeError("Install Poppler locally")
    info = subprocess.run(["pdfinfo", str(source)], check=True,
                          capture_output=True, text=True, timeout=30,
                          env={**os.environ, "LC_ALL": "C"})
    match = re.search(r"^Pages:\s+(\d+)\s*$", info.stdout, re.MULTILINE)
    if not match or int(match.group(1)) < 1:
        raise ValueError("Cannot determine PDF page count")
    count = int(match.group(1))
    destination.parent.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + 3600
    with tempfile.TemporaryDirectory(dir=destination.parent) as temp:
        root = Path(temp)
        stage = root / "output"
        pages = stage / book_id
        pages.mkdir(parents=True)
        rows = []
        for i in range(1, count + 1):
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Rendering time budget exceeded")
            prefix = root / "page"
            subprocess.run(["pdftoppm", "-f", str(i), "-l", str(i),
                            "-singlefile", "-r", str(dpi), "-scale-to", "3000",
                            "-png", str(source), str(prefix)], check=True,
                           timeout=min(120, remaining))
            path = prefix.with_suffix(".png")
            target = pages / f"{i}.webp"
            with Image.open(path) as img:
                img = img.convert("RGB")
                img.save(target, "WEBP", quality=quality, method=4)
                width, height = img.size
            with Image.open(target) as check:
                check.verify()
            path.unlink()
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
