#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <env_file>"
  exit 1
fi
ENV_FILE="$1"

# Extraction des variables
JWT_SECRET="$(awk -F= '/^JWT_SECRET=/{print $2}' "$ENV_FILE")"
ANON_KEY="$(awk -F= '/^ANON_KEY=/{print $2}' "$ENV_FILE")"
SERVICE_ROLE_KEY="$(awk -F= '/^SERVICE_ROLE_KEY=/{print $2}' "$ENV_FILE")"

if [ -z "$JWT_SECRET" ] || [ -z "$ANON_KEY" ] || [ -z "$SERVICE_ROLE_KEY" ]; then
  echo "Erreur : JWT_SECRET, ANON_KEY ou SERVICE_ROLE_KEY manquant dans $ENV_FILE"
  exit 2
fi

# Validate HS256 signatures with Python's standard library. This keeps the
# checker portable and independent from another project's source tree.
python3 - "$JWT_SECRET" "$ANON_KEY" "$SERVICE_ROLE_KEY" <<'PY'
import base64
import hashlib
import hmac
import json
import sys

secret = sys.argv[1].encode()
for name, token, expected_role in (
    ("ANON_KEY", sys.argv[2], "anon"),
    ("SERVICE_ROLE_KEY", sys.argv[3], "service_role"),
):
    try:
        header, payload, signature = token.split(".")
        expected = hmac.new(
            secret, f"{header}.{payload}".encode(), hashlib.sha256
        ).digest()
        actual = base64.urlsafe_b64decode(signature + "=" * (-len(signature) % 4))
        claims = json.loads(
            base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))
        )
    except (ValueError, json.JSONDecodeError) as exc:
        raise SystemExit(f"{name}: invalid JWT ({exc})")
    if not hmac.compare_digest(actual, expected):
        raise SystemExit(f"{name}: invalid signature")
    if claims.get("role") != expected_role:
        raise SystemExit(f"{name}: expected role {expected_role!r}")
    print(f"{name}: valid ({expected_role})")
PY
