-- LinkedIn Visibility Pipeline — SQLite schema.
-- Idempotent: re-running is safe.
-- Apply with: sqlite3 data/visibility.sqlite < db/init.sql

PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;

-- Raw RSS items pulled by the daily ingest job.
CREATE TABLE IF NOT EXISTS ingest_items (
    id           INTEGER PRIMARY KEY AUTOINCREMENT,
    title        TEXT    NOT NULL,
    summary      TEXT,
    link         TEXT    NOT NULL,
    link_hash    TEXT    NOT NULL UNIQUE,             -- sha256(link) for dedupe
    source       TEXT    NOT NULL,                    -- feed key from sources.yaml
    fetched_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    used_at      TEXT                                  -- set when consumed by writer
);
CREATE INDEX IF NOT EXISTS idx_ingest_unused
    ON ingest_items (used_at, fetched_at DESC);

-- Initial candidates from the writer agent (1 row per candidate).
CREATE TABLE IF NOT EXISTS writer_drafts (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    run_id              TEXT    NOT NULL,             -- groups candidates from one run
    source_item_id      INTEGER NOT NULL REFERENCES ingest_items(id),
    post_text           TEXT    NOT NULL,
    rationale           TEXT,
    visual_type         TEXT    NOT NULL CHECK (visual_type IN
        ('chart', 'diagram', 'screenshot_suggestion', 'ai_image', 'none')),
    visual_description  TEXT,
    created_at          TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_writer_drafts_run ON writer_drafts (run_id);

-- Per-candidate verdicts and rubric scores from the critic.
CREATE TABLE IF NOT EXISTS critic_reviews (
    id                          INTEGER PRIMARY KEY AUTOINCREMENT,
    writer_draft_id             INTEGER NOT NULL UNIQUE REFERENCES writer_drafts(id),
    hook_strength               INTEGER NOT NULL CHECK (hook_strength BETWEEN 1 AND 5),
    voice_match                 INTEGER NOT NULL CHECK (voice_match BETWEEN 1 AND 5),
    has_real_take               INTEGER NOT NULL CHECK (has_real_take BETWEEN 1 AND 5),
    style_guide_adherence       INTEGER NOT NULL CHECK (style_guide_adherence BETWEEN 1 AND 5),
    specificity                 INTEGER NOT NULL CHECK (specificity BETWEEN 1 AND 5),
    ai_isms_detected            TEXT    NOT NULL DEFAULT '[]',  -- JSON array
    style_violations            TEXT    NOT NULL DEFAULT '[]',  -- JSON array
    specific_improvement_notes  TEXT    NOT NULL DEFAULT '[]',  -- JSON array
    verdict                     TEXT    NOT NULL CHECK (verdict IN
        ('publish_as_is', 'revise', 'discard')),
    verdict_reason              TEXT,
    created_at                  TEXT    NOT NULL DEFAULT (datetime('now'))
);

-- Drafts after the agent loop, awaiting user approval.
CREATE TABLE IF NOT EXISTS final_drafts (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    writer_draft_id     INTEGER NOT NULL UNIQUE REFERENCES writer_drafts(id),
    post_text           TEXT    NOT NULL,
    change_summary      TEXT,                          -- from reviser, if it ran
    revised             INTEGER NOT NULL DEFAULT 0,    -- 1 if reviser produced this
    visual_type         TEXT    NOT NULL,
    visual_description  TEXT,
    status              TEXT    NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'edited', 'rejected', 'posted')),
    user_edit           TEXT,                          -- final text after user edits, if any
    created_at          TEXT    NOT NULL DEFAULT (datetime('now')),
    decided_at          TEXT
);
CREATE INDEX IF NOT EXISTS idx_final_drafts_status ON final_drafts (status, created_at DESC);

-- Generated visuals tied to a final draft.
CREATE TABLE IF NOT EXISTS images (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    final_draft_id  INTEGER NOT NULL REFERENCES final_drafts(id),
    kind            TEXT    NOT NULL CHECK (kind IN ('chart', 'diagram', 'ai_image')),
    path            TEXT    NOT NULL,                  -- on-disk path under IMAGES_DIR
    prompt          TEXT,                              -- the AI image prompt, if applicable
    source_artifact TEXT,                              -- python script or mermaid spec text
    created_at      TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_images_draft ON images (final_draft_id);

-- Approved and published posts. linkedin_url filled in when user submits the mark-posted webhook.
CREATE TABLE IF NOT EXISTS posts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    final_draft_id  INTEGER NOT NULL UNIQUE REFERENCES final_drafts(id),
    image_id        INTEGER REFERENCES images(id),
    linkedin_url    TEXT    NOT NULL,
    posted_at       TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_posts_posted_at ON posts (posted_at DESC);

-- Parsed from LinkedIn notification emails. One row per inbound comment.
CREATE TABLE IF NOT EXISTS comments (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id           INTEGER REFERENCES posts(id),    -- nullable: we may not be able to match
    email_message_id  TEXT    NOT NULL UNIQUE,         -- IMAP message-id for dedupe
    commenter_name    TEXT,
    commenter_title   TEXT,
    comment_text      TEXT    NOT NULL,
    post_ref_text     TEXT,                            -- whatever post-reference we parsed
    received_at       TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_comments_received ON comments (received_at DESC);

-- Suggested replies awaiting user review. User sends manually; we never post.
CREATE TABLE IF NOT EXISTS reply_drafts (
    id                    INTEGER PRIMARY KEY AUTOINCREMENT,
    comment_id            INTEGER NOT NULL UNIQUE REFERENCES comments(id),
    suggested_reply       TEXT,
    no_reply_recommended  INTEGER NOT NULL DEFAULT 0,
    reason                TEXT,
    status                TEXT    NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'sent', 'discarded')),
    created_at            TEXT    NOT NULL DEFAULT (datetime('now')),
    decided_at            TEXT
);

-- Weekly metrics manually logged from LinkedIn's analytics UI.
CREATE TABLE IF NOT EXISTS weekly_metrics (
    id                  INTEGER PRIMARY KEY AUTOINCREMENT,
    post_id             INTEGER NOT NULL REFERENCES posts(id),
    week_starting       TEXT    NOT NULL,             -- ISO date of the Monday
    impressions         INTEGER,
    reactions           INTEGER,
    comments_count      INTEGER,
    reposts             INTEGER,
    profile_views       INTEGER,
    search_appearances  INTEGER,
    inbound_messages    INTEGER,                       -- count of new recruiter/peer DMs flagged
    note                TEXT,
    logged_at           TEXT    NOT NULL DEFAULT (datetime('now')),
    UNIQUE (post_id, week_starting)
);

-- Lightweight run log for ops visibility.
CREATE TABLE IF NOT EXISTS run_log (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    workflow    TEXT    NOT NULL,
    run_id      TEXT,
    status      TEXT    NOT NULL CHECK (status IN ('ok', 'warn', 'error')),
    message     TEXT,
    created_at  TEXT    NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_run_log_workflow ON run_log (workflow, created_at DESC);
