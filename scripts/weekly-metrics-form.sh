#!/usr/bin/env bash
# Sends the user an email listing the past week's posts with empty metric
# fields they can fill in and reply with (or run a sqlite insert).

source "$(dirname "$0")/lib.sh"
require_cmd sqlite3 jq python3

WEEK_START="$(python3 -c "import datetime; d=datetime.date.today(); print((d - datetime.timedelta(days=d.weekday())).isoformat())")"

POSTS="$(sqlite_json "
    SELECT p.id, p.linkedin_url, p.posted_at, substr(fd.post_text, 1, 80) AS preview
    FROM posts p
    JOIN final_drafts fd ON fd.id = p.final_draft_id
    WHERE p.posted_at >= datetime('now', '-7 days')
    ORDER BY p.posted_at;
")"

if [ "$POSTS" = "[]" ]; then
    echo "no posts this week — skipping form"
    exit 0
fi

FORM="$(printf '%s' "$POSTS" | python3 -c "
import json, sys, textwrap
posts = json.load(sys.stdin)
lines = []
for p in posts:
    lines.append(f\"\"\"
post_id={p['id']}    posted_at={p['posted_at']}
url: {p['linkedin_url']}
preview: {p['preview']}…

  impressions:
  reactions:
  comments:
  reposts:
  profile_views:
  search_appearances:
  inbound_messages:

To log, paste the values into:
  sqlite3 \\\"\$DB_PATH\\\" \\\"INSERT INTO weekly_metrics
    (post_id, week_starting, impressions, reactions, comments_count, reposts,
     profile_views, search_appearances, inbound_messages)
    VALUES ({p['id']}, '$WEEK_START', <I>, <R>, <C>, <RP>, <PV>, <SA>, <IM>);\\\"
\"\"\")
print('\\n'.join(lines))
")"

export SUBJECT="[LinkedIn pipeline] weekly metrics — please fill in"
export BODY="Past week's posts. Pull these from LinkedIn analytics and log them.

$FORM"

"$(dirname "$0")/notify.sh"
