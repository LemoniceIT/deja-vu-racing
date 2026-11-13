#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

godot=${GODOT_BIN:-godot}
work_dir=$(mktemp -d)
trap 'rm -r -- "$work_dir"' EXIT
export XDG_DATA_HOME="$work_dir/data"
export XDG_CONFIG_HOME="$work_dir/config"
export XDG_CACHE_HOME="$work_dir/cache"
mkdir -p "$XDG_DATA_HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME"

run_godot() {
    local expected_status=$1
    shift
    local status=0
    printf '\nGodot %s\n' "$*"
    "$godot" --headless --path . "$@" > "$work_dir/godot.log" 2>&1 || status=$?
    cat "$work_dir/godot.log"
    if [[ $status -ne $expected_status ]]; then
        echo "Expected Godot exit code $expected_status, got $status" >&2
        return 1
    fi
    # The existing shutdown diagnostic also appears after successful scene runs.
    if grep -E '^(SCRIPT ERROR:|ERROR:|Parse Error:)' "$work_dir/godot.log" |
        grep -Ev '^ERROR: [0-9]+ resources? still in use at exit '; then
        return 1
    fi
}

run_godot 0 --editor --import

for scene in main test_mountain test_mountain_night; do
    run_godot 0 --fixed-fps 60 --quit-after 10 "res://scenes/$scene.tscn"
done

validator=(--fixed-fps 60 --script res://tools/validate_mountain.gd)
run_godot 0 "${validator[@]}"
grep -Fx 'Mountain validation passed' "$work_dir/godot.log"
run_godot 1 "${validator[@]}" -- force-timeout
grep -Fx 'Mountain validation failed: timeout' "$work_dir/godot.log"
