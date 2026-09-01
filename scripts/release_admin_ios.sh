#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP=admin exec bash "$ROOT/scripts/release_ios.sh"
