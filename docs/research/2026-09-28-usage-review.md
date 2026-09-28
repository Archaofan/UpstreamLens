# UpstreamLens usage review and UX design

Date: 2026-09-28. Scope: the existing local iPhone app for public GitHub releases, tags, and paths. Personal context stays on device; refresh remains manual or on opening the app. Device signing and Widget App Group behavior still require real-device verification.

## Comparable products and useful patterns

| Product | Verified behavior | Lesson for UpstreamLens |
| --- | --- | --- |
| [GitHub Notifications](https://docs.github.com/en/subscriptions-and-notifications/how-tos/viewing-and-triaging-notifications/managing-notifications-from-your-inbox) | Read, unread, and Done are separate states. Read items remain in the inbox until Done; filters and bulk triage are available. | Opening a finding should not remove it from the work queue. |
| [Releases.app](https://releases.app/) | Previews a source before saving, combines feeds into a timeline, and allows pausing and manual refresh. | Make the source and its next check understandable at setup; keep pause and refresh visible. |
| [NewReleases](https://newreleases.io/) | Tracks GitHub releases and tags, shows release notes, and offers version filtering. | Preserve upstream evidence and identify changes that matter instead of emphasizing the version number alone. |
| [changedetection.io](https://changedetection.io/) | Starts from a watched target and offers trigger or ignore filters. | Keep a specific Skill path and the user's relevance terms easy to enter. |

These products solve broader or different problems. The first implementation pass focuses on the local, personal workflow rather than adding accounts, push delivery, AI summaries, or more providers.

## Current friction observed in code

1. `FindingDetailView` marks a finding viewed on opening. The home list shows only unread findings. The finding therefore vanishes from the main work queue before the user marks it handled.
2. The home list presents findings by discovery time and shows no source name or explicit completion action. A user must enter the detail screen and find a status picker to finish triage.
3. The first screen says to use the toolbar plus button, while the source form presents every optional personal field at once. The first check only establishes a baseline, but this is explained away from the action.
4. The home screen has a global check time, while source rows show errors without showing their individual last check time.

## Selected behavior

- Home shows a **待处理** queue containing both `unread` and `viewed`; only `handled` leaves it. The queue orders `important`, `uncertain`, then `routine`, with newest first within a level. A compact filter shows all pending or important pending. Each row shows source, relevance, read state, reason, and a direct completion action. Completed findings remain accessible in a history list and may be reopened.
- Opening an unread finding sets it to viewed but keeps it in the queue. The detail screen has a prominent **标为已处理** action and still links to the GitHub original. Handling updates local storage immediately. This does not infer that the user upgraded anything.
- Empty home state offers a visible **添加来源** action and explains that the first successful check creates a baseline. Source setup shows the monitor target and two useful personal fields first; version, keywords, and rationale sit under an optional disclosure section. Existing values remain visible when editing.
- Source rows show a last successful check time or a pending-first-check label, along with current errors. A failed check does not erase the prior successful time.
- Widget remains an unread, relevant-change indicator as originally specified; its count can differ from the larger pending queue after an item is viewed. The home screen explicitly distinguishes unread and pending counts.

## Acceptance checks

- A viewed finding remains pending; only a handled finding moves to history. Reopening a handled finding restores it to pending.
- Important pending findings appear before uncertain or routine ones. The important filter never silently changes finding status.
- Existing JSON backups load without migration, and personal context is never added to network requests.
- iOS CI runs the full simulator test suite, unsigned archive, and IPA checks. The device installation and Widget sharing checks remain separate.
