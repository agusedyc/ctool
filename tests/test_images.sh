#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CTOOL="${SCRIPT_DIR}/ctool"

TMP_DIR=$(mktemp -d /tmp/ctool-test.XXXXXX)
cleanup() {
  docker rmi ctool-test-img:latest 2>/dev/null || true
  docker volume rm ctool_test_vol 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# 1. Setup mock project
PROJECT_DIR="${TMP_DIR}/test-proj"
mkdir -p "$PROJECT_DIR"
cat <<EOF > "${PROJECT_DIR}/docker-compose.yml"
services:
  test:
    image: ctool-test-img:latest
    volumes:
      - test_vol:/data
volumes:
  test_vol:
EOF

# Ensure tag exists
docker tag nginx:alpine ctool-test-img:latest

echo "=== Test 1: Backup includes images.tar.gz by default ==="
cd "$TMP_DIR"
"$CTOOL" backup "$PROJECT_DIR"

BACKUP_ARCHIVE=$(find "$TMP_DIR" -maxdepth 1 -name "test-proj-backup-*.tar.gz" | head -n 1)
if [[ -z "$BACKUP_ARCHIVE" ]]; then
  echo "FAIL: Backup archive was not created."
  exit 1
fi

if tar -tzf "$BACKUP_ARCHIVE" | grep "images.tar.gz" >/dev/null; then
  echo "PASS: images.tar.gz found in archive."
else
  echo "FAIL: images.tar.gz not found in archive."
  exit 1
fi

echo "=== Test 2: Backup with --no-images skips images.tar.gz ==="
"$CTOOL" backup "$PROJECT_DIR" --no-images
BACKUP_ARCHIVE_NO_IMG=$(find "$TMP_DIR" -maxdepth 1 -name "test-proj-backup-*.tar.gz" | grep -v "$BACKUP_ARCHIVE" | head -n 1)
if tar -tzf "$BACKUP_ARCHIVE_NO_IMG" | grep "images.tar.gz" >/dev/null; then
  echo "FAIL: images.tar.gz should not be in archive with --no-images."
  exit 1
else
  echo "PASS: images.tar.gz omitted with --no-images."
fi

echo "=== Test 3: Restore loads images from images.tar.gz ==="
# Remove image first
docker rmi ctool-test-img:latest
# Restore
RESTORE_DIR="${TMP_DIR}/restore-dest"
mkdir -p "$RESTORE_DIR"
cd "$RESTORE_DIR"
# Run restore non-interactively (simulate 'n' for compose up prompt)
echo "n" | "$CTOOL" restore "$BACKUP_ARCHIVE"

if docker image inspect ctool-test-img:latest >/dev/null 2>&1; then
  echo "PASS: ctool-test-img:latest successfully restored into docker."
else
  echo "FAIL: ctool-test-img:latest was not loaded."
  exit 1
fi

echo "ALL TESTS PASSED"
