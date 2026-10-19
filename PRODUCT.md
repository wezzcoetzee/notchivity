# Product

## Register

product

## Users

One developer (Wesley) on macOS, working in an editor or terminal all day with several Claude Code accounts and a handful of open GitHub pull requests. The notch sits in peripheral vision. The job is a half-second glance: is anything on fire, how much Claude and Codex budget is left, when does it reset. Hovering is the only deliberate interaction; everything else is passive.

## Product Purpose

Notchivity turns the hardware notch into a status instrument for coding-subscription usage and PR health. It replaced three tools (boringNotch, tokengochi, pr-tracker) so that one app owns the notch and one poller talks to the usage API. Success means the user never opens GitHub or the Claude usage page to check state, and never misses a CI failure, a review request, or an approaching usage limit. Events surface once as a short peek, then get out of the way.

## Brand Personality

Quiet, precise, instrumental. A cockpit gauge, not a companion. The interface says nothing until something matters, says it once, and returns to silence. Copy is lowercase, terse, and factual ("3 to set up", "resets 2h 10m", "nothing open"). No exclamation marks, no encouragement, no chatter.

References: Raycast and Linear for type scale and hairline rules; macOS Control Centre and menu bar extras for blending in rather than standing out.

## Anti-references

- boringNotch and Dynamic Island clones: no media player, no bouncy island physics, no glassy or blurred chrome.
- Dashboard SaaS: no cards, no hero metrics, no gradient accents, no pill badges, no decorative icons.
- Notification spam: never repeat an event, never peek on the first fetch after launch.

## Design Principles

1. **Silence is the default.** The collapsed notch is indistinguishable from the hardware notch. Anything visible in the collapsed state must justify itself as urgent.
2. **Colour is a signal, not decoration.** Red, amber, green, and blue mean failing, needs action, ready, and awaiting review. Nothing else is coloured. White is the neutral for text and for usage under 75%.
3. **One glance, one answer.** Every state (collapsed, peek, expanded) answers a single question and stops. Density is welcome; decoration is not.
4. **Match the hardware.** True black backgrounds, corner radii that continue the notch curve, and expansion that grows from the notch rather than appearing beside it. The notch is physically black, so the app is too.
5. **Act from where you are.** Click a row to open the PR, right-click for the rest. No navigation, no modals inside the notch; the Settings window is the only separate surface.

## Accessibility & Inclusion

No requirements beyond macOS defaults. Personal tool with a single known user; fixed 11 to 13pt type and colour-carried status are accepted trade-offs for notch density.
