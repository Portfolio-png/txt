# Paper

Flutter application for the Paper ERP-style dashboard experience.

## Local Development

The local Paper stack now defaults to `http://localhost:18080` for the backend so it does not collide with older services that may still be running on `8080`.

Start the backend:

```bash
cd backend
npm start
```

Start the Flutter app:

```bash
flutter run
```

If you need a different backend URL, override it explicitly:

```bash
flutter run --dart-define=PAPER_API_BASE_URL=http://localhost:8080
```

## Project Layout Pattern

This project follows a `sidebar navigation + dynamic main content area` layout.

- The left panel is the `sidebar` or `side navigation`.
- The right panel is the `main content area` or `content panel`.

In the design discussion :

- The `blue box` = sidebar navigation
- The `red box` = main content area

## Architecture Decision

When a user clicks an item in the sidebar, we keep the outer screen layout in place and change only the main content area.

Examples:

- Clicking `Inventory` should load `inventory.dart` in the main content area.
- Clicking `Invoices` should load `invoices.dart` in the main content area.
- Clicking `Dashboard` should load `dashboard.dart` in the main content area.

This pattern is commonly described as:

- `sidebar-driven content switching`
- `master-detail layout`
- `shell layout with nested content`

For this repo, we should use the first term in team discussions:

`Sidebar-driven content switching`

## Official Flutter Architecture

This repo should follow:

`Feature-first Flutter architecture with Provider, reusable widgets, and a shared AppShell using sidebar-driven dynamic content switching.`

Core decisions:

- Use `Provider` for app shell state and feature state.
- Use one shared `AppShell` for sidebar, top bar, and main content area.
- Keep the sidebar fixed and swap only the main content widget.
- Build a reusable widget layer for cards, panels, buttons, headers, filters, and layout containers.
- Keep feature-specific widgets inside their own feature folders.

## Recommended Folder Structure

```text
lib/
  app/
    shell/
      app_shell.dart
      app_sidebar.dart
      app_topbar.dart
      navigation_provider.dart

  core/
    widgets/
      app_card.dart
      app_button.dart
      app_section_title.dart
      app_info_panel.dart
      app_stat_card.dart
      app_filter_bar.dart
      app_empty_state.dart
    theme/
    constants/
    utils/

  features/
    dashboard/
      data/
      domain/
      presentation/
    inventory/
      data/
      domain/
      presentation/
    production_pipelines/
      data/
      domain/
      presentation/
    invoices/
      data/
      domain/
      presentation/
    reports/
      data/
      domain/
      presentation/
```

Feature-level shape:

```text
feature_name/
  data/
    models/
    repositories/
    mock/
  domain/
    entities/
    services/
  presentation/
    screens/
    widgets/
    providers/
    state/
```

## Implementation Guidance

Each feature screen should follow this idea:

1. Keep one parent shell widget that owns the sidebar and top bar.
2. Store the selected sidebar key in state.
3. Swap only the widget inside the main content area based on the selected key.
4. Use `Provider` to expose and update selected navigation state.
5. Keep feature content split into separate files/widgets such as `inventory.dart`, `invoices.dart`, and `dashboard.dart`.
6. Prefer reusable base widgets from `core/widgets` before creating new shared UI patterns.

Typical Flutter structure:

```dart
Row(
  children: [
    AppSidebar(
      selectedKey: selectedKey,
      onItemSelected: onItemSelected,
    ),
    Expanded(
      child: _buildContent(selectedKey),
    ),
  ],
)
```

Example content switch:

```dart
Widget _buildContent(String selectedKey) {
  switch (selectedKey) {
    case 'inventory':
      return const InventoryScreen();
    case 'invoices':
      return const InvoicesScreen();
    case 'dashboard':
    default:
      return const DashboardScreen();
  }
}
```

## Reusable Widget Rule

Use reusable widgets for UI pieces that appear in more than one module.

Good candidates:

- app shell containers
- buttons
- cards
- info panels
- section headings
- filter bars
- stat tiles
- table wrappers
- empty states

Keep these inside `core/widgets`.

Do not over-generalize feature-specific components too early.

Examples:

- `AppCard` should be shared.
- `AppInfoPanel` should be shared.
- `PipelineStageNode` should stay inside `production_pipelines`.
- `InventoryPropertyPanel` should stay inside `inventory` unless reused elsewhere.

## Delivery Estimate

Based on the diagrams and the architecture above, a realistic estimate is:

- App shell, Provider setup, sidebar switching, and reusable base widgets: `4 to 7 days`
- Initial frontend for dashboard, inventory, and production pipelines with mock data: `2 to 4 weeks`
- More polished frontend with responsive behavior, better reuse, and cleaner states: `4 to 6 weeks`
- Full working product with backend integration, CRUD, validations, graph interactions, and testing: `6 to 12+ weeks`

Production pipeline work is the biggest variable.

If the pipeline screen is only a viewer:

- `1 to 2 weeks`

If the pipeline screen needs rich interactions such as branching, merging, click selection, detail panels, editing, and graph-style behavior:

- `3 to 6 weeks`

Recommended execution order:

1. App shell and navigation
2. Reusable widget system
3. Inventory screens
4. Production pipeline viewer
5. Pipeline interactions and editing
6. Backend integration and testing

## Current Reference

The current `production_pipelines` feature already uses this direction:

- Sidebar selection is stored in controller state.
- The sidebar widget highlights the active item.
- Future work should connect each sidebar key to a dedicated content widget in the main panel.

Relevant files:

- [production_pipelines_screen.dart](~/Paper/lib/features/production_pipelines/presentation/screens/production_pipelines_screen.dart)
- [production_pipelines_controller.dart](~/Paper/lib/features/production_pipelines/presentation/state/production_pipelines_controller.dart)
- [pp_sidebar.dart](~/Paper/lib/features/production_pipelines/presentation/widgets/pp_sidebar.dart)

## Team Rule

For new screens and modules, do not rebuild the whole page for each menu item. Reuse the same shell and update only the main content area unless a flow truly needs separate route navigation.

## To start backend:

cd /Users/rutuparnpuranik/Paper
node backend/server.js
