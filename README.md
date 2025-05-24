# PISworm - Raspberry Pi Docker Swarm Cluster Manager

A modular, headless Bash script system to automatically discover, configure, and manage a Docker Swarm cluster of Raspberry Pis.

## Features

- Automatic Pi discovery using MAC address detection
- Static IP configuration and network setup
- Secure SSH configuration and validation
- Docker Swarm initialization and configuration
- Portainer deployment for web-based management
- Optional monitoring stack with Prometheus and Grafana
- Modular design for easy extension

## Prerequisites

- Raspberry Pis running Raspberry Pi OS (64-bit recommended)
- SSH enabled on all Pis (`sudo raspi-config`)
- Required packages on control node:
  ```bash
  sudo apt update
  sudo apt install -y sshpass nmap docker.io yq
  ```

## Folder Structure

PISworm/
├── swarm-cluster.sh      # Main script
├── config.yml           # Configuration file
├── functions/          # Modular function files
│ ├── discover_pis.sh   # Pi discovery
│ ├── setup_pis.sh      # Pi configuration
│ ├── init_swarm.sh     # Swarm initialization
│ └── deploy_services.sh # Service deployment
├── docker-compose.monitoring.yml  # Monitoring stack
└── logs/               # Log output directory


## Usage

1. Edit `config.yml` to match your environment.
2. Ensure your modular scripts exist under `functions/`.
3. Run as root: `sudo ./swarm-cluster.sh`

## Extending

Add new modular scripts to `functions/` and call them from `swarm-cluster.sh`.
