#!/usr/bin/env bash
# Promotes the standby to a writable primary.
set -euo pipefail
cd "$(dirname "$0")/.."

SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=10"
psql_standby() { ssh $SSH_OPTS standby 'sudo -u postgres psql -tAq' <<< "$1"; }

if [[ "$(psql_standby 'SELECT pg_is_in_recovery();')" == "f" ]]; then
  echo "Standby is already a primary, nothing to promote."
  exit 0
fi

echo "Promoting standby..."
psql_standby "SELECT pg_promote(true, 60);" > /dev/null

if [[ "$(psql_standby 'SELECT pg_is_in_recovery();')" != "f" ]]; then
  echo "ABORT: standby is still in recovery after promote."
  exit 1
fi
echo "Standby promoted. It is now the primary."
