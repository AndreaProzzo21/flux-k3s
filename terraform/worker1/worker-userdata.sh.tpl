#!/bin/bash
set -euo pipefail

fallocate -l 2G /swapfile
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
echo '/swapfile none swap sw 0 0' >> /etc/fstab
echo 'vm.swappiness=10' >> /etc/sysctl.conf
sysctl -p

curl -sfL https://get.k3s.io | \
  K3S_URL="https://${master_private_ip}:6443" \
  K3S_TOKEN="${k3s_token}" \
  INSTALL_K3S_EXEC="agent --node-name k3s-worker" sh -