import sys
import subprocess
import tempfile
import os

BLACKLIST_ARGS = ["-x", "*.git*", "*.venv*", "*__pycache__*", "*.DS_Store*", "*DerivedData*", "*venv*", "*env*"]

try:
    tmp_dir = tempfile.gettempdir()
    zip_path = os.path.join(tmp_dir, "FULL_PROJECT_BUNDLE.zip")
    
    # Remove if exists
    if os.path.exists(zip_path):
        os.remove(zip_path)
        
    print(f"Creating zip at {zip_path}...")
    
    # 1. Zip deterministic-website-audit (Current Dir)
    cmd1 = ["zip", "-q", "-r", zip_path, "."] + BLACKLIST_ARGS
    print(f"Running: {' '.join(cmd1)}")
    subprocess.check_call(cmd1)
    
    # 2. Add astra (Sibling Dir)
    # We need to add 'astra' folder to the root of the zip.
    # The clean way is to cd to parent and zip astra, but we can't cd .. easily
    # So we pass absolute path of astra, but we want it relative in zip.
    # 'zip' stores relative paths by default if run locally.
    # If we run 'zip -r zip_path ../astra', it stores '../astra'.
    # We want 'astra/'.
    
    astra_path = os.path.abspath("../astra")
    if os.path.exists(astra_path):
        # We can try using --symlinks if needed, but astra is a repo.
        # Best trick: use -j (junk paths) is bad for recursive.
        # We will attempt to add it by path.
        cmd2 = ["zip", "-q", "-r", zip_path, "../astra"] + BLACKLIST_ARGS
        print(f"Running: {' '.join(cmd2)}")
        subprocess.check_call(cmd2)
    else:
        print(f"Warning: {astra_path} not found.")

    print(f"SUCCESS: Zip created at: {zip_path}")
    print("Please copy it to your Desktop.")

except Exception as e:
    print(f"FAILED: {e}")
    sys.exit(1)
