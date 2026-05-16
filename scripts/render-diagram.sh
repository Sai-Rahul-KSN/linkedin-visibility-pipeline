#!/usr/bin/env bash
# Asks Claude for a Mermaid spec, then renders it via mmdc.
# Usage: render-diagram.sh <final_draft_id>

source "$(dirname "$0")/lib.sh"
require_cmd "$CLAUDE_CMD" sqlite3 jq python3 mmdc
require_running

FINAL_DRAFT_ID="${1:?final_draft_id required}"

ROW_JSON="$(sqlite_json "
    SELECT visual_description, post_text
    FROM final_drafts WHERE id = $FINAL_DRAFT_ID LIMIT 1;
")"
[ "$ROW_JSON" = "[]" ] && { echo "no final_draft $FINAL_DRAFT_ID" >&2; exit 1; }

DIAGRAM_DESCRIPTION="$(printf '%s' "$ROW_JSON" | jq -r '.[0].visual_description')"
POST_TEXT="$(printf '%s' "$ROW_JSON" | jq -r '.[0].post_text')"
export DIAGRAM_DESCRIPTION POST_TEXT

USER_PROMPT="$(render_template "$REPO_ROOT/prompts/diagram-spec.txt")"

RESULT="$(claude_structured \
    "$REPO_ROOT/schemas/diagram-spec-output.json" \
    "" \
    "$USER_PROMPT")"

SPEC="$(printf '%s' "$RESULT" | jq -r '.mermaid_spec')"
MMD_FILE="$REPO_ROOT/tmp/diagram-${FINAL_DRAFT_ID}.mmd"
OUTPUT_PATH="$IMAGES_DIR/${FINAL_DRAFT_ID}.png"

printf '%s' "$SPEC" > "$MMD_FILE"

if mmdc -i "$MMD_FILE" -o "$OUTPUT_PATH" -t neutral -b transparent -w 1200 -H 630 \
       2> "$REPO_ROOT/tmp/diagram-${FINAL_DRAFT_ID}.err"; then
    python3 - "$DB_PATH" "$FINAL_DRAFT_ID" "$OUTPUT_PATH" "$MMD_FILE" <<'PY'
import pathlib, sqlite3, sys
db, fid, path, spec_file = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
spec = pathlib.Path(spec_file).read_text(encoding="utf-8")
conn = sqlite3.connect(db); conn.execute("PRAGMA foreign_keys = ON")
conn.execute(
    "INSERT INTO images (final_draft_id, kind, path, source_artifact) VALUES (?, 'diagram', ?, ?)",
    (fid, path, spec),
)
conn.commit(); conn.close()
PY
    echo "diagram written to $OUTPUT_PATH"
else
    echo "diagram render failed — see $REPO_ROOT/tmp/diagram-${FINAL_DRAFT_ID}.err" >&2
    exit 3
fi
