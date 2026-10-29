#!/usr/bin/env bash
# Detects the current public IP, then:
#   1. updates my_ip in terraform.tfvars (so Terraform stays consistent), and
#   2. if the bastion security group already exists, replaces its SSH rule.
# Run it before any pipeline or demo, especially after changing networks.
set -euo pipefail
cd "$(dirname "$0")/.."

MY_IP=$(curl -s --max-time 10 https://checkip.amazonaws.com || curl -s --max-time 10 https://ifconfig.me)
MY_IP=$(echo "$MY_IP" | tr -d '[:space:]')
if [[ ! "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: could not detect public IP (got '$MY_IP')"
  exit 1
fi
CIDR="$MY_IP/32"
echo "Current public IP: $MY_IP"

if grep -q '^my_ip' terraform.tfvars 2>/dev/null; then
  sed -i "s#^my_ip.*#my_ip = \"$CIDR\"#" terraform.tfvars
else
  echo "my_ip = \"$CIDR\"" >> terraform.tfvars
fi
echo "terraform.tfvars updated."

SG_ID=$(aws ec2 describe-security-groups \
  --filters Name=group-name,Values=ha-pg-bastion-sg \
  --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null || true)

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
  echo "Bastion security group does not exist yet (first deploy); nothing else to do."
  exit 0
fi

OLD=$(aws ec2 describe-security-groups --group-ids "$SG_ID" \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' --output text)

for c in $OLD; do
  if [[ "$c" != "$CIDR" ]]; then
    aws ec2 revoke-security-group-ingress --group-id "$SG_ID" \
      --protocol tcp --port 22 --cidr "$c" > /dev/null
    echo "Removed old SSH rule: $c"
  fi
done

if ! grep -qw "$CIDR" <<< "$OLD"; then
  aws ec2 authorize-security-group-ingress --group-id "$SG_ID" \
    --protocol tcp --port 22 --cidr "$CIDR" > /dev/null
  echo "Added SSH rule: $CIDR"
else
  echo "SSH rule for $CIDR already present."
fi
