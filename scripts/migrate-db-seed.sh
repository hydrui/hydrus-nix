SEED_DIR="${1:-tests/db-seed}"
READINESS_TIMEOUT_SECONDS="${HYDRUS_MIGRATION_READINESS_TIMEOUT_SECONDS:-300}"
GRACEFUL_SHUTDOWN_TIMEOUT_SECONDS="${HYDRUS_MIGRATION_GRACEFUL_SHUTDOWN_TIMEOUT_SECONDS:-30}"
TERM_TIMEOUT_SECONDS="${HYDRUS_MIGRATION_TERM_TIMEOUT_SECONDS:-10}"
KILL_TIMEOUT_SECONDS="${HYDRUS_MIGRATION_KILL_TIMEOUT_SECONDS:-5}"
API_URL="http://localhost:45869/api_version"
DB_FILES=(
  client.db
  client.caches.db
  client.mappings.db
  client.master.db
)

WORK_DIR=$(mktemp -d)
HYDRUS_PID=""
HYDRUS_PGID=""

hydrus_process_is_running() {
  [[ -n "$HYDRUS_PID" ]] && kill -0 "$HYDRUS_PID" 2>/dev/null
}

hydrus_process_group_is_running() {
  [[ -n "$HYDRUS_PGID" ]] && kill -0 -- "-$HYDRUS_PGID" 2>/dev/null
}

wait_for_hydrus_process_exit() {
  local timeout_seconds="$1"
  local deadline=$((SECONDS + timeout_seconds))

  while hydrus_process_is_running; do
    if ((SECONDS >= deadline)); then
      return 1
    fi

    sleep 1
  done

  if [[ -n "$HYDRUS_PID" ]]; then
    wait "$HYDRUS_PID" 2>/dev/null || true
    HYDRUS_PID=""
  fi
}

wait_for_hydrus_process_group_exit() {
  local timeout_seconds="$1"
  local deadline=$((SECONDS + timeout_seconds))

  while hydrus_process_group_is_running; do
    if ((SECONDS >= deadline)); then
      return 1
    fi

    sleep 1
  done
}

signal_hydrus_process_group() {
  local signal_name="$1"

  if hydrus_process_group_is_running; then
    kill "-$signal_name" -- "-$HYDRUS_PGID" 2>/dev/null || true
  fi
}

clean_up_hydrus_process_group() {
  if ! hydrus_process_group_is_running; then
    return
  fi

  signal_hydrus_process_group TERM

  if ! wait_for_hydrus_process_group_exit "$TERM_TIMEOUT_SECONDS"; then
    signal_hydrus_process_group KILL
    wait_for_hydrus_process_group_exit "$KILL_TIMEOUT_SECONDS" || true
  fi
}

cleanup() {
  local status="$?"
  trap - EXIT

  clean_up_hydrus_process_group

  if [[ -n "$HYDRUS_PID" ]]; then
    wait "$HYDRUS_PID" 2>/dev/null || true
  fi

  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    rm -rf -- "$WORK_DIR"
  fi

  exit "$status"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

stop_hydrus_cleanly() {
  if ! hydrus_process_is_running; then
    if [[ -n "$HYDRUS_PID" ]]; then
      wait "$HYDRUS_PID" 2>/dev/null || true
      HYDRUS_PID=""
    fi

    clean_up_hydrus_process_group
    return 0
  fi

  echo "Sending SIGINT for clean shutdown..."
  signal_hydrus_process_group INT

  if wait_for_hydrus_process_exit "$GRACEFUL_SHUTDOWN_TIMEOUT_SECONDS"; then
    clean_up_hydrus_process_group
    return 0
  fi

  echo "WARNING: Hydrus did not exit after SIGINT; sending SIGTERM."
  signal_hydrus_process_group TERM

  if ! wait_for_hydrus_process_exit "$TERM_TIMEOUT_SECONDS"; then
    echo "WARNING: Hydrus did not exit after SIGTERM; sending SIGKILL."
    signal_hydrus_process_group KILL
    wait_for_hydrus_process_exit "$KILL_TIMEOUT_SECONDS" || true
  fi

  clean_up_hydrus_process_group
  return 1
}

report_database_version() {
  local version

  if [[ ! -f "$WORK_DIR/client.db" ]]; then
    return
  fi

  version=$(sqlite3 "$WORK_DIR/client.db" "SELECT version FROM version;" 2>/dev/null || true)

  if [[ -n "$version" ]]; then
    echo "Hydrus database version at exit: $version"
  fi
}

for db_file in "${DB_FILES[@]}"; do
  if [[ ! -f "$SEED_DIR/$db_file.zst" ]]; then
    echo "ERROR: Missing seed database file: $SEED_DIR/$db_file.zst"
    exit 1
  fi
done

if curl --connect-timeout 1 --max-time 2 -sf "$API_URL" >/dev/null 2>&1; then
  echo "ERROR: A process is already responding at $API_URL."
  exit 1
fi

echo "Copying seed database files to working directory..."
for db_file in "${DB_FILES[@]}"; do
  cp "$SEED_DIR/$db_file.zst" "$WORK_DIR/"
done

echo "Decompressing initial database seed..."
for db_file in "${DB_FILES[@]}"; do
  zstd --rm -d "$WORK_DIR/$db_file.zst"
done

echo "Creating client_files directory structure..."
for prefix in f t; do
  for i in $(seq 0 255); do
    printf -v hex '%02x' "$i"
    mkdir -p "$WORK_DIR/client_files/${prefix}${hex}"
  done
done

echo "Starting hydrus-client for migration..."
setsid env \
  QT_QPA_PLATFORM=offscreen \
  hydrus-client -d "$WORK_DIR" &
HYDRUS_PID=$!
HYDRUS_PGID=$HYDRUS_PID

echo "Waiting up to $READINESS_TIMEOUT_SECONDS seconds for API..."
ready=false
deadline=$((SECONDS + READINESS_TIMEOUT_SECONDS))

while ((SECONDS < deadline)); do
  if curl --connect-timeout 1 --max-time 2 -sf "$API_URL" >/dev/null 2>&1; then
    ready=true
    echo "Hydrus API is responding; migration is complete."
    break
  fi

  if ! hydrus_process_is_running; then
    wait "$HYDRUS_PID" 2>/dev/null || true
    HYDRUS_PID=""
    echo "ERROR: Hydrus exited before its API became ready."
    report_database_version
    exit 1
  fi

  sleep 1
done

if [[ "$ready" != true ]]; then
  echo "ERROR: Timed out waiting for Hydrus to become ready."
  stop_hydrus_cleanly || true
  report_database_version
  exit 1
fi

if ! stop_hydrus_cleanly; then
  echo "ERROR: Hydrus required forced termination after migration; refusing to publish the seed."
  report_database_version
  exit 1
fi

report_database_version

echo "Checkpointing and validating databases..."
for db_file in "${DB_FILES[@]}"; do
  checkpoint_result=$(sqlite3 "$WORK_DIR/$db_file" "PRAGMA wal_checkpoint(TRUNCATE);")

  if [[ "${checkpoint_result%%|*}" != "0" ]]; then
    echo "ERROR: SQLite WAL checkpoint was busy for $db_file: $checkpoint_result"
    exit 1
  fi

  if [[ $(sqlite3 "$WORK_DIR/$db_file" "PRAGMA quick_check;") != "ok" ]]; then
    echo "ERROR: SQLite quick_check failed for $db_file."
    exit 1
  fi
done

rm -f "$WORK_DIR"/*.db-wal "$WORK_DIR"/*.db-shm "$WORK_DIR"/*.db-journal

echo "Compressing migrated database seed..."
for db_file in "${DB_FILES[@]}"; do
  zstd -f "$WORK_DIR/$db_file"
done

echo "Publishing migrated databases to seed directory..."
for db_file in "${DB_FILES[@]}"; do
  cp "$WORK_DIR/$db_file.zst" "$SEED_DIR/"
done

echo "Migration complete."
