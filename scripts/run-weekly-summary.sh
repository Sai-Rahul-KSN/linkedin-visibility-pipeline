#!/usr/bin/env bash
# Builds the weekly summary email by feeding metrics through claude.

source "$(dirname "$0")/lib.sh"
require_cmd "$CLAUDE_CMD" sqlite3 jq python3
require_running

POSTS_JSON="$(sqlite_json "
    SELECT p.id AS post_id,
           p.linkedin_url,
           p.posted_at,
           fd.post_text,
           wm.impressions, wm.reactions, wm.comments_count,
           wm.reposts, wm.profile_views, wm.search_appearances,
           wm.inbound_messages, wm.week_starting
    FROM posts p
    JOIN final_drafts fd  ON fd.id = p.final_draft_id
    LEFT JOIN weekly_metrics wm ON wm.post_id = p.id
    WHERE p.posted_at >= datetime('now', '-7 days')
    ORDER BY p.posted_at DESC;
")"

BASELINE_JSON="$(sqlite_json "
    WITH recent AS (
        SELECT impressions, reactions, comments_count, reposts,
               profile_views, search_appearances, inbound_messages
        FROM weekly_metrics
        WHERE logged_at >= datetime('now', '-35 days')
          AND logged_at <  datetime('now', '-7 days')
    )
    SELECT
        (SELECT impressions       FROM recent ORDER BY impressions       LIMIT 1 OFFSET (SELECT COUNT(*)/2 FROM recent)) AS median_impressions,
        (SELECT reactions         FROM recent ORDER BY reactions         LIMIT 1 OFFSET (SELECT COUNT(*)/2 FROM recent)) AS median_reactions,
        (SELECT comments_count    FROM recent ORDER BY comments_count    LIMIT 1 OFFSET (SELECT COUNT(*)/2 FROM recent)) AS median_comments,
        (SELECT profile_views     FROM recent ORDER BY profile_views     LIMIT 1 OFFSET (SELECT COUNT(*)/2 FROM recent)) AS median_profile_views;
")"

if [ "$POSTS_JSON" = "[]" ]; then
    echo "no posts in the last 7 days — sending 'data unavailable' note"
    export SUBJECT="[LinkedIn pipeline] weekly summary — no posts"
    export BODY="No posts in the last 7 days. Nothing to summarize."
    "$(dirname "$0")/notify.sh"
    exit 0
fi

export POSTS_JSON BASELINE_JSON
USER_PROMPT="$(render_template "$REPO_ROOT/prompts/weekly-summary.txt")"

# This call doesn't need structured output; just text.
SUMMARY="$("$CLAUDE_CMD" -p \
    --model "$CLAUDE_MODEL" \
    --output-format json \
    --allowed-tools "" \
    --append-system-prompt "$(cat "$REPO_ROOT/config/voice-profile.md")" \
    "$USER_PROMPT" | jq -r '.result')"

export SUBJECT="[LinkedIn pipeline] weekly summary"
export BODY="$SUMMARY"
"$(dirname "$0")/notify.sh"
