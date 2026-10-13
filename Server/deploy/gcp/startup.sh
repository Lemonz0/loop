#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y docker.io docker-compose-v2 git
systemctl enable --now docker
install -d -m 0755 /opt/loop
install -d -m 0700 /srv/loop
install -d -o 1000 -g 1000 -m 0700 /srv/loop/data /srv/loop/uploads
install -d -m 0700 /srv/loop/caddy-data /srv/loop/caddy-config

# Source is public. Accounts, uploaded media, and secrets are transferred over
# authenticated SSH separately and never placed in VM metadata or Git.
if [ ! -d /opt/loop/source/.git ]; then
    git clone --depth 1 --branch main https://github.com/Lemonz0/loop.git /opt/loop/source
fi
cp /opt/loop/source/Server/deploy/gcp/compose.yml /opt/loop/compose.yml
cp /opt/loop/source/Server/deploy/gcp/Caddyfile /opt/loop/Caddyfile

# Do not create an empty replacement account store before the migration.
if [ -f /srv/loop/.env ] && [ -f /srv/loop/hosting.env ] && [ -f /srv/loop/data/auth.json ]; then
    cd /opt/loop
    docker compose up -d --build
fi
