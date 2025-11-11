#!/usr/bin/env python3
# dionaea_http_test.py

import yaml
import requests
import sys
import os
from pathlib import Path

def load_config(config_path="config.yaml"):
    with open(config_path) as f:
        return yaml.safe_load(f)

def run_http_tests(targets, output_base, dry_run=False):
    paths = ["/", "/phpMyAdmin/", "/.env", "/wp-login.php"]
    
    for target in targets:
        print(f"[*] Testing HTTP on {target}")
        if dry_run:
            print(f"    [DRY RUN] Would request: http://{target}{{path}}")
            continue

        for path in paths:
            try:
                url = f"http://{target}{path}"
                headers = {"User-Agent": "tpot-attack-sim/1.0"}
                resp = requests.get(url, headers=headers, timeout=5)
                print(f"    [+] Requested {url} → {resp.status_code}")
            except Exception as e:
                print(f"    [-] Failed {url}: {e}")

        # Save proof/log (optional)
        log_dir = Path(output_base) / "dionaea" / "http"
        log_dir.mkdir(parents=True, exist_ok=True)
        (log_dir / f"{target.replace('.', '_')}_http_test.log").write_text(
            f"HTTP test completed at {__import__('datetime').datetime.now()}\n"
        )

if __name__ == "__main__":
    config = load_config()
    run_http_tests(
        targets=config["targets"],
        output_base=config["output_base"],
        dry_run=config.get("dry_run", False)
    )