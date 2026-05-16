#!/usr/bin/env bash
# Send an email notification using the SMTP_* env vars.
# Reads BODY from env (multiline ok). Subject from SUBJECT env. Optional ATTACHMENT.

source "$(dirname "$0")/lib.sh"
require_cmd python3

: "${SUBJECT:?SUBJECT required}"
: "${BODY:?BODY required}"
: "${NOTIFY_TO:?NOTIFY_TO required (in .env)}"
: "${SMTP_HOST:?SMTP_HOST required}"
: "${SMTP_USER:?SMTP_USER required}"
: "${SMTP_PASS:?SMTP_PASS required}"
: "${SMTP_PORT:=587}"

ATTACHMENT="${ATTACHMENT:-}"

python3 - <<PY
import os, smtplib, ssl
from email.message import EmailMessage
from pathlib import Path

msg = EmailMessage()
msg["From"]    = os.environ["SMTP_USER"]
msg["To"]      = os.environ["NOTIFY_TO"]
msg["Subject"] = os.environ["SUBJECT"]
msg.set_content(os.environ["BODY"])

att = os.environ.get("ATTACHMENT", "")
if att and Path(att).exists():
    data = Path(att).read_bytes()
    msg.add_attachment(data, maintype="image", subtype="png", filename=Path(att).name)

ctx = ssl.create_default_context()
with smtplib.SMTP(os.environ["SMTP_HOST"], int(os.environ["SMTP_PORT"])) as s:
    s.starttls(context=ctx)
    s.login(os.environ["SMTP_USER"], os.environ["SMTP_PASS"])
    s.send_message(msg)
print("sent")
PY
