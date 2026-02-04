#!/usr/bin/env python3
import os
import shutil
import time
from pathlib import Path

# Config
DAYS_TO_KEEP = 30
NOW = time.time()
cutoff = NOW - (DAYS_TO_KEEP * 86400)

DIRS_TO_NUKE = [
    "build",
    "DerivedData",
    "ModuleCache.noindex"
]

DIRS_TO_PRUNE = [
    "reports",
    "runs",
    "../astra/runs"
]

def get_age(path):
    return path.stat().st_mtime

def format_size(size):
    for unit in ['B', 'KB', 'MB', 'GB']:
        if size < 1024:
            return f"{size:.1f}{unit}"
        size /= 1024
    return f"{size:.1f}TB"

def clean_directory():
    total_freed = 0
    root = Path(".")
    
    print("--- Cleaning Temp Files ---")
    # 1. Nuke Build Artifacts
    for pattern in DIRS_TO_NUKE:
        for path in root.rglob(pattern):
            if path.is_dir():
                try:
                    size = sum(f.stat().st_size for f in path.rglob('*') if f.is_file())
                    shutil.rmtree(path)
                    print(f"Deleted {path} ({format_size(size)})")
                    total_freed += size
                except Exception as e:
                    print(f"Error deleting {path}: {e}")

    # 2. Nuke __pycache__ and .DS_Store
    print("\n--- Cleaning Caches ---")
    for path in root.rglob("__pycache__"):
        try:
            shutil.rmtree(path)
            # Rough estimate 
            total_freed += 4096 
        except: pass
        
    for path in root.rglob(".DS_Store"):
        try:
            path.unlink()
        except: pass

    # 3. Prune Old Reports/Runs
    print(f"\n--- Pruning Data Older Than {DAYS_TO_KEEP} Days ---")
    for dir_name in DIRS_TO_PRUNE:
        target_dir = Path(dir_name)
        if not target_dir.exists():
            continue
            
        for item in target_dir.iterdir():
            try:
                if not item.is_dir():
                    continue
                
                age = get_age(item)
                if age < cutoff:
                    size = sum(f.stat().st_size for f in item.rglob('*') if f.is_file())
                    shutil.rmtree(item)
                    print(f"Pruned {item} ({format_size(size)})")
                    total_freed += size
            except (PermissionError, OSError):
                continue
            except Exception as e:
                # print(f"Skipped {item}: {e}")
                pass

    print(f"\nTotal Space Reclaimed: {format_size(total_freed)}")

if __name__ == "__main__":
    clean_directory()
