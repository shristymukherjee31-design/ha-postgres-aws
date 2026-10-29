#!/usr/bin/env bash
# Confirms the primary is really down before a failover is allowed.
# Three consecutive failed checks are required. If the primary responds,
# the script aborts unless FORCE=1 is set.
set -uo pipefail
cd "$(dirname "$0")/.."

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"
PRIMARY_IP=$(terraform output -raw primary_private_ip)

# The checks run from the standby, so it must be reachable first.
if ! ssh $SSH_OPTS standby true 2>/dev/null; then
  echo "ABORT: standby is not reachable, cannot verify the primary."
  exit 1
fi

for i in 1 2 3; do
  if ssh $SSH_OPTS standby "/usr/lib/postgresql/16/bin/pg_isready -h $PRIMARY_IP -p 5432 -t 3" > /dev/null 2>&1; then
    echo "Check $i/3: primary is responding"
    if [[ "${FORCE:-0}" != "1" ]]; then
      echo "ABORT: primary is healthy. Set FORCE=1 to override."
      exit 1
    fi
    echo "FORCE=1 is set, continuing."
    exit 0
  fi
  echo "Check $i/3: primary is NOT responding"
  sleep 5
done

echo "Primary confirmed down after 3 failed checks."
