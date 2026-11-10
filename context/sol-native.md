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
