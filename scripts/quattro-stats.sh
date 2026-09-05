#!/usr/bin/env bash
# Wrapper so the manifest can point at a stable, executable entry point.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$DIR/quattro-stats.py"
