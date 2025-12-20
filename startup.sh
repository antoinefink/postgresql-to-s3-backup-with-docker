#!/bin/bash

# Exit on error and catch pipeline failures
set -e
set -o pipefail

# Default backup mode to 'now' if not set
: ${BACKUP_MODE:="now"}
# Default cron schedule to daily at midnight if not set and mode is periodic
: ${BACKUP_CRON_SCHEDULE:="0 0 * * *"}
# Default S3 endpoint to AWS S3
: ${S3_ENDPOINT:="s3.amazonaws.com"}

# Allow providing database connection details via a single DATABASE_URL.
# If DATABASE_URL is set, it populates DATABASE_* values unless already provided.
if [ -n "${DATABASE_URL:-}" ]; then
  if ! dburl_parsed="$(
    python3 - <<'PY'
import base64
import os
import sys
import urllib.parse

url = (os.environ.get("DATABASE_URL") or "").strip()
if not url:
    sys.exit(0)

if url.startswith("postgres://"):
    url = "postgresql://" + url[len("postgres://") :]

try:
    parsed = urllib.parse.urlparse(url)
except Exception as exc:
    print(f"invalid DATABASE_URL: {exc}", file=sys.stderr)
    sys.exit(2)

if parsed.scheme not in ("postgresql", "postgres"):
    print(f"invalid DATABASE_URL scheme: {parsed.scheme!r}", file=sys.stderr)
    sys.exit(2)

query = urllib.parse.parse_qs(parsed.query)

def first(*keys: str) -> str:
    for key in keys:
        values = query.get(key)
        if values:
            return values[0]
    return ""

def unquote(value: str) -> str:
    return urllib.parse.unquote(value) if value else ""

host = unquote(parsed.hostname or first("host"))
dbname = unquote(parsed.path.lstrip("/") or first("dbname", "database"))
user = unquote(parsed.username or first("user", "username"))
password = unquote(parsed.password or first("password"))

port = parsed.port or first("port")
port_str = str(port).strip() if port is not None else ""
if not port_str:
    port_str = "5432"

def b64(value: str) -> str:
    return base64.b64encode(value.encode("utf-8")).decode("ascii")

print(f"HOST_B64={b64(host)}")
print(f"PORT_B64={b64(port_str)}")
print(f"NAME_B64={b64(dbname)}")
print(f"USER_B64={b64(user)}")
print(f"PASS_B64={b64(password)}")
PY
  )"; then
    echo "Error: Failed to parse DATABASE_URL." >&2
    exit 1
  fi

  dburl_host_b64=""
  dburl_port_b64=""
  dburl_name_b64=""
  dburl_user_b64=""
  dburl_pass_b64=""

  while IFS= read -r line; do
    case "$line" in
      HOST_B64=*) dburl_host_b64="${line#HOST_B64=}" ;;
      PORT_B64=*) dburl_port_b64="${line#PORT_B64=}" ;;
      NAME_B64=*) dburl_name_b64="${line#NAME_B64=}" ;;
      USER_B64=*) dburl_user_b64="${line#USER_B64=}" ;;
      PASS_B64=*) dburl_pass_b64="${line#PASS_B64=}" ;;
    esac
  done <<<"$dburl_parsed"

  dburl_host="$(printf '%s' "$dburl_host_b64" | base64 -d)"
  dburl_port="$(printf '%s' "$dburl_port_b64" | base64 -d)"
  dburl_name="$(printf '%s' "$dburl_name_b64" | base64 -d)"
  dburl_user="$(printf '%s' "$dburl_user_b64" | base64 -d)"
  dburl_pass="$(printf '%s' "$dburl_pass_b64" | base64 -d)"

  if [ -z "${DATABASE_IP:-}" ] && [ -n "$dburl_host" ]; then
    export DATABASE_IP="$dburl_host"
  fi
  if [ -z "${DATABASE_PORT:-}" ] && [ -n "$dburl_port" ]; then
    export DATABASE_PORT="$dburl_port"
  fi
  if [ -z "${DATABASE_NAME:-}" ] && [ -n "$dburl_name" ]; then
    export DATABASE_NAME="$dburl_name"
  fi
  if [ -z "${DATABASE_USERNAME:-}" ] && [ -n "$dburl_user" ]; then
    export DATABASE_USERNAME="$dburl_user"
  fi
  if [ -z "${DATABASE_PASSWORD:-}" ] && [ -n "$dburl_pass" ]; then
    export DATABASE_PASSWORD="$dburl_pass"
  fi
fi

# Create .pgpass file with proper permissions and escaping
# .pgpass format: hostname:port:database:username:password
# Colons and backslashes in values must be escaped with backslash
create_pgpass() {
  local host="$1"
  local port="$2"
  local database="$3"
  local username="$4"
  local password="$5"

  # Escape backslashes first, then colons
  local escaped_user="${username//\\/\\\\}"
  escaped_user="${escaped_user//:/\\:}"
  local escaped_pass="${password//\\/\\\\}"
  escaped_pass="${escaped_pass//:/\\:}"

  # Use umask to ensure file is created with correct permissions
  local old_umask
  old_umask=$(umask)
  umask 077
  echo "$host:$port:$database:$escaped_user:$escaped_pass" > /root/.pgpass
  umask "$old_umask"
}

# Validate cron schedule format to prevent command injection
validate_cron_schedule() {
  local schedule="$1"
  # Cron format: 5 space-separated fields (minute hour day month weekday)
  # Each field can be: number, *, */n, n-m, or comma-separated values
  # This regex validates the general structure without allowing shell metacharacters
  local cron_regex='^([0-9a-zA-Z*,/-]+[[:space:]]+){4}[0-9a-zA-Z*,/-]+$'
  if ! printf '%s\n' "$schedule" | grep -qE "$cron_regex"; then
    echo "ERROR: Invalid BACKUP_CRON_SCHEDULE format: '$schedule'" >&2
    echo "Expected format: 'minute hour day month weekday' (e.g., '0 0 * * *')" >&2
    exit 1
  fi
  # Additional check: reject any shell metacharacters
  if printf '%s\n' "$schedule" | grep -qE '[;&|`$(){}\\<>!]'; then
    echo "ERROR: BACKUP_CRON_SCHEDULE contains invalid characters" >&2
    exit 1
  fi
}

# Validate required environment variables
validate_required_vars() {
  local missing_vars=()

  [ -z "${DATABASE_IP:-}" ] && missing_vars+=("DATABASE_IP")
  [ -z "${DATABASE_PORT:-}" ] && missing_vars+=("DATABASE_PORT")
  [ -z "${DATABASE_NAME:-}" ] && missing_vars+=("DATABASE_NAME")
  [ -z "${DATABASE_USERNAME:-}" ] && missing_vars+=("DATABASE_USERNAME")
  [ -z "${DATABASE_PASSWORD:-}" ] && missing_vars+=("DATABASE_PASSWORD")
  [ -z "${DESTINATION:-}" ] && missing_vars+=("DESTINATION")
  [ -z "${S3_ENDPOINT:-}" ] && missing_vars+=("S3_ENDPOINT")

  # Check for AWS credentials (either naming convention)
  if [ -z "${AWS_ACCESS_KEY:-}" ] && [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
    missing_vars+=("AWS_ACCESS_KEY or AWS_ACCESS_KEY_ID")
  fi
  if [ -z "${AWS_SECRET_KEY:-}" ] && [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    missing_vars+=("AWS_SECRET_KEY or AWS_SECRET_ACCESS_KEY")
  fi

  if [ ${#missing_vars[@]} -gt 0 ]; then
    echo "ERROR: Missing required environment variables:" >&2
    for var in "${missing_vars[@]}"; do
      echo "  - $var" >&2
    done
    exit 1
  fi
}

# Function to perform the backup
perform_backup() {
  echo "Performing backup for database $DATABASE_NAME..."
  # Defining the name of the backup file with a timestamp
  date_suffix=$(date +%Y-%m-%d_%H-%M-%S)
  prefix='-'
  suffix='.dump'
  newname="$DATABASE_NAME$prefix$date_suffix$suffix"

  # Configure credentials if not already done by main script execution
  if [ ! -f /root/.pgpass ]; then
    echo "Configuring credentials for cron job..."
    create_pgpass "$DATABASE_IP" "$DATABASE_PORT" "$DATABASE_NAME" "$DATABASE_USERNAME" "$DATABASE_PASSWORD"
  fi

  # Configure AWS CLI environment variables (needed for cron jobs)
  export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$AWS_ACCESS_KEY}"
  export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$AWS_SECRET_KEY}"
  # AWS_DEFAULT_REGION: "auto" works for Cloudflare R2, use a real region for AWS S3
  export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"

  # Dumping the database and upload to S3
  # With set -o pipefail, the script exits if either pg_dump or aws s3 cp fails
  if pg_dump -h "$DATABASE_IP" -p "$DATABASE_PORT" -U "$DATABASE_USERNAME" -Fc "$DATABASE_NAME" | \
    aws s3 cp - "s3://$DESTINATION/$newname" --endpoint-url "https://$S3_ENDPOINT"; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $DATABASE_NAME backup successful: $newname"
  else
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $DATABASE_NAME backup FAILED" >&2
    exit 1
  fi
}

# Main script execution
if [ "$1" = "perform_backup" ]; then
  # Source environment variables saved during initial setup (needed for cron)
  if [ -f /etc/environment ]; then
    set -a
    . /etc/environment
    set +a
  fi
  validate_required_vars
  perform_backup
  exit 0
fi

# Validate required variables before proceeding
validate_required_vars

# Configure credentials
echo "Configuring credentials..."
create_pgpass "$DATABASE_IP" "$DATABASE_PORT" "$DATABASE_NAME" "$DATABASE_USERNAME" "$DATABASE_PASSWORD"

# Configure AWS CLI for S3-compatible storage (e.g., Cloudflare R2)
export AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-$AWS_ACCESS_KEY}"
export AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-$AWS_SECRET_KEY}"
# AWS_DEFAULT_REGION: "auto" works for Cloudflare R2, use a real region (e.g., "us-east-1") for AWS S3
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-auto}"

# Create a log file for cron and make sure it's writable
touch /var/log/cron_backup.log
chmod 0600 /var/log/cron_backup.log

# Export necessary environment variables for cron.
# These will be loaded by cron when it executes jobs.
# Secure the file since it contains credentials.
printenv | grep -E '^(PATH|AWS_ACCESS_KEY|AWS_SECRET_KEY|AWS_ACCESS_KEY_ID|AWS_SECRET_ACCESS_KEY|AWS_DEFAULT_REGION|DATABASE_IP|DATABASE_PORT|DATABASE_NAME|DATABASE_USERNAME|DATABASE_PASSWORD|DESTINATION|S3_ENDPOINT)' > /etc/environment
chmod 0600 /etc/environment

if [ "$BACKUP_MODE" = "now" ]; then
  echo "Backup mode: now. Performing backup immediately."
  perform_backup
  echo "Backup finished."
elif [ "$BACKUP_MODE" = "periodic" ]; then
  echo "Backup mode: periodic. Setting up cron job with schedule: $BACKUP_CRON_SCHEDULE"
  # Validate cron schedule to prevent command injection
  validate_cron_schedule "$BACKUP_CRON_SCHEDULE"
  # Add cron job
  # The > /etc/crontab is used to ensure it's the only job for this simple container
  # For more complex scenarios, one might append or manage crontabs differently
  echo "$BACKUP_CRON_SCHEDULE bash /startup.sh perform_backup >> /var/log/cron_backup.log 2>&1" | crontab -
  crontab -l # List current cron jobs for verification
  echo "Cron job set up. Starting cron daemon and tailing log."

  # Signal handler for graceful shutdown
  cleanup() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Received shutdown signal, cleaning up..."
    [ -n "${CRON_PID:-}" ] && kill "$CRON_PID" 2>/dev/null
    [ -n "${TAIL_PID:-}" ] && kill "$TAIL_PID" 2>/dev/null
    exit 0
  }
  trap cleanup SIGTERM SIGINT SIGHUP

  # Start cron daemon in background
  cron -f &
  CRON_PID=$!

  # Start tail in background to show log activity
  tail -f /var/log/cron_backup.log &
  TAIL_PID=$!

  # Wait for cron process (main process we care about)
  wait $CRON_PID
else
  echo "Error: Invalid BACKUP_MODE specified: '$BACKUP_MODE'. Must be 'now' or 'periodic'."
  exit 1
fi
