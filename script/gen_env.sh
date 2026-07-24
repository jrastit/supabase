#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

usage() {
  cat <<'EOF'
Usage: gen_env.sh [TARGET_DIR] [PROJECT_NAME] [PORT_PREFIX]

Generate a complete .env for a current Supabase Docker installation.

  TARGET_DIR    Directory containing .env.example and utils/ (default: current directory)
  PROJECT_NAME  Project identifier used by Studio and Supavisor (default: directory name)
  PORT_PREFIX   Two-digit port prefix, 10-64 (default: 28)

For PORT_PREFIX=28 the exposed ports are:
  Kong HTTP 28000, Kong HTTPS 28443, Postgres 28432, transaction pooler 28543.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="${1:-$PWD}"
PROJECT_NAME="${2:-$(basename -- "$TARGET_DIR")}"
PORT_PREFIX="${3:-28}"

if [[ ! "$PORT_PREFIX" =~ ^[0-9]{2}$ ]] || (( 10#$PORT_PREFIX < 10 || 10#$PORT_PREFIX > 64 )); then
  echo "PORT_PREFIX must be a two-digit number from 10 through 64." >&2
  exit 2
fi

TARGET_DIR="$(cd -- "$TARGET_DIR" && pwd)"
ENV_EXAMPLE="$TARGET_DIR/.env.example"
ENV_FILE="$TARGET_DIR/.env"

if [[ ! -f "$ENV_EXAMPLE" || ! -f "$TARGET_DIR/utils/generate-keys.sh" ]]; then
  echo "TARGET_DIR must be a current Supabase docker directory with .env.example and utils/." >&2
  exit 2
fi

cp "$ENV_EXAMPLE" "$ENV_FILE"

(
  cd "$TARGET_DIR"
  sh utils/generate-keys.sh --update-env >/dev/null
  if command -v node >/dev/null 2>&1; then
    sh utils/add-new-auth-keys.sh --update-env >/dev/null
  else
    echo "Note: node is unavailable; generated legacy JWT keys only." >&2
  fi
)

python3 - "$ENV_FILE" "$PROJECT_NAME" "$PORT_PREFIX" <<'PY'
import re
import secrets
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
project = sys.argv[2]
prefix = sys.argv[3]

updates = {
    "DASHBOARD_USERNAME": "supabase",
    "KONG_HTTP_PORT": f"{prefix}000",
    "KONG_HTTPS_PORT": f"{prefix}443",
    "POSTGRES_PORT": f"{prefix}432",
    "POOLER_PROXY_PORT_TRANSACTION": f"{prefix}543",
    "POOLER_TENANT_ID": f"{project}-{secrets.token_hex(8)}",
    "STUDIO_DEFAULT_ORGANIZATION": project,
    "STUDIO_DEFAULT_PROJECT": project,
    "SUPABASE_PUBLIC_URL": f"http://localhost:{prefix}000",
    "API_EXTERNAL_URL": f"http://localhost:{prefix}000/auth/v1",
    "SITE_URL": f"http://localhost:{prefix}300",
    "OPENAI_API_KEY": "",
}

text = env_path.read_text()
for key, value in updates.items():
    pattern = rf"(?m)^{re.escape(key)}=.*$"
    replacement = f"{key}={value}"
    if re.search(pattern, text):
        text = re.sub(pattern, replacement, text)
    else:
        text += f"\n{replacement}"
env_path.write_text(text)
PY

chmod 600 "$ENV_FILE"
rm -f "$TARGET_DIR/.env.old" "$TARGET_DIR/docker-compose.yml.old"

"$SCRIPT_DIR/check_env.sh" "$ENV_FILE"
echo "Generated $ENV_FILE for '$PROJECT_NAME'."
echo "HTTP=${PORT_PREFIX}000 HTTPS=${PORT_PREFIX}443 POSTGRES=${PORT_PREFIX}432 POOLER=${PORT_PREFIX}543"
