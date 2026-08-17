#!/bin/bash
set -euo pipefail

BINARY=${1:?usage: cli_test.sh /path/to/thepfuck}
BINARY_DIR=$(cd "$(dirname "$BINARY")" && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/thepfuck-cli.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/bin"

APFEL_STUB="$TEST_DIR/bin/apfel"
touch "$APFEL_STUB"
chmod 755 "$APFEL_STUB"
apply_stub() {
    /bin/cp "$1" "$APFEL_STUB"
    chmod 755 "$APFEL_STUB"
}

GOOD_STUB="$TEST_DIR/good-apfel"
printf '%s\n' '#!/bin/sh' > "$GOOD_STUB"
printf '%s\n' 'printf "%s\n" "$@" > "$APFEL_STUB_ARGS"' >> "$GOOD_STUB"
printf '%s\n' '/bin/cat > "$APFEL_STUB_INPUT"' >> "$GOOD_STUB"
printf '%s\n' ': > "$APFEL_STUB_CALLED"' >> "$GOOD_STUB"
printf '%s\n' 'printf "%s\n" "${APFEL_STUB_RESPONSE-git status}"' >> "$GOOD_STUB"
chmod 755 "$GOOD_STUB"
apply_stub "$GOOD_STUB"

ARGS_FILE="$TEST_DIR/args"
INPUT_FILE="$TEST_DIR/input"
CALLED_FILE="$TEST_DIR/called"
ERR_FILE="$TEST_DIR/stderr"
COMMAND="printf 'boom ü' >&2; exit 1"

OUTPUT=$(PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    APFEL_STUB_ARGS="$ARGS_FILE" \
    APFEL_STUB_INPUT="$INPUT_FILE" \
    APFEL_STUB_CALLED="$CALLED_FILE" \
    APFEL_STUB_RESPONSE="printf 'fixed\\n'" \
    "$BINARY" --command "$COMMAND" --shell zsh --yes 2>"$ERR_FILE")
if [[ "$OUTPUT" != "fixed" ]]; then
    printf 'FAIL direct --yes did not execute the accepted correction\n' >&2
    exit 1
fi
if grep -Fxq "printf 'fixed\\n'" "$ERR_FILE"; then
    printf 'FAIL explicit --command duplicated the correction on stderr\n' >&2
    exit 1
fi
if grep -Fq 'finding a fix for:' "$ERR_FILE"; then
    printf 'FAIL CLI printed the legacy finding-a-fix status\n' >&2
    exit 1
fi
[[ -f "$CALLED_FILE" ]]
grep -Fq '"failed_command":"printf '\''boom ü'\'' >&2; exit 1"' "$INPUT_FILE"
grep -Fq 'boom ü' "$INPUT_FILE"
EXPECTED_ARGS=$(printf '%s\n' '-q' '--code' '-s')
ACTUAL_ARGS=$(sed -n '1,3p' "$ARGS_FILE")
[[ "$ACTUAL_ARGS" == "$EXPECTED_ARGS" ]]

set +e
DIRECT_FAILURE_OUTPUT=$(PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    APFEL_STUB_ARGS="$ARGS_FILE" \
    APFEL_STUB_INPUT="$INPUT_FILE" \
    APFEL_STUB_CALLED="$CALLED_FILE" \
    APFEL_STUB_RESPONSE="exit 7" \
    "$BINARY" --command false --shell zsh --yes 2>"$ERR_FILE")
DIRECT_FAILURE_STATUS=$?
set -e
[[ $DIRECT_FAILURE_STATUS -eq 7 ]]
[[ -z "$DIRECT_FAILURE_OUTPUT" ]]

ENTER_MARKER="$TEST_DIR/enter-ran"
COLOR_TRANSCRIPT="$TEST_DIR/color-transcript"
env -u NO_COLOR \
    PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    APFEL_STUB_ARGS="$ARGS_FILE" \
    APFEL_STUB_INPUT="$INPUT_FILE" \
    APFEL_STUB_CALLED="$CALLED_FILE" \
    APFEL_STUB_RESPONSE="touch '$ENTER_MARKER'" \
    /usr/bin/expect Tests/Integration/enter_to_run.exp "$BINARY" false "$COLOR_TRANSCRIPT"
[[ -f "$ENTER_MARKER" ]]
ESCAPE=$'\033'
if ! grep -Fq "${ESCAPE}[32menter${ESCAPE}[0m" "$COLOR_TRANSCRIPT"; then
    printf 'FAIL enter was not green in the interactive prompt\n' >&2
    exit 1
fi
if ! grep -Fq "${ESCAPE}[31mctrl+c${ESCAPE}[0m" "$COLOR_TRANSCRIPT"; then
    printf 'FAIL ctrl+c was not red in the interactive prompt\n' >&2
    exit 1
fi

PLAIN_MARKER="$TEST_DIR/plain-enter-ran"
PLAIN_TRANSCRIPT="$TEST_DIR/plain-transcript"
PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    NO_COLOR=1 \
    APFEL_STUB_ARGS="$ARGS_FILE" \
    APFEL_STUB_INPUT="$INPUT_FILE" \
    APFEL_STUB_CALLED="$CALLED_FILE" \
    APFEL_STUB_RESPONSE="touch '$PLAIN_MARKER'" \
    /usr/bin/expect Tests/Integration/enter_to_run.exp "$BINARY" false "$PLAIN_TRANSCRIPT"
[[ -f "$PLAIN_MARKER" ]]
grep -Fq '[enter/ctrl+c]' "$PLAIN_TRANSCRIPT"
if grep -Fq "$ESCAPE" "$PLAIN_TRANSCRIPT"; then
    printf 'FAIL NO_COLOR confirmation contained ANSI escapes\n' >&2
    exit 1
fi

ZSH_SOURCE="$TEST_DIR/zsh-source"
SHELL=/bin/zsh "$BINARY" --alias > "$ZSH_SOURCE"
/bin/zsh -n "$ZSH_SOURCE"
grep -Fq 'fuck() {' "$ZSH_SOURCE"

BASH_SOURCE_FILE="$TEST_DIR/bash-source"
SHELL=/bin/bash "$BINARY" --alias FUCK --shell bash > "$BASH_SOURCE_FILE"
/bin/bash -n "$BASH_SOURCE_FILE"
grep -Fq 'function FUCK() {' "$BASH_SOURCE_FILE"

ZSH_UNQUOTED_ALIAS=$(
    PATH="$BINARY_DIR:/usr/bin:/bin" \
        SHELL=/bin/zsh \
        /bin/zsh -f -c 'eval $(thepfuck --alias pfuck); whence -w pfuck' 2>"$ERR_FILE"
)
[[ "$ZSH_UNQUOTED_ALIAS" == "pfuck: function" ]]

BASH_UNQUOTED_ALIAS=$(
    PATH="$BINARY_DIR:/usr/bin:/bin" \
        SHELL=/bin/bash \
        /bin/bash --noprofile --norc -c 'eval $(thepfuck --alias pfuck --shell bash); type -t pfuck' 2>"$ERR_FILE"
)
[[ "$BASH_UNQUOTED_ALIAS" == "function" ]]

rm -f "$CALLED_FILE"
FUNCTION_TRANSCRIPT=$(
    PATH="$TEST_DIR/bin:$BINARY_DIR:/usr/bin:/bin" \
        SHELL=/bin/zsh \
        APFEL_STUB_ARGS="$ARGS_FILE" \
        APFEL_STUB_INPUT="$INPUT_FILE" \
        APFEL_STUB_CALLED="$CALLED_FILE" \
        APFEL_STUB_RESPONSE="printf 'function-ran\\n'" \
        /bin/zsh -f -i -c \
        'alias tpz=ls; eval "$(thepfuck --alias)"; print -s -- "tpz /definitely/thepfuck-missing"; fuck --yes'
)
[[ -f "$CALLED_FILE" ]]
grep -Fq '"failed_command":"ls /definitely/thepfuck-missing"' "$INPUT_FILE"
grep -Fq 'No such file or directory' "$INPUT_FILE"
[[ "$FUNCTION_TRANSCRIPT" == *"function-ran"* ]]

rm -f "$CALLED_FILE"
BASH_FUNCTION_TRANSCRIPT=$(
    PATH="$TEST_DIR/bin:$BINARY_DIR:/usr/bin:/bin" \
        SHELL=/bin/bash \
        APFEL_STUB_ARGS="$ARGS_FILE" \
        APFEL_STUB_INPUT="$INPUT_FILE" \
        APFEL_STUB_CALLED="$CALLED_FILE" \
        APFEL_STUB_RESPONSE="printf 'bash-function-ran\\n'" \
        /bin/bash --noprofile --norc -i -c \
        'alias tpb=ls; eval "$(thepfuck --alias --shell bash)"; history -s "tpb /definitely/thepfuck-bash-missing"; fuck --yes'
)
[[ -f "$CALLED_FILE" ]]
grep -Fq '"failed_command":"ls /definitely/thepfuck-bash-missing"' "$INPUT_FILE"
grep -Fq 'No such file or directory' "$INPUT_FILE"
[[ "$BASH_FUNCTION_TRANSCRIPT" == *"bash-function-ran"* ]]

set +e
EMPTY_OUTPUT=$(PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    APFEL_STUB_ARGS="$ARGS_FILE" \
    APFEL_STUB_INPUT="$INPUT_FILE" \
    APFEL_STUB_CALLED="$CALLED_FILE" \
    APFEL_STUB_RESPONSE="" \
    "$BINARY" --command "false" --shell zsh --yes 2>"$ERR_FILE")
EMPTY_STATUS=$?
set -e
[[ $EMPTY_STATUS -ne 0 ]]
[[ -z "$EMPTY_OUTPUT" ]]

FAIL_STUB="$TEST_DIR/fail-apfel"
printf '%s\n' '#!/bin/sh' > "$FAIL_STUB"
printf '%s\n' 'printf "model unavailable" >&2' >> "$FAIL_STUB"
printf '%s\n' 'exit 5' >> "$FAIL_STUB"
chmod 755 "$FAIL_STUB"
apply_stub "$FAIL_STUB"
set +e
FAIL_OUTPUT=$(PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    "$BINARY" --command "false" --shell zsh --yes 2>"$ERR_FILE")
FAIL_STATUS=$?
set -e
[[ $FAIL_STATUS -ne 0 ]]
[[ -z "$FAIL_OUTPUT" ]]
grep -Fq 'model unavailable' "$ERR_FILE"

set +e
MISSING_OUTPUT=$(PATH="$TEST_DIR/nowhere" \
    "$BINARY" --command "false" --shell zsh --yes 2>"$ERR_FILE")
MISSING_STATUS=$?
set -e
[[ $MISSING_STATUS -ne 0 ]]
[[ -z "$MISSING_OUTPUT" ]]
grep -Fq 'apfel was not found' "$ERR_FILE"

apply_stub "$GOOD_STUB"
rm -f "$CALLED_FILE"
set +e
TIMEOUT_OUTPUT=$(PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    APFEL_STUB_ARGS="$ARGS_FILE" \
    APFEL_STUB_INPUT="$INPUT_FILE" \
    APFEL_STUB_CALLED="$CALLED_FILE" \
    "$BINARY" --command "exec /bin/sleep 5" --shell zsh --timeout 0.1 --yes 2>"$ERR_FILE")
TIMEOUT_STATUS=$?
set -e
[[ $TIMEOUT_STATUS -ne 0 ]]
[[ -z "$TIMEOUT_OUTPUT" ]]
[[ ! -f "$CALLED_FILE" ]]

set +e
REJECT_OUTPUT=$(PATH="$TEST_DIR/bin:/usr/bin:/bin" \
    APFEL_STUB_ARGS="$ARGS_FILE" \
    APFEL_STUB_INPUT="$INPUT_FILE" \
    APFEL_STUB_CALLED="$CALLED_FILE" \
    "$BINARY" --command "false" --shell zsh </dev/null 2>"$ERR_FILE")
REJECT_STATUS=$?
set -e
[[ $REJECT_STATUS -ne 0 ]]
[[ -z "$REJECT_OUTPUT" ]]

printf 'PASS CLI integration\n'
