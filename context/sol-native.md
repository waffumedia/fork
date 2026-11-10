# Fork native handoff

Built one native SwiftUI multiplatform target, Fork (`com.waffu.fork`), for iOS 26 and macOS 26. Read AGENTS.md and docs/UX-SPEC.md before implementation. App code is entirely under apple/. This requested handoff is the only authored file outside apple/. No commits. Existing backend, pipeline, data, scripts, and other working-tree changes were left alone.

## Built

- iOS TabView and macOS NavigationSplitView sidebar: Today, Map, Library, History, Settings. Mac window minimum 1000×700. System fonts, semantic colours, SF Symbols, system controls, automatic light/dark appearance.
- Today: ordered unswiped deck, scene cycling and page dots, metadata/pitch, current-scene deep link, drag/rotation/fly-out, like/dislike buttons, undo via clear, Mac arrows and Command-Z, refresh, empty/completed states. Failed posts retain the item and show the error.
- Map: Ideas/Full, liked filter, searchable node buttons, focus/depth-2 fetch and breadcrumb reset, scene sheets. One Canvas with batched edge paths, dashed bridges and accent cross-bridges, facet colours, zoom-dependent labels, rounded thumbnails, pan/pinch/buttons and native macOS scroll-wheel zoom.
- Library: debounced server search, top 30 facet/tag filters, liked filter, adaptive scene grid, scene sheets, loading/errors/refresh.
- Scene: image and selectable frame strip, timestamp/title/description, Open at, ShareLink, Source navigation, grouped tag buttons that focus Map and dismiss detail sheets.
- Source: title/author/platform/duration/origin/status/pitch, external link, current-verdict like/dislike controls (tap the selected verdict to clear), scene grid.
- History: All/Liked/Disliked, thumbnails/author/verdict/relative time, source navigation, flip/clear swipe actions and Mac context menu.
- Settings: server URL, SecureField token, explicit Save, Keychain storage, stats connection test, shared 401 banner linking to Settings.

## Files

| File | Purpose |
|---|---|
| apple/project.yml | Single-target XcodeGen project and shared Fork scheme |
| apple/Info.plist | Local-network ATS permission, arbitrary loads off |
| apple/Fork.xcodeproj/project.pbxproj | Generated project |
| apple/Fork.xcodeproj/project.xcworkspace/contents.xcworkspacedata | Generated workspace |
| apple/Fork.xcodeproj/xcshareddata/xcschemes/Fork.xcscheme | Generated shared scheme |
| apple/Fork/ForkApp.swift | App entry, platform navigation, shared route state and auth banner |
| apple/Fork/APIClient.swift | Async URLSession/Codable client, Keychain, DEBUG environment, observable loading store |
| apple/Fork/Models.swift | Endpoint response models |
| apple/Fork/Images.swift | Shared bounded image cache, off-main downsampling, reusable stock UI |
| apple/Fork/TodayView.swift | Deck and undo |
| apple/Fork/MapView.swift | Map store, Canvas, gestures, visible thumbnail loading |
| apple/Fork/GraphLayout.swift | Detached 300-iteration spatial-grid force layout and actor cache |
| apple/Fork/LibraryView.swift | Search, tags and grid |
| apple/Fork/DetailViews.swift | Scene and Source details |
| apple/Fork/HistoryView.swift | Verdict history |
| apple/Fork/SettingsView.swift | Connection settings |
| apple/Checks/Smoke.swift | Read-only checks using the actual client/models/layout |
| apple/Checks/run.py | Compiles DEBUG checks; supplies token only via launch environment |
| apple/README.md | Build, credentials, checks and simulator launch notes |
| apple/build-ios.log, apple/build-macos.log | Final successful acceptance build output |
| apple/smoke.log | Successful live checks and layout timing |
| apple/simulator.log | CoreSimulator failure evidence |

## Decisions

- No packages, web views, custom fonts, or custom visual theme. UIKit/AppKit only bridge decoded images into SwiftUI Image; all UI is SwiftUI.
- Token is never in source, project, scheme or logs. DEBUG FORK_TOKEN/FORK_URL prefill in memory; Settings persists only on Save/Test. Release ignores launch environment. A scan against the actual token found no matches anywhere under apple/.
- macOS signing is automatic with empty team and ad hoc identity `-`. iOS simulator builds without signing.
- Debug adds Swift compiler `-disable-sandbox`: Observation macro subprocesses otherwise fail with `sandbox-exec: sandbox_apply: Operation not permitted` inside this already sandboxed host. Release has no override; app network/security permissions aren't changed.
- Layout is computed off the main actor, cached by server/mode/filter/focus/graph fingerprint, then drawn statically. Spatial-grid repulsion bounds the larger graph workload. Thumbnail requests run six at a time, only for visible nodes, downsampled to 96 pixels; normal scene images use up to 1600 pixels. Cache is limited by decoded-image cost.
- Run destination builds sequentially: concurrent builds initially conflicted over Xcode's shared build database. Final exact acceptance commands passed sequentially.

## Verification

With Xcode 26.6 (26.5 SDKs), ran `cd apple && xcodegen`, then:

```sh
xcodebuild -project Fork.xcodeproj -scheme Fork -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Fork.xcodeproj -scheme Fork -destination 'platform=macOS' build
```

Both final builds: **BUILD SUCCEEDED**. iOS simulator compiled arm64 and x86_64; macOS compiled arm64 and signed ad hoc. No Swift compiler warnings/errors in final logs. Xcode prints environment CoreSimulator diagnostics and its usual unused AppIntents metadata warning.

`python3 apple/Checks/run.py` passed against http://localhost:3300 using DEBUG launch environment. Verified real stats/Today/history decoding; Library search and tag filtering; scene/source details and membership; image HTTP 200; valid Open-at URL; both graph modes, idea focus and connected endpoints; cached finite layout positions; 401 banner state. No swipe mutations. Final live snapshot: 246 scenes / 45 sources, Ideas 194 nodes / 2307 edges, Full 441 nodes / 3359 edges. Data changed during this run as the existing backend/library work continued, so these are test-time counts. Synthetic 900 nodes / 4000 edges / 300 iterations: 2.74 seconds in Debug.

## Known gaps / follow-up checks

- `xcrun simctl list devices available` fails with CoreSimulatorService connection invalid / connection refused; runtime discovery and simdiskimaged are unavailable in this sandbox. Couldn't boot, install, launch or capture simulator screenshots. No context/shots images were produced. No desktop app or visible browser was launched.
- Consequently rendered layout, gestures, macOS wheel zoom, Keychain save UI, ShareLink and actually opening an external URL still need an interactive device/simulator check. The read-only check validates the deep-link URL and image, not an openURL interaction.
- Today and History were empty throughout testing. Their empty responses decoded successfully; swipe/undo/flip/clear UI and completion transitions aren't runtime-tested against populated data. Nothing was added to the library to manufacture a deck.
- The backend graph excludes palette ideas. Tapping a palette chip sends the specified idea focus, but that server response may have no nodes. No backend changes were made.

## Round 2

Fixed the owner-reported Map issues in `apple/`:

- Both Ideas and Full use the shared revised force layout. Initial positions now come from a stable FNV-1a ID seed and SplitMix64 samples distributed uniformly inside a disc. Repulsion searches all cells within the 360-point neighbourhood (seven by seven with 120-point cells), applies a circular distance cutoff, and smoothly tapers to zero at that radius. The old cell-shaped force boundary is gone. The simulation runs 1,000 iterations with quadratic cooling from 18.02 to approximately 0.02 points per step. Detached execution, cancellation and caching remain.
- Idea radius is `3 + sqrt(max(1, count))`. The 25 largest ideas (stable ID tie-breaks) always draw labels, including at default fit zoom. Other labels appear at 1.8× zoom relative to fit, independent of graph size.
- Map's Liked only filter starts off. Other screens and interactions are unchanged.
- Updated the native README and read-only smoke checks. Added an uncached determinism check and a 96-node disconnected-cloud regression check for collisions and four-fold angular bias.

Acceptance commands ran sequentially from `apple/`:

```sh
xcodebuild -project Fork.xcodeproj -scheme Fork -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Fork.xcodeproj -scheme Fork -destination 'platform=macOS' build
```

Both **BUILD SUCCEEDED**. Logs: `apple/build-ios.log`, `apple/build-macos.log`. No Swift compiler warnings/errors; the usual unused AppIntents metadata warning and CoreSimulator environment diagnostics remain.

CoreSimulator still fails at `xcrun simctl list devices available` with connection invalid / connection refused and no runtime discovery. Evidence: `apple/simulator.log`. Could not launch or capture screenshots, so rendered appearance and label readability still need owner-side simulator QC. No foreground app control was used. No commits. Existing changes outside apple were left alone apart from this requested handoff append.

Final `python3 apple/Checks/run.py`: **PASS**. Fresh computations matched exactly; the circular cloud had no collapsed pairs and four-fold grid bias 0.00936 (limit 0.2). Live snapshot: 787 scenes / 133 sources; liked Ideas 244 nodes / 2,878 edges; liked Full 560 nodes / 4,380 edges. Both modes/focus, cache, decoding, image fetch, Library search/tag, scene/source, deep-link URL and 401 handling passed. The 900-node / 4,000-edge / 1,000-iteration Debug layout took 20.49 seconds. Log: `apple/smoke.log`. Numerical checks do not replace rendered simulator QC. `git diff --check -- apple context/sol-native.md` passed.

## Round 3

Implemented UX spec section 8, Boards, under `apple/`. This handoff append is the only authored change outside that directory. No commits; unrelated concurrent working-tree changes were left alone.

- Added Boards between Today and Map in the iOS tabs and macOS sidebar. Accounts/Videos segmented index supports search, pull-to-refresh and Refresh, loading/error/empty states, account 2×2 cover collages and post/scene counts, video covers/titles/authors/notes.
- Added live Codable board models and deterministic frame geometry in `BoardModels.swift`; the UI is in `BoardsView.swift`. Account frames wrap in a grid, video boards use the server's single frame. Light grey canvas, white rounded frames, post title, italic note, heart/cross verdict, Open link, horizontal scene cards, timestamp/title, scene detail sheets, board title/subtitle/profile link, pan/pinch, macOS wheel zoom, zoom buttons and Fit.
- Below absolute canvas scale 0.45, one Canvas draws simple card rectangles with no SwiftUI card views or image tasks. Above it, only viewport-intersecting frames, headers and cards instantiate detail views. Thumbnails load lazily, downsample off-main to 480 pixels (320 for account collage cells), and share the bounded 80 MB decoded-image cache. Layout is computed once per response rather than during gestures.
- Source detail has a Board button for its video. Author names in Today, History, scene/source details and video index tiles open account boards. Existing source navigation, voting, swipe actions and scene details remain.
- Inspected both requested live endpoints with curl and credentials read from `.env.local`, without printing the token. NormieEdits has 91 groups / 413 scenes. Five scene timestamps are null; decoding handles them and cards use the existing 0:00 fallback. Quality is optional numeric data.
- The API emits absolute media URLs using the public Tailscale hostname. URLSession failed TLS against that hostname here. `APIClient.imageRequest` now resolves `/api/media/` paths through the configured server, so a localhost connection also fetches its images locally. Other image URLs retain their supplied host. Credentials continue to be sent only to the configured origin.

Final acceptance commands ran sequentially from `apple/`:

```sh
xcodebuild -project Fork.xcodeproj -scheme Fork -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Fork.xcodeproj -scheme Fork -destination 'platform=macOS' build
```

Both **BUILD SUCCEEDED**. Logs: `apple/build-ios.log`, `apple/build-macos.log`. No Swift compiler warnings/errors; existing CoreSimulator diagnostics and the unused AppIntents metadata warning remain. Generated project includes both new files. Credential scan found no token anywhere under `apple/`.

`xcrun simctl list devices available` still fails with CoreSimulatorService connection invalid/refused; evidence is in `apple/simulator.log`. No simulator launch, rendered screenshots or interactive smoothness/gesture check was possible, and no foreground app/browser control was used. Viewport culling and level-of-detail behavior are implemented, but device frame rate remains an owner-side check.

Final `python3 apple/Checks/run.py`: **PASS**. Read-only live checks decoded the index and both board kinds, confirmed NormieEdits 91 groups / 413 scenes, checked nonoverlapping frames and card containment, and resolved a board scene through the existing detail endpoint. Existing Library search/tag, source/scene membership, image HTTP fetch, deep-link URL, graph modes/focus/cache/determinism/cloud/scale and 401 checks all passed. Snapshot: 787 scenes / 133 sources; liked Ideas 244 nodes / 2,878 edges; liked Full 560 nodes / 4,380 edges. Synthetic 900-node layout: 18.05 seconds in Debug. Log: `apple/smoke.log`. `git diff --check -- apple context/sol-native.md` passed.
