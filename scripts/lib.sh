#!/usr/bin/env bash
# Common helpers sourced by every script. Not executable on its own.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# Load .env if present. Variables already in the environment win.
if [ -f "${REPO_ROOT}/.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "${REPO_ROOT}/.env"
    set +a
fi

# Defaults — only set if not already defined.
: "${CLAUDE_CMD:=claude}"
: "${CLAUDE_MODEL:=sonnet}"
: "${DB_PATH:=${REPO_ROOT}/data/visibility.sqlite}"
: "${IMAGES_DIR:=${REPO_ROOT}/data/images}"
: "${SYSTEM_PAUSED:=false}"
: "${AI_IMAGE_ENABLED:=false}"
: "${POLLINATIONS_MODEL:=flux}"

mkdir -p "$(dirname "$DB_PATH")" "$IMAGES_DIR" "${REPO_ROOT}/tmp"

# Bail out cleanly if the kill switch is on.
require_running() {
    if [ "${SYSTEM_PAUSED}" = "true" ]; then
        echo "SYSTEM_PAUSED=true — exiting cleanly." >&2
        exit 0
    fi
}

# Check that required commands exist.
require_cmd() {
    for c in "$@"; do
        if ! command -v "$c" >/dev/null 2>&1; then
            echo "missing required command: $c" >&2
            exit 2
        fi
    done
}

# sqlite_json "SELECT ..."  → JSON array of objects (one per row).
# Returns "[]" if no rows.
sqlite_json() {
    local out
    out="$(sqlite3 "$DB_PATH" -cmd ".mode json" "$1" 2>/dev/null || true)"
    [ -z "$out" ] && out="[]"
    printf '%s' "$out"
}

# Run a one-shot SQL statement (no result expected).
sqlite_exec() {
    sqlite3 "$DB_PATH" "$1"
}

# Substitute {{KEY}} placeholders in a template file using exported env vars.
# Usage: export the placeholder vars, then `render_template path/to/template.txt`.
render_template() {
    python3 - "$1" <<'PY'
import os, re, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    text = f.read()
def sub(m):
    return os.environ.get(m.group(1), m.group(0))
sys.stdout.write(re.sub(r"\{\{([A-Z0-9_]+)\}\}", sub, text))
PY
}

# Call claude -p with structured output. Returns the JSON the model produced.
#
# Implementation notes:
#  - We do NOT use --bare. --bare disables OAuth/keychain reads and requires
#    ANTHROPIC_API_KEY. This pipeline runs on a Claude Pro subscription via
#    OAuth, so --bare would fail with "Not logged in".
#  - --json-schema validates but the model often still wraps output in
#    ```json fences and adds prose. We extract the first balanced JSON
#    object from the result text via python.
#
# Usage: claude_structured <schema.json> <system_prompt_file_or_empty> <user_prompt_string>
claude_structured() {
    local schema="$1"
    local sysprompt_file="$2"
    local user_prompt="$3"

    local sys_args=()
    if [ -n "$sysprompt_file" ] && [ -f "$sysprompt_file" ]; then
        sys_args=(--append-system-prompt "$(cat "$sysprompt_file")")
    fi

    local envelope
    envelope="$("$CLAUDE_CMD" -p \
        --model "$CLAUDE_MODEL" \
        --output-format json \
        --json-schema "$(cat "$schema")" \
        --allowed-tools "" \
        "${sys_args[@]}" \
        "$user_prompt")"

    # Extract just the model's text output, then pull the first balanced JSON
    # object out of it (handles ```json fences, leading prose, etc.).
    # Pass envelope via env var so stdin remains available for the heredoc.
    CLAUDE_ENVELOPE="$envelope" python3 - <<'PY'
import json, os, re, sys
env = json.loads(os.environ["CLAUDE_ENVELOPE"])
if env.get("is_error"):
    print(f"claude error: {env.get('result', '')}", file=sys.stderr)
    sys.exit(2)
text = env.get("result", "")

# Try direct parse first (best case: pure JSON in result).
try:
    obj = json.loads(text)
    print(json.dumps(obj))
    sys.exit(0)
except json.JSONDecodeError:
    pass

# Strip ```json fences if present.
m = re.search(r"```(?:json)?\s*(\{.*?\})\s*```", text, re.DOTALL)
if m:
    try:
        obj = json.loads(m.group(1))
        print(json.dumps(obj))
        sys.exit(0)
    except json.JSONDecodeError:
        pass

# Last resort: find first '{' and decode greedily with JSONDecoder.
i = text.find("{")
if i >= 0:
    try:
        obj, _ = json.JSONDecoder().raw_decode(text[i:])
        print(json.dumps(obj))
        sys.exit(0)
    except json.JSONDecodeError as e:
        print(f"could not parse JSON from model output: {e}", file=sys.stderr)

print(f"no JSON found in model output:\n{text[:500]}", file=sys.stderr)
sys.exit(3)
PY
}

# UUID for run grouping.
new_run_id() {
    python3 -c 'import uuid; print(uuid.uuid4())'
}

# Append a row to run_log. Uses python for safe parameter binding.
log_run() {
    local workflow="$1" run_id="${2:-}" status="$3" message="${4:-}"
    python3 - "$DB_PATH" "$workflow" "$run_id" "$status" "$message" <<'PY'
import sqlite3, sys
db, wf, rid, status, msg = sys.argv[1:6]
conn = sqlite3.connect(db)
conn.execute(
    "INSERT INTO run_log (workflow, run_id, status, message) VALUES (?,?,?,?)",
    (wf, rid, status, msg),
)
conn.commit(); conn.close()
PY
}
