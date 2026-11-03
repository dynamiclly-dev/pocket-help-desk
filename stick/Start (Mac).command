#!/bin/bash
# Double-click in Finder to start Pocket Help Desk (opens in Terminal).
exec bash "$(cd "$(dirname "$0")" && pwd)/system/launch.sh"
