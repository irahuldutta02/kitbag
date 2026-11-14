#!/usr/bin/env bash
# Creates a local self-signed code-signing certificate ("Kitbag Local Signing") in the login keychain.
# build.sh signs with it when present, so the app keeps the same identity across rebuilds and macOS
# remembers its permissions (Location, Bluetooth, Automation, ...) instead of asking again.
set -euo pipefail

NAME="${1:-Kitbag Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
  echo "Certificate \"$NAME\" already exists."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/id.p12" -passout pass:kitbag 2>/dev/null
security import "$TMP/id.p12" -k "$KEYCHAIN" -P kitbag -T /usr/bin/codesign >/dev/null
echo "Created \"$NAME\" in the login keychain."
