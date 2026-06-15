#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PGADMIN_CONFIG_DIR="${PROJECT_DIR}/config/pgadmin"

cd "$PROJECT_DIR"

if [[ ! -f .env ]]; then
  echo "Error: .env file not found. Copy .env.example to .env first." >&2
  exit 1
fi

# shellcheck disable=SC1091
source .env

mkdir -p "$PGADMIN_CONFIG_DIR"

PGPASS_FILE="${PGADMIN_CONFIG_DIR}/pgpass"
echo "postgres:5432:*:${POSTGRES_USER}:${POSTGRES_PASSWORD}" > "$PGPASS_FILE"
chmod 600 "$PGPASS_FILE"

cat > "${PGADMIN_CONFIG_DIR}/servers.json" <<EOF
{
  "Servers": {
    "1": {
      "Name": "PostgreSQL (local)",
      "Group": "Servers",
      "Host": "postgres",
      "Port": 5432,
      "MaintenanceDB": "${POSTGRES_DB}",
      "Username": "${POSTGRES_USER}",
      "SSLMode": "prefer",
      "PassFile": "/pgpass"
    }
  }
}
EOF

echo "pgAdmin configuration updated."
