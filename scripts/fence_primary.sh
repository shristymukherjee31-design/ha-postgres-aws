#!/usr/bin/env bash
# Fences the old primary by stopping its EC2 instance. Promotion must not
# happen unless the instance is confirmed "stopped" (prevents split brain).
set -euo pipefail
cd "$(dirname "$0")/.."

PRIMARY_ID=$(terraform output -raw primary_instance_id)

echo "Fencing primary: stopping $PRIMARY_ID"
aws ec2 stop-instances --instance-ids "$PRIMARY_ID" > /dev/null
aws ec2 wait instance-stopped --instance-ids "$PRIMARY_ID"

STATE=$(aws ec2 describe-instances --instance-ids "$PRIMARY_ID" \
  --query 'Reservations[0].Instances[0].State.Name' --output text)

if [[ "$STATE" != "stopped" ]]; then
  echo "ABORT: primary state is '$STATE', not 'stopped'. Not promoting."
  exit 1
fi
echo "Primary fenced (state: stopped)."
