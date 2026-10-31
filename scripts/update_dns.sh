#!/usr/bin/env bash
# Points db.internal at the promoted standby and records it in SSM.
set -euo pipefail
cd "$(dirname "$0")/.."

ZONE_ID=$(terraform -chdir=terraform output -raw route53_zone_id)
NEW_IP=$(terraform -chdir=terraform output -raw standby_private_ip)
NEW_ID=$(terraform -chdir=terraform output -raw standby_instance_id)

CHANGE_FILE=$(mktemp)
cat > "$CHANGE_FILE" <<JSON
{
  "Comment": "Failover: point db.internal at the new primary",
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "db.internal",
      "Type": "A",
      "TTL": 10,
      "ResourceRecords": [{"Value": "$NEW_IP"}]
    }
  }]
}
JSON

aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "file://$CHANGE_FILE" > /dev/null
rm -f "$CHANGE_FILE"

aws ssm put-parameter --name /ha-pg/current_primary \
  --value "$NEW_ID" --type String --overwrite > /dev/null

echo "db.internal now points to $NEW_IP (instance $NEW_ID)."
