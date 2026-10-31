#!/usr/bin/env bash
# Post-deploy cluster verification for the HA PostgreSQL stack.
# Exits non-zero if any check fails, so a CI pipeline can stop on failure.
set -uo pipefail
cd "$(dirname "$0")/.."

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"
PASS=0
FAIL=0

pass() { echo "PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL  $1  ->  $2"; FAIL=$((FAIL + 1)); }

# Run a SQL statement as the postgres user on a node (SQL is sent via stdin
# to avoid nested shell quoting).
psql_on() { ssh $SSH_OPTS "$1" 'sudo -u postgres psql -tAq' <<< "$2"; }

az_of() {
  aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=$1" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].Placement.AvailabilityZone' --output text
}

PRIMARY_IP=$(terraform -chdir=terraform output -raw primary_private_ip)

# 1. Both database instances are running in different Availability Zones
AZ_P=$(az_of ha-pg-primary)
AZ_S=$(az_of ha-pg-standby)
if [[ "$AZ_P" != "None" && "$AZ_S" != "None" && "$AZ_P" != "$AZ_S" ]]; then
  pass "1. Primary ($AZ_P) and standby ($AZ_S) are running in different AZs"
else
  fail "1. Primary/standby AZ check" "primary=$AZ_P standby=$AZ_S"
fi

# 2. db.internal resolves to the primary's private IP
DNS_IP=$(ssh $SSH_OPTS bastion "getent hosts db.internal" | awk '{print $1}')
if [[ "$DNS_IP" == "$PRIMARY_IP" ]]; then
  pass "2. db.internal resolves to the primary ($DNS_IP)"
else
  fail "2. db.internal DNS" "expected $PRIMARY_IP, got '${DNS_IP}'"
fi

# 3. PostgreSQL port is reachable through db.internal (checked from the bastion)
if ssh $SSH_OPTS bastion "timeout 5 bash -c '</dev/tcp/db.internal/5432'" 2>/dev/null; then
  pass "3. db.internal:5432 is reachable from the bastion"
else
  fail "3. db.internal:5432 reachability" "connection failed"
fi

# 4. The standby is streaming from the primary
STREAMING=$(psql_on primary "SELECT count(*) FROM pg_stat_replication WHERE state='streaming';")
if [[ "$STREAMING" == "1" ]]; then
  pass "4. Replication state is streaming"
else
  fail "4. Replication state" "streaming standbys: '${STREAMING}'"
fi

# 5. The standby is in recovery mode (read-only replica)
IN_RECOVERY=$(psql_on standby "SELECT pg_is_in_recovery();")
if [[ "$IN_RECOVERY" == "t" ]]; then
  pass "5. Standby is in recovery mode"
else
  fail "5. Standby recovery mode" "got '${IN_RECOVERY}'"
fi

# 6. Data written on the primary appears on the standby
TOKEN="check-$(date +%s)"
psql_on primary "CREATE TABLE IF NOT EXISTS validate_check(token text); INSERT INTO validate_check VALUES ('$TOKEN');" > /dev/null
FOUND="0"
for _ in $(seq 1 10); do
  FOUND=$(psql_on standby "SELECT count(*) FROM validate_check WHERE token='$TOKEN';")
  [[ "$FOUND" == "1" ]] && break
  sleep 1
done
if [[ "$FOUND" == "1" ]]; then
  pass "6. Data written on the primary is visible on the standby"
else
  fail "6. Data replication" "token not found on standby"
fi

echo "-----------------------------------------"
echo "Result: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
