#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
drag_test_dir="$(mktemp -d /tmp/chao-drag-test.XXXXXX)"
swiftc -module-cache-path "$drag_test_dir/cache" apps/macos/Sources/BehaviorPolicy.swift tests/BehaviorPolicyTests.swift -o "$drag_test_dir/policy"
"$drag_test_dir/policy"
swiftc -module-cache-path "$drag_test_dir/cache" apps/macos/Sources/BehaviorPolicy.swift apps/macos/Sources/BehaviorPlayer.swift apps/macos/Sources/BehaviorController.swift tests/BehaviorDragTests.swift -o "$drag_test_dir/drag"
"$drag_test_dir/drag"
swiftc -module-cache-path "$drag_test_dir/cache" apps/macos/Sources/BehaviorPolicy.swift apps/macos/Sources/BehaviorPlayer.swift apps/macos/Sources/BehaviorController.swift tests/BehaviorMenuTests.swift -o "$drag_test_dir/menu"
"$drag_test_dir/menu"
swiftc -module-cache-path "$drag_test_dir/cache" apps/macos/Sources/BehaviorPolicy.swift apps/macos/Sources/BehaviorPlayer.swift apps/macos/Sources/BehaviorController.swift tests/BehaviorOverlayTests.swift -o "$drag_test_dir/overlay"
"$drag_test_dir/overlay"
