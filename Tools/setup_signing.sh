#!/bin/bash
# Creates a dedicated keychain with a self-signed code-signing certificate for VozFlow.
# A fixed signing identity keeps macOS privacy permissions (Accessibility, Microphone,
# Speech) valid across rebuilds; ad-hoc signatures change on every build.
# Undo: security delete-keychain ~/Library/Keychains/vozflow-signing.keychain-db
#       (also removes it from the keychain search list)
set -euo pipefail

KC="$HOME/Library/Keychains/vozflow-signing.keychain-db"
NAME="VozFlow Local Signing"
PASS="vozflow-local" # protects only this dedicated keychain, which holds nothing else

if [ ! -f "$KC" ]; then
    security create-keychain -p "$PASS" "$KC"
fi
security set-keychain-settings "$KC" # no auto-lock
security unlock-keychain -p "$PASS" "$KC"
# codesign only finds identities in keychains on the user search list; append ours, keeping the others.
CURRENT=$(security list-keychains -d user | tr -d '"' | xargs)
case "$CURRENT" in
    *vozflow-signing*) ;;
    *) security list-keychains -d user -s $CURRENT "$KC" ;;
esac

if security find-certificate -c "$NAME" "$KC" >/dev/null 2>&1; then
    echo "✓ Identidade \"$NAME\" já existe"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/openssl.cnf" <<EOF
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
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/openssl.cnf" \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
    -out "$TMP/identity.p12" -passout pass:"$PASS"
security import "$TMP/identity.p12" -k "$KC" -P "$PASS" -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$PASS" "$KC" >/dev/null
echo "✓ Identidade \"$NAME\" criada em $KC"
