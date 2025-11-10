# tpot-attacks

Purpose: structured, stage-based attack scripts for T-Pot lab.  
Structure: see repo tree. All destructive scripts require snapshots and explicit confirmation.

Quick start:
1. Edit `config.yml` targets and verify `output_base`.
2. `chmod +x lib/common.sh stage-recon/recon_only.sh run.sh`
3. Dry-run: `DRY_RUN=true ./run.sh stage-recon/recon_only.sh 10.20.20.5`
4. Real run (confirm snapshots): `./run.sh stage-recon/recon_only.sh 10.20.20.5`

Document each run in your report with the output directory path produced by the run.

Example usage:

# Basic bot behavior (default)
python ssh_brute.py

# Crypto miner profile
python ssh_brute.py  --profile miner

# Reconnaissance-focused
python ssh_brute.py --profile recon

# Use IP from config.yml
python ssh_brute.py --profile iot