#!/usr/bin/env bash
# End-to-end smoke test for the agent loop.
#
# What it does:
#  1. Resets the DB (fresh visibility.sqlite from db/init.sql)
#  2. Seeds two fake ingest items (one DE, one GIS)
#  3. Runs the writer agent
#  4. Verifies 2 candidates were inserted
#  5. Runs the critic on each candidate
#  6. Runs the reviser on any candidate the critic marked 'revise'
#  7. Reports counts and shows the first final_draft text
#
# Does NOT touch images, email, or git. Pure agent-loop validation.

source "$(dirname "$0")/lib.sh"
require_cmd "$CLAUDE_CMD" sqlite3 jq python3

echo "[smoke] resetting DB at $DB_PATH"
rm -f "$DB_PATH" "$DB_PATH"-journal "$DB_PATH"-wal "$DB_PATH"-shm
sqlite3 "$DB_PATH" < "$REPO_ROOT/db/init.sql"

echo "[smoke] seeding 2 fake ingest items"
sqlite3 "$DB_PATH" <<'SQL'
INSERT INTO ingest_items (title, summary, link, link_hash, source) VALUES
  ('DuckDB 1.4 ships spatial join improvements',
   'New ST_Intersects pushdown into Parquet predicate filtering. Benchmarks show 3-5x speedups on 100M+ row spatial joins.',
   'https://example.invalid/duckdb-1-4',
   'hash-duckdb-1-4',
   'duckdb'),
  ('GeoParquet 1.1 adds 3D and CRS metadata',
   'The cloud-native geospatial format now supports 3D geometries (POINT Z) and CRS encoding in the metadata block. Existing GeoParquet 1.0 files remain readable.',
   'https://example.invalid/geoparquet-1-1',
   'hash-geoparquet-1-1',
   'cloudnativegeo');
SQL

echo "[smoke] running writer..."
RUN_ID="$("$REPO_ROOT/scripts/run-writer.sh")"
if [ -z "$RUN_ID" ]; then
    echo "[smoke] FAIL: writer produced no run_id" >&2
    exit 1
fi
echo "[smoke] run_id=$RUN_ID"

N="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM writer_drafts WHERE run_id = '$RUN_ID';")"
echo "[smoke] writer inserted $N candidates"
if [ "$N" -ne 2 ]; then
    echo "[smoke] FAIL: expected 2 candidates, got $N" >&2
    exit 1
fi

echo "[smoke] writer candidates:"
sqlite3 "$DB_PATH" -cmd ".mode column" -cmd ".headers on" \
    "SELECT id, visual_type, length(post_text) AS chars,
            substr(post_text, 1, 80) || '...' AS preview
     FROM writer_drafts WHERE run_id = '$RUN_ID';"

echo
echo "[smoke] running critic on each candidate..."
for WID in $(sqlite3 "$DB_PATH" "SELECT id FROM writer_drafts WHERE run_id = '$RUN_ID';"); do
    VERDICT="$("$REPO_ROOT/scripts/run-critic.sh" "$WID")"
    echo "  writer_draft_id=$WID  verdict=$VERDICT"
done

echo
echo "[smoke] critic scores:"
sqlite3 "$DB_PATH" -cmd ".mode column" -cmd ".headers on" \
    "SELECT cr.writer_draft_id AS wid,
            hook_strength AS hook, voice_match AS voice,
            has_real_take AS take, style_guide_adherence AS style,
            specificity AS spec, verdict
     FROM critic_reviews cr
     JOIN writer_drafts wd ON wd.id = cr.writer_draft_id
     WHERE wd.run_id = '$RUN_ID';"

echo
echo "[smoke] running reviser on 'revise' verdicts (if any)..."
REVISE_IDS="$(sqlite3 "$DB_PATH" "
    SELECT wd.id FROM writer_drafts wd
    JOIN critic_reviews cr ON cr.writer_draft_id = wd.id
    WHERE wd.run_id = '$RUN_ID' AND cr.verdict = 'revise';
")"
for WID in $REVISE_IDS; do
    "$REPO_ROOT/scripts/run-reviser.sh" "$WID"
done

echo
echo "[smoke] copying 'publish_as_is' verdicts to final_drafts..."
sqlite3 "$DB_PATH" <<SQL
INSERT INTO final_drafts (writer_draft_id, post_text, change_summary, revised,
                          visual_type, visual_description)
SELECT wd.id, wd.post_text, NULL, 0, wd.visual_type, wd.visual_description
FROM writer_drafts wd
JOIN critic_reviews cr ON cr.writer_draft_id = wd.id
WHERE wd.run_id = '$RUN_ID' AND cr.verdict = 'publish_as_is';
SQL

FINAL_N="$(sqlite3 "$DB_PATH" "
    SELECT COUNT(*) FROM final_drafts fd
    JOIN writer_drafts wd ON wd.id = fd.writer_draft_id
    WHERE wd.run_id = '$RUN_ID';
")"
echo "[smoke] final_drafts from this run: $FINAL_N"

if [ "$FINAL_N" -gt 0 ]; then
    echo
    echo "[smoke] first final draft text:"
    echo "─────────────────────────────────"
    sqlite3 "$DB_PATH" "
        SELECT fd.post_text FROM final_drafts fd
        JOIN writer_drafts wd ON wd.id = fd.writer_draft_id
        WHERE wd.run_id = '$RUN_ID'
        ORDER BY fd.id LIMIT 1;
    "
    echo "─────────────────────────────────"
fi

echo
echo "[smoke] PASS"
