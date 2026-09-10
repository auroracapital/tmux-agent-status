#!/usr/bin/env bash
set -euo pipefail
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/bin"

cat > "$TMP_DIR/bin/tmux" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    show-option)
        case "${*: -1}" in
            @agent-tick-seconds) printf '%s' "$TEST_TICK" ;;
            @agent-ticks-per-collect) printf '%s' "$TEST_COUNT" ;;
        esac ;;
    list-sessions)
        count=0
        [[ -f "$TEST_DIR/cycles" ]] && count=$(cat "$TEST_DIR/cycles")
        (( count >= 7 )) && exit 1
        echo $((count + 1)) > "$TEST_DIR/cycles"
        ;;
esac
exit 0
EOF
cat > "$TMP_DIR/bin/sleep" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$1" >> "$TEST_DIR/sleeps"
EOF
chmod +x "$TMP_DIR/bin/"*

check_options() {
    local tick="$1" count="$2" expected_tick="$3" warning="$4"
    local run_dir
    run_dir=$(mktemp -d "$TMP_DIR/run.XXXXXX")
    PATH="$TMP_DIR/bin:$PATH" HOME="$run_dir/home" \
        TEST_DIR="$run_dir" TEST_TICK="$tick" TEST_COUNT="$count" \
        bash "$REPO_DIR/scripts/sidebar-collector.sh" 2> "$run_dir/errors"
    [[ $(wc -l < "$run_dir/sleeps") -eq 7 ]]
    [[ $(sort -u "$run_dir/sleeps") == "$expected_tick" ]]
    if [[ -n "$warning" ]]; then
        grep -Fq -- "$warning" "$run_dir/errors"
    else
        [[ ! -s "$run_dir/errors" ]]
    fi
}

check_options '' '' 1 ''
check_options 0.25 4 0.25 ''
check_options .5 08 .5 ''
check_options 0 5 1 '@agent-tick-seconds'
check_options invalid 5 1 '@agent-tick-seconds'
check_options 0.1 0 0.1 '@agent-ticks-per-collect'
check_options 0.1 -1 0.1 '@agent-ticks-per-collect'
check_options 0.1 1.5 0.1 '@agent-ticks-per-collect'
check_options 0.1 99999999999999999999999999999 0.1 '@agent-ticks-per-collect'
echo 'Collector polling option checks passed'
