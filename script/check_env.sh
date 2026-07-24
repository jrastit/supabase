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

UTIL_PATH="$(dirname "$0")/../../node_agent/utils/jwt_util.py"

# Vérification des tokens
echo "Vérification ANON_KEY :"
python3 "$UTIL_PATH" --secret "$JWT_SECRET" --mode check --token "$ANON_KEY"
echo "Vérification SERVICE_ROLE_KEY :"
python3 "$UTIL_PATH" --secret "$JWT_SECRET" --mode check --token "$SERVICE_ROLE_KEY"
