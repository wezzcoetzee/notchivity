---
name: Notchivity
description: A macOS notch instrument for Claude usage and pull request status
colors:
  panel-black: "#000000"
  reading-white: "#FFFFFF"
  dimmed-grey: "#787878"
  standby-grey: "#404040"
  stroke-grey: "#333333"
  track-grey: "#212121"
  rule-grey: "#171717"
  hover-grey: "#0F0F0F"
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

The system rejects everything the notch-app category reaches for by reflex: no media player, no Dynamic Island physics, no glassy or blurred surfaces, no cards, no hero numbers, no gradients, no pill badges. Depth is conveyed by hairlines and by the panel growing out of the hardware, never by shadows or blur. Density is a virtue; a 43px row carries a title, a ref, three status flags, and an age.

**Key Characteristics:**
- True black (#000000) everywhere. This is the one project where the "never #000" law is overruled: the surface must match a physically black bezel.
- Colour appears only as status. Four hues map to four PR categories; two of them double as usage warnings.
- One system font at five sizes between 10.5 and 13px. Weight and colour carry hierarchy, not size jumps.
- Hairline rules (1px, #171717) separate rows and sections. No boxes, no borders around groups.
- Two motions only: the panel shape eases out over 220ms, content fades in over 120ms after a 200ms delay. Content vanishes instantly on collapse.

## 2. Colors: The Instrument Palette

Black panel, white readings, one grey ramp for structure, four alarm lamps and one notice lamp.

### Primary
- **Reading White** (#FFFFFF): All primary text, the usage bar fill under 75%, the selected state of a segmented control. White is the neutral reading, not an accent.

### Neutral
- **Panel Black** (#000000): Every background: notch shape, Settings window, chips. Never tinted.
- **Dimmed Grey** (#787878): Secondary text: section titles, sub-labels, refs, ages, unselected tabs, header meta. The only grey used for type.
- **Standby Grey** (#404040): Status dot for a setup check that is switched off.
- **Stroke Grey** (#333333): 1px outlines on segmented controls, steppers and chips in Settings. Brightens to #808080 while a chip is being dragged.
- **Track Grey** (#212121): Empty portion of usage bars and the Settings tab-bar rule.
- **Rule Grey** (#171717): Hairline separators between rows and above link lines.
- **Hover Grey** (#0F0F0F): Row background on hover. The only hover treatment in the notch.

### Tertiary: The Lamps
- **Fault Red** (#F7524A): Failing CI, conflicts, usage at 90% or above. The only colour that may appear in the collapsed tab as a count.
- **Caution Amber** (#D19921): Needs action (changes requested, review comments), usage 75 to 89%, setup items outstanding, non-fatal fetch errors.
- **Clear Green** (#40BA4F): Ready to merge, approved. Also the 5px dot meaning "nothing open, all fetched".
- **Standby Blue** (#59A6FF): Awaiting review. Doubles as the link colour ("view all", "Done", fix buttons).
- **Notice Violet** (#BD8CFF): Informational events only (limit reset, merged). Never used for PR state.

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
- **Title** (600, 13px): Peek headline only. The largest text the app ever shows.
- **Body Strong** (600, 12.5px): PR titles, failing setup check titles, Settings body. One line, tail-truncated.
- **Body** (500, 12px): Usage row labels and percentages (monospaced digits), empty-state lines, unselected Settings tabs.
- **Detail** (400, 11px): Refs, flags, ages, sub-labels, header meta, links, chips, segmented options.
- **Label** (600, 10.5px, 0.4px tracking, UPPERCASE): Section titles ("CLAUDE USAGE", "OPEN PRS") in Dimmed Grey.

### Named Rules
**The Steady Digit Rule.** Every percentage, count, and countdown uses monospaced digits so the layout does not shift as values tick.

**The Lowercase Rule.** Interface copy is lowercase and terse ("nothing open", "3 to set up", "view all 9"). Only PR titles, section labels, and macOS-standard Settings labels are capitalised.

## 4. Elevation

Flat. There are no shadows anywhere. Depth comes from three things: the black panel growing out of the notch, 1px Rule Grey hairlines that separate rows, and the Hover Grey row tint. The Settings window is a standard macOS window with a black background and no custom shadow.

### Named Rules
**The No-Shadow Rule.** Shadows, blur, vibrancy, and glass are forbidden. If a surface needs a shadow to be legible against black, the layout is wrong.

**The Hairline Rule.** Groups are separated by a 1px Rule Grey line at the top of each row, never by boxes, cards, or background changes.

## 5. Components

### Notch Shape
The signature component. A black `UnevenRoundedRectangle` with only the bottom corners rounded: 12px collapsed, 22px expanded or peeking. Width is the hardware notch when collapsed, 440px for a peek, 720px expanded. Shape animates with ease-out over 220ms; content fades in over 120ms after a 200ms delay and is removed instantly on the way back.

### Collapsed Tab (external displays only)
- **Content:** session percentage in Detail size, a 2px usage bar, and either counts (Fault Red failing, Caution Amber needs action) or up to eight 5px category dots.
- **Rule:** on a hardware notch it renders nothing. Only "N to set up" in Caution Amber may override that silence.

### PR Row
- **Shape:** 43px tall, full width, 5px vertical padding, 1px Rule Grey hairline on top.
- **Content:** 8px category dot, Body Strong title over Detail ref, right-aligned Detail flags joined by " · " in Dimmed Grey, optional age.
- **Hover:** background to Hover Grey. Click opens the PR; right-click gives Open, Copy URL, Select, Ask for review in Slack.
- **Selected:** background to Track Grey (Cmd-click toggles). A Link line under the list reads "ask for review in Slack · 3 selected · clear".

### Usage Row
- **Layout:** 52px label column, capsule bar, 40px right-aligned percentage with monospaced digits.
- **Bar:** 5px capsule, Track Grey behind, fill white under 75%, Caution Amber to 89%, Fault Red from 90%. Minimum fill width equals bar height.
- **Sub-line:** Detail size in Dimmed Grey, indented 60px ("session · 2h 10m", "week · resets Thu").

### Section Title
Label style in Dimmed Grey with 6px below. Optional count beside it in Detail Dimmed Grey.

### Link
Standby Blue Detail text with 8px top padding and a Rule Grey hairline above. Used for "view all", "show less", "Done", and setup fix actions. Never underlined, never a button chrome.

### Peek
440px wide, 14px status dot in the event tone, Title headline over Detail Dimmed Grey line. Sits below the notch height plus 6px. Click opens the event URL.

### Settings Controls
- **Tabs:** Body text, white when selected, Dimmed Grey otherwise, 6px vertical padding, Track Grey rule beneath the bar.
- **Rows:** label left, control right, 9px vertical padding, Rule Grey hairline beneath.
- **Segmented control:** 5px radius, Stroke Grey 1px outline, options 3px by 9px padding; selected option is white on black.
- **Stepper and chips:** 5px radius, Stroke Grey outline, 4px by 9px padding. Dragged chip outline brightens to #808080.
- **Threshold tokens:** Detail percentage with a bold 8px xmark in Dimmed Grey; add button is a 18px square with 4px radius.

## 6. Do's and Don'ts

### Do:
- **Do** use #000000 for every background. The panel must match the hardware notch.
- **Do** carry status with the five lamps only: Fault Red, Caution Amber, Clear Green, Standby Blue, Notice Violet.
- **Do** separate rows with a 1px #171717 hairline and nothing else.
- **Do** keep type between 10.5 and 13px, hierarchy through weight and Dimmed Grey.
- **Do** use monospaced digits for anything that ticks.
- **Do** write copy in lowercase, terse and factual: "nothing open", "resets 2h 10m".
- **Do** animate only the shape (220ms ease-out) and a delayed content fade (120ms). Remove content instantly on collapse.
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
