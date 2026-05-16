#!/usr/bin/env bash
# Step A of the drafting cycle.
# Pulls 5 most-recent unused ingest_items, calls the writer agent, and
# inserts 2 candidates into writer_drafts. Echoes the run_id on stdout.

source "$(dirname "$0")/lib.sh"
require_cmd "$CLAUDE_CMD" sqlite3 jq python3
require_running

RUN_ID="$(new_run_id)"

RECENT_POSTS_JSON="$(sqlite_json "
    SELECT fd.post_text
    FROM posts p
    JOIN final_drafts fd ON fd.id = p.final_draft_id
    ORDER BY p.posted_at DESC
    LIMIT 5;
")"

INGEST_ITEMS_JSON="$(sqlite_json "
    SELECT id, title, summary, link, source, fetched_at
    FROM ingest_items
    WHERE used_at IS NULL
    ORDER BY fetched_at DESC
    LIMIT 5;
")"

if [ "$INGEST_ITEMS_JSON" = "[]" ]; then
    echo "no unused ingest items — nothing to draft" >&2
    log_run "drafting-writer" "$RUN_ID" "warn" "no unused ingest items"
    exit 0
fi

STYLE_GUIDE="$(cat "$REPO_ROOT/config/style-guide.md")"
export STYLE_GUIDE RECENT_POSTS_JSON INGEST_ITEMS_JSON

USER_PROMPT="$(render_template "$REPO_ROOT/prompts/writer.txt")"

RESULT="$(claude_structured \
    "$REPO_ROOT/schemas/writer-output.json" \
    "$REPO_ROOT/config/voice-profile.md" \
    "$USER_PROMPT")"

# Persist each candidate. Mark the source items used.
WRITER_RESULT="$RESULT" python3 - "$DB_PATH" "$RUN_ID" <<'PY'
import json, os, sqlite3, sys
db_path, run_id = sys.argv[1], sys.argv[2]
data = json.loads(os.environ["WRITER_RESULT"])
conn = sqlite3.connect(db_path)
conn.execute("PRAGMA foreign_keys = ON")
used = set()
for c in data["candidates"]:
    conn.execute(
        """INSERT INTO writer_drafts
           (run_id, source_item_id, post_text, rationale,
            visual_type, visual_description)
           VALUES (?, ?, ?, ?, ?, ?)""",
        (run_id, c["source_item_id"], c["post_text"], c.get("rationale", ""),
         c["suggested_visual"]["type"], c["suggested_visual"].get("description", "")),
    )
    used.add(c["source_item_id"])
for sid in used:
    conn.execute(
        "UPDATE ingest_items SET used_at = datetime('now') WHERE id = ? AND used_at IS NULL",
        (sid,),
    )
conn.commit()
conn.close()
PY

CANDIDATE_COUNT="$(printf '%s' "$RESULT" | jq -r '.candidates | length')"
log_run "drafting-writer" "$RUN_ID" "ok" "${CANDIDATE_COUNT} candidates"
echo "$RUN_ID"
