#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP=member exec bash "$ROOT/scripts/release_ios.sh"
