# TimeThrottle Repo

Applies only to the repo rooted at `/Users/anthonylarosa/CODEX/TimeThrottle`.

- This repo is separate from the outer `CODEX` workspace and unrelated repos such as `Super Goode`, `Super Goode App`, and `PhotoCleanupStudio`.

- This repo is the iPhone Live Drive app TimeThrottle.
- Preserve the core product model: Apple Maps route planning and ETA baseline, live pace tracking, and optional navigation handoff.
- Keep changes tightly scoped and exact. Do not introduce unrelated product pivots or broad UI rewrites unless explicitly requested.
- Treat generated build, archive, screenshot, and dist artifacts as secondary unless the task is specifically about packaging or release outputs.
- Keep implementation notes and summaries precise about user-visible behavior, data flow, and verification.

## Standing agent workflow

- Tony often starts fresh chats instead of assigning named agents. Treat the current prompt as the source of truth for the task.
- Stay tightly scoped to the requested task. Do not redesign or expand product direction unless Tony explicitly asks.
- Do not create extra work just because related improvements are visible.
- If subagents or helper passes are useful, they may be used internally, but the assigned agent remains responsible for the final result.
- Keep final summaries practical and focused on what changed, what was validated, what was not validated, and git status.

## Prompt modes

- Plan Mode is read-only: inspect files only, do not edit, do not commit, do not push, do not run builds, and return diagnosis, plan, risks, and the next implementation prompt.
- Implementation Mode means make only the requested changes, preserve Drive / Map / Trips / Scanner, preserve the Apple Maps ETA baseline, preserve Scanner independence from Live Drive, update docs only when behavior or privacy changes, run safe validation, and commit or push only if the prompt asks.
- Dist / Install Only means run `./dist-ios`, install the built app to the simulator, skip manual simulator exploration and extra UI testing unless asked, and prefer the direct simulator-build fallback path.
- Release / Archive Mode is only when Tony explicitly asks. Do not archive by default; if build validation is needed, provide commands or follow the explicit release prompt.

## Build and validation defaults

- Safe commands agents may run by default: `swift test`, iOS typecheck if needed, `git status`, `git diff`, `git diff --check`, `rg` searches, and `plutil` / JSON lint when relevant.
- Do not run unless explicitly allowed: `xcodebuild`, archive, Xcode GUI archive, App Store export, simulator launch, or manual simulator testing.
- For simulator packaging, use `./dist-ios`; direct simulator-build fallback is expected.
- Do not repeatedly wait on `xcodebuild` clang-discovery timeouts. Force the old xcodebuild-first path only with `TIMETHROTTLE_FORCE_XCODEBUILD=1 ./dist-ios`.
- Known local Xcode machine-state issue wording includes `Discovering version info for clang`, `ExecuteExternalTool clang -v -E -dM`, and `SWBBuildService` stuck. These are not automatically app-code failures.

## Git and dirty worktree rules

- Before editing, run `git status` and `git diff --name-only`.
- Do not commit `TimeThrottle.xcworkspace/xcuserdata/anthonylarosa.xcuserdatad/UserInterfaceState.xcuserstate`, generated build/dist outputs, or unrelated local signing/profile/resource-order edits.
- For `TimeThrottle.xcodeproj/project.pbxproj`, inspect the diff before staging. Only stage intentional build number, source file, resource, entitlement, or project configuration changes.
- Do not stage unrelated local signing, path, or user-state changes.
- For `AGENTS.md`, preserve repo workflow rules and avoid personal or unnecessary identity hunks unless Tony explicitly asks.
- Stage relevant files only, make one clean commit per task, push to `origin/main` only when the prompt asks, and report the commit hash and push result.

## Version and docs rules

- Keep `MARKETING_VERSION` at `2.0` unless Tony explicitly says to change the app version.
- Bump `CURRENT_PROJECT_VERSION` sequentially when implementation changes app behavior or app files.
- Do not bump the build for docs-only cleanup unless Tony asks.
- Update `README.md`, `CHANGELOG.md`, handoff, master doc, or full breakdown when user-facing behavior changes, privacy/data flow changes, scanner/audio behavior changes, background modes or permissions change, or App Store-facing wording changes.
- Update `privacy-policy.md` only when data collection/use changes, external services change, scanner/audio behavior changes, location/background behavior changes, or stored data changes.
- Do not update docs just for internal refactors unless useful.

## Return formats

- Implementation: task summary, exact files changed, exact changes made, validation, issues / limitations, git result, overall assessment.
- QA: PASS / FAIL, exact blockers only, release readiness.
- Plan Mode: diagnosis, likely root causes, files inspected, recommended plan, risks, next implementation prompt.
