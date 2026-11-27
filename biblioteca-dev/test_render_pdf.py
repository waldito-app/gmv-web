"""Offline smoke test: python biblioteca-dev/test_render_pdf.py.
Requires Poppler and Pillow with WebP support. Uses synthetic pages only.
"""
import json
import tempfile
import unittest
import uuid
from pathlib import Path
from PIL import Image
from render_pdf import render

class RenderTest(unittest.TestCase):
    def test_manifest_and_page_order(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "synthetic.pdf"
            colors = [(220, 30, 30), (30, 220, 30), (30, 30, 220)]
            images = [Image.new("RGB", (300, 420), c) for c in colors]
            images[0].save(source, save_all=True, append_images=images[1:])
            book = str(uuid.uuid4())
            dest = root / "private"
            result = render(source, dest, book)
            rows = json.loads((dest / "manifest.json").read_text())
            self.assertEqual(result["pages"], 3)
            self.assertEqual([r["ordinal"] for r in rows], [1, 2, 3])
            total = 0
            for row, color in zip(rows, colors):
                self.assertEqual(row["book_id"], book)
                self.assertEqual(row["object_name"], f'{book}/{row["ordinal"]}.webp')
                path = dest / row["object_name"]
                total += path.stat().st_size
                with Image.open(path) as img:
                    self.assertEqual(img.format, "WEBP")
                    self.assertEqual(img.size, (row["width_px"], row["height_px"]))
                    self.assertLessEqual(max(img.size), 3000)
                    pixel = img.getpixel((img.width//2, img.height//2))
                    self.assertTrue(all(abs(a-b)<25 for a,b in zip(pixel,color)))
            self.assertEqual(total, result["bytes"])
            self.assertEqual(sorted(p.suffix for p in dest.rglob("*") if p.is_file()), [".json", ".webp", ".webp", ".webp"])
            with self.assertRaises(FileExistsError):
                render(source, dest, book)
            with self.assertRaises(ValueError):
                render(source, root / "bad", book, dpi=10)
            self.assertFalse((root / "bad").exists())

if __name__ == "__main__":
    unittest.main()
