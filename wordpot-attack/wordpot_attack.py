#!/usr/bin/env python3
"""
wordpot_attack.py
Simulates WordPress reconnaissance and exploit attempts that Wordpot detects.
- Uses config.yaml for targets, output_base, dry_run
- Sends safe GET/POST requests that match known attack signatures
- Does NOT execute real exploits or shellcode
"""

import yaml
import requests
import sys
from pathlib import Path
from datetime import datetime


def load_config(config_path="config.yml"):
    """Load config.yaml from repo root."""
    try:
        with open(config_path, 'r') as f:
            return yaml.safe_load(f)
    except FileNotFoundError:
        print(f"❌ config.yaml not found at {config_path}")
        sys.exit(1)


def run_wordpot_tests(targets, output_base, dry_run=False):
    headers = {
        "User-Agent": "Mozilla/5.0 (compatible; WPScan-like; +https://wpscan.com/)",
        "Accept": "*/*"
    }

    attacks = [
        # --- GET Probes (common reconnaissance) ---
        {"method": "GET", "path": "/"},
        {"method": "GET", "path": "/wp-login.php"},
        {"method": "GET", "path": "/wp-admin/"},
        {"method": "GET", "path": "/readme.html"},          # version leak
        {"method": "GET", "path": "/license.txt"},
        {"method": "GET", "path": "/xmlrpc.php"},
        {"method": "GET", "path": "/wp-content/plugins/hello.php"},
        {"method": "GET", "path": "/wp-content/plugins/akismet/akismet.php"},
        {"method": "GET", "path": "/wp-content/plugins/revslider/settings/"},
        
        # --- POST: RevSlider LFI (detected by param 'action=revslider_show_image') ---
        {
            "method": "POST",
            "path": "/wp-admin/admin-ajax.php",
            "data": {"action": "revslider_show_image", "img": "test.jpg"}
        },
        
        # --- POST: xmlrpc introspection (common scanner behavior) ---
        {
            "method": "POST",
            "path": "/xmlrpc.php",
            "data": "<?xml version=\"1.0\"?><methodCall><methodName>system.listMethods</methodName></methodCall>",
            "headers": {"Content-Type": "text/xml"}
        },
        
        # --- POST: Hello Dolly RCE pattern (detected by param 'ip' with shell chars) ---
        {
            "method": "POST",
            "path": "/wp-content/plugins/hello.php",
            "data": {"ip": "127.0.0.1; id"}
        }
    ]

    for target in targets:
        print(f"[*] Simulating WordPress attacks on http://{target}")
        results = []

        for attack in attacks:
            url = f"http://{target}{attack['path']}"
            method = attack["method"]
            
            if dry_run:
                print(f"    [DRY RUN] {method} {url}")
                continue

            try:
                if method == "POST":
                    resp = requests.post(
                        url,
                        data=attack.get("data", {}),
                        headers={**headers, **attack.get("headers", {})},
                        timeout=5
                    )
                    status = resp.status_code
                    print(f"    [+] POST {url} → {status}")
                    results.append(f"POST {url} | {status}")
                else:
                    resp = requests.get(url, headers=headers, timeout=5)
                    status = resp.status_code
                    print(f"    [+] GET  {url} → {status}")
                    results.append(f"GET  {url} | {status}")
            except Exception as e:
                error_msg = f"{method} {url} | ERROR: {e}"
                print(f"    [-] {error_msg}")
                results.append(error_msg)

        # Save log
        log_dir = Path(output_base) / "wordpot"
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / f"{target.replace('.', '_')}_wordpot_attack.log"
        log_file.write_text(
            f"Wordpot attack simulation - {datetime.now()}\n" +
            "\n".join(results) + "\n"
        )
        print(f"    [LOG] Saved to {log_file}\n")


if __name__ == "__main__":
    config = load_config()
    run_wordpot_tests(
        targets=config["targets"],
        output_base=config["output_base"],
        dry_run=config.get("dry_run", False)
    )