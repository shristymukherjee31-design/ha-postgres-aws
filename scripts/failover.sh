#!/usr/bin/env bash
# Orchestrates the full failover: verify, fence, promote, repoint DNS, verify.
set -euo pipefail
cd "$(dirname "$0")/.."

START=$SECONDS
SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"

bash scripts/check_primary.sh
bash scripts/fence_primary.sh
bash scripts/promote_standby.sh
bash scripts/update_dns.sh

# Verify: db.internal must resolve to the new primary (TTL is 10 seconds).
EXPECTED=$(terraform -chdir=terraform output -raw standby_private_ip)
for _ in $(seq 1 6); do
  GOT=$(ssh $SSH_OPTS bastion "getent hosts db.internal" | awk '{print $1}')
  [[ "$GOT" == "$EXPECTED" ]] && break
  sleep 5
done

if [[ "$GOT" != "$EXPECTED" ]]; then
  echo "FAIL: db.internal resolves to '$GOT', expected $EXPECTED"
  exit 1
fi

echo "Failover complete in $((SECONDS - START))s. db.internal -> $GOT"
