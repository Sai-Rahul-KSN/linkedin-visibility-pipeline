# Style guide

The writer and critic both read this. Treat every rule as load-bearing.

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

- 0–3 maximum.
- Only community-relevant ones. `#dataengineering`, `#geospatial`, `#gis`, `#duckdb`, `#geoparquet` are fine. `#tech` is not.
- Placed at the end, on their own line.

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

- Opens with "In today's...", "As a data engineer...", "I'm excited to share...", "Humbled and honored..."
- Uses any phrase from the "Do not say" list in `voice-profile.md`.
- Has zero specific numbers, tools, or named situations.
- Reads like a vendor blog post.
- Ends with "Thoughts?" or "Let me know what you think!" (lazy CTA).
- Uses more than 3 hashtags.
- Contains an emoji used as decoration (not part of a quoted thing).
