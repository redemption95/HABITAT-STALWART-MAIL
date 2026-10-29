#!/usr/bin/env bash
# One-time setup on the VPS (as root), from a copy of this folder:
#   scp -r habitat-mail root@<vps-ip>:/root/ && ssh root@<vps-ip> 'bash /root/habitat-mail/setup.sh'
# Safe to run again. Needs Docker (installed by Habitat's infra/vps/setup.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT=/opt/habitat-mail
[ "$(id -u)" = 0 ] || { echo "Run as root" >&2; exit 1; }
command -v docker >/dev/null || { echo "Docker is not installed" >&2; exit 1; }

echo "== Files"
install -d -m 755 "$ROOT" "$ROOT/backups"
install -m 644 "$HERE/compose.yml" "$ROOT/compose.yml"
install -m 755 "$HERE/backup.sh" "$HERE/restore.sh" "$ROOT/"
[ -f "$ROOT/backup.env" ] || { install -m 600 "$HERE/backup.env.example" "$ROOT/backup.env"; echo "BACKUP_PASSPHRASE=$(openssl rand -hex 32)" >> "$ROOT/backup.env"; }

echo "== Firewall: mail ports (Docker publishes them; these rules document intent and cover non-Docker paths)"
for p in 25 465 587 993; do ufw allow "$p/tcp" >/dev/null; done

echo "== Start"
docker compose -f "$ROOT/compose.yml" up -d

echo "== Nightly backup (03:00 IST) to Cloudflare R2"
cat > /etc/cron.d/habitat-mail-backup <<CRON
CRON_TZ=Asia/Kolkata
0 3 * * * root $ROOT/backup.sh >> $ROOT/backups/backup.log 2>&1
CRON

cat <<DONE

Mail server started. Next (README.md):
  1. First sign-in password: docker compose -f $ROOT/compose.yml logs stalwart | grep -i -A2 password
  2. Open the admin through an SSH tunnel and follow "Configure".
  3. Fill in the R2 keys in $ROOT/backup.env and keep a copy of BACKUP_PASSPHRASE.
DONE
