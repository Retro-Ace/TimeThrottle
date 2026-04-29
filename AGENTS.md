# TimeThrottle Repo

Applies only to the repo rooted at `/Users/anthonylarosa/CODEX/TimeThrottle`.

- This repo is separate from the outer `CODEX` workspace and unrelated repos such as `Super Goode`, `Super Goode App`, and `PhotoCleanupStudio`.

- This repo is the iPhone Live Drive app TimeThrottle.
- Preserve the core product model: Apple Maps route planning and ETA baseline, live pace tracking, and optional navigation handoff.
- Keep changes tightly scoped and exact. Do not introduce unrelated product pivots or broad UI rewrites unless explicitly requested.
- Treat generated build, archive, screenshot, and dist artifacts as secondary unless the task is specifically about packaging or release outputs.
- Keep implementation notes and summaries precise about user-visible behavior, data flow, and verification.

## Simulator packaging

- For simulator packaging, prefer the direct simulator-build path through `./dist-ios`. Do not wait for repeated `xcodebuild` timeouts.
- The `xcodebuild` timeout at clang discovery is a known local machine-state issue on this Mac, not automatically an app-code failure.
- If `./dist-ios` uses the direct fallback path, that is expected here. Set `TIMETHROTTLE_FORCE_XCODEBUILD=1 ./dist-ios` only when explicitly checking the old xcodebuild-first path.
