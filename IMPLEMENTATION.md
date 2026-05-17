# Implementation playbook

Go-live guide for the LinkedIn visibility pipeline. Read this end-to-end
once before starting; do the steps in order.

## Phase 0 — What's already built (no action needed)

You have: full scaffold at `~/Desktop/linkedin-visibility`, n8n + mmdc
installed, ECC plugin registered, smoke test passing, GitHub repo live.
Skip to Phase 1.

---

## Phase 1 — Load the project in Claude Code with the plugin active (5 min)

The ECC plugin gives you access to 230 skills *inside this project*,
including `brand-voice` which you'll use in Phase 2.

```bash
cd ~/Desktop/linkedin-visibility
claude
```

First time only: Claude Code will prompt to **trust the `ecc@ecc` plugin**.
Say yes. (It's installing files from a third-party GitHub repo — that's
why the prompt exists.) You can verify it loaded with:

```
/plugins
```

You should see `ecc@ecc` in the enabled list. If you type `/` you'll now
see ECC's commands like `/loop-start`, `/cost-report`, etc., and if you
ask Claude to "use the brand-voice skill" it will resolve to the plugin's
skill rather than failing.

**If trust prompt didn't appear:** the plugin probably needs a Claude
Code restart to pick up the new `.claude/settings.json`. Close, reopen,
retry `/plugins`.

---

## Phase 2 — Build your voice profile (30–60 min) ⭐ most important step

The bottleneck of this whole pipeline is `config/voice-profile.md`. Don't
skip this; don't fake it.

### 2a. Collect your source material (15 min)

Find **5 to 20 pieces of writing that sound like you at your best**:

- Past LinkedIn posts you're proud of (even if they didn't perform well)
- Old blog posts, README intros, technical write-ups
- DMs/emails where you explained something well
- Side-project descriptions

Paste them into a single scratch file — e.g. `/tmp/source-posts.md` —
separated with `---`.

### 2b. Run the brand-voice skill inside this project (15 min)

In your Claude Code session (still in this project directory), say:

> Use the brand-voice skill. Read /tmp/source-posts.md. Build a VOICE
> PROFILE matching the schema in the skill's
> references/voice-profile-schema.md. My target audience is data
> engineering and GIS recruiters and technical peers. Goal: visibility
> for hiring conversations. Be specific in every section — every line
> in the profile should be observable in the source posts.

Claude will use the skill to extract rhythm, compression, capitalization
norms, parenthetical use, claim style, preferred/banned moves, CTA rules,
channel notes.

### 2c. Paste the result into voice-profile.md (10 min)

Open `config/voice-profile.md`. The bottom of the file has a `VOICE PROFILE`
block with placeholder fields — replace those with what the skill produced.

Then fill in the **top half** of the file too:

- Who you are professionally
- Specific tools, hard-won lessons, what you're still figuring out
- Niches to post about and niches to avoid
- 3–5 example posts in the "Example posts I like" section (these go into
  the writer's context)

### 2d. Iterate (5–15 min)

Run the smoke test against your real profile:

```bash
bash scripts/smoke-test.sh
```

Read the two drafts it produces. Ask honestly: **would I actually post
this from my account?**

- If yes → move to Phase 3.
- If no → identify what's off (too generic? wrong cadence? wrong
  vocabulary?) → tighten the relevant section of `voice-profile.md` →
  re-run. Two or three iterations usually nails it.

---

## Phase 3 — Credentials and external setup (15–25 min)

### 3a. Copy the env template

```bash
cp .env.example .env
```

### 3b. Gmail app password + LinkedIn forwarding rule (10 min)

This is the only fiddly external dependency.

1. In your Gmail account → **Settings → See all settings → Forwarding
   and POP/IMAP → Enable IMAP**.
2. Go to https://myaccount.google.com/apppasswords → generate a 16-char
   app password (you'll need 2-step verification enabled first). Copy it.
3. Open `.env`, set:

   ```
   COMMENT_INBOX_USER=youraddress@gmail.com
   COMMENT_INBOX_PASS=<16-char app password>
   SMTP_USER=youraddress@gmail.com
   SMTP_PASS=<same 16-char app password>
   NOTIFY_TO=youraddress@gmail.com
   ```
4. In your **LinkedIn-registered email** (separate from the one above,
   ideally), create a filter:
   - From: `notifications-noreply@linkedin.com`
   - Subject contains: `commented`
   - Action: **Forward to** your dedicated Gmail (the one above). Or
     apply a label and rely on IMAP filtering.

### 3c. Pollinations API key (3 min)

Only needed if you want AI images. Sign up at `enter.pollinations.ai` →
generate a `pk_...` key → paste into `.env` as `POLLINATIONS_API_KEY=`.

If you'd rather skip AI images for now, set `AI_IMAGE_ENABLED=false` and
leave the key blank. You still get charts + diagrams.

### 3d. Verify SMTP works (2 min)

```bash
cd ~/Desktop/linkedin-visibility
BODY="test" SUBJECT="pipeline smtp test" bash scripts/notify.sh
```

Check your inbox. If nothing arrives in 1 minute, the credentials are
wrong — most common cause: using your Gmail password instead of an app
password.

---

## Phase 4 — Start n8n and activate workflows (10 min)

### 4a. Start n8n

Open a dedicated terminal tab:

```bash
n8n start
```

It binds to `http://localhost:5678`. Keep this terminal open whenever you
want the pipeline running. (Closing it stops all the cron schedules.)

### 4b. First-time owner setup

Open `http://localhost:5678` in a browser. Set up an admin account (any
email/password — this is local-only). Skip the onboarding survey.

### 4c. Activate the workflows

In the n8n UI, click **Workflows** in the left nav. You'll see all 10:

```
ingest-feeds
drafting-cycle
poll-comment-inbox
mark-posted
approve-draft
generate-image
notify-final-draft
draft-reply-suggestions
weekly-metrics-form
weekly-summary
```

For each cron-triggered one, open it and toggle **Active** in the
top-right. Specifically activate:

- `ingest-feeds` (daily 6am — pulls RSS)
- `drafting-cycle` (every 3 days 9am — generates drafts)
- `poll-comment-inbox` (hourly — checks for comments)
- `weekly-metrics-form` (Sunday 7pm — sends you the form)
- `weekly-summary` (Sunday 9pm — sends the Claude-written summary)

The webhook workflows (`mark-posted`, `approve-draft`, `generate-image`,
`notify-final-draft`, `draft-reply-suggestions`) don't need activation in
the same sense — they only fire when their endpoint is hit. You can
leave them inactive unless you start using their URLs.

---

## Phase 5 — First real drafting cycle (5 min wait + your review time)

### 5a. Seed the database with real RSS items

Don't wait for tomorrow's cron — trigger ingest now:

```bash
bash scripts/ingest-feeds.sh
```

This pulls every feed in `config/sources.yaml`, dedupes, inserts into
`ingest_items`. Should take 30 seconds and report something like
"inserted=42 failed_feeds=0".

### 5b. Trigger a drafting cycle by hand

Don't wait three days either:

```bash
bash scripts/drafting-cycle.sh
```

This will:

1. Pick 5 most-recent unused ingest items
2. Run the writer → produce 2 candidates
3. Run the critic on each → score and verdict
4. Run the reviser on any with verdict `revise`
5. Generate an image for each final draft (chart, diagram, or AI image
   based on the writer's suggestion)
6. Email you the result via `notify-final-draft.sh`

Expect this to take **2–4 minutes** and cost roughly **$0.10–0.20** in
Claude credits.

### 5c. Receive the email, approve, post

Check your inbox. You'll get one email per final draft (usually 2) with:

- The post text (800–1500 chars)
- The image attached
- A summary of changes the reviser made
- Instructions for marking it posted

If a draft is good: copy the text, paste into LinkedIn's native post
composer, attach the image, schedule or publish.

After publishing, **run this with the LinkedIn post URL**:

```bash
bash scripts/mark-posted.sh <final_draft_id> https://www.linkedin.com/posts/...
```

(The email tells you which `final_draft_id` to use.) This creates the
`posts` row that comments and metrics will link back to.

If a draft isn't good: discard it. Edit `voice-profile.md` based on why
it was off, and wait for the next cron — or trigger another cycle
manually.

---

## Phase 6 — Steady state (ongoing)

| Cadence | What happens | Your action |
|---|---|---|
| Daily 6am | `ingest-feeds` runs | None |
| Every 3 days 9am | `drafting-cycle` produces 2 drafts | Read email, post 0–2 to LinkedIn, mark posted |
| Hourly | `poll-comment-inbox` checks for LinkedIn notifications | None — drafts appear when there are comments |
| When a draft reply lands in your inbox | You receive a suggested reply | Copy if good, send manually on LinkedIn |
| Sunday 7pm | `weekly-metrics-form` sends you a form | Go to LinkedIn analytics, fill in impressions/reactions/etc., reply |
| Sunday 9pm | `weekly-summary` sends a Claude-written recap | Read it; let it inform next week |

Two important habits:

1. **Always paste the LinkedIn URL via `mark-posted.sh` after publishing.**
   Without this, metrics won't link back to drafts, and the weekly summary
   will be empty.
2. **Don't rubber-stamp.** The moment you stop reading drafts carefully
   is the moment the audience starts smelling them. The system makes
   drafting cheap; it cannot make taste cheap.

---

## Phase 7 — Iteration (week 4 onward)

After ~6 posts, the weekly summary has real signal. Look for:

- **Best-performing post**: what was the hook pattern? The topic? The
  visual type? Update `voice-profile.md` → "Preferred Moves" with what's
  working.
- **Worst-performing post**: what made it land flat? Add the pattern to
  `voice-profile.md` → "Banned Moves" or `style-guide.md` → "Banned
  patterns".

You can re-run brand-voice with your *own* recent posts as source
material:

> Use the brand-voice skill on the past 8 LinkedIn posts in my `posts`
> table (run `sqlite3 data/visibility.sqlite "SELECT fd.post_text FROM
> posts p JOIN final_drafts fd ON fd.id=p.final_draft_id ORDER BY
> p.posted_at DESC LIMIT 8;"` to get them). Update the VOICE PROFILE
> block at the bottom of `config/voice-profile.md` based on what's
> actually working.

That's the compounding loop: pipeline produces drafts → you pick the
best → those become the new source material → the voice profile gets
sharper → drafts get better.

---

## Other ECC skills worth knowing about

The plugin install means these are available to you in this project —
invoke by asking Claude to "use the X skill":

| Skill | When you'd use it |
|---|---|
| `brand-voice` | Phase 2 above, plus quarterly refreshes |
| `article-writing` | If you want to write a longform blog/newsletter piece that pulls themes from your LinkedIn posts |
| `content-engine` | If you decide to cross-post to X / Substack / etc. — it handles platform adaptation |
| `continuous-agent-loop` | If you want to extend the pipeline (e.g. add a researcher agent, a fact-checker, etc.) — reference patterns for loop architecture |
| `cost-tracking` | Only useful if you also install a cost-tracker hook; tells you how much Claude spend the pipeline has incurred |

---

## Common failure modes and fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| Drafts are technically correct but sound generic | `voice-profile.md` is still half-template | Re-run Phase 2 with more source material |
| `n8n start` fails with port-in-use | n8n already running in another terminal | `pkill -f "n8n start"` then retry |
| No email arriving on draft notification | Gmail app password wrong, or 2FA not enabled on the SMTP account | Re-do Phase 3b; test with `BODY=test SUBJECT=test bash scripts/notify.sh` |
| `drafting-cycle.sh` says "no unused ingest items" | RSS hasn't run yet | `bash scripts/ingest-feeds.sh` first |
| Cron fired but nothing visible happened | `SYSTEM_PAUSED=true` in `.env` | Flip to `false` |
| Comments are appearing in inbox but `comments` table is empty | LinkedIn changed their email template — parser regex needs updating | Edit `scripts/poll-comment-inbox.sh`, the python block has the regexes |

---

## Stopping the pipeline

Three levels, pick the right one for the situation:

### Level 1 — Pause future runs (graceful, recommended)

For "stop scheduling new work but let anything in flight finish."

```bash
sed -i '' 's/^SYSTEM_PAUSED=false/SYSTEM_PAUSED=true/' .env
```

Every script checks `require_running` near its top. The next cron tick
sees the flag and exits with status 0. To resume: flip back to `false`.
No restart needed.

### Level 2 — Kill the current script (loop is mid-execution)

For "I'm watching a script run and I want to stop it now."

- **In a terminal:** Ctrl-C
- **In n8n UI:** Executions tab → find running execution → Stop
- **Don't know which terminal:**
  ```bash
  pgrep -lf "scripts/drafting-cycle\|scripts/run-\|claude -p"
  kill <pid>
  ```

### Level 3 — Stop n8n entirely (the whole scheduler goes away)

```bash
pkill -f "n8n start"
pgrep -f "n8n start" && echo "still running" || echo "stopped"
```
