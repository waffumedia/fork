# Inspo — UX spec v0.1 (nominal UI)

Owner brief: "very nominal frontend for now, basically Apple style; we iterate on looks later."
So: system fonts, system colours, native controls, light + dark, no custom branding, no decoration.
Backend is DONE and is the source of truth — do not change `lib/` or `app/api/` (except where noted). Read `AGENTS.md` for the API.

## Surfaces
1. **Web** (Next.js app router, same repo, React 19, no UI library needed; plain CSS modules or one global CSS file).
2. **Native** SwiftUI multiplatform app (iOS 26 + macOS 26) in `apple/`, generated with XcodeGen (`apple/project.yml`).

Both are thin clients of the same API. Auth: web uses cookie (`POST /api/login {token}`), native sends `Authorization: Bearer <token>`.

## Screens (both surfaces)

### 1. Today (default)
```
┌──────────────────────────────┐
│ Today            3 of 10 left │  ← large title + counter
│ ┌──────────────────────────┐ │
│ │                          │ │
│ │   hero scene image       │ │  ← scenes[0].image; tap = next scene (dots below)
│ │   (aspect fit, rounded)  │ │
│ └──────────────────────────┘ │
│      • ○ ○ ○                  │  ← scene dots
│ Title of post                 │
│ @author · 0:44 · Grok pick    │  ← origin badge: "Grok pick" | "Seed" | "Added"
│ "pitch text from Grokbot"     │  ← only if pitch
│ [ Open ↗ ]                    │  ← opens url (scene.link of current scene)
│                               │
│   (✕)                 (♥)    │  ← dislike / like buttons
└──────────────────────────────┘
```
- Swipe right = like, left = dislike (drag gesture; card follows finger, rotates slightly, flies off past ~120 pt). Buttons do the same. Web: also ← / → keys, Z = undo.
- Each swipe → `POST /api/swipe {id, verdict}`. Undo (button in toolbar) → `verdict: "clear"` on the last one.
- When `remaining == 0`: empty state "Done for today" + count of likes; link to Map.
- Source of data: `GET /api/today` → `{day,total,remaining,items:[{id,url,title,author,platform,origin,pitch,duration,verdict,scenes:[{id,image,timestamp,title,link}]}]}`. Items with a verdict are already swiped (skip them in the deck).

### 2. History (bottom of Today on web; own tab on native)
- `GET /api/history` → `{items:[{id,title,author,url,verdict,at,cover}]}`.
- Two filters: All / Liked / Disliked (segmented control). Row: cover thumb, title, @author, ♥ or ✕, relative time. Swipe-to-change verdict on native (like ↔ dislike, or clear).
- Tap → Source detail.

### 3. Map (the taste web)
- `GET /api/graph?mode=ideas|full&liked=1&focus=<id>&depth=1`
  → `{stats, nodes:[scene {id,type:"scene",label,image,timestamp,link,liked,degree} | idea {id,type:"idea",label,facet,count,degree}], edges:[{source,target,kind:"has"|"bridge"|"co",weight,cross?,shared?}]}`
- Web: force-directed graph (d3-force via CDN-free npm `d3-force` is fine), canvas or SVG. Scene nodes = small rounded image thumbnails; idea nodes = text pills coloured by facet (system colours: technique blue, style purple, format orange, motion green, medium grey, concepts teal). Bridge edges dashed; `cross:true` bridges highlighted (accent).
- Controls (top bar): segmented "Ideas | Full", toggle "Liked only", search field (filters + focuses a node).
- Click scene node → right side sheet (Scene detail). Click idea node → refetch with `focus=idea:...&depth=2` (breadcrumb "All ›  kinetic-type", click All to reset).
- Native: Map tab = WKWebView of `<server>/map?embed=1` with the cookie set from the stored token (nominal; native graph comes later). `embed=1` hides the web top nav.

### 4. Scene detail (sheet / page `/scene/[id]`)
- `GET /api/scenes/[id]` → image, frame_urls (1–3 screenshots of that scene), title, description, timestamp, t_start/t_end, link, tags {technique,style,format,motion,medium,palette,concepts}, source {...}.
- Shows: big screenshot, frame strip, "at 0:12" + **Open at 0:12 ↗** (link), "From: <source title> @author" (→ source), tag chips grouped by facet (tap chip → Map focused on that idea).

### 5. Source detail (`/source/[id]`)
- `GET /api/sources/[id]` → metadata + verdict + scenes[] (image, timestamp, link, title).
- Grid of scene cards (image, timestamp, title). Like/Dislike control at top reflecting `verdict`.

### 6. Library / search (web `/library`, native tab "Library")
- `GET /api/scenes?q=&tag=facet:tag&liked=1` → grid of scenes. Search field + tag chips from `GET /api/stats` (`tags` = top tags).

### 7. Settings / Login
- Web `/login`: one secure field "Access token" → POST /api/login → redirect `/`. Any 401 from the API → redirect to /login.
- Native Settings: Server URL (default `http://localhost:3300`), Token (stored in Keychain), "Test connection" (GET /api/stats shows counts).

## Web nav
Top bar (hidden with `?embed=1`): **Today · Map · Library** left, stats text right ("734 scenes · 12 ♥"). Max content width 1100 px; Today card max 420 px wide, centred. Mobile web works at 375 px.

## Native structure
- `TabView`: Today, Map, Library, History, Settings. macOS: same tabs as a sidebar (`NavigationSplitView`), window min 900×640.
- `APIClient` (async/await, URLSession, Codable models mirroring the JSON above), `@Observable` stores.
- Images: `AsyncImage`. Bundle id `com.waffu.inspo`. Signing: automatic, team left empty (`DEVELOPMENT_TEAM` blank) so simulator + "Sign to Run Locally" Mac build work; owner adds team later.
- ATS: allow local networking (`NSAllowsLocalNetworking`) for the localhost/LAN server.

## Acceptance
- `npm run build` passes; `npm run typecheck` passes.
- Web: Today deck swipes and persists (reload keeps state); undo works; Map renders all nodes with no overlap explosion (`stats.nodes` in hundreds), click → sheet with working "Open at" link; Library search returns results; works in dark mode.
- Native: `xcodegen` + `xcodebuild -scheme Inspo -destination 'platform=iOS Simulator,name=iPhone 17'` and `-destination 'platform=macOS'` both build; app shows Today with real data from localhost:3300 in the simulator.
