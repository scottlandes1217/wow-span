#!/bin/zsh
# Build wow-span (and the unmirror recovery tool) and code-sign it.
# With an "Apple Development" certificate the signature is stable, so macOS keeps the Screen Recording
# and Accessibility permissions across rebuilds. Without one it is ad-hoc signed: re-grant after rebuilding.
set -e
cd ${0:A:h}
swiftc -O -swift-version 5 -import-objc-header VirtualDisplay.h main.swift -o wow-span 2>&1 | grep -E " error: " || true
[[ -x wow-span ]]
swiftc -O unmirror.swift -o unmirror
identity=$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"' || true)
codesign -f -s "${identity:--}" -i "${WOW_SPAN_ID:-wow-span}" wow-span
./wow-span --selftest
