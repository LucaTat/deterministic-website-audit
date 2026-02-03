import zipfile
import os
from pathlib import Path

BLACKLIST = {".git", ".venv", "__pycache__", "runs", ".DS_Store", "venv", "env"}

def is_ignored(path_parts):
    return any(p in BLACKLIST for p in path_parts)

def zip_dir(zip_file, source_dir, arcname_prefix):
    source_path = Path(source_dir).resolve()
    if not source_path.exists():
        print(f"Skipping {source_path} (not found)")
        return

    for root, dirs, files in os.walk(source_path):
        # Modify dirs in-place to skip blacklisted
        dirs[:] = [d for d in dirs if d not in BLACKLIST]
        
        for file in files:
            if file in BLACKLIST:
                continue
            
            file_path = Path(root) / file
            rel_path = file_path.relative_to(source_path)
            
            # Skip if any parent part is ignored (double check)
            if is_ignored(rel_path.parts):
                continue
                
            arcname = Path(arcname_prefix) / rel_path
            print(f"Adding {arcname}")
            zip_file.write(file_path, arcname)

import tempfile
output_zip = Path(tempfile.gettempdir()) / "astra_suite.zip"
print(f"Writing to {output_zip}")

with zipfile.ZipFile(output_zip, "w", zipfile.ZIP_DEFLATED) as zf:
    # 1. Add Astra
    zip_dir(zf, "../astra", "astra")
    
    # 2. Add Scope (Current Directory)
    # We must be careful not to include the zip file itself if it's being written here
    zip_dir(zf, ".", "deterministic-website-audit")

print(f"Created {output_zip}")
