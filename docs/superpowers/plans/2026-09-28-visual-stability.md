# Visual and stability implementation plan

1. Add failing AppModel tests for same-source refresh single flight and data-load failure protection. Update the request gate to count the expected calls.
2. Implement per-source request revision tracking and a persistence guard. Preserve old responses only when the requested tracking revision is still current. Allow valid backup import to recover from a failed load.
3. Rework the existing SwiftUI home, detail, and Widget views with semantic colors, readable hierarchy, clear empty states, and refresh progress. Keep actions at least 44 points tall.
4. Run the GitHub Actions simulator tests, archive, and IPA verification. Capture and inspect a simulator screenshot. Fix any build or layout issue found, then merge and verify main.
