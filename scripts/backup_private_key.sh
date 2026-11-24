#!/usr/bin/env bash
set -euo pipefail

KEY="${ITACHI_PRIVATE_KEY:-$HOME/Downloads/ITACHI-DUCHAMP-AUTH/itachi_duchamp_private.pem}"
OUT="${1:-$HOME/Downloads/ITACHI-DUCHAMP-PRIVATE-KEY-BACKUP.zip}"
TMP="$(mktemp -d)"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

test -f "$KEY" || {
  echo "ERROR: private key not found: $KEY"
  exit 2
}

command -v 7z >/dev/null 2>&1 || {
  echo "ERROR: 7z is required."
  echo "Ubuntu/Debian: sudo apt install 7zip"
  exit 3
}

chmod 600 "$KEY" 2>/dev/null || true

cp -f "$KEY" "$TMP/itachi_duchamp_private.pem"
chmod 600 "$TMP/itachi_duchamp_private.pem"

if command -v openssl >/dev/null 2>&1; then
  openssl pkey -in "$KEY" -pubout -out "$TMP/itachi_duchamp_public.pem"
fi

cat > "$TMP/README-PRIVATE-KEY-BACKUP.txt" <<'EOF'
ITACHI Duchamp private signing-key backup.

KEEP THIS ARCHIVE PRIVATE.

- Keep at least two offline copies in separate safe locations.
- Never put this archive in the GitHub repository.
- Use a unique strong archive password.
- Do not store the password beside the archive.
EOF

rm -f "$OUT"

echo "Creating AES-256 encrypted ZIP."
echo "7-Zip will prompt for the archive password."
echo

cd "$TMP"
FILES=(itachi_duchamp_private.pem README-PRIVATE-KEY-BACKUP.txt)
[ -f itachi_duchamp_public.pem ] && FILES+=(itachi_duchamp_public.pem)

# -p without an inline password makes 7-Zip prompt instead of exposing
# the password in shell history/process arguments.
7z a -tzip -mem=AES256 -p "$OUT" "${FILES[@]}"

chmod 600 "$OUT"

echo
echo "BACKUP_CREATED=$OUT"
echo "Test it before relying on it:"
echo "  7z t '$OUT'"
