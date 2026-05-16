# n8n workflows

These workflows live in n8n. Each one is a thin trigger (cron or webhook)
that calls a shell script under `../scripts/`. The shell scripts do the real
work; n8n is reduced to a scheduler + dispatcher.

## How to import

In n8n: **Workflows → Import from File**. After importing each one:

1. Open the trigger node and set the cron expression / verify the path.
2. Open every **Execute Command** node and verify the path matches where
   you cloned this repo (the stubs assume `~/Desktop/linkedin-visibility`).
3. Save and **Activate**.

For the IMAP-based comment poll you'll add Gmail app-password credentials
in n8n (or just rely on the env vars the shell script reads — the script
handles its own IMAP connection, so n8n credentials are optional).

## The 10 workflows (matches spec section 9)

| # | File | Trigger | Calls | Notes |
|---|---|---|---|---|
| 9.1 | `ingest-feeds.json` | cron `RSS_INGEST_CRON` | `ingest-feeds.sh` | No Claude call. Parses RSS/Atom in Python stdlib. |
| 9.2 | `drafting-cycle.json` | cron `DRAFTING_CRON` | `drafting-cycle.sh` | Orchestrates writer → critic → reviser. By default also calls the image and notify scripts inline. |
| 9.3 | `generate-image.json` | webhook `POST /generate-image` | `generate-image.sh <final_draft_id>` | Branches to chart / diagram / ai_image based on `visual_type`. |
| 9.4 | `notify-final-draft.json` | webhook `POST /notify-final-draft` | `notify-final-draft.sh <final_draft_id>` | Sends email with draft text + image attachment. |
| 9.5 | `approve-draft.json` | webhook `POST /approve-draft` | `approve-draft.sh <final_draft_id> <approve\|edit\|reject> [user_edit]` | Records decision; sends ready-to-paste block to user. |
| 9.6 | `mark-posted.json` | webhook `POST /mark-posted` | `mark-posted.sh <final_draft_id> <linkedin_url>` | User submits after pasting into LinkedIn. |
| 9.7 | `poll-comment-inbox.json` | cron `COMMENT_POLL_CRON` | `poll-comment-inbox.sh` | IMAP fetch + parse via Python stdlib. Triggers reply suggestion per new row. |
| 9.8 | `draft-reply-suggestions.json` | webhook `POST /draft-reply-suggestion` | `run-reply.sh <comment_id>` | Generates one reply suggestion. |
| 9.9 | `weekly-metrics-form.json` | cron `WEEKLY_METRICS_CRON` | `weekly-metrics-form.sh` | Sends user the form to fill in. |
| 9.10 | `weekly-summary.json` | cron `WEEKLY_SUMMARY_CRON` | `run-weekly-summary.sh` | Claude-generated summary email. |

## Two ways to run the drafting cycle

The **default** wiring uses `drafting-cycle.sh` as one big shell orchestrator
that calls image + notify inline. This is the simplest path — one cron, one
script, no inter-workflow webhooks to wire up.

The **spec-faithful** alternative uses separate workflows (9.3, 9.4)
triggered by webhooks from inside the drafting cycle. To switch to this:

1. Edit `drafting-cycle.sh` and replace the `generate-image.sh` /
   `notify-final-draft.sh` calls with `curl` calls to the n8n webhooks.
2. Activate `generate-image.json` and `notify-final-draft.json` in n8n.

The two patterns are equivalent functionally. The shell-orchestrator path
is easier to reason about; the webhook path gives you n8n's per-workflow
retry, history, and per-node visibility, which becomes useful once you're
debugging individual failures in production.
