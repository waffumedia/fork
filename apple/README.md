# Fork native app

One SwiftUI target for iOS 26 and macOS 26. No packages or web views.

Generate and build, sequentially (both destinations share Xcode's build database):

```sh
cd apple
xcodegen
xcodebuild -project Fork.xcodeproj -scheme Fork -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Fork.xcodeproj -scheme Fork -destination 'platform=macOS' build
```

Settings stores the server URL in UserDefaults and the token in Keychain. Debug builds also accept `FORK_URL` and `FORK_TOKEN` in the launch environment. Environment values aren't saved until Save or Test connection is pressed. Release builds ignore those variables. For a physical iPhone, use the Mac's LAN hostname or address in Settings; localhost refers to the iPhone itself.

Debug builds use Swift's `-disable-sandbox` compiler option because the build host already runs in a sandbox and cannot start a nested sandbox for Observation macro helpers. This affects compiler subprocesses, not app permissions. Release has no such override. macOS uses ad hoc signing.

Read-only integration checks (loads the local token only into the Debug check executable's environment):

```sh
python3 apple/Checks/run.py
```

Run that command from the repository root. It checks live JSON decoding, search, tag filtering, scene/source details, image fetch, deep-link URL, both graph modes and focus, layout caching, deterministic fresh layouts, circular-cloud separation and grid bias, a 900-node/4,000-edge layout, and 401 state. It doesn't change swipes or claim to test rendered UI. Output is saved to `apple/smoke.log`.

For simulator launch, pass the token through `SIMCTL_CHILD_FORK_TOKEN` and the URL through `SIMCTL_CHILD_FORK_URL` when invoking `xcrun simctl launch booted com.waffu.fork`. Don't put credentials in the scheme or project. Capture UI with `xcrun simctl io booted screenshot ../context/shots/<screen>.png` from `apple/`.

The map uses one Canvas, four batched edge paths, a spatial-grid force layout in a detached task (1,000 iterations, ID-seeded disc positions and circular repulsion), and cached static positions. Images are fetched only for visible scene nodes in batches of six, downsampled off the main thread, and cached. Map starts with Liked only off. Idea radii use square-root scene counts; the 25 largest idea labels stay visible at fit, and other labels appear at 1.8× zoom. Search also exposes Canvas nodes as native buttons. Pan with a drag, zoom with a pinch or the toolbar controls; macOS also converts native ScrollView wheel movement to zoom. Layout cache keys include server, mode, liked filter, focus, and graph membership/degrees.

Boards adds a searchable Accounts/Videos index and a pan/zoom canvas. Account frames wrap in a grid; video boards have one frame. At scales below 0.45, one Canvas draws plain card rectangles and no card/image views are created. Above that scale, only cards and headers intersecting the viewport create SwiftUI views. Board images use off-main downsampling (480 pixels for cards, 320 for collages) and the shared 80 MB decoded-image cache. Fit resets the view; pinch, buttons and macOS wheel control zoom. Author names open account boards; Source has a video Board button. Live checks also decode both board endpoints, verify NormieEdits frame/card geometry and resolve a board scene through the existing detail endpoint.

Fork `/api/media/` image URLs use the configured server connection even if JSON names its public host. Other external images keep their original URLs.
