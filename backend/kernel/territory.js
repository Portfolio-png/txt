'use strict';

// ---------------------------------------------------------------------------
// Territory meter (kernel rule K3).
//
// Reports how much of the app is governed by module manifests vs still living
// as unmanifested legacy. Two dimensions:
//   - declared:  a manifest claims the route segment / table
//   - evacuated: the module's code actually lives in modules/<name>/ (none yet)
// Unclaimed territory is a warning condition, not a norm — this report is the
// burn-down chart for the evacuation.
// ---------------------------------------------------------------------------

const registry = require('./registry');

// Path segments that belong to the kernel itself (auth, permissions, assets,
// infrastructure) rather than to any business module.
const KERNEL_SEGMENTS = new Set([
  ...registry.MODULE_GATE_EXCLUDED_SEGMENTS,
  'kernel',
  // Deployment/ops infrastructure: updater feed, build/activation, factory
  // reset, sandbox fleet sync + replay, SSE events.
  'admin', 'appcast', 'build', 'activation', 'activate',
  'sandbox-dashboard', 'sandbox-sync', 'session-replay', 'events',
]);
// Deliberately NOT kernel: payroll, search, portal, freelancer-jobs,
// freelancer-portal, mobile, production-scrap, company-profile — business
// territory no manifest claims yet. They stay in the unclaimed report until a
// module declares them.

// Tables owned by the kernel (identity, sessions, permissions, assets, config,
// sync/replay infrastructure, search telemetry, activity log).
const KERNEL_TABLES = new Set([
  'users', 'auth_sessions', 'auth_events',
  'role_permissions', 'user_permission_overrides', 'user_permission_templates',
  'permission_templates', 'permission_template_permissions', 'user_record_permissions',
  'company_profiles', 'uploaded_assets', 'asset_upload_sessions',
  'sandbox_activated_machines', 'sandbox_client_configs', 'sandbox_client_pins',
  'sandbox_client_users', 'sandbox_replays', 'sandbox_sync_states',
  'search_history', 'search_clicks', 'entity_activity_log',
]);

function collectExpressRoutes(app) {
  const routes = [];
  // Express 5 exposes the layer stack on app.router; Express 4 on app._router.
  const router = app && (app.router || app._router);
  const stack = router && router.stack;
  if (!Array.isArray(stack)) {
    return routes;
  }
  for (const layer of stack) {
    if (layer.route && layer.route.path) {
      const methods = Object.keys(layer.route.methods || {})
        .filter((m) => m !== '_all')
        .map((m) => m.toUpperCase());
      const paths = Array.isArray(layer.route.path) ? layer.route.path : [layer.route.path];
      for (const p of paths) {
        for (const method of methods) {
          routes.push({ method, path: String(p) });
        }
      }
    }
  }
  return routes;
}

function moduleForApiPath(routePath) {
  if (!routePath.startsWith('/api/')) {
    return { kind: 'non-api' };
  }
  const segment = routePath.slice('/api/'.length).split('/')[0] || '';
  if (/^\/api\/production\/pipeline-templates/.test(routePath)) {
    return { kind: 'module', module: 'pipelines' };
  }
  const moduleKey = registry.PATH_SEGMENT_TO_MODULE[segment];
  if (moduleKey) {
    return { kind: 'module', module: moduleKey };
  }
  if (KERNEL_SEGMENTS.has(segment)) {
    return { kind: 'kernel', segment };
  }
  return { kind: 'unclaimed', segment };
}

async function computeTerritory({ app, allRows, runtime = {} }) {
  const routes = collectExpressRoutes(app).filter((r) => r.path.startsWith('/api/'));
  const perModule = {};
  for (const moduleKey of registry.CRUD_MODULES) {
    perModule[moduleKey] = {
      label: registry.MODULE_LABELS[moduleKey],
      evacuated: Boolean(registry.MODULES[moduleKey].evacuated),
      routes: 0,
      declaredTables: registry.MODULES[moduleKey].tables || [],
      tablesPresent: [],
      // Live per-port call counts (and any other runtime signals) supplied by
      // the boot code — how much cross-border traffic each module serves.
      ...(runtime[moduleKey] ? { runtime: runtime[moduleKey] } : {}),
    };
  }

  let kernelRoutes = 0;
  const unclaimedRouteSegments = new Map();
  for (const route of routes) {
    const owner = moduleForApiPath(route.path);
    if (owner.kind === 'module') {
      perModule[owner.module].routes += 1;
    } else if (owner.kind === 'kernel') {
      kernelRoutes += 1;
    } else if (owner.kind === 'unclaimed') {
      unclaimedRouteSegments.set(
        owner.segment,
        (unclaimedRouteSegments.get(owner.segment) || 0) + 1,
      );
    }
  }

  const tableRows = await allRows(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    [],
  );
  const tables = tableRows.map((row) => row.name);
  const declaredTableOwner = {};
  for (const moduleKey of registry.CRUD_MODULES) {
    for (const table of registry.MODULES[moduleKey].tables || []) {
      declaredTableOwner[table] = moduleKey;
    }
  }
  const unclaimedTables = [];
  let kernelTables = 0;
  for (const table of tables) {
    const owner = declaredTableOwner[table];
    if (owner) {
      perModule[owner].tablesPresent.push(table);
    } else if (KERNEL_TABLES.has(table)) {
      kernelTables += 1;
    } else {
      unclaimedTables.push(table);
    }
  }

  const claimedRoutes = Object.values(perModule).reduce((sum, m) => sum + m.routes, 0);
  const unclaimedRoutes = [...unclaimedRouteSegments.values()].reduce((a, b) => a + b, 0);
  const evacuatedModules = registry.CRUD_MODULES.filter(
    (m) => registry.MODULES[m].evacuated,
  );

  return {
    generatedAt: new Date().toISOString(),
    summary: {
      routes: {
        total: routes.length,
        claimedByModules: claimedRoutes,
        kernel: kernelRoutes,
        unclaimed: unclaimedRoutes,
      },
      tables: {
        total: tables.length,
        claimedByModules: tables.length - unclaimedTables.length - kernelTables,
        kernel: kernelTables,
        unclaimed: unclaimedTables.length,
      },
      evacuation: {
        modulesTotal: registry.CRUD_MODULES.length,
        modulesEvacuated: evacuatedModules.length,
        evacuated: evacuatedModules,
      },
    },
    modules: perModule,
    unclaimed: {
      routeSegments: Object.fromEntries(unclaimedRouteSegments),
      tables: unclaimedTables,
    },
  };
}

module.exports = { computeTerritory, collectExpressRoutes, moduleForApiPath };
