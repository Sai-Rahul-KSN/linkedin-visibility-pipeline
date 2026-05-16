#!/usr/bin/env bash
# Generates a suggested reply for one comment row.
# Usage: run-reply.sh <comment_id>

source "$(dirname "$0")/lib.sh"
require_cmd "$CLAUDE_CMD" sqlite3 jq python3
require_running

COMMENT_ID="${1:?comment_id required}"

ROW_JSON="$(sqlite_json "
    SELECT c.comment_text, c.commenter_title,
           COALESCE(fd.post_text, c.post_ref_text, '') AS post_text
    FROM comments c
    LEFT JOIN posts p         ON p.id = c.post_id
    LEFT JOIN final_drafts fd ON fd.id = p.final_draft_id
    WHERE c.id = $COMMENT_ID LIMIT 1;
")"
[ "$ROW_JSON" = "[]" ] && { echo "no comment $COMMENT_ID" >&2; exit 1; }

COMMENT_TEXT="$(printf '%s' "$ROW_JSON" | jq -r '.[0].comment_text')"
COMMENTER_TITLE="$(printf '%s' "$ROW_JSON" | jq -r '.[0].commenter_title // "unknown"')"
POST_TEXT="$(printf '%s' "$ROW_JSON" | jq -r '.[0].post_text')"
export COMMENT_TEXT COMMENTER_TITLE POST_TEXT

USER_PROMPT="$(render_template "$REPO_ROOT/prompts/reply.txt")"

RESULT="$(claude_structured \
    "$REPO_ROOT/schemas/reply-output.json" \
    "$REPO_ROOT/config/voice-profile.md" \
    "$USER_PROMPT")"

REPLY_RESULT="$RESULT" python3 - "$DB_PATH" "$COMMENT_ID" <<'PY'
import json, os, sqlite3, sys
db, cid = sys.argv[1], int(sys.argv[2])
r = json.loads(os.environ["REPLY_RESULT"])
conn = sqlite3.connect(db); conn.execute("PRAGMA foreign_keys = ON")
conn.execute("""
    INSERT INTO reply_drafts
        (comment_id, suggested_reply, no_reply_recommended, reason)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(comment_id) DO UPDATE SET
        suggested_reply = excluded.suggested_reply,
        no_reply_recommended = excluded.no_reply_recommended,
        reason = excluded.reason
""", (
    cid,
    r.get("suggested_reply", ""),
    1 if r.get("no_reply_recommended") else 0,
    r.get("reason", ""),
))
conn.commit(); conn.close()
PY

echo "reply draft saved for comment_id=$COMMENT_ID"
