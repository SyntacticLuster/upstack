# UPSTACK UI/UX SPECIFICATION v1.0

## Overview

This document specifies the complete user interface design for UPSTACK's in-game systems. The UI is a **pure consumer** of simulation outputs—it displays state and dispatches player commands through explicit hooks but contains no game logic.

**Design tone**: Bureaucratic, clinical, oppressive. The interface should feel like a resource management terminal in a bunker—functional, informative, and subtly grim. No neon, no playful gradients, no arcade aesthetics.

---

## 1) Layout & Information Architecture

### 1.1 Full-Screen Wireframe

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░ TOP BAR (HUD) ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ [Day/Phase/Hour] [Time Controls: ⏸ ½× 1× 2× 4×]     [Alerts: 0] [Collapse] │
├───────────────────────────────────┬─────────────────────────────────────────┤
│                                   │                                         │
│     LEFT RAIL                     │          MAIN CONTENT AREA              │
│     (Resources + Status)          │                                         │
│                                   │     ┌───────────────────────────────┐   │
│   ┌───────────────────────────┐   │     │     OPERATIONS CONSOLE        │   │
│   │ Food       ▼  47          │   │     │     (Scrollable)              │   │
│   │ Water      •  62          │   │     │                               │   │
│   │ Materials  ▲  198         │   │     │ ▾ Pressure Levers             │   │
│   └───────────────────────────┘   │     │   [Ration Hardening]          │   │
│                                   │     │   [Labor Overdrive]           │   │
│   ┌───────────────────────────┐   │     │   [Information Throttling]    │   │
│   │ Morale: 58  Threat: 12    │   │     │                               │   │
│   │ Population: 6             │   │     │ ▾ Expeditions                 │   │
│   └───────────────────────────┘   │     │   [Expedition Compression]    │   │
│                                   │     │   [Module Abandonment]        │   │
│   [Collapse Rail ◀]              │     │                               │   │
│                                   │     │ ▾ Emergency Conversions       │   │
│                                   │     │   [Emergency Conversion]      │   │
│                                   │     └───────────────────────────────┘   │
│                                   │                                         │
├───────────────────────────────────┴─────────────────────────────────────────┤
│ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ LEDGER ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
│ [All] [Sim] [Events] [Debug]                                    [Collapse] │
│ ────────────────────────────────────────────────────────────────────────────│
│ Day 4 · Hour 08  EVENT   policy active, scar accrues                        │
│ Day 4 · Hour 06  SIM     resources updated: food -3, morale -1              │
│ Day 4 · Hour 02  DEBUG   expedition_heat = 4                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Visibility Rules

| Region | Always Visible | Collapsible | Default State |
|--------|----------------|-------------|---------------|
| Top Bar (HUD) | Yes | No | Expanded |
| Left Rail | No | Yes | Expanded |
| Operations Console | Yes (header) | Yes (section bodies) | Sections expanded |
| Ledger | No | Yes | Expanded |

**Collapse behavior**:
- Left Rail collapses to a 32px vertical strip with icons only (hover shows tooltip)
- Ledger collapses to a 40px footer bar showing only filter tabs and last event preview
- Operations sections collapse individually (accordion pattern)

### 1.3 Panel Coexistence Strategy

1. **Vertical stacking with flex**: Operations Console and Ledger share vertical space in the main content area
2. **Proportional split**: Default 65% Operations / 35% Ledger; user-adjustable drag handle
3. **Minimum heights**: Operations 200px, Ledger 120px
4. **Overflow**: Operations scrolls internally; Ledger scrolls internally

### 1.4 Responsive Layout Rules

| Resolution | Left Rail | Operations | Ledger | Notes |
|------------|-----------|------------|--------|-------|
| **800×600** | Collapsed by default (icon strip) | Full width, 55% height | 45% height | HUD time controls stack vertically |
| **1152×648** | 180px fixed | Remaining width | 35% height | Baseline minimum comfortable size |
| **1600×900** | 220px fixed | Remaining width | 35% height | Standard desktop |
| **1920×1080** | 260px fixed | Remaining width, max 900px | 35% height | Content max-width prevents over-stretch |

**Breakpoint behaviors**:
- Below 800px width: Force single-column mode—Operations and Ledger become tabs, not split
- At 1152×648+: Three-column layout (Rail | Operations | Right margin if space)
- Operations Console sections use `fill_expand` but lever cards have `min_size.y = 140px`

---

## 2) Visual Design System

### 2.1 Color Palette

#### Semantic Status Colors

| Token | Hex | RGB | Usage |
|-------|-----|-----|-------|
| `neutral` | `#707f8c` | `112, 127, 140` | Default state, inactive, informational |
| `good` | `#4a8ed9` | `74, 142, 217` | Positive change, resource gain, stable |
| `warning` | `#eba340` | `235, 163, 64` | Caution, scarcity imminent, cost |
| `danger` | `#c73838` | `199, 56, 56` | Critical, active harm, mortality risk |
| `authority` | `#458ed9` | `69, 142, 217` | Expedition/external actions, uncertainty |
| `desperation` | `#a6bd34` | `166, 189, 52` | Emergency measures, moral debt, burns |
| `locked` | `#3d4654` | `61, 70, 84` | Unavailable, burned out, rejected |
| `debug` | `#8a64a0` | `138, 100, 160` | Development-only, hidden in release |

#### Background & Surface Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `bg-primary` | `#0c0e12` | Root background |
| `bg-panel` | `#14181e` | Panel backgrounds |
| `bg-elevated` | `#1c2128` | Cards, lever containers |
| `bg-input` | `#252b34` | Input fields, dropdowns |
| `border-subtle` | `#2a323d` | Separators, card borders |
| `border-active` | `#3a4550` | Focused input borders |

#### Text Colors

| Token | Hex | Usage |
|-------|-----|-------|
| `text-primary` | `#e4e8ec` | Primary content, labels |
| `text-secondary` | `#8c9aab` | Hints, metadata, timestamps |
| `text-muted` | `#5a6878` | Disabled, placeholder |

### 2.2 Typography Rules

**Font family**: Roboto (already in assets) or system monospace for numbers.

| Element | Size | Weight | Line Height | Tracking |
|---------|------|--------|-------------|----------|
| Panel Title | 16px | 600 | 1.25 | +0.02em |
| Section Header | 14px | 600 | 1.3 | +0.04em (uppercase) |
| Lever Title | 13px | 600 | 1.3 | 0 |
| Lever Intent | 11px | 400 | 1.4 | +0.01em |
| Label | 12px | 400 | 1.3 | 0 |
| Input Value | 13px | 500 | 1.0 | 0 (monospace preferred) |
| Tooltip | 11px | 400 | 1.4 | 0 |
| Ledger Timestamp | 11px | 400 | 1.2 | +0.02em |
| Ledger Body | 12px | 400 | 1.4 | 0 |
| HUD Value | 18px | 600 | 1.0 | -0.01em |
| HUD Label | 11px | 400 | 1.2 | +0.04em (uppercase) |

### 2.3 Spacing Rules

| Token | Value | Usage |
|-------|-------|-------|
| `space-xs` | 4px | Inline icon margins, tight groups |
| `space-sm` | 8px | Input padding, row gaps |
| `space-md` | 12px | Card padding, section gaps |
| `space-lg` | 16px | Panel padding, major section gaps |
| `space-xl` | 24px | Top-level region gaps |

**Density guidelines**:
- Lever cards: 12px internal padding, 8px gap between input rows
- Input fields: 6px vertical padding, 10px horizontal padding
- Row height for ledger entries: 28px minimum
- Button height: 32px standard, 28px compact

### 2.4 Tone Enforcement

**DO**:
- Use ALL CAPS for section headers, status labels, result states
- Truncate with ellipsis (...) rather than wrap mid-word
- Keep color saturation low (muted, institutional)
- Show numbers with fixed decimal places where precision matters

**DO NOT**:
- Use rounded corners larger than 4px
- Animate anything unless it communicates state change
- Use icons without text labels (except in collapsed rail)
- Use gradients, glows, or drop shadows

---

## 3) Operations Console Specification

### 3.1 Panel Structure

```
┌──────────────────────────────────────────────────────────────────┐
│ OPERATIONS CONSOLE                                         [▾] │
├──────────────────────────────────────────────────────────────────┤
│ ▾ PRESSURE LEVERS                                               │
│   ├── [Ration Hardening]                                        │
│   ├── [Labor Overdrive]                                         │
│   └── [Information Throttling]                                  │
│                                                                  │
│ ▾ EXPEDITIONS                                                    │
│   ├── [Expedition Compression]                                  │
│   └── [Module Abandonment]                                       │
│                                                                  │
│ ▾ EMERGENCY CONVERSIONS                                          │
│   └── [Emergency Conversion]                                     │
└──────────────────────────────────────────────────────────────────┘
```

Each section has a toggle button (`▾`/`▸`) that collapses/expands its content.

### 3.2 Lever Card Template

Every lever uses this consistent layout:

```
┌─────────────────────────────────────────────────────────────────┐
│ [COLOR BAR 4px]                                                 │
├─────────────────────────────────────────────────────────────────┤
│ LEVER TITLE                                     [Status Chip]   │
│ One-line intent description in secondary text                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│ [Input Field 1]  [Label]      [Tooltip Icon ⓘ]                  │
│ [Input Field 2]  [Label]      [Tooltip Icon ⓘ]                  │
│ ...                                                             │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│ [APPLY BUTTON]                         [Result: APPLIED/REJECTED]│
│                                                                  │
│ ⚠ Warning text if applicable (e.g., "OUTCOMES UNCERTAIN")       │
└─────────────────────────────────────────────────────────────────┘
```

**Status chip states**:
- `INACTIVE` → `neutral` background
- `ACTIVE` → `warning` background (shows remaining hours)
- `DEBT ACCRUING` → `desperation` background
- `BURNED OUT` → `locked` background (conversion only)

### 3.3 Lever Specifications

---

#### 3.3.1 RATION HARDENING

**Purpose (one-line)**: Reduce food consumption at the cost of crew morale and recovery capacity.

**Category**: Pressure · **Color**: `warning` → `danger` (intensity-based lerp)

**Inputs**:

| Field | Label | Type | Range | Tooltip |
|-------|-------|------|-------|---------|
| Mode | Severity | OptionButton | `soft`, `hard` | "SOFT: 10% consumption reduction, minor morale hit. HARD: 25% reduction, significant morale and recovery penalties." |
| Duration | Duration (hours) | SpinBox | 1–8760 | "How many hours this policy remains active. 24 hours = 1 day." |

**Output/Feedback**:

| Result Label | Condition |
|--------------|-----------|
| `ACTIVE (Xh left)` | Policy accepted, X = remaining hours |
| `REJECTED: invalid mode` | Mode not `soft` or `hard` |
| `REJECTED: invalid duration` | Duration ≤ 0 |

**Duration Display**: Show remaining time as `Xh` (hours). Example: `ACTIVE (72h left)`.

**Visual Cues**:
- `soft` mode: title color = `warning`
- `hard` mode: title color = `danger`
- While active: pulsing subtle border animation (0.5s cycle)

---

#### 3.3.2 LABOR OVERDRIVE

**Purpose (one-line)**: Boost workforce output at the cost of fatigue, morale, and long-term efficiency.

**Category**: Pressure · **Color**: `warning` → `danger` (intensity-based lerp)

**Inputs**:

| Field | Label | Type | Range | Tooltip |
|-------|-------|------|-------|---------|
| Intensity | Intensity | SpinBox | 1–5 | "Output multiplier per level: +15%. Higher intensity accelerates labor scar accumulation." |
| Duration | Duration (hours) | SpinBox | 1–8760 | "How many hours the overdrive policy remains active." |

**Output/Feedback**:

| Result Label | Condition |
|--------------|-----------|
| `ACTIVE (Xh left)` | Accepted, X = remaining hours |
| `REJECTED: invalid intensity` | Intensity ≤ 0 |
| `REJECTED: invalid duration` | Duration ≤ 0 |

**Intensity → Color mapping**:
- 1: `warning` at 20% lerp
- 2: `warning` at 40% lerp
- 3: `warning` at 60% lerp
- 4: `danger` at 80% lerp
- 5: `danger` at 100%

---

#### 3.3.3 INFORMATION THROTTLING

**Purpose (one-line)**: Suppress negative information to dampen morale instability, at the cost of decision-making accuracy.

**Category**: Pressure · **Color**: `authority` base

**Inputs**:

| Field | Label | Type | Range | Tooltip |
|-------|-------|------|-------|---------|
| Level | Throttle Level | SpinBox | 1–5 | "Higher levels suppress more information. Increases misallocation risk and backlog accumulation." |
| Duration | Duration (hours) | SpinBox | 1–8760 | "Policy duration in hours." |

**Output/Feedback**:

| Result Label | Condition |
|--------------|-----------|
| `ACTIVE (Xh left)` | Accepted |
| `REJECTED: invalid level` | Level ≤ 0 |
| `REJECTED: invalid duration` | Duration ≤ 0 |

**Visual Cues**:
- Level 1–2: `authority` color
- Level 3–4: blend toward `warning`
- Level 5: blend toward `danger`

---

#### 3.3.4 EXPEDITION COMPRESSION

**Purpose (one-line)**: Accelerate expedition tempo for faster resource acquisition, at the cost of crew attention and delayed consequences.

**Category**: Expedition · **Color**: `authority`

**Inputs**:

| Field | Label | Type | Range | Tooltip |
|-------|-------|------|-------|---------|
| Intensity | Tempo Intensity | SpinBox | 1–5 | "Crew yield bonus per level. Higher intensity accumulates attention debt faster." |
| Duration | Duration (hours) | SpinBox | 1–8760 | "How many hours the accelerated tempo persists." |

**Output/Feedback**:

| Result Label | Condition |
|--------------|-----------|
| `ACTIVE (Xh left)` | Accepted |
| `REJECTED: invalid intensity` | Intensity ≤ 0 |
| `REJECTED: invalid duration` | Duration ≤ 0 |

**Warning Text** (always visible for this lever):
> ⚠ OUTCOMES UNCERTAIN — consequences may manifest beyond the current cycle.

---

#### 3.3.5 MODULE ABANDONMENT

**Purpose (one-line)**: Permanently disable a tower module to cut maintenance costs. Irreversible.

**Category**: Expedition · **Color**: `danger`

**Inputs**:

| Field | Label | Type | Range | Tooltip |
|-------|-------|------|-------|---------|
| ModuleId | Module Instance ID | LineEdit | Format: `f:x:y` | "Coordinates of the module to abandon. Format: floor:x:y (e.g., 0:2:3). Module will be permanently disabled." |

**Output/Feedback**:

| Result Label | Condition |
|--------------|-----------|
| `DISABLED` | Module found and abandoned |
| `REJECTED: module not found` | Coordinates invalid or no module at location |
| `REJECTED: module already abandoned` | Module was previously abandoned |
| `REJECTED: tower unavailable` | Tower reference missing |

**Warning Text** (always visible):
> ⚠ IRREVERSIBLE — this module cannot be restored.

**Visual Cues**:
- Red (`danger`) title and border
- Apply button uses `danger` background

---

#### 3.3.6 EMERGENCY CONVERSION

**Purpose (one-line)**: Forcibly reallocate resources between categories at a permanent efficiency loss.

**Category**: Conversion · **Color**: `desperation`

**Inputs**:

| Field | Label | Type | Range | Tooltip |
|-------|-------|------|-------|---------|
| From | Source Resource | OptionButton | `food`, `water`, `materials`, `morale` | "Resource to draw from." |
| To | Target Resource | OptionButton | `food`, `water`, `materials`, `morale` | "Resource to convert into." |
| Amount | Amount | SpinBox | 1–999 | "Quantity to redeploy. Actual yield depends on current efficiency." |

**Output/Feedback**:

| Result Label | Condition |
|--------------|-----------|
| `QUEUED` | Conversion accepted, pending execution |
| `REJECTED: missing resource` | From or To not specified |
| `REJECTED: invalid target` | From and To are the same |
| `REJECTED: unsupported resource` | Resource not in convertible list |
| `REJECTED: invalid amount` | Amount ≤ 0 |
| `REJECTED: option burned out` | Source resource has reached burn threshold (3 uses) |

**Special UI Elements**:
- **Burn counter**: Show `[X/3]` next to each resource in the From dropdown, where X = current burn count
- When X reaches 3, that option is grayed out and shows `(BURNED)` suffix
- **Debt warning** (always visible):
> ⚠ MORAL DEBT — each use permanently reduces conversion efficiency.

**Color semantics**:
- `desperation` (yellow-green) for title and border
- When a resource is near burn-out (2/3), show `warning` highlight
- When burned out, show `locked` color

---

### 3.4 Duration Display Standard

All duration values entered by the player are in **hours** (matching the sim's hour-tick model).

**Display rules**:
- Input labels: "Duration (hours)"
- Active status: Show raw hours → `ACTIVE (168h left)`
- Optionally show parenthetical: `(168h = 7 days)` in tooltip on hover
- Decrement display: Update every sim tick (every hour)

---

## 4) Ledger Specification

### 4.1 Panel Structure

```
┌──────────────────────────────────────────────────────────────────┐
│ LEDGER                                   [All][Sim][Events][Debug] │
├──────────────────────────────────────────────────────────────────┤
│ STATUS: EVENTS: 47 · FILTER: ALL                                │
├──────────────────────────────────────────────────────────────────┤
│ ┌────────────────────────────────────────────────────────────┐   │
│ │ Day 5 · Hour 02 │ SIM    │ resources: food -3, water -2   │   │
│ ├────────────────────────────────────────────────────────────┤   │
│ │ Day 5 · Hour 01 │ EVENT  │ policy active, scar accrues    │   │
│ ├────────────────────────────────────────────────────────────┤   │
│ │ Day 4 · Hour 23 │ DEBUG  │ expedition_heat = 4            │   │
│ └────────────────────────────────────────────────────────────┘   │
│                                                    [▼ Scroll]    │
└──────────────────────────────────────────────────────────────────┘
```

### 4.2 Filter Tabs

| Tab | Internal Token | Matches |
|-----|----------------|---------|
| All | `ALL` | All events |
| Sim | `SIM` | Resource ticks, state changes |
| Events | `EVENT` | Lever activations, incidents |
| Debug | `DEBUG` | Development/diagnostic entries |

**Behavior**:
- Only one filter active at a time (radio-button style)
- Active filter button uses `text-primary` + underline
- Inactive buttons use `text-secondary`
- Filtering is instant (no animation)

### 4.3 Event Card Layout

Each ledger entry is a single row:

```
┌─────────────┬─────────┬───────────────────────────────────────────┐
│ Timestamp   │ Category│ Message Body                               │
│ Day X · Hr Y│ [color] │ Short summary text, truncated if needed... │
└─────────────┴─────────┴───────────────────────────────────────────┘
```

**Timestamp format**: `Day X · Hour YY` (Y is zero-padded)

**Category chip**:
- Capitalized category name
- Background color from `CATEGORY_COLORS`
- 4px horizontal padding, 2px border-radius

**Message body**:
- Single line, truncated with ellipsis if > 80 characters
- Expandable on click (optional enhancement)

### 4.4 Expanded Event Detail (Optional)

When an event row is clicked, expand to show:

```
┌───────────────────────────────────────────────────────────────────┐
│ Day 5 · Hour 01 │ EVENT │ policy active, scar accrues            │
├───────────────────────────────────────────────────────────────────┤
│ Lever: RATION_HARDENING                                           │
│ Payload: mode=hard, duration_days=3, duration_ticks=72            │
│ Immediate: policy active                                          │
│ Debts: scar accrues                                               │
└───────────────────────────────────────────────────────────────────┘
```

### 4.5 Spam Avoidance

1. **Batching**: Consecutive SIM entries within the same hour can be collapsed into one line: `Hour 04: 3 resource updates`
2. **Max visible**: Hard limit of 300 entries in DOM; older entries pruned from top
3. **Auto-scroll**: Only auto-scroll to bottom if user is already at bottom (within 4px threshold)
4. **Throttle rate**: If > 10 events/second, batch into summary entries

---

## 5) HUD Panel Specification

### 5.1 Top Bar Layout

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ DAY: 5   PHASE: HOUR_TICK   HOUR: 14 (2×)  │ ⏸ ½× 1× 2× 4× │ ALERTS: 2     │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Components** (left to right):
1. **Day/Phase/Hour group**: Always visible
2. **Time controls**: Pause toggle + speed buttons (½×, 1×, 2×, 4×)
3. **Alerts counter**: Number of unacknowledged critical events

### 5.2 Left Rail (Resources + Status)

**Resource Cards**:
```
┌─────────────────────────┐
│ FOOD      ▼  47         │
├─────────────────────────┤
│ WATER     •  62         │
├─────────────────────────┤
│ MATERIALS ▲  198        │
└─────────────────────────┘
```

- Indicator: `▲` (up/good), `▼` (down/bad), `•` (neutral)
- Indicator color matches semantic meaning
- Value animates on change (brief flash)

**Status Chips** (horizontal flow):
```
┌──────────┐ ┌──────────┐ ┌──────────┐
│Morale: 58│ │Threat: 12│ │Pop: 6    │
└──────────┘ └──────────┘ └──────────┘
```

---

## 6) Minimal Implementation Notes

### 6.1 Required UI Nodes/Components

| Component | Node Type | Purpose |
|-----------|-----------|---------|
| `UiRoot` | CanvasLayer | Root UI container |
| `HudPanel` | PanelContainer | Top bar + left rail |
| `TopBar` | HBoxContainer | Day/phase/time + controls |
| `TimeControls` | HBoxContainer | Pause + speed buttons |
| `LeftRail` | VBoxContainer | Resources + status |
| `ResourceCards` | VBoxContainer | Individual resource entries |
| `StatusChips` | FlowContainer | Morale/threat/population |
| `OperationsConsole` | PanelContainer | Main operations panel |
| `OperationsScroll` | ScrollContainer | Scrollable lever area |
| `SectionPressure` | VBoxContainer | Pressure levers section |
| `SectionExpeditions` | VBoxContainer | Expedition levers section |
| `SectionConversions` | VBoxContainer | Conversion levers section |
| `LeverCard` | PanelContainer | Individual lever template |
| `LedgerPanel` | PanelContainer | Event log panel |
| `LedgerFilters` | HBoxContainer | Filter tab buttons |
| `LedgerScroll` | ScrollContainer | Scrollable event list |
| `LedgerItems` | VBoxContainer | Event row container |

### 6.2 Required Data Bindings (Sim → UI)

| UI Element | Sim Property | Update Frequency |
|------------|--------------|------------------|
| Day label | `sim.day` (computed from hour_index) | Every tick |
| Phase label | `sim.phase` | Every tick |
| Hour label | `sim.hour_of_day` | Every tick |
| Resource values | `sim.res.food`, `.water`, `.materials` | Every tick |
| Status values | `sim.res.morale`, `.threat`, `.population` | Every tick |
| Lever active state | `sim.ration_hardening_ticks_left > 0`, etc. | Every tick |
| Lever remaining time | `sim.ration_hardening_ticks_left`, etc. | Every tick |
| Events list | `sim.lever_events` | On append |
| Conversion burn counts | `sim.conversion_burn_counts` | On change |

### 6.3 Node Path Mapping Strategy

To maintain stable node references:

1. **Use `@onready` with explicit paths** from a known root (e.g., `$Scroll/Root/...`)
2. **Define path constants** in a config dictionary (already done in `LEVER_BASE_PATHS`)
3. **Validate on `_ready()`**: Call `_require_section_node()` pattern to fail loudly if paths break
4. **Avoid dynamic node creation** for structural elements—use visibility toggling instead
5. **If renaming is required**, update `LEVER_BASE_PATHS` and `NODE_TOOLTIP_CONFIG` dictionaries as the single source of truth

**Recommended naming convention**:
```
SectionPressure/
  PressureToggle (Button)
  PressureContent (VBoxContainer)
    RationHardening/
      Header/
        Title (Label)
        Intent (Label)
      ModeGroup/
        ModeLabel (Label)
        Mode (OptionButton)
      DurationGroup/
        DurationLabel (Label)
        Duration (SpinBox)
        DurationHint (Label)
      Apply (Button)
      Result (Label)
```

### 6.4 Command Flow Architecture

```
┌─────────────┐    user action    ┌─────────────────┐    apply_lever()    ┌───────────┐
│  UI Control │ ────────────────> │ OperationsConsole │ ────────────────> │ SimBridge │
└─────────────┘                   └─────────────────┘                     └───────────┘
                                                                                 │
                                                                                 v
┌─────────────┐    refresh()      ┌─────────────────┐    tick signal     ┌───────────┐
│  UI Display │ <──────────────── │   HudPanel /    │ <───────────────── │    Sim    │
│             │                   │   LedgerPanel   │                     │           │
└─────────────┘                   └─────────────────┘                     └───────────┘
```

**Invariant**: UI never computes game state. It only:
1. Reads sim properties for display
2. Dispatches player commands through `SimBridge.apply_lever()`
3. Reflects command results from sim's response

---

## Appendix: Quick Reference

### Color Token → Hex

| Token | Hex |
|-------|-----|
| neutral | #707f8c |
| good | #4a8ed9 |
| warning | #eba340 |
| danger | #c73838 |
| authority | #458ed9 |
| desperation | #a6bd34 |
| locked | #3d4654 |

### Typography Quick Reference

- Titles: 14-16px, weight 600
- Labels: 12px, weight 400
- Values: 13-18px, weight 500-600
- Hints: 11px, weight 400, secondary color

### Spacing Quick Reference

- Panel padding: 16px
- Card padding: 12px
- Input row gap: 8px
- Section gap: 16px

---

*End of specification.*
