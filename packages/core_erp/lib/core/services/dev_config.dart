import 'package:flutter/foundation.dart' show kDebugMode;

// Offline dev mode: ignore the backend and drive config from devConfig below.
// OFF by default, so a normal `flutter run` in debug talks to the real backend
// (local or EC2). Opt in for fast UI iteration with no backend:
//   flutter run --dart-define=PAPER_OFFLINE_CONFIG=true
// Always false in release (kDebugMode guard → tree-shaken out).
const bool useDevConfig =
    kDebugMode && bool.fromEnvironment('PAPER_OFFLINE_CONFIG', defaultValue: false);

// Local overrides, applied ONLY when useDevConfig is true.
//
// Edit a value, hit Ctrl+S → hot reload applies it live, no restart, no
// backend. Keys mirror the server config / FeatureKeys (dotted paths flatten
// into nested maps here).
//
// ponytail: a plain Dart map, because hot reload re-evaluates it on every save.
// A JSON asset can't do this — rootBundle reads it once at startup and caches.
const Map<String, dynamic> devConfig = {
  'modules': {
    'orders': true,
    'masters': true,
    'inventory': true,
    'production': true,
    'pm': true,
    'jobs': true,
    'delivery_challans': true,
  },
  'orders': {
    // Change this and save — the orders board recolors live. Proof it works.
    'statusColors': {
      'pending': '#FF00AA',
    },
    'allowCustomActions': true,
    'allowOrdersCreation': true,
  },
  'features': {
    'disableMachineCustomFields': false,
  },
  // 2026 catalog & inventory enhancement bundle (group-scoped item picker,
  // combination groups, measurable units, primary-unit cleanup, movement audit
  // trail). Only honoured in offline dev mode; for a real backend run, enable
  // "Catalog & Inventory Enhancements" for the client in the dashboard instead.
  'enhancements': {
    'catalogInventory': true,
  },
};
