#!/bin/bash
set -Eeuo pipefail
umask 077

LOCK_DIR="/tmp/supabase-backup.lock"
BACKUP_NAME="backup-$(date -u +'%Y-%m-%d_%H-%M-%S-UTC')"
BACKUP_DIR="/backups/$BACKUP_NAME"
ARCHIVE_NAME="$BACKUP_NAME.tar.zst"
ARCHIVE_PATH="/backups/$ARCHIVE_NAME"

required_vars=(SUPA_DB_USER SUPA_DB_PWD SUPA_DB_HOST SUPA_DB_PORT SUPA_DB_NAME)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required environment variable: $var" >&2
    exit 1
  fi
done

required_bins=(pg_dump tar)
for bin in "${required_bins[@]}"; do
  command -v "$bin" >/dev/null || {
    echo "Missing required binary: $bin" >&2
    exit 1
  }
done

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another backup is already running" >&2
  exit 75
fi

cleanup() {
  rm -rf "$LOCK_DIR"
  if [[ -d "$BACKUP_DIR" ]]; then
    echo "Cleaning up dangling raw backup folder..." >&2
    rm -rf "$BACKUP_DIR"
  fi
}
trap cleanup EXIT

urlencode() {
  local raw="$1"
  local length="${#raw}"
  local encoded=""
  local pos char

  for (( pos = 0; pos < length; pos++ )); do
    char="${raw:pos:1}"
    case "$char" in
      [a-zA-Z0-9.~_-]) encoded+="$char" ;;
      *) printf -v encoded '%s%%%02X' "$encoded" "'$char" ;;
    esac
  done

  printf '%s' "$encoded"
}

mkdir -p "$BACKUP_DIR"
echo "Starting Supabase DB dump: $BACKUP_NAME"

export DB_URL="postgres://$(urlencode "$SUPA_DB_USER"):$(urlencode "$SUPA_DB_PWD")@${SUPA_DB_HOST}:${SUPA_DB_PORT}/$(urlencode "$SUPA_DB_NAME")"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/scripts/dump_roles.sh" "$BACKUP_DIR/roles.sql"
"$SCRIPT_DIR/scripts/dump_schema.sh" "$BACKUP_DIR/schema.sql"
"$SCRIPT_DIR/scripts/dump_data.sh" "$BACKUP_DIR/data.sql"
"$SCRIPT_DIR/scripts/dump_mig_schema.sh" "$BACKUP_DIR/migration_history_schema.sql"
"$SCRIPT_DIR/scripts/dump_mig_data.sh" "$BACKUP_DIR/migration_history_data.sql"

(
  cd /backups
  tar --zstd -cf "$ARCHIVE_NAME.tmp" "$BACKUP_NAME"
)

mv "/backups/$ARCHIVE_NAME.tmp" "$ARCHIVE_PATH"

echo "Backup complete: $ARCHIVE_NAME"
