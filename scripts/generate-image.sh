#!/usr/bin/env bash
# Dispatches to the right renderer based on final_drafts.visual_type.
# Usage: generate-image.sh <final_draft_id>

source "$(dirname "$0")/lib.sh"
require_cmd sqlite3 jq python3
require_running

FINAL_DRAFT_ID="${1:?final_draft_id required}"

ROW_JSON="$(sqlite_json "
    SELECT visual_type, visual_description, post_text
    FROM final_drafts WHERE id = $FINAL_DRAFT_ID LIMIT 1;
")"
[ "$ROW_JSON" = "[]" ] && { echo "no final_draft $FINAL_DRAFT_ID" >&2; exit 1; }

VISUAL_TYPE="$(printf '%s' "$ROW_JSON" | jq -r '.[0].visual_type')"

case "$VISUAL_TYPE" in
    chart)               exec "$(dirname "$0")/render-chart.sh"   "$FINAL_DRAFT_ID" ;;
    diagram)             exec "$(dirname "$0")/render-diagram.sh" "$FINAL_DRAFT_ID" ;;
    ai_image)
        if [ "$AI_IMAGE_ENABLED" = "true" ]; then
            exec "$(dirname "$0")/fetch-ai-image.sh" "$FINAL_DRAFT_ID"
        else
            echo "ai_image requested but AI_IMAGE_ENABLED=false; skipping" >&2
            exit 0
        fi
        ;;
    screenshot_suggestion|none)
        echo "no image to generate for visual_type=$VISUAL_TYPE"
        exit 0
        ;;
    *)
        echo "unknown visual_type: $VISUAL_TYPE" >&2
        exit 1
        ;;
esac
