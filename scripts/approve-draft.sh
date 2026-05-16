#!/usr/bin/env bash
# Records the user's decision on a final draft.
# Usage: approve-draft.sh <final_draft_id> <approve|edit|reject> [user_edit_text]

source "$(dirname "$0")/lib.sh"
require_cmd sqlite3 python3

FINAL_DRAFT_ID="${1:?final_draft_id required}"
DECISION="${2:?decision required (approve | edit | reject)}"
USER_EDIT="${3:-}"

case "$DECISION" in
    approve) STATUS="approved" ;;
    edit)    STATUS="edited"   ;;
    reject)  STATUS="rejected" ;;
    *) echo "decision must be approve|edit|reject" >&2; exit 1 ;;
esac

python3 - "$DB_PATH" "$FINAL_DRAFT_ID" "$STATUS" "$USER_EDIT" <<'PY'
import sqlite3, sys
db, fid, status, user_edit = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
conn = sqlite3.connect(db); conn.execute("PRAGMA foreign_keys = ON")
if status == "edited" and user_edit:
    conn.execute(
        "UPDATE final_drafts SET status=?, user_edit=?, decided_at=datetime('now') WHERE id=?",
        (status, user_edit, fid),
    )
else:
    conn.execute(
        "UPDATE final_drafts SET status=?, decided_at=datetime('now') WHERE id=?",
        (status, fid),
    )
conn.commit(); conn.close()
print(f"final_draft {fid} -> {status}")
PY

# If approved/edited, send the user the ready-to-paste block.
if [ "$STATUS" != "rejected" ]; then
    ROW_JSON="$(sqlite_json "
        SELECT COALESCE(user_edit, post_text) AS final_text,
               (SELECT path FROM images WHERE final_draft_id = $FINAL_DRAFT_ID
                ORDER BY id DESC LIMIT 1) AS image_path
        FROM final_drafts WHERE id = $FINAL_DRAFT_ID LIMIT 1;
    ")"
    FINAL_TEXT="$(printf '%s' "$ROW_JSON" | jq -r '.[0].final_text')"
    IMAGE_PATH="$(printf '%s' "$ROW_JSON" | jq -r '.[0].image_path // ""')"

    export SUBJECT="[LinkedIn pipeline] approved — paste this into LinkedIn"
    export BODY="Ready to paste (final_draft_id=$FINAL_DRAFT_ID):

────────  POST TEXT  ────────
$FINAL_TEXT
─────────────────────────────

After publishing, run:
  scripts/mark-posted.sh $FINAL_DRAFT_ID <linkedin-post-url>
"
    [ -n "$IMAGE_PATH" ] && [ -f "$IMAGE_PATH" ] && export ATTACHMENT="$IMAGE_PATH"
    "$(dirname "$0")/notify.sh" || true
fi
