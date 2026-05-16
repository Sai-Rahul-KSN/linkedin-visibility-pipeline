#!/usr/bin/env bash
# Step B: critic. Runs once per writer_drafts row. Inserts a row into critic_reviews.
# Usage: run-critic.sh <writer_draft_id>

source "$(dirname "$0")/lib.sh"
require_cmd "$CLAUDE_CMD" sqlite3 jq python3
require_running

WRITER_DRAFT_ID="${1:?writer_draft_id required}"

ROW_JSON="$(sqlite_json "
    SELECT wd.post_text AS candidate_post_text,
           ii.id   AS source_item_id,
           ii.title AS source_title,
           ii.summary AS source_summary,
           ii.link AS source_link
    FROM writer_drafts wd
    JOIN ingest_items  ii ON ii.id = wd.source_item_id
    WHERE wd.id = $WRITER_DRAFT_ID
    LIMIT 1;
")"

if [ "$ROW_JSON" = "[]" ]; then
    echo "no writer draft with id $WRITER_DRAFT_ID" >&2
    exit 1
fi

CANDIDATE_POST_TEXT="$(printf '%s' "$ROW_JSON" | jq -r '.[0].candidate_post_text')"
SOURCE_ITEM_JSON="$(printf '%s' "$ROW_JSON" | jq -c '.[0] | {title: .source_title, summary: .source_summary, link: .source_link}')"
VOICE_PROFILE="$(cat "$REPO_ROOT/config/voice-profile.md")"
STYLE_GUIDE="$(cat "$REPO_ROOT/config/style-guide.md")"

export CANDIDATE_POST_TEXT SOURCE_ITEM_JSON VOICE_PROFILE STYLE_GUIDE

USER_PROMPT="$(render_template "$REPO_ROOT/prompts/critic.txt")"

RESULT="$(claude_structured \
    "$REPO_ROOT/schemas/critic-output.json" \
    "$REPO_ROOT/prompts/critic-system.txt" \
    "$USER_PROMPT")"

CRITIC_RESULT="$RESULT" python3 - "$DB_PATH" "$WRITER_DRAFT_ID" <<'PY'
import json, os, sqlite3, sys
db_path, draft_id = sys.argv[1], int(sys.argv[2])
r = json.loads(os.environ["CRITIC_RESULT"])
# Tolerate flat output where scores live at the top level instead of nested.
score_keys = ("hook_strength", "voice_match", "has_real_take",
              "style_guide_adherence", "specificity")
if "scores" in r:
    s = r["scores"]
else:
    s = {k: r[k] for k in score_keys if k in r}
conn = sqlite3.connect(db_path)
conn.execute("PRAGMA foreign_keys = ON")
conn.execute("""
    INSERT INTO critic_reviews
      (writer_draft_id, hook_strength, voice_match, has_real_take,
       style_guide_adherence, specificity,
       ai_isms_detected, style_violations, specific_improvement_notes,
       verdict, verdict_reason)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
""", (
    draft_id,
    s["hook_strength"], s["voice_match"], s["has_real_take"],
    s["style_guide_adherence"], s["specificity"],
    json.dumps(r.get("ai_isms_detected", [])),
    json.dumps(r.get("style_violations", [])),
    json.dumps(r.get("specific_improvement_notes", [])),
    r["verdict"], r.get("verdict_reason", ""),
))
conn.commit(); conn.close()
print(r["verdict"])
PY
