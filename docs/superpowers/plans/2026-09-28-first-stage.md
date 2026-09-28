# UpstreamLens first-stage implementation plan

The supplied handoff is the design brief. Build a native iPhone monitor for public GitHub releases, tags, and paths, with a widget and an unsigned IPA. The user will validate installation and App Group behavior on their device.

## File map

- `project.yml`: XcodeGen app, widget, shared models, and test targets.
- `Sources/Shared`: Codable data and widget snapshot schema.
- `Sources/GitHub`: public REST client, pagination, ETag, content retrieval, and errors.
- `Sources/Monitoring`: baseline and change detection, relevance rules.
- `Sources/Storage`: local JSON persistence and widget snapshot writer.
- `Sources/App`: SwiftUI source management, findings, refresh, import/export.
- `Sources/Widget`: WidgetKit presentation of the shared snapshot.
- `Tests`: monitor and relevance behavior.
- `.github/workflows/ios-unsigned.yml`: test, archive, inspect, package, hash, upload.

## Tasks

1. Create the app and widget targets with stable bundle IDs and a shared App Group identifier. Verify XcodeGen generation in macOS CI.
2. Add models and JSON storage. Test serialization, baseline persistence, and read-state persistence.
3. Add the GitHub client for releases, tags, commits by path, and file contents. Test decoding and error mapping. Keep personal notes local.
4. Add monitoring: initial baseline, collect changes up to the known identifier, deduplicate, explain relevance, record failures without clearing cached data. Test each transition.
5. Build source and finding screens, manual/open refresh, JSON import/export, and last-success/error display.
6. Write a compact App Group widget snapshot and build the widget. Device validation determines whether the single-source network fallback is needed.
7. Run simulator tests and unsigned archive in Actions; inspect app/appex architecture, identifiers, signature absence, IPA integrity, and SHA-256. Record the run link and device test separately.

## Review focus

- No historical findings on the first successful check.
- Repeated checks create no duplicate findings.
- Path deletion and inaccessible repositories retain cached data and show an error.
- Unauthenticated rate limits and offline failures are distinguishable.
- Widget data is timestamped and never presented as live data.
