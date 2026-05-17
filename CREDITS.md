# Credits

## everything-claude-code

This project incorporates patterns from
[affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code)
(MIT License, © Affaan Mustafa).

That repo is installed as a Claude Code plugin via `.claude/settings.json`
(`extraKnownMarketplaces.ecc` + `enabledPlugins["ecc@ecc"]`) — its 230 skills,
75 commands, and 60 agents become available during development of this
project.

Specific patterns adapted from that repo into the LinkedIn pipeline's own
configuration:

| What we adapted | Source | Where it lives now |
|---|---|---|
| Voice-extraction schema (rhythm, compression, capitalization, parenthetical use, claim style, banned moves) | `skills/brand-voice` | `config/voice-profile.md` — the `VOICE PROFILE` block at the bottom |
| Core writing rules (lead with the concrete, explain after, proof beats adjectives, one claim per post, never invent) | `skills/article-writing` | `config/style-guide.md` and `prompts/writer.txt` |
| Extended banned patterns ("game-changer", "here's why this matters" bridges, fake vulnerability arcs, engagement bait, forced lowercase) | `skills/article-writing` | `config/style-guide.md` |

Other skills from the source repo we don't currently copy but that are
worth reading if you want to extend the pipeline:

- `skills/content-engine` — platform-native content workflows
- `skills/cost-tracking` — track Claude usage costs from a local SQLite db
- `skills/continuous-agent-loop` (formerly `autonomous-loops`) — reference patterns for autonomous loops

The plugin install means all of those are available as live skills you can
invoke during development — no copy required.
