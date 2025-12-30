#!/usr/bin/env bash
set -euo pipefail

# Ensure essential tools are present (especially for raw ubuntu images)
export DEBIAN_FRONTEND=noninteractive
if ! command -v curl >/dev/null 2>&1 || ! command -v nginx >/dev/null 2>&1 || [ ! -f /usr/sbin/sshd ]; then
  apt-get update
  apt-get install -y curl nginx openssh-server || true
  # Ensure base64 is available (coreutils) — base images usually include this
  if ! command -v base64 >/dev/null 2>&1; then
    apt-get install -y coreutils || true
  fi
fi

# Ensure SSH directory exists and has correct permissions
mkdir -p /root/.ssh
chmod 700 /root/.ssh

# Install SSH pubkey if provided via mounted file or template var
if [ -f /tmp/id_rsa.pub ]; then
  cp /tmp/id_rsa.pub /root/.ssh/authorized_keys || true
  chown root:root /root/.ssh/authorized_keys || true
  chmod 600 /root/.ssh/authorized_keys || true
elif [ -n "${pubkey_b64}" ]; then
  echo "${pubkey_b64}" | base64 -d > /root/.ssh/authorized_keys
  chmod 600 /root/.ssh/authorized_keys
fi

# Ensure SSH service is running
if [ -f /var/run/sshd.pid ]; then
  rm /var/run/sshd.pid
fi
mkdir -p /var/run/sshd
/usr/sbin/sshd -D &

# Write the web page from base64 input (if provided)
if [ -n "${index_b64}" ]; then
  mkdir -p /usr/share/app
  echo "${index_b64}" | base64 -d > /usr/share/app/index.html || true
  # copy to common web paths if they exist
  if [ -d /usr/share/nginx/html ]; then
    cp /usr/share/app/index.html /usr/share/nginx/html/index.html || true
  fi
  if [ -d /var/www/html ]; then
    cp /usr/share/app/index.html /var/www/html/index.html || true
  fi
  # Start nginx if not running
  if ! pgrep nginx >/dev/null; then
    service nginx start || true
  fi
fi
