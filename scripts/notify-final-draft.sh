#!/usr/bin/env bash
# Sends the final draft email with text + image attachment (or note).
# Usage: notify-final-draft.sh <final_draft_id>

source "$(dirname "$0")/lib.sh"
require_cmd sqlite3 jq python3

FINAL_DRAFT_ID="${1:?final_draft_id required}"

ROW_JSON="$(sqlite_json "
    SELECT fd.id, fd.post_text, fd.change_summary, fd.revised,
           fd.visual_type, fd.visual_description,
           img.path AS image_path
    FROM final_drafts fd
    LEFT JOIN images img ON img.final_draft_id = fd.id
    WHERE fd.id = $FINAL_DRAFT_ID LIMIT 1;
")"

[ "$ROW_JSON" = "[]" ] && { echo "no final_draft $FINAL_DRAFT_ID" >&2; exit 1; }

POST_TEXT="$(printf '%s' "$ROW_JSON" | jq -r '.[0].post_text')"
CHANGE_SUMMARY="$(printf '%s' "$ROW_JSON" | jq -r '.[0].change_summary // ""')"
REVISED="$(printf '%s' "$ROW_JSON" | jq -r '.[0].revised')"
VISUAL_TYPE="$(printf '%s' "$ROW_JSON" | jq -r '.[0].visual_type')"
VISUAL_DESC="$(printf '%s' "$ROW_JSON" | jq -r '.[0].visual_description // ""')"
IMAGE_PATH="$(printf '%s' "$ROW_JSON" | jq -r '.[0].image_path // ""')"

CHAR_COUNT="${#POST_TEXT}"

VISUAL_LINE="Visual: $VISUAL_TYPE"
if [ "$VISUAL_TYPE" = "screenshot_suggestion" ]; then
    VISUAL_LINE="Consider attaching: $VISUAL_DESC"
elif [ -n "$IMAGE_PATH" ] && [ -f "$IMAGE_PATH" ]; then
    VISUAL_LINE="Visual ($VISUAL_TYPE) attached."
else
    VISUAL_LINE="Visual: $VISUAL_TYPE — no image generated."
fi

REVISER_LINE=""
if [ "$REVISED" = "1" ] && [ -n "$CHANGE_SUMMARY" ]; then
    REVISER_LINE="Reviser change summary:
$CHANGE_SUMMARY

"
fi

export BODY="Draft ready for review (final_draft_id=$FINAL_DRAFT_ID, $CHAR_COUNT chars).

${REVISER_LINE}${VISUAL_LINE}

────────  POST TEXT  ────────
$POST_TEXT
─────────────────────────────

To approve, paste into LinkedIn. After publishing, run:
  scripts/mark-posted.sh $FINAL_DRAFT_ID <linkedin-post-url>

To reject:
  sqlite3 \"$DB_PATH\" \"UPDATE final_drafts SET status='rejected', decided_at=datetime('now') WHERE id=$FINAL_DRAFT_ID;\"
"

export SUBJECT="[LinkedIn pipeline] draft #$FINAL_DRAFT_ID ready"
[ -n "$IMAGE_PATH" ] && [ -f "$IMAGE_PATH" ] && export ATTACHMENT="$IMAGE_PATH"

"$(dirname "$0")/notify.sh"
