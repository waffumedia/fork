Build the NATIVE SwiftUI multiplatform app "Fork" (iOS 26 + macOS 26) exactly per docs/UX-SPEC.md. Read docs/UX-SPEC.md and AGENTS.md first. Nominal, stock SwiftUI only.
Scope: only files under apple/. Do NOT touch lib/, app/, pipeline/, data/, scripts/.
XcodeGen is installed: write apple/project.yml, run `cd apple && xcodegen`.
API runs at http://localhost:3300. The token is FORK_TOKEN in .env.local: use it only via the DEBUG launch env for your own tests, never in source.
Verify both builds from the Acceptance section succeed. If you can, boot an iOS simulator, install, launch with SIMCTL_CHILD_FORK_TOKEN / SIMCTL_CHILD_FORK_URL and take screenshots of Today, Map (ideas + full), Library and a Scene detail into context/shots/ (xcrun simctl io booted screenshot).
Do not commit. When done write context/sol-native.md: what you built, file list, decisions, known gaps.
