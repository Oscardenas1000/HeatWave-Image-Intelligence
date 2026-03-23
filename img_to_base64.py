#!/usr/bin/env python3
import argparse
import base64
import mimetypes
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(
        description="Convert an image to Base64 and write it to a text file."
    )
    parser.add_argument("image_path", type=Path, help="Path to the image file")
    parser.add_argument(
        "--data-url",
        action="store_true",
        help="Include data URL prefix (mime + base64)",
    )
    parser.add_argument(
        "-o",
        "--out",
        type=Path,
        default=None,
        help="Output file path (default: <image>.base64.txt)",
    )
    args = parser.parse_args()

    img_path = args.image_path
    if not img_path.exists() or not img_path.is_file():
        raise SystemExit(f"File not found: {img_path}")

    raw = img_path.read_bytes()
    b64 = base64.b64encode(raw).decode("ascii")

    if args.data_url:
        mime_type, _ = mimetypes.guess_type(str(img_path))
        mime_type = mime_type or "application/octet-stream"
        content = f"data:{mime_type};base64,{b64}"
    else:
        content = b64

    out_path = args.out or img_path.with_suffix(img_path.suffix + ".base64.txt")
    out_path.write_text(content, encoding="utf-8")
    print(f"Wrote: {out_path}")


if __name__ == "__main__":
    main()
