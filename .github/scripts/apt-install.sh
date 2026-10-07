#!/usr/bin/env bash
set -euo pipefail

if [[ $# -eq 0 ]]; then
  echo "No packages requested"
  exit 0
fi

export DEBIAN_FRONTEND="${DEBIAN_FRONTEND:-noninteractive}"

sudo systemctl stop apt-daily.timer apt-daily-upgrade.timer unattended-upgrades.service 2>/dev/null || true
sudo systemctl kill --kill-who=all apt-daily.service apt-daily-upgrade.service unattended-upgrades.service 2>/dev/null || true
sudo killall -9 unattended-upgr unattended-upgrade apt-get apt 2>/dev/null || true

echo 'Acquire::ForceIPv4 "true";' | sudo tee /etc/apt/apt.conf.d/99force-ipv4 >/dev/null

apt_opts=(
  -o Acquire::Retries=3
  -o Acquire::http::Timeout=15
  -o Acquire::https::Timeout=15
  -o Acquire::ftp::Timeout=15
  -o Acquire::http::Pipeline-Depth=0
  -o DPkg::Lock::Timeout=30
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confold
)

install_packages() {
  sudo timeout -k 5 60 apt-get "${apt_opts[@]}" update -y &&
    sudo timeout -k 5 180 apt-get "${apt_opts[@]}" install -y --no-install-recommends "$@"
}

for attempt in 1 2 3; do
  echo "Installing system packages (attempt ${attempt}/3): $*"
  if install_packages "$@"; then
    exit 0
  fi
  echo "apt-get failed on attempt ${attempt}; retrying..."
  sudo killall -9 apt-get apt 2>/dev/null || true
  sleep $((attempt * 5))
done

echo "Failed to install system packages after 3 attempts"
exit 1
