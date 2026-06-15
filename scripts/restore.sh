#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_DIR"

if [[ ! -f .env ]]; then
  echo "Error: .env file not found. Copy .env.example to .env first." >&2
  exit 1
fi

# shellcheck disable=SC1091
source .env

BACKUP_FILE="${1:-}"

if [[ -z "$BACKUP_FILE" ]]; then
  echo "Usage: $0 <backup_file.sql.gz>" >&2
  echo "Available backups:" >&2
  ls -lh backups/*.sql.gz 2>/dev/null || echo "  (none)" >&2
  exit 1
fi

if [[ ! -f "$BACKUP_FILE" ]]; then
  echo "Error: backup file not found: $BACKUP_FILE" >&2
  exit 1
fi

echo "Restoring ${BACKUP_FILE} into database ${POSTGRES_DB}..."
echo "WARNING: This will overwrite data in the target database."

if [[ "${FORCE:-}" != "1" ]]; then
  read -r -p "Continue? [y/N] " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Aborted."
    exit 0
  fi
fi

gunzip -c "$BACKUP_FILE" | docker compose exec -T -e PGPASSWORD="$POSTGRES_PASSWORD" postgres \
  psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1

echo "Restore completed."
