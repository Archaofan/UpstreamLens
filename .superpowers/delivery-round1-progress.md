# SDD ledger — plan: docs/plans/2026-09-29-delivery-round1.md

Pre-flight: T2→T5 (models consumed by AppModel), T3/T4→T6 (engine+client consumed by UI), T5→T6 (probe closures). No conflicts found: closures injected with defaults keep test call sites compiling.

Ruling (process): 本机无 Xcode，无法本地跑测试 — TDD 红绿循环改为"同批提交代码+测试，推送分支后以 Actions 单测为红绿门"；每批 commit 对应一个任务，Actions 红则修复回归。
Task T1-T8, T9: code+tests+README committed in one batch — Ruling: 无本地 Xcode，无法逐任务本地跑测试，红绿门统一由 Actions 承担（见计划 Global constraints）。
CI loop record (delivery-round1, run 36453939764 → 36459336316):
- R1 dup @State pendingClipboardAdd (ContentView) → removed; R2-3: diff ternary type, search tuple destructure, keypath \isEmpty, hashValue; R5 try export; R6 slow type-check AddSourceView body → split builders, NavigationPath() reset
- R7 first full test run: 89 tests / 13 assertion failures → root causes fixed in impl:
  * LocalData.effectiveRetentionDays treated 0 (永久保留) as 90 → rewritten; pruned() no-ops on 0
  * DiffEngine.counts subtracted from mutated set → subtracting() on immutable sets
  * DiffEngine.lines trimmed common prefix/suffix unconditionally (context lines lost) → trim only when >400 lines
  * RelevanceEngine.terms: no space splitting (mixed CJK+ASCII terms unusable) → split on spaces/全角空格; minASCIILength default 2, no max()
  * ParsedVersion.parse: split dropped empty segments → "1..3"/"1.2.3.4" accepted → omittingEmptySubsequences: false
  * ParsedGitHubURL: host never validated (example.com accepted), plain-text >2 segments accepted → github.com host check + plain==2 segments
  * watchSource tree-no-path didn't prefill installedVersion
  * Diagnostics.contains empty-needle semantics settled: false (test updated)
- R9: String.firstIndex(of:) type error → range(of:)
- R10: terms test still used 1-char words → test updated to 2-char (implementation rule stands)
Final review (fresh subagent) → 1 Critical, 5 Important, 11 Minor.
Fix pass (one pass, TDD where applicable):
- Final: fixed Critical#1 Finding.isPrerelease Bool->Bool? (custom decode default) — regression test testLegacyBackupWithFindingsDecodes
- Final: fixed Imp#1 assess reorder (breaking>keywords>version>context) — testBreakingTermOverridesRoutineVersionGap
- Final: fixed Imp#2 ParsedVersion Int overflow crash — testOverflowingNumericSegmentDoesNotCrash
- Final: fixed Imp#3 containsWord scans all occurrences — testWordBoundaryScansPastEmbeddedOccurrence
- Final: fixed Imp#4 RepoConfirmView manual fallback wired via onRequestManual callback
- Final: fixed Imp#5 retention nil = keep-forever (no silent deletion) — testDefaultRetentionIsOffUntilUserOptsIn + legacy test updated
- Minors fixed opportunistically: dead PendingNavigation removed; markAllHandled UI entry added (plan T6 scope); rateLimited info captured in refresh catch; detectPatterns completion dispatched to MainActor; README ldid wording corrected
Deferred minors: widget headline comparator inconsistency; circular accessory shows 0 when snapshot nil; AddSourceView onSubmit+debounce double-search risk; RepoConfirmView footer request-count wording; refreshAll rate budget; snapshot read duplication & hardcoded ids in widget; perform retry untested; testProfileDataIsOptionalAndSafe no assertions
Merge: main d124752 (delivery-round1 merged --no-ff); final main run 36470282984 SUCCESS (IPA artifact UpstreamLens-unsigned 0.65MB, id 10992111087).
Deliverable JSON: deliverables/UpstreamLens-import-2026-09-29.json (gitignored, 7 public sources; chaofanhermes is private/unauthenticated-404, excluded).
Post-merge validation: screenshots artifact visually checked (home light mode renders correctly, new copy present).
Beautify round (2026-09-29, branch beautify-round1):
- Research: iOS 26 Icon Composer .icon needs macOS tool — not producible on Windows; asset-catalog appearances (Light/Dark/Tinted) is the documented path and required for iOS 17 target anyway.
- Icon v2: bold round-capped arcs (SDF, 6.2% stroke vs 3.7%), richer cyan→deep-teal gradient + glow + vignette; three variants (light/dark/grayscale-from-dark for tinting). Visual check via local render at 200/80/60px.
- Launch screen background color (LaunchBackground, light #F2F2F7 / dark #000) to kill white flash.
- App: summary card soft shadow + symbolEffect(.pulse) while refreshing; filled SF Symbols for source rows. Widget: faint accent gradient over .fill.tertiary.
Beautify merge: main (run 36474760675 SUCCESS, IPA 1.05MB id=10993187458 — size grew from three-appearance icon set). branch beautify-round1 deleted. Home light/dark screenshots re-verified: card shadow visible, layout unchanged, dark mode clean.
Round 3 (2026-09-29, branch productionize-round1): notifications + background refresh + stability + presets.
Research: iOS notif conventions (threadIdentifier per source, interruptionLevel active for important / passive else, provisional auth option, respect Focus/Scheduled Summary — no custom quiet hours); changedetection.io pattern = many channels + per-watch rules; Releases.app digest scheduling.
Presets verified unauthenticated: swiftlang/swift (release, renamed from apple/swift), swiftlang/swift-evolution (path proposals), XcodesOrg/xcodes (release), obra/superpowers (path skills).
