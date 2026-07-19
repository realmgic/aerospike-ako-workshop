#!/usr/bin/env bash
# Backward-compatible wrapper — prefer load-data.sh
exec "$(dirname "$0")/load-data.sh" "$@"
