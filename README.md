# Notchivity

A macOS notch app that shows Claude, Codex and Grok Build usage across every signed-in account and the status of your open pull requests. Hover the notch to expand it, or press ⌃⌥N from any app. Events (CI failed, approved, ready to merge, usage thresholds, usage resets) drop a short peek out of the notch and can post to Notification Center.

It replaces three earlier tools: boringNotch (the notch shell), [tokengochi](../tokengochi) (usage) and [pr-tracker](../pr-tracker) (PRs).

![Usage and open PRs in the expanded notch](screenshots/framed/expanded.png)

## Install

Download the DMG from [Releases](https://github.com/wezzcoetzee/notchivity/releases) and drag Notchivity to Applications.

You need macOS 14 or later, the GitHub CLI signed in (`gh auth login`), and at least one of Claude Code, Codex or Grok Build signed in. On first launch macOS asks to let Notchivity read each Claude account's credentials from Keychain; click Always Allow. Then hover the notch, or press ⌃⌥N.

The app is not notarized, so the first launch shows "Apple could not verify Notchivity". Click Done, then open System Settings, Privacy & Security, and click Open Anyway next to Notchivity. Or clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Notchivity.app
```

## States

| State | When | Shows |
|---|---|---|
| Collapsed | always | On a hardware notch: nothing, the shape matches the notch exactly, except "N to set up" until first-run setup passes. On other displays the black tab shows one account's usage % with a 2pt underline and the failing and needs-action PR counts (or category dots), each switchable in Displays. A PR fetch error shows a hollow amber ring in place of the indicator |
| Peek | for 3 s after an event | One line: what happened, then on which PR or account |
| Expanded | while hovered, or after ⌃⌥N | Usage on the left, open PRs on the right, and a header line |

### The expanded panel

- **Header.** The left side shows the worst thing right now in its colour ("CI failed · web#318", else usage at 90% or more, else a PR needing action), and nothing when all is calm; hover it for the signed-in GitHub login. The right side shows "updated 12s ago", then "setup" and "settings". When a fetch fails, the fault takes the freshness text's place: a lone one by name ("token expired · fix"), several as a count ("2 issues · fix"). Both sides stay clear of the hardware notch.
- **Usage.** One block per account, most urgent first (90%+, then 75%+, then failing). The name and lead %, the lead window's bar with the other windows as thin lines under it, then the next reset and the other readings ("resets 2h 14m · week 61%"). The session leads unless another window has reached 75% and is fuller. At 75% or more the reset moves up beside the name ("Work · resets 47m") when it fits. Two accounts with one name read "1 of 2", "2 of 2". An account with no reading shows no bar, just "?" and why. Readings over 15 minutes old grey out and say "as of 3h ago".
- **PRs.** Grouped failing → needs action → ready → awaiting review. A row shows its two most urgent flags on the right and counts the rest ("+3"); the tooltip lists them all. An amber row always leads with its reason ("2 unresolved", "changes requested", "not approved", or "draft" on an approved draft), and a blue row with "awaiting review" unless it is a draft or already approved. A long list ends in "view all" (or scrolls, per settings); "view all" shows up to 12 rows, then scrolls.
- **Faults carry their fix where you read them.** "token expired · open Claude Code" under the account (hover for the full sentence), "GitHub unreachable · retry" in place of an empty PR list, or "as of 14m ago · retry" beside the PR count when the old list is still on screen. The header's "fix" opens the setup checklist with every fault's fix in one place.

### Pointer

Click a PR row to open it. Right-click a row for Open on GitHub, Copy URL and, with Slack set up, Ask for Review in Slack and Select for Slack Ask. Cmd-click rows (or Select) to pick several (a selected row's dot gets a white ring), then "ask for review in Slack" under the list sends them as one message. A success shows above that line for a few seconds. A failure stays until a retry or "clear", with a fix link when there is one ("Slack token rejected · open Slack settings", or "invite the Slack bot to the channel · open Slack", which opens the channel), and the failed PRs stay selected so the line below is the retry. Hovering a row shows its full title and these gestures.

Right-click anywhere else for Refresh Now, Dismiss Peek (while one is up), Setup Check, Settings and Quit.

Until you've used them, hovers show one grey line under the list naming the ways in a hover never reveals: cmd-click, right-click and ⌃⌥N. Each disappears once used.

### Keyboard

⌃⌥N (switchable in Displays) opens the panel on the screen under the pointer and gives it the keyboard. A grey line under the list shows the keys that apply at that moment.

| Key | Does |
|---|---|
| ↑ ↓ | Move between PRs (the focused row gets a white left edge) |
| Return | Open the PR in the background; the header confirms "opened web#318" and the panel stays up |
| Space | Select the PR for a Slack ask |
| A | Ask for review of the selection, or the highlighted PR, after a 3-second "undo" window |
| M | Open the highlighted PR's menu (the same as right-click) |
| F | Apply the first fault's fix |
| R | Refresh |
| S | Open the setup checklist (there, ↑↓ move, Return applies a row's fix, Esc goes back) |
| V | "view all" or "show less" |
| C | Clear the selection |
| ⌘, | Settings |
| Esc | Cancel a pending ask, otherwise close |

Clicking another app hands the keyboard back. VoiceOver announces peeks, a pending ask, its result, and faults appearing or clearing while the panel is open.

### Peeks

Click a peek to open what it is about. Hovering a peek waits 600 ms before expanding so the click lands first. Headlines say what happened first, then on what ("CI failed · web#318", "session at 88% · Work"), so a long name is what gets cut. Three or more events at once (after sleep, a CI storm) arrive as one peek led by the most urgent ("CI failed · web#322 · 3 more"), with the rest counted by kind underneath ("approved · new comments · merged"). A peek you hover into counts as seen and does not replay. The first time setup ever passes, one peek says the notch is live ("ready · hover the notch or ⌃⌥N").

A transient failure (expired token, network, server error) retries after a minute instead of the full refresh interval; rate limits, keychain prompts and missing Grok/Codex snapshots wait the interval.

## Settings

"settings" in the expanded header, ⌘, from the keyboard, or the right-click menu opens a standard Settings window.

| Tab | Settings |
|---|---|
| General | Launch at login (needs the app in /Applications), Slack channel and bot token (saved on Return, tab switch, window close or quit), setup check summary and "show on next hover", version, quit |
| PRs | Category order (drag, or right-click a chip for Move Left / Move Right), overflow mode (view all or scroll), rows before overflow, hide drafts, show age |
| Usage | Quota source (accounts on this Mac or CLI proxy), refresh interval, notification thresholds, account names |
| Notifications | Peek on or off, peek duration, per-event Notification Center toggles |
| Displays | Hover delay, the ⌃⌥N shortcut on or off, show on external displays (a black tab at the top centre of notch-less screens), what the tab shows (usage on or off and for which account, PR indicator as counts, dots or nothing) |

Cmd-1 to Cmd-5 switch tabs; Cmd-W closes the window.

Slack settings and the CLI proxy URL are written to `~/.config/notchivity/config.json`. The CLI proxy token is stored in macOS Keychain; other preferences live in UserDefaults.

### CLI proxy

In Settings › Usage › Quota source › Configure, enter your [CLI proxy](https://github.com/WebDotNext/cliproxy) base URL and its read-only `USAGE_LIMITS_TOKEN`. The proxy must include [usage-limits support](https://github.com/WebDotNext/cliproxy/pull/10), have management enabled, and permit remote management when Notchivity runs on another machine. Set `USAGE_LIMITS_TOKEN` in the proxy process environment and restart the proxy to enable the scoped token.

When a URL is configured, Notchivity reads `GET /v8/management/usage-limits` instead of discovering local Claude, Codex, or Grok accounts. It shows each supported account separately, maps the proxy's `xai` provider to Grok Build, and preserves unknown percentages and reset times. The proxy omits account names; use the Names rows in Usage to give accounts friendly labels. The regular refresh interval still applies, so the first read can show a pending account until the proxy's background refresh completes.

Failed requests retain the last readings with an error; pending and stale observations stay marked until refreshed. Passed reset times do not invent zero usage. An empty successful response removes old accounts. Clearing the URL and saving restores local discovery and removes the stored proxy token. A configured but unreachable or invalid proxy never falls back to local discovery. Setup check and `--doctor` use the selected source too.

## Setup check

On launch the app runs a checklist: Claude sign-in found (optional once Codex or Grok Build reads, so a Codex-only or Grok-only setup completes), usage readable per account, Codex and Grok Build usage when signed in, `gh` installed and signed in, PR fetch works, plus optional notifications, Slack and launch at login. Until every required item has passed once, hovering the notch shows the checklist instead of the dashboard and the collapsed notch reads "N to set up"; after that, a failing fetch is shown in the dashboard header ("token expired · fix").

Checks that need a look come first, failing ones on top; passing checks fold into one "N passed · show" line; optional ones sit under an "Optional" label with their fixes in grey until hovered. Each failing row has a one-click fix and the list rechecks itself every 10 seconds. The checklist's "skip for now" link (or "close", once nothing required fails) always returns to the dashboard: skipped while checks still fail, the checklist stays away until relaunch, failures show in the dashboard header, "N to set up" stays under the notch, and checks rerun every minute so it clears once fixed. Bring it back any time with "setup" in the dashboard header, S from the keyboard, the right-click menu ("Setup Check") or Settings › General ("show on next hover"); brought back that way it goes away when the panel collapses.

The same checks from the terminal:

```sh
.build/release/Notchivity --doctor
```

Exit code 1 when a required check fails.

## Data

- **Claude usage**: every 3 minutes by default (Settings › Usage), for `~/.claude` and each `~/.claude-*` sibling. The OAuth token is read from the Keychain item Claude Code created (first run shows one "wants to use confidential information" prompt per account; click Always Allow). Token refresh belongs to Claude Code / T3 Code; a 401 means neither has run for a while.
- **Codex usage**: read from disk on the same interval. Codex records its rate limits in the rollout log of every session (`~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`), so there is no token and no second caller on OpenAI's API; `primary` is the session window and `secondary` the week. The row only appears when `~/.codex/auth.json` exists. The freshest reading is selected by its event timestamp across all sessions, including older sessions that have resumed. The reading only moves when Codex runs, so the panel says "as of Nh ago" once it is over 15 minutes old, and a window whose reset time has passed reads as empty again.
- **Grok Build usage**: read from `~/.grok/logs/unified.jsonl` on the same interval. Grok Build logs its included credit allowance after billing fetches (including `/usage`). The row appears when `~/.grok/auth.json` exists; credentials are never read and no API requests are made. The freshest timestamp wins, and the last reading survives log trimming while the app runs. Only the actual allowance window is shown: weekly or monthly, including legacy monthly credits. This is the subscription allowance, which can be shared across Grok products, rather than session token counts or API spending. Readings over 15 minutes old show "as of Nh ago". After the recorded period ends, usage becomes unknown until Grok records another snapshot; it is never assumed to be 0%. If no snapshot exists, open `grok` and run `/usage` (update Grok Build if its version does not log billing snapshots). `GROK_HOME` and `GROK_AUTH_PATH` overrides are supported when present in Notchivity's launch environment. Grok checks are optional and never block setup. The log schema follows [Grok Build's billing implementation](https://github.com/xai-org/grok-build/blob/2bdd1d6a6369de0e8c68132ea4539e9abd9e14a8/crates/codegen/xai-grok-shell/src/extensions/billing.rs).
- **PRs**: every 60 seconds via `gh api graphql` for `is:pr is:open author:@me`, up to 100 (the count reads "100+" at the limit). Uses your existing `gh auth`.
- PRs refetch when you open the panel if the last fetch is more than a few seconds old. Usage never polls more often than its interval, except that a transient failure (expired token, network, server error) retries after a minute; a rate limit waits the full interval.

## Events

| Event | Peek | Notification Center by default |
|---|---|---|
| CI failed, conflicts, changes requested, approved, ready to merge (an approval that makes a PR ready shows as "ready to merge" alone, unless that notification is off) | yes | yes |
| Usage crossed a threshold (50 / 75 / 90 / 100 by default) | yes | yes |
| New review comments, merged, usage reset, PR fetch failing | yes | no |

The collapsed tab's % and underline use the chosen account's lead window, the same one the panel leads with: the session, unless another window has reached 75% and is fuller; for Grok Build, its allowance period.

Usage peeks at 90 %+ mention another account of the same provider when it has headroom. Thresholds fire once per crossing; a reset re-arms them. Nothing fires on the first fetch after launch.

## Slack

Optional. Fill in the channel and token under Settings › General, or create `~/.config/notchivity/config.json`:

```json
{ "slackChannel": "C0123456789", "slackBotToken": "xoxb-…" }
```

The bot token needs `chat:write`. Without `slackBotToken` it falls back to `claude -p` and your Slack MCP connection. The first ask posts the PR URL top-level; later asks post a reminder in that thread. A multi-select ask posts one list message, which becomes the thread for every PR in it.

## Build and run

Needs the full Xcode toolchain: the Command Line Tools lack the SwiftUI macro plugin, so `@State` fails to compile. Run `sudo xcode-select -s /Applications/Xcode.app` once, or prefix commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

```sh
swift build -c release
.build/release/Notchivity
```

Notification Center and launch at login need a real bundle:

```sh
./make-app.sh 0.2.0        # → dist/Notchivity.app, Notchivity-0.2.0.dmg, Notchivity-0.2.0.zip
open dist/Notchivity-0.2.0.dmg   # drag to Applications
```

The bundle is ad-hoc signed. On another Mac the first launch needs Open Anyway, as in Install.

Pull requests and pushes to `main` run the tests (and `swift format lint` when a `.swift-format` config exists) through the [shared macOS CI workflow](https://github.com/wezzcoetzee/.github/blob/main/.github/workflows/macos-ci.yml).

To publish a release, push a version tag from a commit containing `.github/workflows/release.yml`:

```sh
git tag v0.2.0
git push origin v0.2.0
```

The [shared macOS release workflow](https://github.com/wezzcoetzee/.github/blob/main/.github/workflows/macos-release.yml) runs `./make-app.sh` with the tag's version (without `v`) and attaches the DMG and ZIP to a GitHub Release with generated notes. Tags containing a hyphen, such as `v0.2.0-beta.1`, create prereleases. Signing stays ad-hoc; no Apple credentials or notarisation are involved.

`NOTCHIVITY_STATE=expanded` or `=peek` pins the panel open for screenshots; `NOTCHIVITY_SETTINGS=1` opens the Settings window at launch.

## Tests

```sh
swift test
```

Covers account discovery, Codex and Grok usage parsing, CLI proxy requests and quota normalization, snapshot freshness and expiry, setup diagnostics (including Codex-only and Grok-only setups), PR categorisation, flags and GraphQL decoding, the event diff and burst summaries, and Slack failure messages and their fixes.

## Formatting

```sh
swift format --in-place --recursive Package.swift Sources Tests scripts
swift format lint --strict --recursive Package.swift Sources Tests scripts
```

Rules live in `.swift-format` (4-space indent, 160 columns). `swift format` ships with the Swift 6 toolchain.

## Layout

```
Sources/NotchivityKit   models, fetchers, EventDiff, SlackNudger, SetupCheck (no AppKit)
Sources/Notchivity      NSPanel over the notch, SwiftUI views, AppModel, the ⌃⌥N hot key, Notifier
Tests/NotchivityKitTests
```

Design rules live in `DESIGN.md` and product context in `PRODUCT.md`.

## Screenshots

<table>
  <tr>
    <td><img src="screenshots/framed/peek.png" alt="Events drop out of the notch"></td>
    <td><img src="screenshots/framed/nudge.png" alt="Selected PRs with ask for review in Slack"></td>
  </tr>
  <tr>
    <td><img src="screenshots/framed/tab.png" alt="The collapsed tab on a display without a notch"></td>
    <td><img src="screenshots/framed/setup.png" alt="Setup checks with a fix on each failing row and the passing ones folded"></td>
  </tr>
</table>

These images render the real SwiftUI views offscreen with fixed sample data, so no real accounts or PRs appear:

```sh
swift build && .build/debug/Notchivity --screenshots screenshots
```

That writes the bare views to `screenshots/raw/` and the five App Store images (expanded, peek, nudge, tab, setup), with the headline and background at 2880×1800, to `screenshots/framed/`. Headlines live in `Screenshots.render`.

`--gallery <dir>` renders every state for design review: the default dashboard, loading, empty, errors, a stale list after a failed refresh, selection, overflow, Slack status and failure, the first-hover hint, a stress state (long, emoji, CJK and RTL text, every flag, every fault), a crowd (9 accounts, 50 PRs), the setup checklist with and without keyboard focus, the collapsed tab modes, all peeks and each Settings tab. Settings reads `~/.config/notchivity/config.json`, so point `CFFIXED_USER_HOME` at a scratch home to keep your own channel out of the images.
