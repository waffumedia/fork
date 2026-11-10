# Fork — UX spec v0.2 (native app, nominal UI)

Owner: "I want this to be an APP, not a website." + "very nominal frontend for now, basically Apple style; we iterate on looks later."
Fork = ideas forking off each other (the web) + the utensil. No web UI at all: the Next.js server is only the API.

- One SwiftUI **multiplatform** target (iOS 26 + macOS 26) in `apple/`, generated with XcodeGen (`apple/project.yml`).
- Stock SwiftUI only: system fonts, system colours, SF Symbols, light + dark. No custom branding, no decoration.
- Backend is DONE and is the source of truth — do not change `lib/`, `app/`, `pipeline/`. Read `AGENTS.md` for every endpoint + JSON shape.
- Auth: `Authorization: Bearer <token>` on every request. Token + server URL live in Settings (token in Keychain).

## Tabs
iOS: `TabView` — Today · Map · Library · History · Settings. macOS: `NavigationSplitView` sidebar with the same items, window min 1000×700.

### 1. Today (default) — the swipe deck
```
┌──────────────────────────────┐
│ Today            3 of 10 left │  large title + counter
│ ┌──────────────────────────┐ │
│ │   hero scene image       │ │  scenes[i].image; tap = next scene of this item
│ │   (aspect fit, rounded)  │ │
│ └──────────────────────────┘ │
│      • ○ ○ ○                  │  page dots per scene
│ Title of post                 │
│ @author · 0:44 · Grok pick    │  origin badge
│ "pitch from Grokbot"          │  only if pitch
│ [ Open at 0:12 ↗ ]            │  opens current scene.link (openURL)
│   (✕)        (↺)       (♥)   │  dislike · undo · like
└──────────────────────────────┘
```
- Swipe right = like, left = dislike: card follows the finger (DragGesture), slight rotation, flies off past ~120 pt, springs back otherwise. Buttons do the same. macOS: ← / → keys, ⌘Z undo.
- `GET /api/today` → `{day,total,remaining,items:[{id,url,title,author,platform,origin,pitch,duration,verdict,scenes:[{id,image,timestamp,title,link}]}]}`. Items with a non-null verdict are already swiped; deck shows the rest in order.
- Swipe → `POST /api/swipe {id, verdict:"like"|"dislike"}`; undo → same id with `"clear"`.
- Empty states: `total == 0` → "Grokbot hasn't sent today's picks yet" + pull to refresh. `remaining == 0` → "Done for today · N liked" + button to Map.

### 2. Map — the taste web (native, no web view)
- `GET /api/graph?mode=ideas|full&liked=1&focus=<node id>&depth=1|2`
  → `{stats, nodes:[ {id,type:"scene",label,image,timestamp,link,liked,degree} | {id,type:"idea",label,facet,count,degree} ], edges:[{source,target,kind:"has"|"bridge"|"co",weight,cross?,shared?}]}`
- Draw with SwiftUI `Canvas` (not one View per node). Layout: simple force-directed (repulsion + spring edges + centering) computed off the main thread for ~300 iterations, then static; cache positions per (mode, focus). Must stay smooth with ~900 nodes / ~4000 edges: draw edges as one path per kind, skip labels below a zoom threshold.
- Pan (drag) + pinch/scroll-wheel zoom. Idea nodes = small circles + text label coloured by facet (technique blue, style purple, format orange, motion green, medium gray, concepts teal). Scene nodes = rounded-square thumbnails (load images lazily, cache; draw a plain square until loaded). `bridge` edges thin dashed; `cross:true` bridges in accent colour; `has` edges hairline.
- Toolbar: segmented **Ideas | Full**, toggle **Liked only**, search field (matches node labels; picking one focuses it).
- Tap idea → refetch with `focus=idea:<facet>:<tag>&depth=2`, breadcrumb "All › kinetic-type" (tap All to reset). Tap scene → Scene detail sheet.

### 3. Scene detail (sheet on iOS, inspector/sheet on macOS)
- `GET /api/scenes/<id>` → `image, frame_urls[1–3], title, description, timestamp, t_start, t_end, link, tags{technique,style,format,motion,medium,palette,concepts}, source{id,title,author,url,verdict}`.
- Big screenshot, horizontal strip of the other frames, "at 0:12", **Open at 0:12 ↗** (link), "From <source title> · @author" (→ Source detail), tag chips grouped by facet (tap → Map focused on that idea), ShareLink for the link.

### 4. Source detail
- `GET /api/sources/<id>` → metadata + verdict + `scenes[]` (image, timestamp, title, link). Grid of scene cards; like/dislike control reflecting `verdict`.

### 5. Library
- `GET /api/scenes?q=&tag=facet:tag&liked=1&limit=60` → adaptive grid of scene cards (image, timestamp, title). `.searchable` text + tag chips from `GET /api/stats` (`tags`, top ~30). Tap → Scene detail.

### 6. History
- `GET /api/history` → `{items:[{id,title,author,url,verdict,at,cover}]}`. Segmented All / Liked / Disliked. Row: cover thumb, title, @author, ♥/✕, relative time. Swipe actions: flip verdict or clear. Tap → Source detail.

### 7. Settings
- Server URL (default `http://localhost:3300`), Token (SecureField → Keychain), "Test connection" → `GET /api/stats` shows "734 scenes · 130 sources". Any 401 anywhere → banner "Check token in Settings".

## Code shape
- `APIClient` (async/await URLSession, Codable models mirroring the JSON), `@Observable` stores per screen, shared image cache.
- Bundle id `com.waffu.fork`, product name **Fork**. `DEVELOPMENT_TEAM` empty, automatic signing; macOS `CODE_SIGN_IDENTITY "-"` so it builds without an account. ATS: `NSAllowsLocalNetworking` + `NSAllowsArbitraryLoads` off.
- DEBUG only: launch env `FORK_TOKEN` / `FORK_URL` prefill Settings for tests. Never hardcode the token.

## Acceptance
- `cd apple && xcodegen` then `xcodebuild -project Fork.xcodeproj -scheme Fork -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build` and `-destination 'platform=macOS' build` both succeed.
- Launched in an iOS simulator with FORK_TOKEN/FORK_URL env against http://localhost:3300: Today, Map (both modes), Library search, Scene detail "Open at" all work with real data.
