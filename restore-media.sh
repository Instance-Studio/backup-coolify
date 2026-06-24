#!/usr/bin/env bash
#
# restore-media.sh — interactive download of backed-up folders from S3.
# Reverse of backup-media.sh. Fully standalone: no config file, no
# rclone.conf — runs anywhere, just needs rclone. Prompts for S3
# details, lists what's in the bucket, downloads the folder you pick.
#
set -euo pipefail

c_bold=$'\e[1m'; c_dim=$'\e[2m'; c_grn=$'\e[32m'; c_ylw=$'\e[33m'; c_rst=$'\e[0m'
say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s%s%s\n' "$c_bold" "$*" "$c_rst"; }
ask()  { # ask "Prompt" "default" -> echoes answer
  local p="$1" def="${2:-}" ans
  if [ -n "$def" ]; then read -rp "$p [$def]: " ans; echo "${ans:-$def}";
  else read -rp "$p: " ans; echo "$ans"; fi
}
asksecret() { local p="$1" ans; read -rsp "$p: " ans; echo >&2; echo "$ans"; }

command -v rclone >/dev/null 2>&1 || { say "${c_ylw}rclone not installed.${c_rst} Get it: https://rclone.org/install.sh" >&2; exit 1; }

# ---------- 1. S3 details ----------
hdr "1/4  S3 details"
BUCKET="$(ask 'Bucket name' instancebackup)"
SERVER_NAME="$(ask 'Server name (folder under bucket)' "$(hostname -s)")"
REGION="$(ask 'Region' nbg1)"
ENDPOINT="$(ask 'Endpoint' "https://${REGION}.your-objectstorage.com")"
ACCESS_KEY="$(ask 'S3 access key')"
SECRET_KEY="$(asksecret 'S3 secret key')"

BASE="${BUCKET}/${SERVER_NAME}"
S3_FLAGS=(
  --s3-provider "Other"
  --s3-access-key-id "$ACCESS_KEY"
  --s3-secret-access-key "$SECRET_KEY"
  --s3-region "$REGION"
  --s3-env-auth=false
)
[ -n "$ENDPOINT" ] && S3_FLAGS+=( --s3-endpoint "$ENDPOINT" )

# ---------- 2. pick folder ----------
hdr "2/4  Pick folder"
say "Listing :s3:${BASE}/ ..."
mapfile -t DIRS < <(rclone lsf --dirs-only -R ":s3:${BASE}/" "${S3_FLAGS[@]}" 2>/dev/null | sed 's#/$##' | sort -u)
if [ "${#DIRS[@]}" -eq 0 ]; then
  say "  ${c_ylw}(nothing found at :s3:${BASE}/ — check server name / credentials)${c_rst}"
  exit 1
fi
i=0
for d in "${DIRS[@]}"; do i=$((i+1)); printf '  %s%2d%s  %s\n' "$c_grn" "$i" "$c_rst" "$d"; done
say "  ${c_dim} 0  (everything — whole server)${c_rst}"

sel="$(ask 'Number to download' 1)"
if [ "$sel" = "0" ]; then
  PREFIX=""
else
  PREFIX="${DIRS[$((sel-1))]:-}"
  [ -n "$PREFIX" ] || { say "invalid selection" >&2; exit 2; }
fi
SRC=":s3:${BASE}${PREFIX:+/$PREFIX}"

# ---------- 3. destination ----------
hdr "3/4  Destination"
DEST="$(ask 'Local download dir' "./restore/${PREFIX:-$SERVER_NAME}")"

# ---------- 4. run ----------
hdr "4/4  Download"
RUN_FLAGS=( --transfers 8 --progress )

if [ "$(ask 'Dry-run first (preview only)? (y/n)' y)" = "y" ]; then
  say "${c_dim}preview — nothing written${c_rst}"
  rclone copy "$SRC" "$DEST" "${S3_FLAGS[@]}" "${RUN_FLAGS[@]}" --dry-run -v || true
fi

if [ "$(ask "Download ${SRC} -> ${DEST} now? (y/n)" y)" = "y" ]; then
  mkdir -p "$DEST"
  rclone copy "$SRC" "$DEST" "${S3_FLAGS[@]}" "${RUN_FLAGS[@]}"
  say "${c_grn}done${c_rst} -> $DEST"
else
  say "aborted."
fi
