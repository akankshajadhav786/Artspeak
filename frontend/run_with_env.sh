#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h}/.."
set -a
source "$repo_root/.env.frontend"
set +a

cd "$repo_root/frontend"
exec flutter run \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY" \
  --dart-define="INFERENCE_API_URL=$INFERENCE_API_URL" \
  "$@"
