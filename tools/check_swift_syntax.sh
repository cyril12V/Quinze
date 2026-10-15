#!/usr/bin/env bash
# Syntax-checks every Swift file of the iOS app and extensions with the Linux toolchain
# (parse only: types and Apple frameworks are checked by the macOS CI).
set -euo pipefail
cd "$(dirname "$0")/.."
source /opt/swiftlang/env.sh
mapfile -t files < <(find App Extensions Shared -name '*.swift' 2>/dev/null | sort)
status=0
for f in "${files[@]}"; do
  swiftc -parse "$f" || status=1
done
echo "checked ${#files[@]} files, status=$status"
exit $status
