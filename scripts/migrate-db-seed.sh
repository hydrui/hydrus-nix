SEED_DIR="${1:-tests/db-seed}"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Copying seed database files to working directory..."
cp "$SEED_DIR"/client*.db.zst "$WORK_DIR/"

echo "Decompressing initial database seed..."
zstd --rm -d "$WORK_DIR"/client*.db.zst

echo "Creating client_files directory structure..."
for prefix in f t; do
  for i in $(seq 0 255); do
    printf -v hex '%02x' "$i"
    mkdir -p "$WORK_DIR/client_files/${prefix}${hex}"
  done
done

echo "Starting hydrus-client for migration..."
QT_QPA_PLATFORM=offscreen \
  hydrus-client -d "$WORK_DIR" &
HYDRUS_PID=$!

echo "Waiting for API..."
SECONDS=0
while [ $SECONDS -lt 300 ]; do
  if curl -sf http://localhost:45869/api_version >/dev/null 2>&1; then
    echo "Hydrus API is responding, migration complete."
    break
  fi
  sleep 1
done

if [ $SECONDS -ge 300 ]; then
  echo "ERROR: Timed out waiting for hydrus to become ready."
  kill -INT $HYDRUS_PID 2>/dev/null || true
  wait $HYDRUS_PID 2>/dev/null || true
  exit 1
fi

echo "Sending SIGINT for clean shutdown..."
kill -INT $HYDRUS_PID
wait $HYDRUS_PID || true

echo "Checkpointing WAL files..."
for db in "$WORK_DIR"/client*.db; do
  sqlite3 "$db" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
done
rm -f "$WORK_DIR"/*.db-wal "$WORK_DIR"/*.db-shm "$WORK_DIR"/*.db-journal

echo "Copying migrated databases back to seed directory..."
cp "$WORK_DIR"/client.db "$SEED_DIR/"
cp "$WORK_DIR"/client.caches.db "$SEED_DIR/"
cp "$WORK_DIR"/client.mappings.db "$SEED_DIR/"
cp "$WORK_DIR"/client.master.db "$SEED_DIR/"

echo "Compressing initial database seed..."
zstd --rm -f "$SEED_DIR"/client*.db

echo "Migration complete."
