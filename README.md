# backup-coolify

Media backup for Coolify hosts → S3 (Hetzner Object Storage) via [rclone](https://rclone.org).

**Scans `/data/coolify` for media folders on every run** — new Coolify apps are
backed up automatically, no reconfigure. Mirrors to one bucket on a cron
schedule. No `rclone.conf` needed — all settings live in one config file.

## What's here

| File | Purpose |
|------|---------|
| `install.sh` | Interactive setup: prompts for S3 details, scans `/data/coolify` for media folders, writes config, sets perms, installs cron. |
| `backup-media.sh` | The runtime. Reads config, syncs each path to S3. Run by cron. |
| `backup-media.conf.example` | Reference config. `install.sh` generates the real `backup-media.conf`. |

## Quick start

```bash
git clone <repo-url> backup-coolify
cd backup-coolify
./install.sh
```

`install.sh` walks five steps:

1. **rclone** — checks it's installed, offers to install.
2. **S3 details** — bucket, region (`fsn1` = Falkenstein), endpoint (auto from
   region), access key, secret key (hidden input), mode.
3. **Auto-discovery** — set the scan root + folder-name regex, see a live
   preview of what matches right now. The scan re-runs on *every* backup, so
   you don't pick paths here — new apps are caught automatically.
4. **Write config** — creates `backup-media.conf` (chmod 600).
5. **Test & schedule** — runs a `--dry-run` on the first path, then optionally
   installs the cron job (default `0 2 * * *` = daily 02:00).

## Manual config

Skip the installer and copy the template instead:

```bash
cp backup-media.conf.example backup-media.conf
chmod 600 backup-media.conf
$EDITOR backup-media.conf
```

Key fields:

| Field | Notes |
|-------|-------|
| `BUCKET` | Hetzner bucket name (globally unique, lowercase). |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Hetzner S3 credentials (console → Object Storage → bucket → S3 credentials). |
| `PROVIDER` | `Other` for Hetzner (generic S3). |
| `REGION` / `ENDPOINT` | `fsn1` + `https://fsn1.your-objectstorage.com` for Falkenstein. |
| `MODE` | `sync` = exact 1:1 mirror (deletes remote files not in source). `copy` = additive, never deletes. |
| `KEEP_OLD` | Folder name to archive overwritten/deleted versions. Empty = off. |
| `SCAN_ROOT` | Root searched for media folders every run. Default `/data/coolify`. |
| `MEDIA_NAMES` | Regex of folder names to back up (`media\|uploads?\|storage\|...`). |
| `EXTRA_PATHS` | Optional manual `"LOCAL\|S3_PREFIX"` entries the scan won't find. |

**How paths are chosen:** every run, `find` matches any directory under
`SCAN_ROOT` whose name matches `MEDIA_NAMES`. The S3 prefix is that path with
`SCAN_ROOT` stripped (e.g. `/data/coolify/applications/abc/media` →
`applications/abc/media`). New apps appear automatically — nothing to edit.
Widen coverage by adding names to `MEDIA_NAMES`.

## Running

```bash
./backup-media.sh                  # uses ./backup-media.conf
./backup-media.sh /path/to/other.conf
```

Cron (daily 02:00):

```cron
0 2 * * * /home/joren/Projects/backup-coolify/backup-media.sh
```

Logs: `/var/log/backup-media.log`. Exit non-zero if any path failed or was
missing (catches an unmounted volume).

## Important — sync deletes

With `MODE="sync"` the remote becomes an **exact mirror**. Files removed or
renamed locally are **deleted from S3** on the next run. Local corruption or an
accidental delete propagates to the backup.

Hetzner Object Storage does **not** support S3 bucket versioning, so there is no
server-side recovery net. If you need one, either:

- set `KEEP_OLD="archive"` to keep timestamped old versions in the bucket
  (prune them periodically — they grow unbounded), or
- use `MODE="copy"` so the backup is additive and never deletes.

## Security

- `backup-media.conf` holds plaintext S3 credentials. It is gitignored and
  written `chmod 600`. Never commit it.
- Only `backup-media.conf.example` (placeholders) is tracked.

## Verify Coolify mount paths

The scan is a name heuristic. To confirm actual mount sources:

```bash
docker inspect <container> | grep -i source
```
