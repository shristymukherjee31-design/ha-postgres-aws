#!/usr/bin/env bash
# Logical backup of the application database to S3 (pg_dump, custom format).
# The dump runs on the bastion against db.internal, so it always targets the
# current primary, and is streamed through this machine into S3.
set -euo pipefail
cd "$(dirname "$0")/.."

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"
BUCKET=$(terraform output -raw backup_bucket)
APP_PW=$(awk -F'"' '/^app_password/ {print $2}' ansible/group_vars/all/secrets.yml)
if [[ -z "$APP_PW" ]]; then
  echo "ERROR: app_password not found in ansible/group_vars/all/secrets.yml"
  exit 1
fi

KEY="backups/appdb-$(date +%Y%m%d-%H%M%S).dump"
echo "Dumping appdb via db.internal -> s3://$BUCKET/$KEY"

# The password is sent on stdin so it never appears in a command line.
if ! printf '%s\n' "$APP_PW" | ssh $SSH_OPTS bastion \
    'read -r PGPASSWORD; export PGPASSWORD; pg_dump -h db.internal -U appuser -d appdb -Fc' \
    | aws s3 cp - "s3://$BUCKET/$KEY" --only-show-errors; then
  echo "ERROR: backup failed, removing the partial object."
  aws s3 rm "s3://$BUCKET/$KEY" --only-show-errors || true
  exit 1
fi

# Keep a stable pointer to the newest backup for the restore script.
aws s3 cp "s3://$BUCKET/$KEY" "s3://$BUCKET/backups/latest.dump" --only-show-errors

SIZE=$(aws s3api head-object --bucket "$BUCKET" --key "$KEY" --query ContentLength --output text)
echo "Backup complete: s3://$BUCKET/$KEY ($SIZE bytes)"
