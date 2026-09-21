#!/usr/bin/env bash
# Start the API and the Vite dev server together.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

export PATH="${HOME}/.local/bin:${PATH}"

cleanup() {
    kill 0 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "API      -> http://127.0.0.1:8000"
echo "Frontend -> http://127.0.0.1:5173"
echo

uvicorn backend.app.main:app --reload --port 8000 &
(cd frontend && npm run dev) &

wait
