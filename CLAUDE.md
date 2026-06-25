# CLAUDE.md

Guidance for any agent (or human) working in this repo.

## Feature flags are mandatory

**Every user-facing feature or module ships behind a feature flag. No feature
reaches a client build ungated.** This is the core product mechanic: it's how we
hand each client a tailored subset of the app and keep unreleased work dark.

To add a feature, also add its flag — in the same change:

1. Declare an annotated key in `FeatureKeys`
   ([feature_flags.dart](packages/core_erp/lib/core/services/feature_flags.dart)):
   ```dart
   @FeatureFlag(category: 'Orders Screen', displayName: 'My Feature', desc: 'What it does')
   static const String myFeature = 'orders.myFeature'; // dotted path → nested config
   ```
2. Gate the UI/behaviour with `FeatureFlags.isEnabled(FeatureKeys.myFeature)`.
   For a whole module / nav area, also wire it into
   `ConfigService.isModuleEnabled` and `_moduleForNavKey`
   ([config_service.dart](packages/core_erp/lib/core/services/config_service.dart))
   so both the sidebar and the content router honour it.
3. Regenerate the dashboard registry so the flag becomes a per-client toggle
   (run from repo root):
   ```
   dart run bin/generate_registry.dart   # writes backend/feature_registry.json
   ```

Defaults: `FeatureFlags.isEnabled` returns **false** for unknown keys, so a new
flag is OFF until enabled in a client's config. Per-client config lives in the
`sandbox_client_configs` table, edited via the dashboard at
`http://localhost:18080/dashboard`, served to the app by `GET /sandbox-config/:clientId`.

## Replacing a working flow (selector flags)

To build a new version of an existing flow **without removing the one that
works**: the flag *selects the implementation*. You add a branch and a new file,
and never edit the current flow — that's what guarantees it keeps working.

1. Add a selector flag, default OFF (everyone keeps the current flow):
   ```dart
   @FeatureFlag(category: 'Orders Screen', displayName: 'New Order Flow (v2)', desc: '...')
   static const String ordersFlowV2 = 'orders.flowV2';
   ```
2. Branch at the flow's **single entry point** (e.g. `OrdersScreen.openEditor`):
   ```dart
   if (FeatureFlags.isEnabled(FeatureKeys.ordersFlowV2)) {
     return OrderEditorV2.open(context, initialOrderGroup); // new flow
   }
   // ...existing flow below, unchanged...
   ```
3. The new flow lives in its own file; the old widget is never touched. Flip the
   flag per client to roll v2 out to one client at a time.

Notes:
- 3+ variants → make the flag a string (`"orders.flow": "v1" | "v2"`) and `switch`.
- Unreleased / secret v2 → also wrap the branch in a compile-time
  `const bool.fromEnvironment('GARAGE')` so it's tree-shaken out of client builds
  until you choose to ship it (runtime flag picks it; compile-time flag decides if
  it's even present).

## Dev run modes

- `flutter run -d windows` — debug against the backend at `localhost:18080`.
  Point at another backend (e.g. EC2) with `--dart-define=PAPER_API_BASE_URL=http://HOST:18080`.
- `--dart-define=PAPER_OFFLINE_CONFIG=true` — no backend; config comes from
  [dev_config.dart](packages/core_erp/lib/core/services/dev_config.dart),
  hot-reloadable on Ctrl+S. Use for fast UI iteration.
- Backend: `cd backend && npm start` (Node, port 18080).
