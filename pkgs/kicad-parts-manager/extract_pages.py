#!/usr/bin/env python3
"""Extract pages 90-100 from a PDF file."""

from pathlib import Path
import sys

from pypdf import PdfReader, PdfWriter

def extract_pages(input_path: str, output_path: str, start_page: int, end_page: int):
    """Extract a range of pages from a PDF.

    Args:
        input_path: Path to input PDF
        output_path: Path to output PDF
        start_page: First page to extract (1-indexed)
        end_page: Last page to extract (1-indexed, inclusive)
    """
    reader = PdfReader(input_path)
    writer = PdfWriter()

    total_pages = len(reader.pages)
    print(f"Input PDF has {total_pages} pages")

    # Convert to 0-indexed
    start_idx = start_page - 1
    end_idx = end_page  # end_page is inclusive, so we use it directly for range

    if start_idx < 0 or end_idx > total_pages:
        print(f"Error: Page range {start_page}-{end_page} is out of bounds (1-{total_pages})")
        sys.exit(1)

    print(f"Extracting pages {start_page} to {end_page}...")

    for i in range(start_idx, end_idx):
        writer.add_page(reader.pages[i])

    with open(output_path, "wb") as output_file:
        writer.write(output_file)

    print(f"Saved {end_page - start_page + 1} pages to: {output_path}")

if __name__ == "__main__":
    input_pdf = Path.home() / "Downloads" / "IMXRT1060IEC.pdf"
    output_pdf = Path.home() / "Downloads" / "IMXRT1060IEC_pages_90-100.pdf"

    extract_pages(str(input_pdf), str(output_pdf), 90, 100)
