#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h}/.."
while IFS='=' read -r name value; do
	[[ -z "$name" || "$name" == \#* ]] && continue
	value="${value##[[:space:]]#}"
	export "$name=$value"
done < "$repo_root/.env.inference"

cd "$repo_root"
if [[ -x "$repo_root/.venv-ml/bin/uvicorn" ]]; then
	uvicorn_bin="$repo_root/.venv-ml/bin/uvicorn"
else
	uvicorn_bin="$(command -v uvicorn)"
fi
exec "$uvicorn_bin" services.inference_api:app --host 127.0.0.1 --port 8000 "$@"