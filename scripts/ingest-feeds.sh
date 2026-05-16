#!/usr/bin/env bash
# Pulls every feed in config/sources.yaml, dedupes by link hash, inserts new
# rows into ingest_items. No Claude call. Safe to run hourly if needed.

source "$(dirname "$0")/lib.sh"
require_cmd sqlite3 python3
require_running

python3 - "$DB_PATH" "$REPO_ROOT/config/sources.yaml" <<'PY'
import hashlib, sqlite3, sys, urllib.error, urllib.request
from xml.etree import ElementTree as ET

db_path, sources_path = sys.argv[1], sys.argv[2]

# Tiny stdlib YAML reader sufficient for our flat key: [list] structure.
def read_sources(path):
    out = {}
    current = None
    with open(path, "r", encoding="utf-8") as f:
        for raw in f:
            line = raw.rstrip()
            if not line or line.lstrip().startswith("#"):
                continue
            if not line.startswith(" "):
                current = line.split(":", 1)[0].strip()
                out[current] = []
            else:
                stripped = line.strip()
                if stripped.startswith("- "):
                    out[current].append(stripped[2:].strip())
    return out

NS = {
    "atom": "http://www.w3.org/2005/Atom",
    "content": "http://purl.org/rss/1.0/modules/content/",
}

def text_or_none(elem, *tags):
    for t in tags:
        node = elem.find(t)
        if node is not None:
            return (node.text or "").strip()
        # try with atom ns
        node = elem.find(f"atom:{t}", NS)
        if node is not None:
            return (node.text or "").strip()
    return ""

def parse_feed(xml_bytes):
    """Return list of (title, summary, link)."""
    items = []
    try:
        root = ET.fromstring(xml_bytes)
    except ET.ParseError:
        return items
    # RSS 2.0
    for item in root.iter("item"):
        title = text_or_none(item, "title")
        link  = text_or_none(item, "link")
        summary = text_or_none(item, "description")
        if title and link:
            items.append((title, summary, link))
    # Atom
    for entry in root.iter("{http://www.w3.org/2005/Atom}entry"):
        title = entry.findtext("atom:title", default="", namespaces=NS).strip()
        link  = ""
        for l in entry.findall("atom:link", NS):
            if l.attrib.get("rel", "alternate") == "alternate":
                link = l.attrib.get("href", "")
                break
        if not link:
            l = entry.find("atom:link", NS)
            link = l.attrib.get("href", "") if l is not None else ""
        summary = entry.findtext("atom:summary", default="", namespaces=NS).strip() \
               or entry.findtext("atom:content", default="", namespaces=NS).strip()
        if title and link:
            items.append((title, summary, link))
    return items

def fetch(url, timeout=15):
    req = urllib.request.Request(url, headers={"User-Agent": "linkedin-visibility-ingest/1.0"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()

sources = read_sources(sources_path)
conn = sqlite3.connect(db_path); conn.execute("PRAGMA foreign_keys = ON")

inserted = 0
failed   = 0
for source_key, urls in sources.items():
    for url in urls:
        try:
            body = fetch(url)
        except (urllib.error.URLError, TimeoutError) as e:
            print(f"FEED FAIL {source_key} {url}: {e}", file=sys.stderr)
            failed += 1
            continue
        for title, summary, link in parse_feed(body):
            link_hash = hashlib.sha256(link.encode("utf-8")).hexdigest()
            try:
                conn.execute("""
                    INSERT INTO ingest_items (title, summary, link, link_hash, source)
                    VALUES (?, ?, ?, ?, ?)
                """, (title[:500], summary[:2000], link, link_hash, source_key))
                inserted += 1
            except sqlite3.IntegrityError:
                pass  # already have this link
conn.commit(); conn.close()
print(f"ingest: inserted={inserted} failed_feeds={failed}")
PY

log_run "ingest-feeds" "" "ok" "ran"
