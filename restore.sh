#!/usr/bin/env bash
# Restores a mail backup. STOPS the mail server and REPLACES its config and all mailboxes.
#   /opt/habitat-mail/restore.sh <mail-YYYYMMDD-HHMMSS.tar.gz.gpg>
# From R2 first: rclone copy r2:habitat-backups/mail/<file> /opt/habitat-mail/backups/ (variables as in backup.sh)
set -euo pipefail
FILE="${1:?usage: restore.sh <backup file>}"
ROOT=/opt/habitat-mail
set -a; . "$ROOT/backup.env"; set +a
read -r -p "Replace ALL mail with $FILE? Type 'restore' to continue: " answer
[ "$answer" = restore ] || { echo "Cancelled"; exit 1; }

docker compose -f "$ROOT/compose.yml" up --no-start stalwart   # make sure the volumes exist
docker compose -f "$ROOT/compose.yml" stop stalwart
for v in config data; do
  dir=$(docker volume inspect -f '{{.Mountpoint}}' "habitat-mail_$v")
  find "$dir" -mindepth 1 -delete
done
gpg --batch --decrypt --passphrase "$BACKUP_PASSPHRASE" "$FILE" | tar -C / -xzpf -
docker compose -f "$ROOT/compose.yml" up -d stalwart
echo "Restored $FILE"
