# TimeThrottle Docs Map

Last audited date: 2026-04-22

Scope: Documentation map for meaningful docs currently present in `/Users/anthonylarosa/CODEX/TimeThrottle`.

## Core Orientation Docs

- `AGENTS.md`
  - Repo-specific agent instructions for keeping TimeThrottle work tightly scoped and product-truthful.
  - Clarity note: clear and short.
- `README.md`
  - Main repo overview, product summary, version/build notes, repo layout, and quick start reading order.
  - Clarity note: clear and useful as the first document.

## Release And Policy Docs

- `CHANGELOG.md`
  - Release-facing notes for current versions, especially `v1.4.3` and `v1.4.2`.
  - Clarity note: clear, focused, and intentionally current-state oriented.
- `privacy-policy.md`
  - Current privacy, data-use, local-storage, and handoff-service explanation for the app.
  - Clarity note: detailed and practical.

## Handoff And Long-Form Project Docs

- `TimeThrottle_Developer_Handoff.md`
  - Short current-state handoff for someone who needs the fastest practical summary.
  - Clarity note: clear and concise.
- `TimeThrottle_Master_Project_Doc.md`
  - Broader current-state product and project reference after the README.
  - Clarity note: clear, but overlaps with the handoff doc on product summary and repo tree.
- `TimeThrottle_Full_Project_Breakdown.txt`
  - Longest plain-text breakdown, including project summary, feature framing, team-role notes, and repo summary.
  - Clarity note: useful as a fuller narrative, but overlaps heavily with the README and master doc.

## New Audit Docs Added In This Pass

- `TIMETHROTTLE_SETUP_OVERVIEW.md`
  - Beginner-friendly setup and orientation summary for this repo only.
- `TIMETHROTTLE_FILE_INDEX.md`
  - Skimmable index of important files and folders with current-use notes.
- `TIMETHROTTLE_AGENTS_AND_WORKFLOW.md`
  - Plain-English explanation of repo rules, boundaries, and working flow.
- `TIMETHROTTLE_DOCS_MAP.md`
  - This doc map for quick documentation navigation.
- `TIMETHROTTLE_RECOMMENDED_CLEANUP_NOTES.md`
  - Documentation-only cleanup suggestions without changing repo behavior.

## Supporting Non-Markdown Doc-Like File

- `TimeThrottle_Full_Project_Breakdown.txt`
  - Plain-text reference instead of Markdown.
  - Clarity note: content is understandable, but naming and format make it feel more like an internal handoff artifact than a standard repo doc.

## Overlap And Gaps

### Clear docs

- `README.md`
- `AGENTS.md`
- `CHANGELOG.md`
- `privacy-policy.md`
- `TimeThrottle_Developer_Handoff.md`

### Overlapping docs

- `README.md`, `TimeThrottle_Developer_Handoff.md`, `TimeThrottle_Master_Project_Doc.md`, and `TimeThrottle_Full_Project_Breakdown.txt` all repeat the same core product framing and version context.
- The overlap is not wrong, but it makes the doc stack feel heavier than the small repo size suggests.

### Thin or missing areas

- There is no single doc dedicated to explaining the relationship between `Package.swift`, `TimeThrottle.xcodeproj`, and `TimeThrottle.xcworkspace`.
- There is no dedicated doc for `scripts/`, `build/`, `dist/`, and `SCREENSHOTS/`; their purpose had to be inferred from filenames and script contents.
- There is no separate release-process checklist doc, although pieces of that workflow appear across `README.md`, `CHANGELOG.md`, and generated export folders.

## Suggested Reading Order

1. `README.md`
2. `AGENTS.md`
3. `TimeThrottle_Developer_Handoff.md`
4. `TIMETHROTTLE_SETUP_OVERVIEW.md`
5. `TIMETHROTTLE_FILE_INDEX.md`
6. `TimeThrottle_Master_Project_Doc.md`
7. `TimeThrottle_Full_Project_Breakdown.txt`
