---
name: Notchivity
description: A macOS notch instrument for coding-subscription usage and pull request status
colors:
  panel-black: "#000000"
  reading-white: "#FFFFFF"
  dimmed-grey: "#787878"
  standby-grey: "#404040"
  stroke-grey: "#333333"
  track-grey: "#212121"
  rule-grey: "#171717"
  hover-grey: "#141414"
  fault-red: "#F7524A"
  caution-amber: "#D19921"
  clear-green: "#40BA4F"
  standby-blue: "#59A6FF"
  notice-violet: "#BD8CFF"
typography:
  title:
    fontFamily: "SF Pro (system)"
    fontSize: "13px"
    fontWeight: 600
  body-strong:
    fontFamily: "SF Pro (system)"
    fontSize: "12.5px"
    fontWeight: 600
  body:
    fontFamily: "SF Pro (system)"
    fontSize: "12px"
    fontWeight: 500
  detail:
    fontFamily: "SF Pro (system)"
    fontSize: "11px"
    fontWeight: 400
  label:
    fontFamily: "SF Pro (system)"
    fontSize: "10.5px"
    fontWeight: 600
    letterSpacing: "0.4px"
rounded:
  notch-collapsed: "12px"
  notch-expanded: "22px"
  control: "5px"
  control-sm: "4px"
spacing:
  hairline: "1px"
  xs: "4px"
  sm: "8px"
  md: "12px"
  gutter: "18px"
  gap: "22px"
components:
  pr-row:
    backgroundColor: "{colors.panel-black}"
    textColor: "{colors.reading-white}"
    typography: "{typography.body-strong}"
    height: "43px"
    padding: "5px 0"
  pr-row-hover:
    backgroundColor: "{colors.hover-grey}"
  usage-bar-track:
    backgroundColor: "{colors.track-grey}"
    rounded: "9999px"
    height: "5px"
  usage-bar-collapsed:
    backgroundColor: "{colors.track-grey}"
    rounded: "9999px"
    height: "2px"
  link:
    textColor: "{colors.standby-blue}"
    typography: "{typography.detail}"
  section-title:
    textColor: "{colors.dimmed-grey}"
    typography: "{typography.label}"
  segmented-option:
    backgroundColor: "{colors.panel-black}"
    textColor: "{colors.dimmed-grey}"
    typography: "{typography.detail}"
    rounded: "{rounded.control}"
    padding: "3px 9px"
  segmented-option-selected:
    backgroundColor: "{colors.reading-white}"
    textColor: "{colors.panel-black}"
  chip:
    backgroundColor: "{colors.panel-black}"
    textColor: "{colors.reading-white}"
    typography: "{typography.detail}"
    rounded: "{rounded.control}"
    padding: "4px 9px"
---

# Design System: Notchivity

## 1. Overview

**Creative North Star: "The Cockpit Gauge"**

Notchivity is an instrument panel, not an app. Black is the panel, white is the reading, colour is the alarm lamp. At rest the collapsed shape is indistinguishable from the hardware notch: no glow, no text, no chrome. On hover it grows downward as a continuation of the bezel, curved at the same radius family, and lays out two dense columns of readings. When something changes it drops a single line for three seconds and withdraws.

The system rejects everything the notch-app category reaches for by reflex: no media player, no Dynamic Island physics, no glassy or blurred surfaces, no cards, no hero numbers, no gradients, no pill badges. Depth is conveyed by hairlines and by the panel growing out of the hardware, never by shadows or blur. Density is a virtue; a 43px row carries a title, a ref, two status flags, and an age.

**Key Characteristics:**
- True black (#000000) everywhere. This is the one project where the "never #000" law is overruled: the surface must match a physically black bezel.
- Colour appears only as status. Four hues map to four PR categories; two of them double as usage warnings.
- One system font at five sizes between 10.5 and 13px. Weight and colour carry hierarchy, not size jumps.
- Hairline rules (1px, #171717) separate rows and sections. No boxes, no borders around groups.
- Two motions only: the panel shape eases out over 220ms, content fades in over 100ms after a 100ms delay, landing as the shape finishes. Content vanishes instantly on collapse.

## 2. Colors: The Instrument Palette

Black panel, white readings, one grey ramp for structure, four alarm lamps and one notice lamp.

### Primary
- **Reading White** (#FFFFFF): All primary text, the usage bar fill under 75%, the selected state of a segmented control. White is the neutral reading, not an accent.

### Neutral
- **Panel Black** (#000000): Every background: notch shape, Settings window, chips. Never tinted.
- **Dimmed Grey** (#787878): Secondary text: section titles, sub-labels, refs, ages, unselected tabs, header meta. The only grey used for type.
- **Standby Grey** (#404040): Status dot for a setup check that is switched off.
- **Stroke Grey** (#333333): 1px outlines on segmented controls, fields and chips in Settings. Brightens to #808080 while a chip is being dragged. Also the fill of a selected PR row that has keyboard or hover focus.
- **Track Grey** (#212121): Empty portion of usage bars and the Settings tab-bar rule.
- **Rule Grey** (#171717): Hairline separators between rows and above link lines.
- **Hover Grey** (#141414): Row background on hover. The only hover treatment in the notch.

### Tertiary: The Lamps
- **Fault Red** (#F7524A): Failing CI, conflicts, usage at 90% or above, a failing required setup check. In the checklist, passing and switched-off rows dim their titles so only rows that need a look stay white. With Caution Amber, the only colours that may appear in the collapsed tab as counts.
- **Caution Amber** (#D19921): Needs action (changes requested, review comments), usage 75 to 89%, the "N to set up" label, optional checks needing attention in the setup checklist. A failed fetch is not amber in the dashboard: it is counted in the header in white. The one exception is the collapsed tab, where a PR fetch error is a hollow amber ring, distinct from the filled lamps.
- **Clear Green** (#40BA4F): Ready to merge, approved. Also the 5px dot meaning "nothing open, all fetched". A passing CI is the absence of an alarm and shows nothing.
- **Standby Blue** (#59A6FF): Awaiting review, as the dot and as the "awaiting review" flag. Doubles as the link colour ("view all", "close", "setup", "settings", fix buttons).
- **Notice Violet** (#BD8CFF): Informational events only (usage reset, merged, the one-time "ready" peek). Never used for PR state.

### Named Rules
**The Alarm Lamp Rule.** A colour on screen must mean one of: failing, needs action, ready, awaiting review, or notice. Any colour used for decoration, branding, or emphasis is forbidden.

**The White Reading Rule.** Usage under 75% is white, not green. Green means a PR is ready; it never means "you are fine".

**The Bezel Rule.** Backgrounds are #000000 with no tint, no gradient, no blur. If the background is distinguishable from the hardware notch, it is wrong.

## 3. Typography

**Display Font:** none. There is no display tier.
**Body Font:** SF Pro via the system font, with monospaced digits wherever a number can change.
**Label/Mono Font:** SF Pro semibold, uppercased and tracked for section titles.

**Character:** Small, even, and quiet. The whole scale spans 2.5 points. Hierarchy comes from weight (400 vs 500 vs 600) and from white versus Dimmed Grey, not from size.

### Hierarchy
- **Title** (600, 13px): Peek headline only. The largest text the app ever shows. (The CLI proxy sheet heading uses Body Strong.)
- **Body Strong** (600, 12.5px): PR titles, failing setup check titles, Settings body. One line, tail-truncated.
- **Body** (500, 12px): Usage row labels and percentages (monospaced digits), empty-state lines, unselected Settings tabs.
- **Detail** (400, 11px): Refs, flags, ages, sub-labels, header meta, links, chips, segmented options.
- **Label** (600, 10.5px, 0.4px tracking, UPPERCASE): Section titles ("USAGE", "OPEN PRS") in Dimmed Grey.

### Named Rules
**The Steady Digit Rule.** Every percentage, count, and countdown uses monospaced digits so the layout does not shift as values tick.

**The Lowercase Rule.** Interface copy is lowercase and terse ("nothing open", "3 to set up", "view all 9"). Only PR titles, section labels, and macOS-standard Settings labels are capitalised.

## 4. Elevation

Flat. There are no shadows anywhere. Depth comes from three things: the black panel growing out of the notch, 1px Rule Grey hairlines that separate rows, and the Hover Grey row tint. The Settings window is a standard macOS window with a black background and no custom shadow.

### Named Rules
**The No-Shadow Rule.** Shadows, blur, vibrancy, and glass are forbidden. If a surface needs a shadow to be legible against black, the layout is wrong.

**The Hairline Rule.** Groups are separated by a 1px Rule Grey line (at the top of each notch row, beneath each Settings row), never by boxes, cards, or background changes.

## 5. Components

### Notch Shape
The signature component. A black `UnevenRoundedRectangle` with only the bottom corners rounded: 12px collapsed, 22px expanded or peeking. Width is the hardware notch when collapsed, 440px for a peek, 720px expanded. Shape animates with ease-out over 220ms; content fades in over 100ms after a 100ms delay and is removed instantly on the way back.

### Collapsed Tab (screens without a notch)
- **Content:** the chosen account’s first available window percentage in Detail size, a 2px usage bar, and either counts (Fault Red failing, Caution Amber needs action) or up to eight 5px category dots. In either mode a fetched, empty list shows one 5px Clear Green dot.
- **Errors:** a PR fetch error replaces the indicator with a 7px hollow Caution Amber ring (1.5px stroke), so a fault never reads as a needs-action lamp; a usage reading that failed to refresh or is over 15 minutes old shows its percentage and underline in Dimmed Grey (red stays red), and "?" once its window has reset.
- **Rule:** on a hardware notch it renders nothing. Only "N to set up" in Caution Amber may override that silence.

### PR Row
- **Shape:** 43px tall, full width, 5px vertical padding, 1px Rule Grey hairline on top.
- **Content:** 8px category dot, Body Strong title over the Detail ref (middle-truncated, so a long repo keeps its "#number"), right-aligned Detail flags joined by " · " in Dimmed Grey, optional age. At most two flags sit on the right and the rest are counted in Dimmed Grey ("+3"); the tooltip lists every flag. An amber dot always has an amber flag saying why ("2 unresolved", "not approved", or "draft" on an approved draft). A blue dot leads with a Standby Blue "awaiting review" unless the PR is a draft or already approved (then blue only means CI is running, which its flag says).
- **Stale list:** when a refresh fails with PRs on screen, the section title row adds "· as of 14m ago · retry" in Detail Dimmed Grey with the fix as a link ("copy gh auth login" when signed out). An empty list reads "GitHub unreachable · retry".
- **First hovers:** a Detail Dimmed Grey line under the list names the ways in a hover never shows ("⌘-click select · right-click for more · ⌃⌥N for the keyboard"). Each part retires the first time that gesture is used; the line stops after 20 hover opens regardless. Keyboard opens never show it.
- **"view all":** up to 12 rows, or 60% of the panel's screen if less, then the list scrolls with half a row showing.
- **Hover and keyboard focus:** one highlight shared by the pointer and the arrow keys: background to Hover Grey, reaching 8px past the text column so text never touches the fill edge. Click or Return opens the PR; right-click gives "Open on GitHub", "Copy URL" and, with Slack set up, "Ask for Review in Slack" and "Select for One Slack Ask" (context menus use macOS title case). Focus from the arrow keys adds a 2px white bar on the fill's leading edge, because Hover Grey alone is about 1.2:1 on black. It is the one side edge in the system: white, never a lamp colour, and only while the keyboard drives. The system tooltip carries the full title and the gestures ("click to open · cmd-click to select · right-click for more").
- **Selected:** background to Track Grey (Stroke Grey when it also has focus) and a 1.5px white ring around the dot, so selection never rests on fill alone. Cmd-click or Space toggles, only with Slack set up. A Link line under the list reads "ask for review in Slack · 3 selected · clear". The Slack result shows above it under one shared hairline: success in Dimmed Grey for a few seconds, failure in white with its fix link until a retry or "clear". Failed PRs stay selected, so the line below is the retry.

### Usage Row

One block per account, sorted most urgent first: lead window at 90% or more, then 75% or more, then failed readings, then the rest in discovery order. The collapsed tab and Settings keep discovery order.

- **Name line:** Body name, full column width, tail-truncated only if it must; the lead percentage right-aligned with monospaced digits, toned like the lead bar, never truncated. At 75% or more the lead's reset joins the name line in white Body regular ("Work · resets 47m"), since it is then the answer, but only if both fit whole; otherwise the reset stays complete on the sub-line. An unknown percentage reads as a dim "?". Two accounts with one name add "· 1 of 2" in Detail Dimmed Grey.
- **Bars:** full column width, 3px under the name. The lead window gets the 5px capsule; each other window is a 2px line 3px beneath it, Dimmed Grey until 75%, then Caution Amber or Fault Red. The session leads unless another window has reached 75% and is fuller; the collapsed tab uses the same rule.
- **Bar fill:** Track Grey behind, lead fill white under 75%, Caution Amber to 89%, Fault Red from 90%. Minimum fill width equals bar height.
- **Sub-line:** Detail, Dimmed Grey, flush with the name: the lead's reset, then the other windows' readings ("resets 2h 14m · week 61%"). A non-session lead names itself ("month · resets 7 Dec"). A secondary reading at 75% or more takes its lamp colour in the line.
- **Faults and age:** one more Dimmed Grey line ("as of 3h ago"); a failed fetch carries its fix inline as a link ("token expired · open Claude Code"); the bars and percentage grey (red stays red) and read "?" once the window has reset. An account with no reading at all has no bars, so an empty track never reads as 0%: just the name, "?" and the reason. The header still counts faults for the glance.
- **Rhythm:** 6px above and below each block, so the first name sits level with the first PR title.
- **Tooltip and VoiceOver:** every window with "% used" and its reset, and the provider after a renamed account ("Work (Claude)").

### Header
Notch-height row in Detail, Dimmed Grey. The left slot, the first one seen, carries state, not identity: the worst thing right now in its lamp colour (a failing PR "CI failed · web#318", else usage at 90% or more "session at 96% · Claude", else a PR needing action), and nothing when calm. The GitHub login is that slot's tooltip. On the right: freshness ("updated Ns ago", or "usage updated…" while PRs have never loaded), replaced for 2 seconds by a keyboard confirmation ("opened web#318"); then the faults in white with a "fix" link, naming a lone fault ("token expired · fix") and counting several ("2 issues · fix"), or a plain "setup" link; then "settings". A fault takes the freshness text's place rather than adding to it. The header shares its band with the hardware notch, so each side is capped at its half of the panel minus the notch width; the fault text truncates before the links. Both "fix" and "setup" open the setup checklist over the dashboard. Each link has a 24px-tall hit area around its 11px text. The notch has no icons: every action is a word.

### Keyboard Session
⌃⌥N opens the panel with the keyboard. The focused row carries the white leading edge (see PR Row). Under the list, one Detail Dimmed Grey line lists the keys that do something right now ("↑↓ ↩ open · space select · a ask · r refresh · s setup · v view all · ⌘, settings · esc"): Slack keys only with Slack set up, "c clear" only with a selection, "v" only when the list overflows. The pointer never sees it. "a" waits 3 seconds on a Link line ("asking for review of 2 PRs · undo") before posting; Esc or "undo" cancels, and Esc closes the panel only when nothing is pending. "m" opens the highlighted PR's menu (the same actions as its right-click), "f" applies the first fault's fix. VoiceOver hears peeks, a pending ask, its result, and faults appearing or clearing while the panel is open.

### Section Title
Label style in Dimmed Grey with 6px below. Optional count beside it, also Label style in Dimmed Grey, shown only when it is a real non-zero reading.

### Link
Standby Blue Detail text with 8px top padding and a Rule Grey hairline above. Used for "view all", "show less" and the selection line. The same blue without the hairline marks inline links ("close", setup fixes). Never underlined, never a button chrome.

### Peek
440px wide, 14px status dot in the event tone, Title headline over Detail Dimmed Grey line. Sits below the notch height plus 6px. Click opens the event URL and dismisses the peek. Headlines lead with what happened, then the subject ("CI failed · web#318", "session at 88% · Work"), so truncation cuts the subject, never the news. Three or more queued events become one peek: the most urgent headline plus "· 3 more", and the rest counted by kind as the detail ("approved · new comments · merged"). The first time setup ever passes, a single Notice Violet peek says "ready · hover the notch or ⌃⌥N".

### Setup Checklist
Same width and 43px rows as the dashboard. Required checks that need a look first, failing rows on top. Passing checks, required and optional, fold into one dim "N passed" row with a "show" link. Optional checks that need a look follow under one "OPTIONAL" Section Title, with the "optional ·" prefix dropped from their details and their fix links in Dimmed Grey until hovered, so the required fixes lead the eye. Passing and switched-off titles dim; only rows that need a look stay white. The header reads "N to set up" in Caution Amber with "skip for now" (or "close" once nothing required fails). From the keyboard, ↑↓ moves the same white-edged highlight as PR rows through the rows, Return applies the row's fix and Esc goes back; "↑↓ move · ↩ fix · esc back" shows once the arrows are in use.

### Settings Controls
- **Tabs:** Body text, white when selected, Dimmed Grey otherwise, 6px vertical padding, Track Grey rule beneath the bar.
- **Rows:** label left, control right, at least 43px tall like a PR row (8px vertical padding), Rule Grey hairline beneath. Setup checklist rows share the same 43px minimum.
- **Segmented control:** 5px radius, Stroke Grey 1px outline, options 3px by 9px padding; selected option is white on black.
- **Fields and chips:** 5px radius, Stroke Grey outline, 4px by 9px padding. Text fields are a chip holding right-aligned Body text; the CLI proxy sheet's full-width fields use 8px padding. Dragged chip outline brightens to #808080.
- **Menu picker:** a chip holding the current value and a Dimmed Grey up-down chevron. Used where the options come from data (which account), so a segmented control would overflow.
- **Links and status:** lowercase like the notch ("configure…", "show on next hover", "quit"). Switches, pickers and name fields write through; the Slack fields save on Return, tab switch, window close or quit, so a half-typed channel never switches Slack actions on. There is no Save. The CLI proxy sheet is the exception: it validates and stores a Keychain token, so it keeps native Cancel and Save buttons.
- **Disabled rows:** the title dims to Dimmed Grey with the control.
- **Threshold tokens:** Detail percentage with a bold 8px xmark in Dimmed Grey; add button is a 18px square with 4px radius.

## 6. Do's and Don'ts

### Do:
- **Do** use #000000 for every background. The panel must match the hardware notch.
- **Do** carry status with the five lamps only: Fault Red, Caution Amber, Clear Green, Standby Blue, Notice Violet.
- **Do** separate rows with a 1px #171717 hairline and nothing else.
- **Do** keep type between 10.5 and 13px, hierarchy through weight and Dimmed Grey.
- **Do** use monospaced digits for anything that ticks.
- **Do** write copy in lowercase, terse and factual: "nothing open", "resets 2h 10m".
- **Do** animate only the shape (220ms ease-out) and a delayed content fade (100ms after 100ms). Remove content instantly on collapse.
- **Do** put actions where the data is: click a row, right-click for more. Settings is the only separate surface.

### Don't:
- **Don't** build anything from boringNotch or Dynamic Island clones: no media player, no bouncy island physics, no glassy or blurred chrome.
- **Don't** borrow from dashboard SaaS: no cards, no hero metrics, no gradient accents, no pill badges, no decorative icons.
- **Don't** use colour for decoration, branding, or emphasis. If it is not a status, it is white or grey.
- **Don't** colour usage green. Under 75% is white.
- **Don't** add shadows, blur, vibrancy, tinted blacks, or gradients.
- **Don't** show anything in the collapsed hardware notch except "N to set up".
- **Don't** repeat an event, and never peek on the first fetch after launch.
- **Don't** use exclamation marks, encouragement, or chatter in copy. No em dashes.
- **Don't** open modals inside the notch. Inline states (loading…, nothing open, error line) only.
