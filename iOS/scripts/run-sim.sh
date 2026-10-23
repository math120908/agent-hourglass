#!/usr/bin/env bash
# Boot the simulator (headless), install the app and launch it with optional args.
# Usage: run-sim.sh <app path> [args...]   (SIM_NAME / SIM_OS from env)
set -euo pipefail
app="$1"; shift
udid="$("$(dirname "$0")/sim-udid.sh" "${SIM_NAME:-iPhone 17}" "${SIM_OS:-26.0}")"
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
# Simulator.app is optional (absent on headless machines).
open -a Simulator 2>/dev/null || true
xcrun simctl install "$udid" "$app"
xcrun simctl terminate "$udid" cc.kuoc.agent-hourglass.ios 2>/dev/null || true
xcrun simctl launch "$udid" cc.kuoc.agent-hourglass.ios "$@"
