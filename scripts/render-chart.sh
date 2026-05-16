#!/usr/bin/env bash
# Asks Claude to write a matplotlib script, then runs it.
# Usage: render-chart.sh <final_draft_id>

source "$(dirname "$0")/lib.sh"
require_cmd "$CLAUDE_CMD" sqlite3 jq python3
require_running

FINAL_DRAFT_ID="${1:?final_draft_id required}"

ROW_JSON="$(sqlite_json "
    SELECT visual_description, post_text
    FROM final_drafts WHERE id = $FINAL_DRAFT_ID LIMIT 1;
")"
[ "$ROW_JSON" = "[]" ] && { echo "no final_draft $FINAL_DRAFT_ID" >&2; exit 1; }

CHART_DESCRIPTION="$(printf '%s' "$ROW_JSON" | jq -r '.[0].visual_description')"
POST_TEXT="$(printf '%s' "$ROW_JSON" | jq -r '.[0].post_text')"
export CHART_DESCRIPTION POST_TEXT

USER_PROMPT="$(render_template "$REPO_ROOT/prompts/chart-script.txt")"

RESULT="$(claude_structured \
    "$REPO_ROOT/schemas/chart-script-output.json" \
    "" \
    "$USER_PROMPT")"

SCRIPT="$(printf '%s' "$RESULT" | jq -r '.python_script')"
SCRIPT_FILE="$REPO_ROOT/tmp/chart-${FINAL_DRAFT_ID}.py"
OUTPUT_PATH="$IMAGES_DIR/${FINAL_DRAFT_ID}.png"

printf '%s' "$SCRIPT" > "$SCRIPT_FILE"

if OUTPUT_PATH="$OUTPUT_PATH" python3 "$SCRIPT_FILE" 2> "$REPO_ROOT/tmp/chart-${FINAL_DRAFT_ID}.err"; then
    python3 - "$DB_PATH" "$FINAL_DRAFT_ID" "$OUTPUT_PATH" "$SCRIPT_FILE" <<'PY'
import pathlib, sqlite3, sys
db, fid, path, script_file = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
script = pathlib.Path(script_file).read_text(encoding="utf-8")
conn = sqlite3.connect(db); conn.execute("PRAGMA foreign_keys = ON")
conn.execute(
    "INSERT INTO images (final_draft_id, kind, path, source_artifact) VALUES (?, 'chart', ?, ?)",
    (fid, path, script),
)
conn.commit(); conn.close()
PY
    echo "chart written to $OUTPUT_PATH"
else
    echo "chart script failed — see $REPO_ROOT/tmp/chart-${FINAL_DRAFT_ID}.err" >&2
    exit 3
fi
