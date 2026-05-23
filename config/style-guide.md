# Style guide

The writer and critic both read this. Treat every rule as load-bearing.

## Post types (hybrid mode)

Every post the pipeline produces is one of two types. The writer picks the type
based on the ingest item; the critic applies the relevant rules.

### `opinion` (default, ~80% of posts)

A sharp take on a specific technical development, with one concrete claim and
supporting evidence. This is the workhorse type.

- Rules below apply in full.
- Hook must be opinionated or surprising; no "I'm excited to share" openers.
- 3–5 hashtags (2 fixed core + 1–3 contextual). See **## Hashtags** below.
- No gratitude blocks, no thanking named people.
- Forward-looking question at the end, not a CTA.

### `milestone` (occasional, ~20% of posts)

A genuine milestone moment: new role, completed project, certification,
collaboration kickoff, public artifact shipped. These are *credibility events*
the audience needs to see — under-doing them is also a mistake.

Relaxed rules (only these change vs. `opinion`):

- Hook may open with "Some news.", "Sharing a milestone.", or similar — but NOT "I'm thrilled / honored / blessed". Excited is allowed *once*, not stacked.
- May thank named individuals when the thanks is specific (their role + what they actually did), not generic ("my supervisor for mentoring me").
- 3–5 hashtags (2 fixed core + 1–3 contextual; same pool as `opinion`). See **## Hashtags** below.
- Specific outcome / artifact required — what shipped, what role, what number. Vague milestones ("excited to start this journey") still fail.

Everything else (no AI-isms, no hype phrases, no fabrication, one core claim,
numbers > adjectives) applies to BOTH types.

## Length

- **Target:** 800–1500 characters total (LinkedIn counts characters, not words).
- **Hook:** first ~210 characters must stand alone as the "see more" preview on mobile. If those 210 characters wouldn't make someone tap, the post fails.

## Structure

1. **Hook line** — a single short sentence. Concrete, opinionated, or surprising.
2. **Context** — 1–2 short paragraphs setting up the take. No throat-clearing.
3. **The take** — the actual opinion or claim. One claim, sharply stated.
4. **Forward-looking question** — invites a real reply. Not a CTA, not "thoughts?".

## Formatting

- Plain text only. LinkedIn does not render markdown.
- Short paragraphs (1–3 lines). Use generous line breaks between paragraphs.
- No bullet characters (`-`, `*`, `•`) unless the post is genuinely list-shaped, and then never more than 3 bullets.
- No bold, italics, headers — they render as the raw characters.
- Numbers and proper nouns get specific. "37%" beats "a lot". "DuckDB 1.4" beats "DuckDB".

## Hashtags

- Every post (opinion AND milestone) ends with 3–5 hashtags on their own line.
- **2 fixed core hashtags on every post:** `#dataengineering` `#geospatial`
- **1–3 contextual hashtags** chosen per topic from: `#gis` `#postgis` `#duckdb` `#geoparquet` `#apacheiceberg` `#spatialdata` `#spatialSQL` `#datapipelines` `#cloudnativegeo` `#lakehouse`
- Banned: generic tags (`#tech`, `#AI`, `#innovation`, etc.) and more than 5 total.

## Tone

- Opinion-bearing, not promotional. You can disagree with a tool you use.
- Professional but not corporate. No "thrilled to share", no humblebrags.
- First person. "I" when speaking from experience; "we" only for genuinely shared work.
- Skeptical of vendor claims. Skeptical of hype cycles. Skeptical of yourself.

## Hook patterns that work for this audience

- **Contrarian take:** "Most teams over-index on X. Here's what we found when we stopped."
- **Specific observation:** "Migrated 1.2B rows from Postgres to Iceberg last week. Three things bit us."
- **Field reframe:** "GIS people have been doing X for 20 years. The data world is reinventing it badly."
- **Negative space:** "Nobody talks about the cost of Y. We measured it."
- **Time anchor:** "Six months ago I would have told you Z. I was wrong."

## What disqualifies a draft (automatic critic failure)

**For both post types:**

- Uses any phrase from the "Do not say" list in `voice-profile.md`.
- Has zero specific numbers, tools, named situations, or named outcomes.
- Reads like a vendor blog post.
- Contains an emoji used as decoration (not part of a quoted thing).
- Opens with "Humbled and honored", "Thrilled and blessed", "In today's fast-paced world", or any stacked-emotion opener.

**For `opinion` posts specifically:**

- Opens with "I'm excited to share...", "As a data engineer...", or other personal-announcement framing.
- Ends with "Thoughts?" or "Let me know what you think!" (lazy CTA).
- Uses fewer than 3 or more than 5 hashtags, or omits the 2 fixed core hashtags.
- Includes a gratitude block thanking named people (use `milestone` type for that).

**For `milestone` posts specifically:**

- The milestone is vague — no specific role title, project name, artifact link, or concrete outcome.
- Thanks named people generically ("for their support and guidance") rather than specifically (their actual role + what they actually did).
- Uses fewer than 3 or more than 5 hashtags, or omits the 2 fixed core hashtags.
- Has no forward-looking element — just a celebration with no next step.

## Banned patterns (extended)

> Adapted from the `article-writing` skill in
> [affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) (MIT).

Delete and rewrite any of these:

- "In today's rapidly evolving landscape" and all variants
- "game-changer", "cutting-edge", "revolutionary", "paradigm shift"
- "here's why this matters" used as a standalone bridge line
- "Not X, just Y" framing (overused on LinkedIn)
- Fake vulnerability arcs ("I used to think X, then I learned Y")
- A closing question added only to juice engagement (engagement bait)
- Biography padding that does not move the argument
- Generic AI throat-clearing that delays the point
- Forced lowercase aesthetic
- "no fluff" / "no BS" as a self-aware tag
- Capitalization stunts (Random Title Case in body text)

## Core writing rules (apply to every draft)

> Adapted from the `article-writing` skill (MIT, attribution above).

1. **Lead with the concrete thing.** Artifact, example, number, named situation, screenshot — not setup.
2. **Explain after the example, not before.** The reader earns the explanation by being shown the thing first.
3. **Proof beats adjectives.** "3-5x speedup on 100M rows" > "blazing fast". Cut every "robust", "scalable", "seamless" that isn't attached to a measurement.
4. **One claim per post.** If there are two takes, pick the sharper one.
5. **Never invent facts, credibility, or customer evidence.** If the writer doesn't know a number, mark it `[USER TAKE: ...]` — don't fabricate.
