import os
import zlib
import csv
import argparse
import sys

def compute_crc32(file_path):
    """Compute CRC32 checksum of a file."""
    crc = 0
    try:
        with open(file_path, 'rb') as f:
            while chunk := f.read(8192):
                crc = zlib.crc32(chunk, crc)
        return format(crc & 0xFFFFFFFF, '08X')  # Return as uppercase hex
    except Exception as e:
        return f"ERROR: {e}"

def scan_directory(root_dir, output_csv, extra_columns=None):
    """Recursively scan directory and write CRC32 values to CSV.

    extra_columns: list of additional column names to append to the CSV header.
    """
    extra_columns = extra_columns or []

    with open(output_csv, 'w', newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        # Use canonical CSV headers compatible with CRC-FileOrganizer
        headers = ['FileName', 'Size', 'CRC32', 'Path'] + extra_columns
        writer.writerow(headers)

        for dirpath, _, filenames in os.walk(root_dir):
            for filename in filenames:
                full_path = os.path.join(dirpath, filename)
                crc32 = compute_crc32(full_path)

                try:
                    filesize = os.path.getsize(full_path)
                except OSError:
                    filesize = ''

                # Path: use only the parent folder name as requested
                # Normalize dirpath to remove any trailing slashes so basename() returns the folder name
                norm_dir = os.path.normpath(dirpath)
                parent_folder = os.path.basename(norm_dir)
                if not parent_folder:
                    # Fallback: use the root_dir's basename if normalization produced an empty name
                    parent_folder = os.path.basename(os.path.normpath(root_dir))

                # Prepare row: FileName, Size, CRC32, Path, [extra empty columns]
                row = [filename, filesize, crc32, parent_folder]
                if extra_columns:
                    row.extend([''] * len(extra_columns))

                writer.writerow(row)
                print(f"{filename} ({filesize} bytes) in '{parent_folder}' → {crc32}")


# --- USAGE ---
if __name__ == "__main__":
    # Default paths (can be overridden via CLI)
    default_root = "D:/PornPornPorn/Photo Sets/_Sorted/TeenFuns_com/"
    default_output = "D:/ScanSorting/_98_Logs/crc32_report.csv"

    parser = argparse.ArgumentParser(description="Scan directory and write CRC32 report compatible with CRC-FileOrganizer")
    parser.add_argument("root_dir", nargs="?", default=default_root, help="Root directory to scan (default from script)")
    parser.add_argument("output_csv", nargs="?", default=default_output, help="Output CSV file path")
    parser.add_argument("-c", "--column", action="append", dest="extra_columns",
                        help="Additional column name to append to CSV (can be repeated)")
    args = parser.parse_args()

    try:
        scan_directory(args.root_dir, args.output_csv, extra_columns=args.extra_columns)
        print(f"\n✅ CRC32 report written to: {args.output_csv}")
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)
