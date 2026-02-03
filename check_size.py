
import os
from pathlib import Path

def get_size(start_path = '.'):
    total_size = 0
    for dirpath, dirnames, filenames in os.walk(start_path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            # skip if it is symbolic link
            if not os.path.islink(fp):
                total_size += os.path.getsize(fp)

    return total_size

print("Scanning for large directories...")
for root in [".", "../astra"]:
    print(f"--- Scanning {root} ---")
    p = Path(root).resolve()
    for item in p.iterdir():
        if item.is_dir():
            size_mb = get_size(str(item)) / (1024 * 1024)
            if size_mb > 1:
                print(f"{item.name}: {size_mb:.2f} MB")
