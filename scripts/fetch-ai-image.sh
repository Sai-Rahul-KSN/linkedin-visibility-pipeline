#!/usr/bin/env bash
# Refines the visual description into an image prompt via Claude, then
# fetches the image from Pollinations.
# Usage: fetch-ai-image.sh <final_draft_id>

source "$(dirname "$0")/lib.sh"
require_cmd "$CLAUDE_CMD" sqlite3 jq python3 curl
require_running

if [ "$AI_IMAGE_ENABLED" != "true" ]; then
    echo "AI_IMAGE_ENABLED=false; skipping" >&2
    exit 0
fi
if [ -z "${POLLINATIONS_API_KEY:-}" ]; then
    echo "POLLINATIONS_API_KEY not set; skipping" >&2
    exit 0
fi

FINAL_DRAFT_ID="${1:?final_draft_id required}"

ROW_JSON="$(sqlite_json "
    SELECT visual_description, post_text
    FROM final_drafts WHERE id = $FINAL_DRAFT_ID LIMIT 1;
")"
[ "$ROW_JSON" = "[]" ] && { echo "no final_draft $FINAL_DRAFT_ID" >&2; exit 1; }

VISUAL_DESCRIPTION="$(printf '%s' "$ROW_JSON" | jq -r '.[0].visual_description')"
POST_TEXT="$(printf '%s' "$ROW_JSON" | jq -r '.[0].post_text')"
export VISUAL_DESCRIPTION POST_TEXT

USER_PROMPT="$(render_template "$REPO_ROOT/prompts/image-prompt.txt")"

RESULT="$(claude_structured \
    "$REPO_ROOT/schemas/image-prompt-output.json" \
    "" \
    "$USER_PROMPT")"

IMAGE_PROMPT="$(printf '%s' "$RESULT" | jq -r '.image_prompt')"
ENCODED_PROMPT="$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1]))" "$IMAGE_PROMPT")"
OUTPUT_PATH="$IMAGES_DIR/${FINAL_DRAFT_ID}.png"

URL="https://gen.pollinations.ai/image/${ENCODED_PROMPT}?model=${POLLINATIONS_MODEL}&width=1200&height=630"

if curl -sS -L --fail \
        -H "Authorization: Bearer ${POLLINATIONS_API_KEY}" \
        -o "$OUTPUT_PATH" "$URL"; then
    python3 - "$DB_PATH" "$FINAL_DRAFT_ID" "$OUTPUT_PATH" "$IMAGE_PROMPT" <<'PY'
import sqlite3, sys
db, fid, path, prompt = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
conn = sqlite3.connect(db); conn.execute("PRAGMA foreign_keys = ON")
conn.execute(
    "INSERT INTO images (final_draft_id, kind, path, prompt) VALUES (?, 'ai_image', ?, ?)",
    (fid, path, prompt),
)
conn.commit(); conn.close()
PY
    echo "ai_image written to $OUTPUT_PATH"
else
    echo "pollinations fetch failed" >&2
    exit 3
fi
