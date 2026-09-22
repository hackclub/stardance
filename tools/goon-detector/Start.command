#!/bin/zsh
cd "${0:A:h}"
if [[ ! -x ./NativeDetector || NativeDetector.swift -nt NativeDetector ]]; then
  DEVELOPER_DIR=/Library/Developer/CommandLineTools swiftc -module-cache-path "${TMPDIR:-/tmp}/goon-detector-swift-cache" NativeDetector.swift -o NativeDetector || exit 1
fi
if pgrep -x NativeDetector >/dev/null; then
  echo "Detector is already running. Look for 🥀 in your menu bar."
  exit 0
fi
nohup ./NativeDetector "$(python3 -c 'import sys; print(sys.executable)')" > "${TMPDIR:-/tmp}/goon-detector.log" 2>&1 < /dev/null &
echo "Detector started. Use the 🥀 menu bar icon to test or quit. You can close this window."
