#!/usr/bin/env bash
# Run in a terminal: bash /path/to/stick/start-linux.sh
exec bash "$(cd "$(dirname "$0")" && pwd)/system/launch.sh"
