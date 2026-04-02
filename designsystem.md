# XRoads Design System

> Version 1.0 — Unified design language across Swift (native macOS) and Tauri (cross-platform) implementations.

---

## 1. Design Philosophy

XRoads adopts a **dark-first, terminal-native** aesthetic inspired by cyberpunk interfaces, IDE dark themes (GitHub Dark, VS Code Pro), and sci-fi command centers. The design communicates:

- **Technical authority** — monospace typography, dense information, terminal-grade UX
- **Living system** — neon glows, pulsing indicators, energy connections between agents
- **Control & orchestration** — hexagonal layouts, central brain, radial hierarchy

**No light mode.** The entire system is dark-only by design.

---

## 2. Color Palette

### 2.1 Backgrounds

| Token | Hex | Usage |
|-------|-----|-------|
| `bg-app` | `#0d1117` / `#0a0a0f` | Deepest layer, app background |
| `bg-canvas` | `#010409` | Terminal panes, log views |
| `bg-surface` | `#161b22` / `#111118` | Cards, panels, chat areas |
| `bg-elevated` | `#1c2128` / `#1a1a24` | Hover states, elevated modals |
| `bg-slot-card` | `#14161a` | Slot card interior |
| `bg-slot-header` | `#1a1d23` | Slot card header bar |
| `bg-terminal` | `#0d0f12` | Terminal content area |

### 2.2 Text

| Token | Hex | Usage |
|-------|-----|-------|
| `text-primary` | `#e6edf3` / `#e4e4e7` | Titles, main content |
| `text-secondary` | `#7d8590` / `#a1a1aa` | Labels, metadata |
| `text-tertiary` | `#484f58` / `#52525b` | Placeholders, disabled text |
| `text-inverse` | `#0d1117` | Text on light backgrounds |

### 2.3 Borders

| Token | Hex | Usage |
|-------|-----|-------|
| `border-default` | `#30363d` / `#2a2a36` | Subtle panel borders |
| `border-muted` | `#21262d` | Very discrete separators |
| `border-accent` | `#388bfd` | Active/focus states |
| `border-inactive` | `#333840` | Slot card inactive border |

### 2.4 Accent Colors

| Token | Hex | Role |
|-------|-----|------|
| `accent-primary` | `#388bfd` | Claude AI blue — primary CTA, focus rings |
| `accent-primary-hover` | `#4493ff` | Hover state |
| `accent-primary-glow` | `#388bfd` @ 15% | Glow aura behind active elements |
| `neon-green` | `#0DF170` | Tauri primary accent, cursor, success glow |
| `neon-blue` | `#00D4FF` | Tauri secondary accent, info |
| `neon-purple` | `#8B5CF6` | Tauri tertiary accent, settings |

### 2.5 Status Colors

| Status | Hex | Glow (15%) | Usage |
|--------|-----|------------|-------|
| Success / Running | `#3fb950` | `#3fb95026` | Active agents, passing tests |
| Warning / Pending | `#d29922` | `#d2992226` | Processing, waiting approval |
| Error / Failed | `#f85149` | `#f8514926` | Crashed agents, build failures |
| Info / Idle | `#79c0ff` | `#79c0ff26` | Informational, idle state |

### 2.6 Terminal ANSI Colors

| Name | Hex |
|------|-----|
| Green | `#58a6ff` |
| Cyan | `#79c0ff` |
| Yellow | `#d29922` |
| Red | `#ff7b72` |
| Magenta | `#bc8cff` |

### 2.7 Agent Slot Border Colors

| Agent | Hex | Identifier |
|-------|-----|------------|
| Claude | `#388bfd` | Blue |
| Gemini | `#d29922` | Gold |
| Codex | `#3fb950` | Green |
| Empty | `#30363d` | Neutral gray |

### 2.8 Orchestrator Creature States

| State | Hex | Animation |
|-------|-----|-----------|
| Idle | `#7d8590` | Slow pulse |
| Planning | `#d29922` | Amber glow |
| Distributing | `#388bfd` | Expanding rings |
| Monitoring | `#3fb950` | Steady glow |
| Synthesizing | `#bc8cff` | Purple pulse |
| Celebrating | `#ffd700` | Sparkle |
| Concerned | `#f85149` | Rapid pulse |
| Sleeping | `#484f58` | Dim |

### 2.9 Neon Accent (Brain Visualization)

| Name | RGB | Usage |
|------|-----|-------|
| Neon Cyan | `rgb(0, 230, 255)` | Neural filaments, synapses |
| Neon Magenta | `rgb(255, 51, 204)` | Energy bursts, alerts |
| Neon Purple | `rgb(153, 77, 255)` | Processing state |

---

## 3. Typography

### 3.1 Font Stack

```
Primary:  'SF Mono', 'JetBrains Mono', 'Fira Code', monospace
Fallback: system-ui monospace
```

Both platforms use **100% monospace** typography. No sans-serif or serif fonts.

### 3.2 Type Scale

| Token | Size | Weight | Usage |
|-------|------|--------|-------|
| `display` | 24px | Semibold | Page titles, hero headings |
| `h1` | 20px | Semibold | Section headings |
| `h2` | 16px | Medium | Panel titles, subheadings |
| `h3` | 14px | Medium | Card headers, group labels |
| `body` | 14px | Regular | Main content text |
| `small` | 12px | Regular | Secondary text |
| `terminal` | 13px | Regular | Terminal output, code |
| `code` | 13px | Regular | Inline code |
| `xs` | 11px | Regular | Labels, toolbar text |
| `xxs` | 10px | Regular | Badges, compact labels |
| `tiny` | 9px | Regular | Timestamps, micro-labels |
| `label` | 7–8px | Medium | Miniature annotations |

### 3.3 Text Treatments

- **Uppercase** + `letter-spacing: 0.05em` for category labels
- **Monospace bold** for emphasis within paragraphs
- **Text opacity** for hierarchy (`opacity: 0.7` for secondary, `0.4` for tertiary)

---

## 4. Spacing & Layout

### 4.1 Spacing Scale

| Token | Value | Usage |
|-------|-------|-------|
| `xs` | 4px | Tight gaps, inline spacing |
| `sm` | 8px | Compact padding, icon gaps |
| `md` | 16px | Standard padding, card insets |
| `lg` | 24px | Section spacing |
| `xl` | 32px | Major section breaks |

### 4.2 Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| `radius-xs` | 4px | Sharp corners, badges |
| `radius-sm` | 6px | Buttons, small cards |
| `radius-md` | 8px | Cards, panels |
| `radius-lg` | 12px | Elevated modals, sheets |
| `radius-full` | 9999px | Pill badges, status dots |

### 4.3 Layout Dimensions

| Element | Size |
|---------|------|
| Window min | 1280 × 800 px |
| Window default | 1440 × 900 px |
| Sidebar width | 240px |
| Inspector width | 320px |
| Chat max width | 800px |
| Header height | 48px |
| Input bar height | 56px |
| Button height | 36px |
| Status dot | 8px |
| Slot card | 220 × 160 px |
| Orchestrator brain | 200 × 220 px |
| Brain view | 160 × 140 px |
| Panel header | 40px |

### 4.4 Layout Structure

```
┌──────────────────────────────────────────────────────────┐
│  Toolbar (48px)                                          │
├──────┬───────────────────────────────────────┬───────────┤
│      │                                       │           │
│ Side │         Dashboard / Terminal Grid      │ Cockpit   │
│ bar  │                                       │ Panel     │
│      │    ┌───┐  ┌───┐                       │           │
│ 240  │    │ S1│  │ S2│                       │   320px   │
│  px  │    └───┘  └───┘                       │           │
│      │         🧠 Brain                      │           │
│      │    ┌───┐  ┌───┐                       │           │
│      │    │ S3│  │ S4│                       │           │
│      │    └───┘  └───┘                       │           │
│      │                                       │           │
├──────┴───────────────────────────────────────┴───────────┤
│  Bottom Bar / Metrics                                    │
└──────────────────────────────────────────────────────────┘
```

**Hexagonal Slot Layout**: 6 terminal slots arranged at 270°, 330°, 30°, 90°, 150°, 210° around a central orchestrator brain. Radius scales with container: `min(containerW × 0.35, 320)`.

---

## 5. Components

### 5.1 Buttons

| Variant | Background | Text | Border | Hover |
|---------|------------|------|--------|-------|
| Primary | `accent-primary` @ 20% | `accent-primary` | `accent-primary` @ 30% | 40% bg |
| Neon | `neon-green` @ 20% | `neon-green` | `neon-green` @ 30% | 50% border |
| Secondary | `bg-elevated` | `text-secondary` | `border-default` | Lighten bg |
| Destructive | `#f85149` @ 20% | `#f85149` | `#f85149` @ 30% | 40% bg |
| Ghost | transparent | `text-secondary` | none | `bg-elevated` |
| Icon | transparent | `text-secondary` | none | Scale 1.1 |

All buttons: `height: 36px`, `border-radius: 6px`, `font: 11px monospace semibold`.

### 5.2 Cards

**Slot Card** (220 × 160 px)
- Background: `bg-slot-card`
- Border: 1px `border-default`, color changes to agent color on hover
- Header: 36px, `bg-slot-header`, agent icon + name + status dot
- Content: terminal preview area
- Hover: `translateY(-2px)`, shadow `0 4px 12px rgba(0,0,0,0.4)`
- Active: glowing border matching agent color

**Panel Card**
- Background: `bg-surface`
- Border: 1px `border-default`
- Padding: `md` (16px)
- Corner radius: `radius-md` (8px)

### 5.3 Status Badges

- Dot: 8px circle, color matches status
- Active: pulsing animation (2s cycle)
- Text badge: pill shape, 10px font, status color bg @ 15%

### 5.4 Input Fields

- Background: `bg-canvas`
- Border: 1px `border-default`, focus → `border-accent`
- Padding: 8px horizontal, 6px vertical
- Font: 11–13px monospace
- Placeholder: `text-tertiary`

### 5.5 Modals / Sheets

- Overlay: `rgba(0,0,0,0.6)` + `backdrop-blur: 4px`
- Container: `bg-surface`, `radius-lg`, border `border-default`
- Width: 420–560px depending on content
- Animation: scale 0.95→1 + fade (0.15s)

### 5.6 Panels (Collapsible)

- Collapse animation: width transition 0.15s ease-in-out
- Resize handle: 4px hit area on leading/trailing edge
- Header: 40px, icon + title + collapse chevron

### 5.7 Terminal View

- Font: 13px monospace
- Background: `bg-canvas` (#010409)
- Cursor: block, `neon-green`
- Selection: `neon-green` @ 18%
- Line height: 1.2

---

## 6. Iconography

### 6.1 Icon System

- **Swift**: SF Symbols (Apple's system icon set)
- **Tauri**: Emoji-based icons (🧠 Claude, ✨ Gemini, ⌨️ Codex)

### 6.2 Key Icons (SF Symbol Names)

| Icon | Symbol | Usage |
|------|--------|-------|
| Branch | `arrow.triangle.branch` | Git branch |
| Add | `plus.circle.fill` | Add action |
| Settings | `gearshape` | Configure |
| Close | `xmark` | Dismiss |
| Success | `checkmark.circle.fill` | Approve, done |
| Warning | `exclamationmark.triangle.fill` | Alert |
| Error | `xmark.circle.fill` | Reject, fail |
| Delete | `trash` | Remove |
| Chat | `text.bubble` | Messages |
| Brain | `brain.heart.profile` | AI orchestrator |
| Shield | `shield.lefthalf.filled` | Approval gates |
| Magic | `wand.and.stars` | Generation |
| Play | `play.circle` | Execute |
| Refresh | `arrow.clockwise` | Reload |
| Search | `magnifyingglass` | Find |
| Crown | `crown.fill` | Chairman |
| Heart | `heart.fill` | Heartbeat |
| Sparkles | `sparkles` | Skills |
| Paint | `paintbrush.fill` | Art direction |

### 6.3 Icon Sizing

| Context | Size |
|---------|------|
| Inline text | 10–12px |
| Toolbar | 14px |
| Card header | 12–14px |
| Feature icon | 16px |
| Hero | 24px+ |

---

## 7. Animations & Motion

### 7.1 Timing Tokens

| Token | Duration | Usage |
|-------|----------|-------|
| `fast` | 100ms | Immediate feedback (hover, press) |
| `normal` | 150ms | Standard transitions (panels, tabs) |
| `slow` | 200ms | Meaningful transitions (modals, slides) |
| `modal` | 250ms | Sheet appear/dismiss |
| `pulse` | 2000ms | Continuous status indicators |
| `suite-pulse` | 4000ms | Suite glow border cycle |

### 7.2 Easing

| Easing | Usage |
|--------|-------|
| `ease-in-out` | Most transitions |
| `ease-out` | Entry animations (fade in, scale in) |
| `linear` | Continuous rotation, shimmer |

### 7.3 Animation Catalog

**Entry Animations**
- Fade in: opacity 0→1, translateY 4px→0 (0.2s)
- Scale in: scale 0.95→1, opacity 0→1 (0.15s)
- Slide right: translateX 12px→0 (0.2s)
- Slide left: translateX -12px→0 (0.2s)

**Continuous Animations**
- Status pulse: opacity 0.6↔1.0 (2s cycle, infinite)
- Glow pulse: box-shadow intensity oscillation (2s)
- Suite border: inset glow color cycling (4s)
- Skeleton shimmer: gradient slide left→right (1.5s)
- Brain rotation: energy rings at varying speeds
- Neural filaments: traveling particles along paths
- Synapse flow: dashed stroke offset animation (1.5s)

**Interactive Animations**
- Hover lift: translateY(-2px), shadow expand (0.15s)
- Hover scale: scale 1.02 (0.15s)
- Press: scale 0.98 (0.1s)
- Focus ring: border-color transition (0.15s)
- Panel collapse: width → 0 (0.15s)

**Brain Visualization**
- Idle: slow radius pulse, dim glow
- Running: faster pulse, bright neon connections, particle orbits
- Merging: purple glow, converging animations
- Error: rapid red pulse
- Complete: gold celebration sparkle

---

## 8. Shadows & Elevation

| Level | Shadow | Usage |
|-------|--------|-------|
| 0 | none | Flat cards, inline elements |
| 1 | `0 2px 8px rgba(0,0,0,0.3)` | Hover cards |
| 2 | `0 4px 12px rgba(0,0,0,0.4)` | Elevated cards, dropdowns |
| 3 | `0 8px 24px rgba(0,0,0,0.5)` | Modals, floating panels |
| Glow | `0 0 20px <accent> @ 15%` | Active status, neon elements |

---

## 9. Grid & Composition Rules

### 9.1 Dashboard Grid
- 6 slots in hexagonal arrangement
- Central brain at origin
- Synapse lines connecting brain to each slot
- Minimum slot gap: 16px

### 9.2 Panel Composition
- Sidebar (left): navigation, workspace list
- Main (center): dashboard or terminal grid
- Inspector (right): cockpit, git, intelligence panels
- Chat (overlay left): collapsible chat panel

### 9.3 Information Density
- Dense mode: 9–11px text, 4px spacing, maximum data
- Comfortable mode: 12–14px text, 8–16px spacing
- Default is dense — this is a power-user tool

---

## 10. Cross-Platform Parity

| Element | Swift (Native) | Tauri (Web) |
|---------|----------------|-------------|
| Colors | `Color` extensions | CSS variables + Tailwind |
| Typography | `.system(.monospaced)` | `font-family: 'SF Mono'...` |
| Layout | SwiftUI stacks/grids | Flexbox + CSS Grid |
| Animation | SwiftUI `.animation()` | CSS keyframes + transitions |
| Icons | SF Symbols | Emoji + inline SVG |
| Terminal | PTY + custom view | xterm.js |
| State | `@Observable` | Zustand |
| Components | SwiftUI views | React TSX |

Both platforms share the same:
- Color values and palette
- Hexagonal slot layout concept
- Brain/orchestrator visualization
- Slot card dimensions and styling
- Typography scale and font choices
- Dark-only theme
- Animation timing and easing curves
