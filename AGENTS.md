# Inspo — agent guide

Private swipe-to-learn reference library for motion design, design and video edits.
Grokbot finds 10 links a day → the owner swipes right (like) / left (dislike) → every link is split into **scenes**
(screenshot + exact timestamp + deep link + tags) → likes build a **taste profile** and an Obsidian-style **web** of ideas.

## Fastest ways in (pick one)
| You are | Use |
|---|---|
| Claude / any MCP agent | MCP server `http://localhost:3300/api/mcp` (Bearer `INSPO_TOKEN`). Tools: `get_taste_profile`, `search_scenes`, `get_scene`, `get_source`, `get_taste_web`, `list_ideas`, `get_today`, `swipe`, `get_history`, `add_link`. |
| A script | REST API below (same token). |
| A human or agent with only files | `data/LIBRARY.md` (every source → its scenes with timestamps + links) and `data/library.json` (same, machine-readable). Regenerate: `npm run export`. |

Add the MCP to Claude Code:
```
claude mcp add --transport http inspo http://localhost:3300/api/mcp --header "Authorization: Bearer $INSPO_TOKEN" -s user
```

## Data model
- **source** — one saved link. `id` = `yt-<videoId>` | `x-<statusId>` | `ig-<code>` | `pin-<id>` | `creator-x-<handle>` (creator/profile seeds are not downloaded). `origin` = `seed` (owner's hand-picked list) | `grok` (Grokbot pick) | `manual`. `status` = `queued` → `ready` (scenes cut) → `tagged` | `error` | `seed`.
- **scene** — `id` = `<source id>:<n>`. `t_start`/`t_end` seconds, `timestamp` "m:ss", `link` (YouTube links carry `&t=`; X has no time links so read `timestamp`), `frames` = 1–3 screenshots, `hero` = the middle one, `tags` by facet.
- **facets** (controlled vocabulary in `pipeline/taxonomy.json`): technique, style, format, motion, medium, palette, + free `concepts`.
- **swipe** — one verdict per source (latest wins). Un-swiped seeds count as a half-like in the taste profile.
- **web** — `idea:<facet>:<tag>` nodes; scene→idea `has` edges; scene↔scene `bridge` edges (shared rare ideas, IDF-weighted, different sources; `cross:true` = different formats/genres); `co` edges between ideas in `mode=ideas`.

## REST API (auth: `Authorization: Bearer <INSPO_TOKEN>`, `?token=`, or cookie)
| | |
|---|---|
| `GET /api/today` | today's 10 (Grok picks first, then un-rated seeds) |
| `POST /api/swipe {id, verdict: like\|dislike\|clear}` | record a swipe; when the day is done Grokbot is notified |
| `GET /api/history` | likes + dislikes, newest first |
| `GET /api/taste` | taste profile (summary, loves/avoids per facet, creators, weights) |
| `GET /api/graph?mode=ideas\|full&liked=1&focus=<id>&depth=1` | the web |
| `GET /api/scenes?q=&tag=facet:tag&liked=1` · `GET /api/scenes/<id>` | search / one scene |
| `GET /api/sources?origin=&status=&verdict=` · `GET /api/sources/<id>` · `POST /api/sources {url,note}` | sources |
| `GET /api/stats` | counts + top tags |
| `GET /api/media/<source id>/<file>.jpg` | screenshots (public) |
| `GET /api/worker` · `POST /api/worker {ids?}` | Mac worker queue / re-import JSON |

## Grokbot bridge (auth: `GROK_SECRET` as `?token=`, Bearer, or `X-Inspo-Signature: sha256=<hmac(body)>`)
- `GET /api/grok/brief?token=…` — what to hunt: task, taste summary, liked creators, seed creators, links already owned.
- `POST /api/grok/inbox?token=…` `{"items":[{"url","pitch","title?"}]}` — submit picks (or `GET …/inbox?token=…&url=…&pitch=…`).
- Outbound: when all 10 of a day are swiped, `POST` to `GROK_WEBHOOK_URL` (env or `settings.grok_webhook_url`) with `{event:"day_complete", results, taste, brief_url}` signed with `X-Inspo-Signature`.

## Pipeline (runs on the owner's Mac)
- `python3 pipeline/ingest.py seed/links.txt` — download (yt-dlp `--js-runtimes node` for YouTube, fxtwitter API for X), ffmpeg scene detection, merge flash frames, keep ≤6/10/14/18 representative scenes by length, 1–3 screenshots each → `data/sources/<id>.json`, `data/media/<id>/`.
- `~/Claude/tools/asr/.venv-mlx/bin/python pipeline/tag.py` — Qwen3-VL (local, MLX) tags every scene against the taxonomy.
- `npm run import` — JSON → database. `python3 pipeline/worker.py --loop` — does all three for queued links.

## Layout
`lib/` backend (db, library, taste, graph, grok, mcp) · `app/api/` routes · `pipeline/` Python ingest/tag/worker · `data/` sources JSON + screenshots (raw downloads in `data/raw`, git-ignored) · `apple/` SwiftUI app · `docs/UX-SPEC.md` UI spec · `context/` run logs and agent hand-off notes.
