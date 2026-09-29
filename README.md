> English · [简体中文](README.zh-CN.md)

# UpstreamLens

A personal on-device tech-change radar for iPhone. It watches Release, Tag, and commits to specific file/directory paths of public GitHub repos. The first check only records a baseline; later changes are judged against your locally stored usage, in-use version, and keywords, with verifiable reasoning. The main App keeps its data on-device; the Widget only reads a trimmed snapshot from the App Group container. Developer: [@Archaofan](https://github.com/Archaofan) · [Project home](https://github.com/Archaofan/UpstreamLens)

**Language**: The App defaults to English. On first launch the onboarding's first page lets you pick English / 中文 / Follow System, and you can switch anytime in Settings → General → Language; the UI updates immediately. The Widget follows the App's language.

## Workflow

1. **Add a source**: Tap “+” in the top-right, **search a repo name** or **paste a GitHub link** (repo, `/tree/` branch directory, or `/blob/` file link). The App reads the repo description, default branch, topics, and latest version to prefill. “Common presets” offer curated AI/high-star and Agent-toolchain sources (OpenClaw, Hermes Agent, DeepSeek Harness, n8n, AutoGPT, Firecrawl, Dify, Open WebUI); tapping one prefills it, with the project's GitHub avatar as the icon. For Skill files choose “Path” mode and the App lists every SKILL.md in the repo to pick from. Manual entry remains the fallback.
2. **“In-use version” is a dropdown**: The confirm page and “Edit usage” read the upstream Release/Tag list (1 API request) so you can pick instead of memorizing; you can still type a commit SHA manually if the list fails.
3. After saving, the first successful check only records the baseline. Whether it auto-checks afterward is configurable in Settings → Monitoring & Refresh (check-on-open is on by default); each source shows its last successful check time and any error.
4. The home “Pending changes” list includes unread and seen items, with “Worth Attention” first. Opening a detail marks it seen but keeps it pending; verify the reasoning and the original GitHub text, then tap “Mark Handled”, the row-end checkmark, or swipe to complete. Swipe the other way to toggle read/unread.
5. Handled items live in “Handled records” (searchable) and can be re-added to pending from the detail. The Widget only counts **unread and relevant** changes, so its number may drop after you view an item while the App still keeps it pending.
6. Personal usage (purpose, version, keywords) can be filled in anytime from a source's “Edit usage”; the judging engine cites the exact matched wording so you can trace it back to the original.
7. “Settings” is split into four sub-pages: **General** (language, GitHub sign-in, notifications), **Monitoring & Refresh** (check-on-open, background-refresh toggle and interval), **Data & Backup** (JSON import/export, handled-record cleanup, AI batch-add), and **About & Diagnostics** (version, project home, diagnostics you can copy to the developer).

## Batch-add sources with AI

Settings → Data & Backup → Help offers a copyable prompt: hand it to an AI that can access your machine/server (an Agent CLI, IDE assistant, etc.). It scans the open-source projects you use (package managers, dependency files, Docker, CLI tools), learns their versions, and outputs an `upstreamlens.source-list` JSON list. Save it as .json and use “Import AI Source List”: the App only **merges new** sources (same repo + mode is de-duplicated and skipped), never modifies or deletes existing sources or personal info, and runs a check right after import to establish the baseline.

## Notifications & background checks

Notifications are off by default. After enabling them in Settings → General → Notifications they follow these rules (modeled on GitHub Notifications and iOS notification conventions):

- Only “Worth Attention” and “Uncertain Impact” changes are notified; “Routine Update” never interrupts. Multiple notifications from one source are **auto-grouped** in Notification Center; at most 5 per check, with the rest folded into a summary.
- “Worth Attention” uses banner + sound (interruption level active); “Uncertain Impact” enters Notification Center silently (passive), and whether it interrupts is entirely up to the system Focus mode and scheduled summary—the App builds no custom quiet hours.
- Each source can disable notifications individually in “Edit usage”.
- Tapping a notification opens the corresponding change detail.

**Check/refresh strategy** is configurable in Settings → Monitoring & Refresh:

- **Check for updates on open** (default on): auto-check when returning to the foreground; when off, checks happen only on manual pull-to-refresh.
- **Background refresh** (default on): registered via `BGAppRefreshTask`; after entering the background it runs about once per the chosen interval (15 / 30 / 60 / 180 min); when off, no background rounds are scheduled. iOS schedules by usage patterns and may coalesce, defer, or skip—**not a real-time alert**.
- Background rounds carry an API budget guard: when the quota is low they are skipped to reserve it for the foreground.

“Handled” only means you finished the local review, not that you upgraded upstream. Personal usage and notes stay on-device and are never sent to GitHub.

## Data durability

- Before every write the current `data.json` is rotated to `data.json.bak`; if the main file is corrupt, launch auto-recovers from the backup and notifies you.
- Records are capped at 1000: beyond that, eviction follows “oldest handled → oldest seen → oldest unread” to keep the JSON from growing without bound and slowing reads/writes.

## Widget & signing

The Widget relies on the App Group shared container. **When sideloading with a free Apple ID, the App Group in the signing profile carries a 10-digit team-ID prefix** (e.g. `ABCDEF1234.group.com.upstreamlens.ios`), which differs from the unprefixed ID requested in entitlements—this is the root cause of “diagnostics shows the entitlement but the container is unavailable”. App and Widget now parse the actually-authorized group name from `embedded.mobileprovision` at runtime and adapt automatically (see `Sources/Shared/AppGroupResolver.swift`). The 2×2 size leads with the count plus at most a two-line short headline and the check time, so the headline is not truncated to an ellipsis; Widget copy follows the App language. This project's IPA has entitlements embedded into the App and Widget binaries with adhoc codesign before packaging (brew ldid on the macOS runner is unreliable, so system codesign is used), so the sideloading tool can read and register the App Group when re-signing. If the Widget still shows “Shared data unavailable”, generate diagnostics in-App via Settings → About & Diagnostics → Generate Diagnostics and copy the text: it shows the profile's authorized group list, the group actually used (auto-adapted for prefix), whether the shared container is reachable, and whether `embedded.mobileprovision` and the main binary really contain the App Group entitlement—so you can pinpoint which link dropped it.

## Build

This project uses XcodeGen to produce the project. The GitHub Actions `iOS unsigned IPA` workflow is pinned to `macos-26`, selects Xcode 26.6, runs unit tests, produces an unsigned archive, embeds App and Widget entitlements with adhoc codesign (no real signing), verifies identifiers, architecture, and entitlements, then uploads the IPA and SHA-256. After a successful run, download both files from that Actions run's `UpstreamLens-unsigned` artifact, and verify the IPA with SHA-256.

Fixed identifiers:

- App: `com.upstreamlens.ios`
- Widget: `com.upstreamlens.ios.widget`
- App Group: `group.com.upstreamlens.ios`
- URL scheme: `upstreamlens://` (`findings` opens the pending queue; `add` opens the add page)

Keep these identifiers unchanged on updates. **A successful Actions build does not guarantee device installation or App Group sharing.**

## Installation & Gate A verification

Use the already-verified sideloading route: first install the downloaded unsigned IPA on Windows with iloader; afterward import and re-sign a local IPA in SideStore on the iPhone. Connect LocalDevVPN during SideStore operations. Plugging in, trusting, importing, and re-signing are done by the device owner. Do not pre-sign the IPA. The Widget extension consumes an extra App ID; mind the free Apple ID's 7-day validity and sideloading slots.

After install, check first:

1. The main App opens; first launch shows onboarding (four pages, language on page one, shown once); the home screen shows the empty state.
2. The Widget appears in the add-widget list (including lock-screen rectangular/circular styles).
3. Add a public GitHub source; the first check produces no historical changes; the Widget shows the snapshot and check time.
4. If the Widget shows “Shared data unavailable”, generate info in Settings → About & Diagnostics and record it; this means App Group sharing still needs resolving under the real re-signing chain.
5. With the network off, open the App; old changes remain and times are not faked as real-time data.

## GitHub sign-in (optional)

It works **without signing in** by default via the public GitHub API. Paste a read-only Personal Access Token in Settings → General → GitHub Sign-In (fine-grained recommended; only Metadata + Contents read-only needed) to lift the limit (about 5000/hour vs 60/hour unauthenticated) and to monitor **private repos**. On sign-in the App validates the token via `/rate_limit` (consumes no quota) and refuses to store an invalid one; the token is kept only in the local Keychain, never uploaded or written into exported backups, and can be revoked anytime via “Sign Out”. Personal usage and notes still stay on-device.

## Current limitations

- Unauthenticated uses the public GitHub API: 60/hour per IP for core endpoints and 10/min for search; when rate-limited the App shows the estimated recovery time. Signing in raises this to about 5000/hour and enables private repos (see above).
- By default it checks on open and about every 30 minutes in the background, both adjustable in Monitoring & Refresh; the Widget timeline is scheduled by iOS and is not a real-time alert.
- Reads at most three pages of 100 upstream records each; if unchecked for a long time and beyond that range, re-verify the baseline.
- JSON import replaces the on-device list and change records—export a backup first.
- Version comparison targets semantic versions (including calendar versions like 2026.9.24); irregular tag names do not participate in version comparison.
