# Product

<!-- impeccable:product-schema 1 -->

## Register

product

## Platform

macos

Native SwiftUI app with an AppKit `NSPanel` over the notch, macOS 14+. Not one of Impeccable's web/ios/android/adaptive values; follow macOS Human Interface conventions (menu bar extras, Control Centre, standard Settings window).

## Users

Primary: one developer (Wesley) on macOS, working in an editor or terminal all day with several Claude Code accounts and a handful of open GitHub pull requests. The notch sits in peripheral vision. The job is a half-second glance: is anything on fire, how much Claude, Codex and Grok Build budget is left, when does it reset. Hovering is the main interaction; a click opens a PR and right-click does the rest. Everything else is passive.

Secondary: other developers with multiple coding-subscription accounts who install the open-source DMG from GitHub Releases. Defaults stay tuned to the primary user, but a stranger must be able to get from first launch to a working notch without reading source.

## Product Purpose

Notchivity turns the hardware notch into a status instrument for coding-subscription usage and PR health. It replaced three tools (boringNotch, tokengochi, pr-tracker) so that one app owns the notch and one poller talks to each usage source. Success means the user never opens GitHub or the Claude usage page to check state, and never misses a CI failure, a review request, or an approaching usage limit. Events surface once as a short peek, then get out of the way.

## Positioning

The combination and the restraint together: every Claude, Codex and Grok Build account's budget and reset time, plus open PR health, in one notch that stays indistinguishable from the hardware until something matters. Usage trackers cover one provider or one account; notch apps are media players and widgets; PR trackers live in a menu bar or browser tab. None of them is silent by default.

## Operating Context

- MacBooks with a hardware notch, plus notch-less external displays where a small black tab stands in for the notch.
- Claude Code accounts discovered locally via `CLAUDE_CONFIG_DIR`, Codex and Grok Build usage snapshots, or a remote CLI proxy as the quota source.
- GitHub via the user's existing `gh auth`; PRs are `is:pr is:open author:@me`.
- Slack (bot token, or `claude -p` with a Slack MCP fallback) for review asks.
- Distribution: open source, DMG and ZIP on GitHub Releases, ad-hoc signed, not notarized. First launch needs Open Anyway or clearing quarantine.

## Capabilities and Constraints

Durable features future work must preserve:

- Three notch states: **collapsed** (matches the hardware notch), **peek** (one line for ~3 s after an event), **expanded** (while hovered: accounts and usage windows left, PRs grouped failing → needs action → ready → awaiting review right).
- **Slack review asks:** right-click a PR or cmd-click several to ask for review in one Slack message; later asks post a reminder in the same thread. "Ask for review" is the one name for this everywhere.
- **External display tab:** usage % with underline and failing / needs-action counts or dots on notch-less screens, configurable per display.
- **CLI proxy quota source** as an alternative to local discovery.
- **Keyboard access:** ⌃⌥N opens the notch from any app; arrows, Return, Space and Esc work the PR list.
- **First-run setup checks:** a checklist with a fix on each failing row; the collapsed notch shows "N to set up" until it passes.
- Failed fetches are counted once in the header; its "fix" opens the setup checklist, which carries each fix. Columns name what is affected in grey; hover reveals the full sentence.
- Notification Center posting per event type; thresholds fire once per crossing and re-arm on reset; nothing fires on the first fetch after launch.
- Settings is a standard macOS Settings window (General, PRs, Usage, Notifications, Displays); it is the only surface outside the notch.

Terminology: collapsed, peek, expanded, tab, setup check, ask for review, failing, needs action, ready, awaiting review.

Constraints: no AppKit in `NotchivityKit`; builds need the full Xcode toolchain; launch at login and notifications need the app bundle in /Applications.

Open: whether to pursue notarization or Mac App Store distribution. Undecided; do not design for or claim either.

## Brand Personality

Quiet, precise, instrumental. A cockpit gauge, not a companion. The interface says nothing until something matters, says it once, and returns to silence. Copy is lowercase, terse, and factual ("3 to set up", "resets 2h 10m", "nothing open"). No exclamation marks, no encouragement, no chatter.

References: Raycast and Linear for type scale and hairline rules; macOS Control Centre and menu bar extras for blending in rather than standing out.

## Anti-references

- boringNotch and Dynamic Island clones: no media player, no bouncy island physics, no glassy or blurred chrome.
- Dashboard SaaS: no cards, no hero metrics, no gradient accents, no pill badges, no decorative icons.
- Notification spam: never repeat an event, never peek on the first fetch after launch.

## Evidence on Hand

- `screenshots/framed/` (expanded, peek, nudge, tab, setup) at 2880×1800 with headlines, and `screenshots/raw/` bare views. Rendered from real SwiftUI views with fixed sample data via `--screenshots`.
- `--gallery <dir>` renders every state (loading, empty, errors, selection, overflow, setup, tab modes, peeks, each Settings tab) for design review.
- `ux-review/report.html`: an earlier UX review.
- `AppIcon.png`, drawn by `scripts/draw-icon.swift`.

Absent, do not fabricate: user counts, download numbers, testimonials, press, App Store listing, notarization.

## Product Principles

1. **Primary user first, strangers can follow.** Defaults, density and copy are tuned to one heavy user. Anything a newcomer needs (setup, auth, errors) explains itself in place with a fix, never in a separate onboarding flow.
2. **One app owns the notch.** New capability joins the existing collapsed / peek / expanded glance rather than adding a surface, window, or competing indicator.
3. **Every problem carries its fix.** A failing setup check, expired token, or fetch error names the cause in a few words and offers the action that resolves it.

## Design Principles

1. **Silence is the default.** The collapsed notch is indistinguishable from the hardware notch. Anything visible in the collapsed state must justify itself as urgent.
2. **Colour is a signal, not decoration.** Red, amber, green, and blue mean failing, needs action, ready, and awaiting review; violet marks notices (merged, limit reset) and blue doubles as the link colour. Nothing else is coloured. White is the neutral for text and for usage under 75%.
3. **One glance, one answer.** Every state (collapsed, peek, expanded) answers a single question and stops. Density is welcome; decoration is not.
4. **Match the hardware.** True black backgrounds, corner radii that continue the notch curve, and expansion that grows from the notch rather than appearing beside it. The notch is physically black, so the app is too.
5. **Act from where you are.** Click a row to open the PR, right-click for the rest. No navigation, no modals inside the notch; the Settings window is the only separate surface.

## Accessibility & Inclusion

No requirements beyond macOS defaults. Fixed 10.5 to 13pt type and colour-carried status are accepted trade-offs for notch density. These were set when the user base was one person; with others now welcome they stand until a real user need says otherwise.
