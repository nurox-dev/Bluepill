# Project BluePill App Theme

This document explains the BluePill visual system for product UI, brand consistency, marketing handoff, and future implementation work.

Source of truth:

```text
flutter/lib/theme/app_theme.dart
```

The Flutter app uses Material 3 with the expressive dynamic scheme variant, then pins the BluePill palette back onto the generated color roles. This keeps the modern Material 3 Expressive feel while preserving the original BluePill brand colors.

## Brand Personality

BluePill should feel like a calm command center for personal progress.

- Clear, focused, and confidence-building.
- Modern and lively without feeling decorative.
- Useful before flashy.
- Dense enough for daily planning, but not visually heavy.
- Bright brand moments should guide attention, not dominate the whole screen.

## Core Palette

Primary, secondary, and tertiary map to clear product meanings.

| Role | Light | Dark | Use |
| --- | --- | --- | --- |
| Primary | `#2563EB` | `#60A5FA` | Brand identity, primary actions, active progress, key links |
| Secondary | `#65A30D` | `#A3E635` | Success, selected navigation, completion, supportive emphasis |
| Tertiary | `#E11D48` | `#FB7185` | Human emphasis, attention, focus states, expressive gradients |

Use `Theme.of(context).colorScheme` instead of hard-coded colors whenever possible.

## Neutral Palette

Light mode:

| Token | Hex |
| --- | --- |
| Background | `#F5F7FB` |
| Surface | `#FFFFFF` |
| Surface alt | `#F8FAFC` |
| Surface container | `#F1F5F9` |
| Surface container high | `#EFF2F7` |
| Surface container highest | `#E2E8F0` |
| Border | `#E2E8F0` |
| Text | `#111827` |
| Muted text | `#475569` |

Dark mode:

| Token | Hex |
| --- | --- |
| Background | `#090D16` |
| Surface | `#111827` |
| Surface alt | `#172033` |
| Surface container | `#1E293B` |
| Surface container high | `#22314A` |
| Surface container highest | `#26344B` |
| Border | `#26344B` |
| Text | `#E5E7EB` |
| Muted text | `#CBD5E1` |

Surfaces should create hierarchy quietly. Prefer color scheme surface roles over custom grays.

## Brand Usage

Use primary blue for:

- Product logo and brand marks.
- Main call to action.
- Current progress and active controls.
- Links and high-confidence affordances.

Use secondary lime for:

- Selected navigation.
- Completed states.
- Positive reinforcement.
- Secondary containers and chips.

Use tertiary rose for:

- Focus rings and active input borders.
- Expressive button gradients.
- Attention moments that are not errors.
- Small emphasis in empty states or loading visuals.

Error colors should come from `colorScheme.error`, not tertiary rose.

## Material 3 Expressive Rules

BluePill uses Material 3 Expressive in these ways:

- `useMaterial3: true`.
- `DynamicSchemeVariant.expressive`.
- Rounded superellipse component shapes.
- Rich state layers for hover, focus, and press.
- Updated Material 3 progress indicators with `year2023: false`.
- Expressive transitions using `FadeForwardsPageTransitionsBuilder` and emphasized easing.

Keep Expressive styling in the theme layer first. Only style individual widgets when a screen needs domain-specific composition.

## Shape System

BluePill uses soft, modern geometry with `RoundedSuperellipseBorder`.

| Shape | Radius | Typical use |
| --- | ---: | --- |
| Small | `10` | Chips, tooltips, compact labels |
| Medium | `16` | Buttons and controls |
| Large | `22` | Cards and grouped surfaces |
| Extra large | `28` | Navigation indicators, dialogs, bottom sheets |

Avoid sharp corners unless the element is a data grid, divider, or full-width layout boundary.

## Typography

Font family:

```text
Roboto
```

Typography is intentionally confident:

- Headlines and titles use heavy weights, usually `FontWeight.w900`.
- Body text stays readable with 1.35 to 1.45 line height.
- Labels are bold for scanability in controls and dashboards.
- Letter spacing stays `0`.

Use theme text styles first:

```dart
Theme.of(context).textTheme.titleLarge
Theme.of(context).textTheme.bodyMedium
Theme.of(context).textTheme.labelLarge
```

## Components

Cards:

- Use `BpCard` for normal content groups.
- Cards should use surface container colors and a subtle outline.
- Do not nest cards inside cards unless the inner item is a repeated list item.

Buttons:

- Use `FilledButton` for primary actions.
- Filled buttons use the BluePill blue-to-lime or blue-to-rose expressive gradient.
- Use `OutlinedButton` for secondary actions.
- Use `TextButton` for low-emphasis actions.
- Button backgrounds are clipped to the same superellipse shape as the button material.

Navigation:

- Selected navigation uses secondary containers.
- Unselected navigation uses muted surface text.
- Keep labels short because the app is used repeatedly.

Inputs:

- Inputs use filled Material 3 fields.
- Focus state uses tertiary rose.
- Prefix and suffix icons should come from the theme color roles.

Chips:

- Chips are for compact metadata, filters, and prompt suggestions.
- Selected chips use secondary containers.
- Avoid using chips as large buttons.

Progress and loading:

- Use `ExpressiveLoadingIndicator` for circular loading.
- Use `LinearProgressIndicator` for determinate progress.
- Both should inherit `ProgressIndicatorThemeData`.

## Marketing And External Brand

For screenshots, landing pages, or pitch material:

- Lead with the primary blue.
- Use lime for success/progress signals.
- Use rose sparingly for human warmth and urgency.
- Keep backgrounds close to the app surfaces so screenshots and marketing feel related.
- Avoid monochrome blue layouts. BluePill is blue-led, but not blue-only.

For simple brand swatches:

```text
BluePill Blue: #2563EB
Progress Lime: #65A30D
Focus Rose: #E11D48
Light Background: #F5F7FB
Dark Background: #090D16
```

## Implementation Guidance

When adding UI:

1. Start with `Theme.of(context).colorScheme`.
2. Use shared widgets such as `BpCard`, `SectionTitle`, `EmptyState`, and `ExpressiveLoadingIndicator`.
3. Prefer theme-level component styling over local style overrides.
4. Use `RoundedSuperellipseBorder` for new controls that need custom shape.
5. Keep local gradients rare. The primary gradient already lives in the filled button theme.

When changing the theme:

- Update `flutter/lib/theme/app_theme.dart`.
- Update this document if tokens, roles, or component behavior change.
- Run `flutter analyze`.
- Run `flutter build web` when the change affects app-wide rendering.

## Do And Do Not

Do:

- Use Material 3 color roles.
- Keep the previous BluePill palette intact unless this doc is intentionally revised.
- Use strong typography for dashboard scanability.
- Let accent colors signal meaning.

Do not:

- Add random blue or purple gradients outside the theme.
- Hard-code component colors inside screens when a color role exists.
- Use tertiary rose as an error color.
- Make marketing-style hero sections inside the product app.
- Reintroduce older Material 2 style shapes or component defaults.
