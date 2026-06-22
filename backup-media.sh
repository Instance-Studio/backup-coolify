#!/usr/bin/env bash
#
# backup-media.sh — media backup to S3 via rclone.
# Scans SCAN_ROOT for media folders on EVERY run, so new Coolify apps
# are picked up automatically. All config in backup-media.conf.
# No rclone.conf needed: S3 backend passed as flags.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONF="${1:-$SCRIPT_DIR/backup-media.conf}"

[ -f "$CONF" ] || { echo "config not found: $CONF" >&2; exit 2; }
# shellcheck source=/dev/null
source "$CONF"

# Server segment: isolates each host's backups in the shared bucket.
# Empty in conf -> fall back to hostname.
SERVER_NAME="${SERVER_NAME:-$(hostname -s)}"
BASE="${BUCKET}/${SERVER_NAME}"

# S3 backend flags (defines remote ":s3:" inline).
S3_FLAGS=(
  --s3-provider "$PROVIDER"
  --s3-access-key-id "$AWS_ACCESS_KEY_ID"
  --s3-secret-access-key "$AWS_SECRET_ACCESS_KEY"
  --s3-region "$REGION"
  --s3-env-auth=false
)
[ -n "$ENDPOINT" ] && S3_FLAGS+=( --s3-endpoint "$ENDPOINT" )

RUN_FLAGS=(
  --bwlimit "$BWLIMIT"
  --transfers "$TRANSFERS"
  --log-file "$LOG"
  --log-level INFO
  --stats-one-line
)
# RCLONE_DRY=1 -> preview only, transfer nothing, log to stderr too.
if [ "${RCLONE_DRY:-0}" = "1" ]; then
  RUN_FLAGS+=( --dry-run -v )
fi

# ---- Discover paths fresh each run ----
declare -a TARGETS=()
if [ -d "$SCAN_ROOT" ]; then
  while IFS= read -r d; do TARGETS+=("$d"); done < <(
    find "$SCAN_ROOT" -type d -regextype posix-extended \
      -iregex ".*/(${MEDIA_NAMES})" 2>/dev/null | sort -u
  )
else
  echo "[$(date)] WARN scan root missing: $SCAN_ROOT" >> "$LOG"
fi
# Append any manual extras: "LOCAL|PREFIX"
TARGETS+=("${EXTRA_PATHS[@]:-}")

STAMP="$(date +%Y-%m-%d_%H%M%S)"
fail=0
count=0

echo "[$(date)] === backup run start (found ${#TARGETS[@]} candidate(s)) ===" >> "$LOG"

for entry in "${TARGETS[@]}"; do
  [ -n "$entry" ] || continue
  if [[ "$entry" == *"|"* ]]; then          # manual "LOCAL|PREFIX"
    src="${entry%%|*}"; prefix="${entry##*|}"
  else                                       # scanned path -> prefix from path
    src="$entry"; prefix="${src#"$SCAN_ROOT"/}"
  fi
  dest=":s3:${BASE}/${prefix}"

  [ -d "$src" ] || { echo "[$(date)] SKIP missing: $src" >> "$LOG"; fail=1; continue; }

  extra=()
  [ -n "$KEEP_OLD" ] && extra+=( --backup-dir ":s3:${BASE}/${prefix}/${KEEP_OLD}/${STAMP}" )

  echo "[$(date)] ${MODE} ${src} -> ${dest}" >> "$LOG"
  if rclone "$MODE" "$src" "$dest" "${S3_FLAGS[@]}" "${RUN_FLAGS[@]}" "${extra[@]}"; then
    count=$((count+1))
  else
    echo "[$(date)] ERROR backing up $src" >> "$LOG"
    fail=1
  fi
done

echo "[$(date)] === backup run done (synced=$count fail=$fail) ===" >> "$LOG"
exit "$fail"
