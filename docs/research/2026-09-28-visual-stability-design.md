# Visual and stability iteration

Date: 2026-09-28. User preference: **原生清爽**. Scope: the existing iPhone app and Widget; monitoring rules and the local-only data model stay intact.

## Design

The home screen should reveal the pending count, unread count, and last successful check at a glance. A compact summary card leads into the pending queue. Findings use a clear title, source, relevance cue, and direct 44-point completion control. Source rows use consistent symbols and concise check or error text. Compact empty states keep the add-source action visible on the first screen. Widget permission diagnostics sit below the primary content. Pull-to-refresh and an in-progress indicator make a manual check visible. The detail screen leads with the relevance judgment and keeps the upstream link and completion action easy to find. The Widget uses one dominant count and a short headline.

Use SwiftUI semantic fills and foreground styles, Dynamic Type text styles, and SF Symbols. Avoid fixed RGB colors and fixed heights for text. This follows [Apple's color guidance](https://developer.apple.com/design/human-interface-guidelines/color), [layout guidance](https://developer.apple.com/design/human-interface-guidelines/layout), [widget guidance](https://developer.apple.com/design/human-interface-guidelines/widgets), and [progress indicator guidance](https://developer.apple.com/design/human-interface-guidelines/progress-indicators).

## Stability behavior

For a given source and tracking revision, only one network refresh may be active. A source edit or baseline reset may start a new request while the old response is discarded. A failed local data load must block automatic saves so a corrupt file cannot be silently replaced by empty data. Importing a valid backup re-enables saving. A failed save restores the last saved in-memory state and does not publish an unsaved Widget snapshot.

## Checks

Unit tests cover duplicate refreshes, refresh after revision change, failed load save protection, failed save rollback, and import recovery. CI builds and runs tests on an iPhone simulator and produces an unsigned IPA. A simulator screenshot is reviewed for the empty home screen. Real-device installation and App Group behavior remain to be checked on a signed device build.
