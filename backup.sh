#!/bin/bash
set -Eeuo pipefail
umask 077

BACKUP_NAME="backup-$(date -u +'%Y-%m-%d_%H-%M-%S-UTC')"
BACKUP_DIR="/backups/$BACKUP_NAME"
ARCHIVE="/backups/$BACKUP_NAME.zip"
LOCK_DIR="/tmp/supabase-backup.lock"

required_vars=(SUPA_DB_USER SUPA_DB_PWD SUPA_SERVER_IP SUPA_DB_NAME)
for var in "${required_vars[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required environment variable: $var" >&2
    exit 1
  fi
done

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another backup is already running" >&2
  exit 75
fi

cleanup() {
  rm -rf "$BACKUP_DIR" "$LOCK_DIR"
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

DB_URL="postgres://$(urlencode "$SUPA_DB_USER"):$(urlencode "$SUPA_DB_PWD")@${SUPA_SERVER_IP}:5432/$(urlencode "$SUPA_DB_NAME")"

mkdir -p "$BACKUP_DIR"
echo "Starting Supabase DB dump: $BACKUP_NAME"

supabase db dump --db-url "$DB_URL" --file "$BACKUP_DIR/roles.sql" --role-only
supabase db dump --db-url "$DB_URL" --file "$BACKUP_DIR/schema.sql"
supabase db dump --db-url "$DB_URL" --file "$BACKUP_DIR/data.sql" --use-copy --data-only
supabase db dump --db-url "$DB_URL" -f "$BACKUP_DIR/history_schema.sql" --schema supabase_migrations
supabase db dump --db-url "$DB_URL" -f "$BACKUP_DIR/history_data.sql" --use-copy --data-only --schema supabase_migrations

(
  cd /backups
  zip -qr "$ARCHIVE.tmp" "$BACKUP_NAME"
)
mv "$ARCHIVE.tmp" "$ARCHIVE"

echo "Backup complete: $BACKUP_NAME.zip"
