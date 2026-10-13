#!/bin/zsh
# ==============================================================================
# ArtSpeak: Start Both Backend & Frontend Simultaneously
# ==============================================================================
set -euo pipefail

repo_root="${0:A:h}"
cd "$repo_root"

echo "🎨 Starting ArtSpeak Multimodal System..."

# 1. Start Backend API in Background
echo "🚀 [1/2] Launching Backend Inference API on http://127.0.0.1:8000..."
./services/run_inference.sh --reload &
BACKEND_PID=$!

# Trap Ctrl+C to terminate both processes cleanly
cleanup() {
    echo "\n🛑 Shutting down ArtSpeak services..."
    kill "$BACKEND_PID" 2>/dev/null || true
    exit 0
}
trap cleanup SIGINT SIGTERM EXIT

# Give backend a moment to boot
sleep 2

# 2. Start Frontend in Chrome
echo "💻 [2/2] Launching Flutter Frontend on http://localhost:3000..."
cd "$repo_root/frontend"
./run_with_env.sh -d chrome --web-port=3000
