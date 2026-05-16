#!/usr/bin/env bash
# Step C: reviser. Runs only on writer_drafts whose critic verdict is 'revise'.
# Inserts the revised draft into final_drafts (revised=1).
# Usage: run-reviser.sh <writer_draft_id>

source "$(dirname "$0")/lib.sh"
require_cmd "$CLAUDE_CMD" sqlite3 jq python3
require_running

WRITER_DRAFT_ID="${1:?writer_draft_id required}"

ROW_JSON="$(sqlite_json "
    SELECT wd.post_text         AS original_post_text,
           wd.visual_type        AS visual_type,
           wd.visual_description AS visual_description,
           cr.ai_isms_detected   AS ai_isms,
           cr.style_violations   AS style_violations,
           cr.specific_improvement_notes AS improvement_notes,
           cr.verdict_reason     AS verdict_reason
    FROM writer_drafts  wd
    JOIN critic_reviews cr ON cr.writer_draft_id = wd.id
    WHERE wd.id = $WRITER_DRAFT_ID
    LIMIT 1;
")"

if [ "$ROW_JSON" = "[]" ]; then
    echo "no writer draft + critic review pair for id $WRITER_DRAFT_ID" >&2
    exit 1
fi

ORIGINAL_POST_TEXT="$(printf '%s' "$ROW_JSON" | jq -r '.[0].original_post_text')"
AI_ISMS="$(printf '%s' "$ROW_JSON" | jq -r '.[0].ai_isms')"
STYLE_VIOLATIONS="$(printf '%s' "$ROW_JSON" | jq -r '.[0].style_violations')"
IMPROVEMENT_NOTES="$(printf '%s' "$ROW_JSON" | jq -r '.[0].improvement_notes')"
VERDICT_REASON="$(printf '%s' "$ROW_JSON" | jq -r '.[0].verdict_reason')"
VISUAL_TYPE="$(printf '%s' "$ROW_JSON" | jq -r '.[0].visual_type')"
VISUAL_DESCRIPTION="$(printf '%s' "$ROW_JSON" | jq -r '.[0].visual_description')"

STYLE_GUIDE="$(cat "$REPO_ROOT/config/style-guide.md")"
export ORIGINAL_POST_TEXT AI_ISMS STYLE_VIOLATIONS IMPROVEMENT_NOTES VERDICT_REASON STYLE_GUIDE

USER_PROMPT="$(render_template "$REPO_ROOT/prompts/reviser.txt")"

RESULT="$(claude_structured \
    "$REPO_ROOT/schemas/reviser-output.json" \
    "$REPO_ROOT/config/voice-profile.md" \
    "$USER_PROMPT")"

REVISED_TEXT="$(printf '%s' "$RESULT" | jq -r '.revised_post_text')"
CHANGE_SUMMARY="$(printf '%s' "$RESULT" | jq -r '.change_summary')"

python3 - "$DB_PATH" "$WRITER_DRAFT_ID" "$REVISED_TEXT" "$CHANGE_SUMMARY" "$VISUAL_TYPE" "$VISUAL_DESCRIPTION" <<'PY'
import sqlite3, sys
db, wid, text, summary, vt, vd = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], sys.argv[5], sys.argv[6]
conn = sqlite3.connect(db); conn.execute("PRAGMA foreign_keys = ON")
conn.execute("""
    INSERT INTO final_drafts
        (writer_draft_id, post_text, change_summary, revised,
         visual_type, visual_description)
    VALUES (?, ?, ?, 1, ?, ?)
""", (wid, text, summary, vt, vd))
conn.commit(); conn.close()
PY

echo "final_draft created for writer_draft_id=$WRITER_DRAFT_ID (revised)"
