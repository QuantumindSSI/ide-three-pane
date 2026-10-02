#!/usr/bin/env bash
#
# compact-event-store.sh
#
# Reclaims disk space in the OpenCode event store by dropping superseded
# snapshot events, then rewriting the database file.
#
# WHY THIS IS SAFE
# ----------------
# OpenCode stores session history as an event-sourced log in the `event` table
# (aggregate_id, seq, type, data). Two event types dominate the file:
#
#   message.updated.1        data = {sessionID, info:{id, ...}}
#   message.part.updated.1   data = {sessionID, part:{id, ...}, time}
#
# Both carry the COMPLETE state of one entity, identified by info.id or
# part.id, rather than a delta. During streaming, one message is rewritten on
# every token, so a single entity accumulates hundreds of near-identical rows.
# Only the highest seq per entity contributes to reconstructed state; every
# earlier row for that same id is superseded and contributes nothing.
#
# Measured on this machine before compaction:
#   message.updated.1   keep 17,756 rows (59 MB) / drop 51,381 rows (2,224 MB)
#
# RESIDUAL RISK
# -------------
# Intermediate revisions are destroyed. Final state of every message and part
# is preserved exactly, and no session is removed. If you rely on inspecting a
# message's intermediate revisions, do not run this. The original database is
# retained as a timestamped backup, so the operation is reversible.
#
# The script refuses to run while OpenCode is running, verifies free space,
# checks integrity before and after, and aborts unless the session, message
# and part row counts are identical across the rewrite.

set -euo pipefail

readonly DATA_DIR="${HOME}/.local/share/opencode"
readonly DB="${DATA_DIR}/opencode.db"
readonly WORK="${DATA_DIR}/opencode.db.compact-work"
readonly STAMP="$(date +%Y%m%d-%H%M%S)"
readonly BACKUP="${DATA_DIR}/opencode.db.backup-${STAMP}"

# Every superseded-snapshot rule lives here. Each entry is TYPE:JSON_ID_PATH.
readonly SNAPSHOT_RULES=(
  "message.updated.1:\$.info.id"
  "message.part.updated.1:\$.part.id"
)

log()  { printf '[compact] %s\n' "$*"; }
fail() { printf '[compact] ERROR: %s\n' "$*" >&2; exit 1; }

# BSD stat uses -f %z, GNU stat uses -c %s. Resolve once per run.
if stat -f %z / >/dev/null 2>&1; then
  file_size() { stat -f %z "$1"; }
else
  file_size() { stat -c %s "$1"; }
fi

cleanup_work() {
  if [[ -f "${WORK}" ]]; then
    rm -f "${WORK}" "${WORK}-wal" "${WORK}-shm"
  fi
}
trap cleanup_work EXIT

# Refuses to proceed while any OpenCode process holds the database open.
assert_opencode_stopped() {
  if pgrep -x opencode >/dev/null 2>&1; then
    printf '[compact] ERROR: OpenCode is running. PIDs:\n' >&2
    pgrep -lx opencode >&2
    fail "quit every OpenCode window and TUI, then re-run this script"
  fi
  log "no OpenCode process running"
}

# VACUUM INTO plus the retained copy needs roughly twice the database size.
assert_disk_space() {
  local db_bytes avail_bytes need_bytes
  db_bytes=$(file_size "${DB}")
  avail_bytes=$(( $(df -k "${DATA_DIR}" | awk 'NR==2 {print $4}') * 1024 ))
  need_bytes=$(( db_bytes * 2 ))
  if (( avail_bytes < need_bytes )); then
    fail "need $(( need_bytes / 1048576 )) MB free, have $(( avail_bytes / 1048576 )) MB"
  fi
  log "disk space OK: $(( avail_bytes / 1048576 )) MB free, $(( need_bytes / 1048576 )) MB required"
}

# Prints "sessions|messages|parts" so the rewrite can be proven lossless.
projection_counts() {
  sqlite3 "$1" \
    "SELECT (SELECT COUNT(*) FROM session)
         || '|' || (SELECT COUNT(*) FROM message)
         || '|' || (SELECT COUNT(*) FROM part);"
}

assert_integrity() {
  local target="$1" label="$2" result
  result=$(sqlite3 "${target}" "PRAGMA integrity_check;")
  [[ "${result}" == "ok" ]] || fail "${label} failed integrity_check: ${result}"
  log "${label} integrity_check ok"
}

# Deletes every snapshot row that is not the newest for its entity id.
delete_superseded() {
  local target="$1" rule type id_path
  for rule in "${SNAPSHOT_RULES[@]}"; do
    type="${rule%%:*}"
    id_path="${rule#*:}"
    sqlite3 "${target}" <<SQL
DELETE FROM event
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           ROW_NUMBER() OVER (
             PARTITION BY aggregate_id, type, json_extract(data, '${id_path}')
             ORDER BY seq DESC
           ) AS rn
    FROM event
    WHERE type = '${type}'
  )
  WHERE rn > 1
);
SQL
    log "compacted ${type}"
  done
}

main() {
  [[ -f "${DB}" ]] || fail "database not found at ${DB}"

  assert_opencode_stopped
  assert_disk_space
  assert_integrity "${DB}" "source"

  local before_counts after_counts before_events after_events before_mb after_mb
  before_counts=$(projection_counts "${DB}")
  before_events=$(sqlite3 "${DB}" "SELECT COUNT(*) FROM event;")
  before_mb=$(( $(file_size "${DB}") / 1048576 ))
  log "before: ${before_mb} MB, ${before_events} events, counts ${before_counts}"

  cleanup_work
  # VACUUM INTO takes a read transaction and folds in any pending WAL frames,
  # producing a consistent standalone copy. A plain cp would miss the WAL.
  log "writing consistent working copy (this reads the whole database)"
  sqlite3 "${DB}" "VACUUM INTO '${WORK}';"

  delete_superseded "${WORK}"

  log "rewriting working copy to release freed pages"
  sqlite3 "${WORK}" "VACUUM;"

  assert_integrity "${WORK}" "compacted"

  after_counts=$(projection_counts "${WORK}")
  after_events=$(sqlite3 "${WORK}" "SELECT COUNT(*) FROM event;")
  after_mb=$(( $(stat -f %z "${WORK}") / 1048576 ))

  if [[ "${before_counts}" != "${after_counts}" ]]; then
    fail "projection mismatch: before ${before_counts}, after ${after_counts}. Nothing was changed."
  fi
  log "projections preserved: sessions|messages|parts = ${after_counts}"

  # Swap only after every check has passed. The original becomes the backup.
  mv "${DB}" "${BACKUP}"
  mv "${WORK}" "${DB}"
  rm -f "${DATA_DIR}/opencode.db-wal" "${DATA_DIR}/opencode.db-shm"
  trap - EXIT

  log "after:  ${after_mb} MB, ${after_events} events"
  log "reclaimed $(( before_mb - after_mb )) MB, dropped $(( before_events - after_events )) superseded events"
  log "backup retained at ${BACKUP}"
  log "verify with: opencode mcp list   then browse your sessions"
  log "once satisfied, delete the backup: rm '${BACKUP}'"
}

main "$@"
