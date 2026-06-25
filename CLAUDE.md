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

## Dev run modes

- `flutter run -d windows` — debug against the backend at `localhost:18080`.
  Point at another backend (e.g. EC2) with `--dart-define=PAPER_API_BASE_URL=http://HOST:18080`.
- `--dart-define=PAPER_OFFLINE_CONFIG=true` — no backend; config comes from
  [dev_config.dart](packages/core_erp/lib/core/services/dev_config.dart),
  hot-reloadable on Ctrl+S. Use for fast UI iteration.
- Backend: `cd backend && npm start` (Node, port 18080).
