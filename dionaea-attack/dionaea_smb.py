#!/usr/bin/env python3
# dionaea_smb_test.py

import yaml
import sys
from pathlib import Path
from smb.SMBConnection import SMBConnection

def load_config(config_path="config.yaml"):
    with open(config_path) as f:
        return yaml.safe_load(f)

def test_smb(targets, output_base, dry_run=False):
    for target in targets:
        print(f"[*] Testing SMB on {target}:445")
        if dry_run:
            print(f"    [DRY RUN] Would connect to {target}:445")
            continue

        try:
            conn = SMBConnection('', '', 'tpot-client', 'dionaea-sim', use_ntlm_v2=True)
            if conn.connect(target, 445, timeout=5):
                print(f"    [+] SMB connected to {target}")
                conn.close()
                success = True
            else:
                print(f"    [-] SMB connection failed")
                success = False
        except Exception as e:
            print(f"    [!] SMB error: {e}")
            success = False

        # Log result
        log_dir = Path(output_base) / "dionaea" / "smb"
        log_dir.mkdir(parents=True, exist_ok=True)
        (log_dir / f"{target.replace('.', '_')}_smb_test.log").write_text(
            f"Success: {success}\nTimestamp: {__import__('datetime').datetime.now()}\n"
        )

if __name__ == "__main__":
    config = load_config()
    test_smb(
        targets=config["targets"],
        output_base=config["output_base"],
        dry_run=config.get("dry_run", False)
    )