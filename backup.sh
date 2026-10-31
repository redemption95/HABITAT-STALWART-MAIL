#!/usr/bin/env bash
# Nightly mail backup: pauses Stalwart for a few seconds (a consistent copy, like a power cut it
# recovers from), archives its config and data, encrypts, copies to Cloudflare R2, keeps 5 days here.
# Senders retry automatically, so nothing is lost during the pause.
set -euo pipefail
ROOT=/opt/habitat-mail
set -a; . "$ROOT/backup.env"; set +a
OUT="$ROOT/backups"
FILE="$OUT/mail-$(date +%Y%m%d-%H%M%S).tar.gz.gpg"
vol() { docker volume inspect -f '{{.Mountpoint}}' "habitat-mail_$1"; }
CONFIG=$(vol config) DATA=$(vol data)

docker compose -f "$ROOT/compose.yml" pause stalwart
trap 'docker compose -f "$ROOT/compose.yml" unpause stalwart' EXIT
tar -C / -czf - "${CONFIG#/}" "${DATA#/}" \
  | gpg --batch --yes --symmetric --cipher-algo AES256 --passphrase "$BACKUP_PASSPHRASE" -o "$FILE"
docker compose -f "$ROOT/compose.yml" unpause stalwart
trap - EXIT
[ -s "$FILE" ] || { echo "Backup is empty" >&2; exit 1; }
echo "Saved $FILE ($(du -h "$FILE" | cut -f1))"

if [ -n "${R2_ACCESS_KEY_ID:-}" ]; then
  export RCLONE_CONFIG_R2_TYPE=s3 RCLONE_CONFIG_R2_PROVIDER=Cloudflare \
    RCLONE_CONFIG_R2_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID" RCLONE_CONFIG_R2_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY" \
    RCLONE_CONFIG_R2_ENDPOINT="https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com" RCLONE_CONFIG_R2_NO_CHECK_BUCKET=true
  rclone copy "$FILE" "r2:$R2_BACKUP_BUCKET/mail/"
  echo "Copied to r2:$R2_BACKUP_BUCKET/mail/"
else
  echo "!! R2 keys not set in $ROOT/backup.env: backup kept on this server only" >&2
fi
find "$OUT" -name 'mail-*.tar.gz.gpg' -mtime +5 -delete
