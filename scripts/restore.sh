#!/usr/bin/env bash
# Restores the application database from an S3 backup (default: the latest).
# Usage: ./scripts/restore.sh [backups/appdb-YYYYMMDD-HHMMSS.dump]
# Existing objects in appdb are dropped and recreated from the dump.
set -euo pipefail
cd "$(dirname "$0")/.."

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"
BUCKET=$(terraform output -raw backup_bucket)
KEY="${1:-backups/latest.dump}"
APP_PW=$(awk -F'"' '/^app_password/ {print $2}' ansible/group_vars/all/secrets.yml)
if [[ -z "$APP_PW" ]]; then
  echo "ERROR: app_password not found in ansible/group_vars/all/secrets.yml"
  exit 1
fi

if ! aws s3api head-object --bucket "$BUCKET" --key "$KEY" > /dev/null 2>&1; then
  echo "ERROR: s3://$BUCKET/$KEY does not exist."
  exit 1
fi

echo "Restoring s3://$BUCKET/$KEY into appdb via db.internal"

# First line on stdin is the password, the rest is the dump itself.
{ printf '%s\n' "$APP_PW"; aws s3 cp "s3://$BUCKET/$KEY" - --only-show-errors; } \
  | ssh $SSH_OPTS bastion \
    'read -r PGPASSWORD; export PGPASSWORD; pg_restore -h db.internal -U appuser -d appdb --clean --if-exists --no-owner --exit-on-error'

echo "Restore complete."
