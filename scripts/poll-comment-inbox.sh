#!/usr/bin/env bash
# Polls the dedicated comment-notification inbox over IMAP, parses each
# new LinkedIn notification email, inserts rows into `comments`, and
# triggers run-reply.sh for each new row.
#
# LinkedIn's email format changes. The parser below is a best-effort: it
# pulls the commenter line and the quoted comment body. If LinkedIn
# changes the template, edit the regexes in the Python block.

source "$(dirname "$0")/lib.sh"
require_cmd sqlite3 python3
require_running

: "${COMMENT_INBOX_HOST:?COMMENT_INBOX_HOST required in .env}"
: "${COMMENT_INBOX_USER:?COMMENT_INBOX_USER required in .env}"
: "${COMMENT_INBOX_PASS:?COMMENT_INBOX_PASS required in .env}"
: "${COMMENT_INBOX_PORT:=993}"

# Collect new comment ids to feed to run-reply.sh after the python block.
NEW_IDS_FILE="$REPO_ROOT/tmp/new-comment-ids.txt"
: > "$NEW_IDS_FILE"

python3 - "$DB_PATH" "$NEW_IDS_FILE" <<'PY'
import email, imaplib, os, re, sqlite3, sys
from email.header import decode_header
from html.parser import HTMLParser

db_path, ids_file = sys.argv[1], sys.argv[2]

HOST = os.environ["COMMENT_INBOX_HOST"]
USER = os.environ["COMMENT_INBOX_USER"]
PASS = os.environ["COMMENT_INBOX_PASS"]
PORT = int(os.environ.get("COMMENT_INBOX_PORT", "993"))

class TextOnly(HTMLParser):
    def __init__(self):
        super().__init__()
        self.parts = []
        self.skip = 0
    def handle_starttag(self, tag, attrs):
        if tag in ("script", "style"):
            self.skip += 1
    def handle_endtag(self, tag):
        if tag in ("script", "style") and self.skip > 0:
            self.skip -= 1
    def handle_data(self, data):
        if not self.skip:
            self.parts.append(data)
    def text(self):
        return re.sub(r"\s+", " ", " ".join(self.parts)).strip()

def decode(s):
    if not s:
        return ""
    out = []
    for part, enc in decode_header(s):
        if isinstance(part, bytes):
            out.append(part.decode(enc or "utf-8", errors="replace"))
        else:
            out.append(part)
    return "".join(out)

def extract_body(msg):
    if msg.is_multipart():
        plain = html = ""
        for part in msg.walk():
            ct = part.get_content_type()
            if ct == "text/plain" and not plain:
                plain = part.get_payload(decode=True).decode(
                    part.get_content_charset() or "utf-8", errors="replace")
            elif ct == "text/html" and not html:
                raw = part.get_payload(decode=True).decode(
                    part.get_content_charset() or "utf-8", errors="replace")
                p = TextOnly(); p.feed(raw); html = p.text()
        return plain or html
    payload = msg.get_payload(decode=True) or b""
    return payload.decode(msg.get_content_charset() or "utf-8", errors="replace")

def parse_linkedin(subject, body):
    """
    Pull out (commenter_name, commenter_title, comment_text, post_ref_text).
    LinkedIn subject pattern (varies): "Name commented on your post"
    Body usually contains the comment text in quotes / blockquote.
    """
    commenter_name = ""
    commenter_title = ""
    comment_text = ""
    post_ref = ""

    m = re.search(r"^(.+?)\s+(?:commented|replied|mentioned you)", subject, re.IGNORECASE)
    if m:
        commenter_name = m.group(1).strip()

    quote = re.search(r"[\"“]([^\"”]{6,500})[\"”]", body)
    if quote:
        comment_text = quote.group(1).strip()
    else:
        m = re.search(r"commented on your post[:\.]?\s*(.{6,500}?)\s*(View|Reply|Like|Unsubscribe)",
                      body, re.IGNORECASE | re.DOTALL)
        if m:
            comment_text = re.sub(r"\s+", " ", m.group(1)).strip()

    pr = re.search(r"your post[:\s]+\"([^\"]{6,200})\"", body)
    if pr:
        post_ref = pr.group(1).strip()

    return commenter_name, commenter_title, comment_text, post_ref

conn = sqlite3.connect(db_path); conn.execute("PRAGMA foreign_keys = ON")
new_ids = []

with imaplib.IMAP4_SSL(HOST, PORT) as M:
    M.login(USER, PASS)
    M.select("INBOX")
    typ, data = M.search(None, '(FROM "notifications-noreply@linkedin.com" UNSEEN SUBJECT "commented")')
    if typ != "OK":
        print("imap search failed", file=sys.stderr); sys.exit(1)
    for num in data[0].split():
        typ, msg_data = M.fetch(num, "(RFC822)")
        if typ != "OK":
            continue
        msg = email.message_from_bytes(msg_data[0][1])
        message_id = decode(msg.get("Message-ID", ""))
        subject    = decode(msg.get("Subject", ""))
        body       = extract_body(msg)
        name, title, text, post_ref = parse_linkedin(subject, body)
        if not text:
            continue  # couldn't parse — leave unread for manual review
        try:
            cur = conn.execute("""
                INSERT INTO comments
                    (email_message_id, commenter_name, commenter_title,
                     comment_text, post_ref_text)
                VALUES (?, ?, ?, ?, ?)
            """, (message_id, name, title, text, post_ref))
            new_ids.append(cur.lastrowid)
            M.store(num, "+FLAGS", "\\Seen")
        except sqlite3.IntegrityError:
            M.store(num, "+FLAGS", "\\Seen")  # dup
            continue

conn.commit(); conn.close()
with open(ids_file, "w") as f:
    for cid in new_ids:
        f.write(f"{cid}\n")
print(f"new comments: {len(new_ids)}")
PY

# Generate reply drafts for each new comment.
while read -r cid; do
    [ -z "$cid" ] && continue
    "$(dirname "$0")/run-reply.sh" "$cid" || echo "reply gen failed for comment_id=$cid" >&2
done < "$NEW_IDS_FILE"

# Send a batched notification listing the new reply drafts.
PENDING="$(sqlite_json "
    SELECT rd.id AS reply_id, rd.suggested_reply, rd.no_reply_recommended,
           rd.reason, c.commenter_name, c.comment_text
    FROM reply_drafts rd
    JOIN comments c ON c.id = rd.comment_id
    WHERE rd.status = 'pending' AND rd.created_at >= datetime('now', '-2 hours')
    ORDER BY rd.created_at DESC;
")"

if [ "$PENDING" != "[]" ]; then
    export PENDING
    BODY="$(python3 -c "
import json, os
items = json.loads(os.environ['PENDING'])
out = []
for i, x in enumerate(items, 1):
    if x['no_reply_recommended']:
        out.append(f\"{i}. [{x['commenter_name']}] — NO REPLY suggested. Reason: {x['reason']}\\n   Comment: {x['comment_text']}\\n\")
    else:
        out.append(f\"{i}. [{x['commenter_name']}] said: {x['comment_text']}\\n   Suggested reply (reply_id={x['reply_id']}):\\n   {x['suggested_reply']}\\n\")
print('\\n'.join(out))
")"
    export BODY
    export SUBJECT="[LinkedIn pipeline] $(printf '%s' "$PENDING" | python3 -c "import json,sys; print(len(json.load(sys.stdin)))") new reply drafts"
    "$(dirname "$0")/notify.sh" || true
fi

log_run "poll-comment-inbox" "" "ok" "ran"
