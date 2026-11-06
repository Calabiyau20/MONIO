#!/bin/bash
# Build Stratawright on macOS (Apple Silicon), then launch it and run a
# daw-cli smoke test. Double-click this file in Finder, or run it in Terminal.
# Everything is logged to build.log next to this script.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
LOG="$ROOT/build.log"
exec > >(tee "$LOG") 2>&1

step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mFAILED: %s\033[0m\nSee %s\n' "$*" "$LOG"; exit 1; }

step "Checking prerequisites"
xcode-select -p >/dev/null 2>&1 || { xcode-select --install || true; fail "Xcode Command Line Tools missing. Finish the install dialog, then run this again."; }
command -v brew >/dev/null 2>&1 || fail "Homebrew not found. Install it from https://brew.sh, then run this again."
brew install cmake pkg-config git

step "Installing Qt 6.8.0 into ~/Qt (aqtinstall in a private venv)"
# Homebrew's Python refuses global 'pip install' (PEP 668), which breaks the
# repo's install_qt.sh, so give aqtinstall its own virtualenv.
VENV="$HOME/.stratawright-aqt"
[ -x "$VENV/bin/aqt" ] || { python3 -m venv "$VENV" && "$VENV/bin/pip" install --quiet aqtinstall; }
PATH="$VENV/bin:$PATH" bash scripts/install_qt.sh

step "Bootstrapping vcpkg and third-party SDKs"
bash scripts/setup_vcpkg.sh
bash scripts/setup_third_party.sh

step "Building release (first run compiles vcpkg deps; expect 20-60 min)"
./scripts/build.sh release

APP="$ROOT/build/release/bin/stratawright.app"
CLI="$ROOT/build/release/src/Agentic layer/daw-cli"
[ -d "$APP" ] || fail "App bundle not found at $APP"
[ -x "$CLI" ] || fail "daw-cli not found at $CLI"

step "Launching Stratawright"
open "$APP"
for _ in $(seq 1 60); do
  "$CLI" status >/dev/null 2>&1 && break
  sleep 1
done
"$CLI" status || fail "DAW did not answer on /tmp/daw_session.sock within 60 s"

step "Smoke test: agent controls"
TEST_WAV="$ROOT/smoke_test_tone.wav"
python3 - "$TEST_WAV" <<'PY'
import math, struct, sys, wave
sr = 48000
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(b"".join(struct.pack("<hh", s, s) for s in
        (int(8000 * math.sin(2 * math.pi * 110 * i / sr)) for i in range(sr * 2))))
PY

run() { printf '\n$ daw-cli %s\n' "$*"; "$CLI" "$@" || echo "   -> exit $?"; }
run transport set-tempo --bpm 124
run track create-batch --names "Kick_01.wav,Snare_Top.wav,Bass_DI.wav,Synth_Lead.wav" --type audio
run track sanitize-names
run track auto-color
run track set-gain --track 1..4 --db -6
run track set-pan --track 4 --value -0.3
run clip add-audio --track 3 --path "$TEST_WAV" --start 1.1.0
run clip list --track 3
run track create --name "Drum Bus" --type folder
run route folder --track 1..2 --to 5
run plugin scan
run plugin list --head 10
run route list
run track list --format tsv

step "Done"
echo "App: $APP"
echo "CLI: $CLI"
echo "The smoke-test tracks are in the open session; close it without saving if you don't want them."
