# Notchivity

A macOS notch app that shows Claude usage across every signed-in account and the status of your open pull requests. Hover the notch to expand it. Events (CI failed, approved, ready to merge, usage thresholds, limit resets) drop a short peek out of the notch and can post to Notification Center.

It replaces two earlier tools: [tokengochi](../tokengochi) (usage) and [pr-tracker](../pr-tracker) (PRs). 

## States

| State | When | Shows |
|---|---|---|
| Collapsed | always | On a hardware notch: nothing, the shape matches the notch exactly. On other displays the black tab shows the session % with a 2pt underline and the failing and needs-action PR counts, each switchable in Displays |
| Peek | for 3 s after an event | One line: what happened, on which PR or account |
| Expanded | while hovered | Accounts with session and weekly bars and reset times on the left, open PRs grouped failing → needs action → ready → awaiting review on the right |

Click a PR row to open it. Right-click a row for copy URL or "Ask for review in Slack". Cmd-click rows (or right-click › Select) to pick several, then "ask for review in Slack" under the list sends them as one message. Right-click anywhere else for refresh, setup check, settings, quit. When the list is longer than the row limit it ends in a "view all" link (or scrolls, per settings).

## Settings

The gear in the expanded header, Cmd-, or the right-click menu opens a standard Settings window.

| Tab | Settings |
|---|---|
| General | Launch at login (needs the app in /Applications), Slack channel and bot token, run setup check, version |
| PRs | Category order (drag), overflow mode (view all or scroll), rows before overflow, hide drafts, show age |
| Usage | Account for the tab's underline, poll interval, notification thresholds |
| Notifications | Peek on or off, peek duration, per-event Notification Center toggles |
| Displays | Show on external displays (a black tab at the top centre of notch-less screens), what the tab shows (usage on or off, PR indicator as counts, dots or nothing), hover delay |

Slack settings are written to `~/.config/notchivity/config.json`; everything else lives in UserDefaults.

## Setup check

On launch the app runs a checklist: Claude sign-in found, usage readable per account, `gh` installed and signed in, PR query works, plus optional notifications, Slack and launch at login. Until every required item has passed once, hovering the notch shows the checklist instead of the dashboard and the collapsed notch reads "N to set up"; after that, a failing fetch shows as an inline line on the dashboard. Each row has a one-click fix and the list rechecks itself every 10 seconds. Bring it back any time from the right-click menu ("Setup check").

The same checks from the terminal:

```sh
.build/release/Notchivity --doctor
```

Exit code 1 when a required check fails.

## Data

- **Usage**: every 3 minutes by default (Settings › Usage), for `~/.claude` and each `~/.claude-*` sibling. The OAuth token is read from the Keychain item Claude Code created (first run shows one "wants to use confidential information" prompt per account; click Always Allow). Token refresh belongs to Claude Code / T3 Code; a 401 means neither has run for a while.
- **PRs**: every 60 seconds via `gh api graphql` for `is:pr is:open author:@me`. Uses your existing `gh auth`.
- PRs refetch when you open the panel if the last fetch is more than a few seconds old. Usage never polls more often than its interval.

## Events

| Event | Peek | Notification Center by default |
|---|---|---|
| CI failed, conflicts, changes requested, approved, ready to merge | yes | yes |
| Usage crossed a threshold (50 / 75 / 90 / 100 by default) | yes | yes |
| New review comments, merged, limit reset, fetch failing | yes | no |

Usage peeks at 90 %+ mention the other account when it has headroom. Thresholds fire once per crossing; a reset re-arms them. Nothing fires on the first fetch after launch.

## Slack

Optional. Fill in the channel and token under Settings › General, or create `~/.config/notchivity/config.json`:

```json
{ "slackChannel": "C0123456789", "slackBotToken": "xoxb-…" }
```

Without `slackBotToken` it falls back to `claude -p` and your Slack MCP connection. The first ask posts the PR URL top-level; later asks nudge in that thread. A multi-select ask posts one list message, which becomes the thread for every PR in it.

## Build and run

```sh
swift build -c release
.build/release/Notchivity
```

Notification Center and launch at login need a real bundle:

```sh
./make-app.sh 0.1.0        # → dist/Notchivity.app, Notchivity-0.1.0.dmg, Notchivity-0.1.0.zip
open dist/Notchivity-0.1.0.dmg   # drag to Applications
```

The bundle is ad-hoc signed. On another Mac the first launch needs right-click → Open.

`NOTCHIVITY_STATE=expanded` or `=peek` pins the panel open for screenshots; `NOTCHIVITY_SETTINGS=1` opens the Settings window at launch.

## Tests

```sh
swift test
```

Covers account discovery, PR categorisation and GraphQL decoding, and the event diff.

## Layout

```
Sources/NotchivityKit   models, fetchers, EventDiff, SlackNudger (no AppKit)
Sources/Notchivity      NSPanel over the notch, SwiftUI views, AppModel, Notifier
Tests/NotchivityKitTests
```
