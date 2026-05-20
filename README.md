# Puzzle House

An iMessage-native daily-puzzle leaderboard for families. Track results from
Wordle, Connections, Strands, and Apple News' Emoji Game in a shared house,
with streaks, a daily champion, and frictionless sharing via the Share Sheet
and Messages.

iOS / iPadOS / macOS (Mac Catalyst), native SwiftUI, CloudKit-backed. The full
implementation plan lives at `~/.claude/plans/my-parents-and-i-refactored-hippo.md`.

## Status

All four planned weeks have landed (modulo the manual signing/CloudKit-Dashboard
setup and real-device verification).

**Week 1 — foundation**
- Pluggable parser registry: Wordle, Connections, Strands; synthetic Emoji Game
- Z-score combined daily score with breadth bonus
- Per-game + house streaks with timezone-aware day boundaries
- `puzzlecheck` CLI

**Week 2 — app + CloudKit**
- Real `CloudKitService` / `ZoneManager` / `ShareManager` / `SubscriptionManager`
- File-backed `ChangeTokenStore` + `OfflineWriteQueue` (App-Group ready)
- `SpoilerPolicy` and `HouseholdStore` (Observable, MainActor)
- `PuzzleHouseApp` library: `RootView`, `Today`, `History`, `HouseSwitcher`,
  `PasteSubmit`, `CreateHousehold`
- `PuzzleHouse.xcodeproj` generated from `project.yml`

**Week 3 — extensions, OCR, polish**
- House-streak badge + per-game streak chips surfaced on the Today view
- Share Extension's offline write queue drains on bootstrap and on
  `scenePhase == .active`, rewriting placeholder household/author with real values
- iMessage app picker — tap a result, builds an `MSMessage` (template layout
  with caption / subcaption / trailing emoji), inserts into the active
  conversation ready to send
- Emoji Game OCR — Vision text recognition + synthetic-text bridge into
  `EmojiGameParser`; `PhotosPicker` entry in `PasteSubmitView` so a screenshot
  becomes a parsed result

**Week 4 — notifications + settings**
- `NotificationService` (local notifications) — daily reminder and weekly
  recap, schedulable from settings
- `NotificationPolicy` picks reminder time: explicit override or median of
  the user's rolling 7-day submit history (fallback 09:00 local)
- Settings tab: spoiler toggle, per-notification toggles, permission flow,
  current-house metadata, version/build info
- Real `HistoryView` grouping the rolling 14-day window by day with
  per-day leaderboard + expandable grids

**Test suite: 68 unit tests, ~80 ms.**
**Xcode build: succeeds for iOS Simulator without code signing.**

## Building

**Swift Package (logic + CLI, no signing needed)**

```bash
cd PuzzleHouseKit
swift build
swift test           # 68 tests, <100ms

# Paste a puzzle, get a parsed result:
printf 'Wordle 1,247 4/6\n\n⬛🟨⬛⬛⬛\n⬛⬛🟨🟨⬛\n🟨🟩🟨⬛⬛\n🟩🟩🟩🟩🟩\n' \
  | swift run -c release puzzlecheck
```

**Xcode app + extensions**

```bash
# Regenerate the project file after any project.yml change:
xcodegen generate

# Compile-check for iOS Simulator (no signing required):
xcodebuild -scheme PuzzleHouse \
  -project PuzzleHouse.xcodeproj \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build

# Open in Xcode:
open PuzzleHouse.xcodeproj
```

Requires Xcode 26 / Swift 6.3. Package targets Swift 5.10 / iOS 17 so Xcode
15.3+ also compiles the logic.

## Still requires you

1. **Open `PuzzleHouse.xcodeproj` in Xcode.**
2. **Set your Team** on each of the three targets in Signing & Capabilities
   (Automatic signing).
3. **Provision the CloudKit container** `iCloud.com.jestats.PuzzleHouse` at
   <https://icloud.developer.apple.com/dashboard/> and deploy the schema for
   `Household`, `Membership`, `PuzzleResult`, `Reaction`. On `PuzzleResult`:
   add a field `puzzleDayEpoch` of type `Int(64)` and mark it **Queryable +
   Sortable** (this is what the recent-history range query uses — String
   fields don't support `>=` in CloudKit). Mark `householdID` Queryable on
   both `Membership` and `PuzzleResult`; mark `recordName` Queryable on every
   type.
4. **Provision the App Group** `group.com.jestats.PuzzleHouse` at
   <https://developer.apple.com/account/resources/identifiers/list/applicationGroup>.
5. **App icon** — a starter icon is generated at
   `PuzzleHouse/Assets.xcassets/AppIcon.appiconset/icon.png`. Regenerate
   anytime with `swift run --package-path PuzzleHouseKit make-icon`. Replace
   with a real design when ready.
6. **Run on a real iPhone** (Simulator iCloud is flaky), create a household,
   invite Mom/Dad, share a result from Wordle into Puzzle House.

For TestFlight: archive build, upload via Xcode Organizer or `xcodebuild
-exportArchive`, configure test group in App Store Connect.

## Future work (week 5+)

The architecture review and plan call out items we explicitly punted from this
4-week sprint:

- **Silent push for "Mom solved before you"** — `CKQuerySubscription` is
  already created in `createHousehold`; needs APNs entitlement wiring, an
  `AppDelegate` to handle `application(_:didReceiveRemoteNotification:)`, and
  local-notification renotification logic.
- **Real Emoji Game grid reconstruction** — current OCR pulls only score; full
  pixel-sampling of the grid lives behind `EmojiGridReader.read(image:)`.
- **Background queue drain** — `BGTaskScheduler` task so pending Share Ext
  writes flush even without a foreground open.
- **App icon, widget, watch glance.**

## Layout

```
puzzle-house/
├── project.yml                         XcodeGen recipe
├── PuzzleHouse.xcodeproj/              GENERATED
├── PuzzleHouse/                        Main app target
├── PuzzleHouseShareExtension/          Share Extension
├── PuzzleHouseMessages/                iMessage app extension
└── PuzzleHouseKit/                     Local Swift Package
    ├── Sources/
    │   ├── PuzzleCore/                 Models, value types, PuzzleDay
    │   ├── PuzzleParsers/              Protocol, registry, per-game parsers
    │   ├── PuzzleScoring/              z-score CombinedScore, streaks, SpoilerPolicy
    │   ├── PuzzleCloudKit/             Real CK service, identifiers, App Group queue
    │   ├── PuzzleVision/               OCR pipeline + Emoji Game synth bridge
    │   ├── PuzzleUI/                   Shared SwiftUI views (ResultCard, Avatar, etc.)
    │   ├── PuzzleHouseApp/             HouseholdStore + Today/History/Houses/Settings,
    │   │                               NotificationService, MessagesPickerView
    │   └── puzzlecheck/                CLI sanity tool
    └── Tests/                          68 tests
```

## Adding a New Game

1. Create a parser in `PuzzleHouseKit/Sources/PuzzleParsers/` conforming to
   `PuzzleParser`.
2. Register it in `ParserRegistry.all`.
3. Add a `Game` constant in `PuzzleCore/Game.swift` if you want a typed handle.
4. Write tests with real share-text samples.
5. Verify: `swift run puzzlecheck < sample.txt`.

## Threat model

CloudKit shared zones give every household member full read access to every
record — there's no row-level field projection. Grid hiding ("spoiler
protection") is enforced client-side in `SpoilerPolicy` and `GridReveal`. A
technically-inclined family member could read raw `CKRecord`s out of the zone
and bypass it. This is fine for a family app; document but don't pretend
otherwise.
