## Design Context

### Users

Symphony's primary users are **developer-operators** — engineers who deploy and monitor autonomous AI coding agents working on GitHub issues. They use Symphony to observe agent progress, inspect run history, review live provider event logs, and intervene when agents need approval or encounter errors.

Their context is split-attention: operators glance at the UI periodically while doing their own work, then dive deep when something needs investigation. The interface must support both **at-a-glance status scanning** and **detailed forensic inspection** equally well.

### Brand Personality

**Precise. Calm. Trustworthy.**

Symphony orchestrates autonomous agents doing real work on real codebases. The interface must inspire confidence that the system is under control. It should feel like a well-built instrument panel — every element earns its place, nothing is decorative, and the operator can trust what they see at any moment.

Emotional goals:

- **Confidence**: "I know exactly what's happening across all my issues."
- **Calm awareness**: "Nothing urgent is hiding from me."
- **Engineering precision**: "The data I see is accurate and complete."

### Aesthetic Direction

**Visual tone**: Technical minimalism with semantic clarity. The design is intentionally restrained — system-native colors and typography ensure the UI feels like a first-class citizen on both iOS and macOS without competing with the data it presents.

**Current palette** (all system-semantic, auto dark/light):

- Backgrounds: `Color.secondary` at 0.06–0.08 opacity (cards, rows)
- Selection: `Color.accentColor` at 0.12 opacity
- Text: `.primary` (content), `.secondary` (metadata, timestamps)
- Status signals: `.red` (errors), `.orange` (warnings, blockers, approval requests), `.blue` (labels, info badges)
- No custom brand colors — system-native by design

**Typography** (system fonts, Dynamic Type):

- Headings: `.title2`/`.title3` semibold
- Content: `.headline`, `.subheadline`, `.callout`
- Metadata: `.caption`, `.caption2`
- Code/IDs: `.monospaced` variants

**Layout**: `NavigationSplitView` — sidebar (connection + issue list) / detail (issue, run, logs). Responsive via `horizontalSizeClass` for iPhone compact layout.

**References**: The density and data-first approach draws from developer tools like Xcode Instruments, Linear's clean issue tracking, and GitHub's own issue UI. The split-view pattern follows Apple's Mail/Notes convention.

**Anti-references**: Overly branded dashboards (Datadog's visual density without hierarchy), consumer-focused social apps, anything with decorative illustrations or mascots.

**Theme**: Both light and dark mode, automatic via system semantic colors. No manual theme toggle — respects system preference.

### Design Principles

1. **Data density over decoration** — Every pixel serves observability. No ornamental elements, gradients, or illustrations. White space is used for hierarchy, not aesthetics.

2. **Semantic color only** — Colors communicate meaning (error = red, warning = orange, info = blue, neutral = secondary). Never use color for branding or decoration. System semantic colors ensure automatic dark/light adaptation.

3. **Platform-native first** — Use SwiftUI system components, fonts, and behaviors. The app should feel like it belongs on macOS and iOS without custom chrome. Respect platform conventions (NavigationSplitView, SF Symbols, Dynamic Type).

4. **Glanceability before depth** — The sidebar must communicate overall system health in 2 seconds. Priority badges, state indicators, and provider labels are visible without tapping. Detail views reward investigation but aren't required for status awareness.

5. **Accessibility as foundation** — Semantic font sizes (Dynamic Type), system colors (automatic contrast), accessibility identifiers on all interactive elements. WCAG AA compliance as minimum. Respect reduced motion preferences.

### Design Tokens

```
Spacing:
  section-gap-desktop: 20pt
  section-gap-compact: 12pt
  card-padding: 16pt
  inline-gap: 8pt

Corner Radius:
  card: 16pt (continuous)
  row: 14pt (continuous)
  badge: capsule
  nested-card: 12pt (continuous)
  log-event: 8pt (continuous)

Opacity:
  card-background: 0.08
  nested-background: 0.06
  selection-highlight: 0.12
  status-tint: 0.08
  badge-background: 0.12–0.15
```
