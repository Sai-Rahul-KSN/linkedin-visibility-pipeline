# LinkedIn Visibility Pipeline

Semi-automated pipeline that builds niche visibility on LinkedIn around
data engineering, GIS / geospatial, and the convergence between them.

The spec this implements is `../linkedin-visibility.md` (v4).

## Status of this scaffold

This is the **full scaffold**, not a finished system. What's here:

- Config templates (`config/`)
- JSON schemas for the agent loop (`schemas/`)
- Prompt templates (`prompts/`)
- Shell helpers that wrap `claude -p` (`scripts/`)
- SQLite schema (`db/init.sql`)
- n8n workflow JSON stubs (`workflows/`)
- `.env.example` and `.gitignore`

What you still need to do:

1. Fill in `config/voice-profile.md` — **the single biggest determinant of output quality.**
2. Copy `.env.example` to `.env` and fill in credentials.
3. Install the missing prerequisites (see below).
4. Import the workflow JSON stubs into n8n and wire up the credentials.
5. Run `db/init.sql` against `data/visibility.sqlite`.

## Prerequisites

Already present on this machine: `claude`, `python3`, `git`.
Not yet installed (commands you'll want to run yourself):

```bash
# n8n (orchestration)
npm install -g n8n

# mermaid-cli (diagram rendering)
npm install -g @mermaid-js/mermaid-cli

# Python libs for chart rendering
pip3 install matplotlib plotly pandas
```

For AI images you also need a Pollinations key — sign up at
`enter.pollinations.ai` and put the `pk_...` value into `.env`.

## Layout

```
config/             editable config the agents read at runtime
schemas/            JSON schemas the agent loop validates against
prompts/            user-prompt templates for each Claude call
scripts/            shell wrappers around `claude -p` and renderers
workflows/          n8n workflow JSON (import via n8n UI)
db/init.sql         SQLite schema
data/               runtime SQLite + generated images (gitignored)
.env.example        copy to .env and fill in
```

## How the agent loop runs (every 3 days)

```
ingest_items ──► scripts/run-writer.sh   ──► writer_drafts
                 scripts/run-critic.sh   ──► critic_reviews (per candidate)
                 scripts/run-reviser.sh  ──► final_drafts (conditional)
                 scripts/render-*.sh     ──► images/
                 scripts/notify.sh       ──► email to user
```

The scripts are designed to be invoked from n8n's Execute Command node
with arguments — they read input from stdin/files and emit JSON on
stdout. You can also run them by hand to test.

## First-run smoke test

After filling in `.env` and `voice-profile.md`:

```bash
sqlite3 data/visibility.sqlite < db/init.sql

# Seed a fake ingest item to test the writer
sqlite3 data/visibility.sqlite "INSERT INTO ingest_items
  (title, summary, link, source, fetched_at)
  VALUES ('DuckDB 1.4 ships spatial improvements',
          'New ST_* functions and Parquet read performance.',
          'https://example.invalid/x', 'duckdb', datetime('now'));"

scripts/run-writer.sh
```

## Safety constraints (locked in by spec section 3)

- Nothing posts to LinkedIn without you approving it and pasting it.
- No replies sent without you sending them.
- No scraping. No auto-following. No bought engagement.
- No paid APIs added without your explicit approval.

These are enforced by the system never holding LinkedIn credentials.
