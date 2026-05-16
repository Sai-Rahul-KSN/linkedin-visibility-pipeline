#!/usr/bin/env bash
# Records that the user posted a draft. Inserts into posts and flips status.
# Usage: mark-posted.sh <final_draft_id> <linkedin_url>

source "$(dirname "$0")/lib.sh"
require_cmd sqlite3 python3

FINAL_DRAFT_ID="${1:?final_draft_id required}"
LINKEDIN_URL="${2:?linkedin_url required}"

python3 - "$DB_PATH" "$FINAL_DRAFT_ID" "$LINKEDIN_URL" <<'PY'
import sqlite3, sys
db, fid, url = sys.argv[1], int(sys.argv[2]), sys.argv[3]
conn = sqlite3.connect(db); conn.execute("PRAGMA foreign_keys = ON")
img = conn.execute(
    "SELECT id FROM images WHERE final_draft_id = ? ORDER BY id DESC LIMIT 1",
    (fid,),
).fetchone()
image_id = img[0] if img else None
conn.execute(
    "INSERT INTO posts (final_draft_id, image_id, linkedin_url) VALUES (?, ?, ?)",
    (fid, image_id, url),
)
conn.execute(
    "UPDATE final_drafts SET status='posted', decided_at=datetime('now') WHERE id=?",
    (fid,),
)
conn.commit(); conn.close()
print(f"marked posted: final_draft_id={fid}")
PY
