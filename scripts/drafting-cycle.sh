#!/usr/bin/env bash
# Orchestrates the full writer → critic → reviser flow for one cycle.
# Idempotent enough to run by hand; n8n calls the sub-scripts individually
# via Execute Command nodes, but this is a convenient shortcut for testing.

source "$(dirname "$0")/lib.sh"
require_cmd "$CLAUDE_CMD" sqlite3 jq python3
require_running

SCRIPT_DIR="$(dirname "$0")"

echo "→ running writer..."
RUN_ID="$("$SCRIPT_DIR/run-writer.sh")"
if [ -z "$RUN_ID" ]; then
    echo "writer produced nothing; aborting cycle" >&2
    exit 0
fi
echo "  run_id=$RUN_ID"

# Get the new writer_drafts ids for this run.
CANDIDATE_IDS="$(sqlite3 "$DB_PATH" "SELECT id FROM writer_drafts WHERE run_id = '$RUN_ID' ORDER BY id;")"

FINAL_COUNT=0
DISCARD_REASONS=()

for WID in $CANDIDATE_IDS; do
    echo "→ critic on writer_draft_id=$WID..."
    VERDICT="$("$SCRIPT_DIR/run-critic.sh" "$WID")"
    echo "  verdict=$VERDICT"

    case "$VERDICT" in
        publish_as_is)
            # Copy directly to final_drafts with revised=0.
            python3 - "$DB_PATH" "$WID" <<'PY'
import sqlite3, sys
db, wid = sys.argv[1], int(sys.argv[2])
conn = sqlite3.connect(db); conn.execute("PRAGMA foreign_keys = ON")
row = conn.execute(
    "SELECT post_text, visual_type, visual_description FROM writer_drafts WHERE id = ?",
    (wid,)
).fetchone()
if row is None:
    sys.exit(1)
conn.execute("""
    INSERT INTO final_drafts
        (writer_draft_id, post_text, change_summary, revised,
         visual_type, visual_description)
    VALUES (?, ?, NULL, 0, ?, ?)
""", (wid, row[0], row[1], row[2]))
conn.commit(); conn.close()
PY
            FINAL_COUNT=$((FINAL_COUNT + 1))
            ;;
        revise)
            "$SCRIPT_DIR/run-reviser.sh" "$WID"
            FINAL_COUNT=$((FINAL_COUNT + 1))
            ;;
        discard)
            REASON="$(sqlite3 "$DB_PATH" "SELECT verdict_reason FROM critic_reviews WHERE writer_draft_id = $WID;")"
            DISCARD_REASONS+=("draft $WID: $REASON")
            ;;
        *)
            echo "unknown verdict '$VERDICT' for writer_draft_id=$WID" >&2
            ;;
    esac
done

if [ "$FINAL_COUNT" -eq 0 ]; then
    REASONS_STR="$(printf '%s\n' "${DISCARD_REASONS[@]}")"
    echo "All candidates discarded. Notifying user." >&2
    DRAFT_BODY="Drafting run $RUN_ID produced no usable candidates.

Critic reasons:
$REASONS_STR"
    SUBJECT="[LinkedIn pipeline] no drafts this cycle"
    BODY="$DRAFT_BODY" SUBJECT="$SUBJECT" "$SCRIPT_DIR/notify.sh" || true
    log_run "drafting-cycle" "$RUN_ID" "warn" "all candidates discarded"
    exit 0
fi

# Trigger image + notification for each new final_draft from this run.
NEW_FINAL_IDS="$(sqlite3 "$DB_PATH" "
    SELECT fd.id FROM final_drafts fd
    JOIN writer_drafts wd ON wd.id = fd.writer_draft_id
    WHERE wd.run_id = '$RUN_ID'
    ORDER BY fd.id;
")"

for FID in $NEW_FINAL_IDS; do
    echo "→ generating image for final_draft_id=$FID..."
    "$SCRIPT_DIR/generate-image.sh" "$FID" || echo "  image generation failed (non-blocking)"
    echo "→ notifying user for final_draft_id=$FID..."
    "$SCRIPT_DIR/notify-final-draft.sh" "$FID" || echo "  notify failed"
done

log_run "drafting-cycle" "$RUN_ID" "ok" "$FINAL_COUNT final drafts"
echo "cycle complete: $FINAL_COUNT final drafts"
