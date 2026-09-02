import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The local read replica.
///
/// Reads are served from here rather than from the network, so a screen paints
/// from disk at launch instead of waiting on a request. The server is still the
/// source of truth; this is a copy of it kept current by replaying the
/// changelog.
///
/// **Every table stores the server's payload verbatim** in `raw_payload_json`
/// alongside a few extracted columns. The extracted ones exist to filter and
/// sort in SQL — the list screens need `name`, `challan_no`, `status` — and the
/// payload exists so a row can be handed back to the same `fromJson` the
/// network path uses. Without it, every new field the server learns to send
/// would need a migration here before the app could see it, and the replica
/// would quietly serve a subset of the truth.
///
/// The grain matches the endpoints exactly, which is why orders are stored as
/// **`local_order_items`**: `/api/orders` selects `FROM order_items`, one row
/// per order line with a status computed from its pipeline runs. A table of
/// order *headers* would mirror something the app never reads.
class LocalDatabaseHelper {
  LocalDatabaseHelper._();

  static final LocalDatabaseHelper instance = LocalDatabaseHelper._();

  static const int schemaVersion = 1;

  Database? _database;
  String? _namespace;

  /// Whose replica this is.
  ///
  /// A shared workshop machine may have several people signing in, and one
  /// person's workspace must not be served to the next — permissions differ, so
  /// the rows differ. Separate files rather than a discriminator column: a
  /// forgotten `WHERE user_id = ?` would leak silently, a separate file cannot.
  Future<void> useNamespace(String namespace) async {
    final next = namespace.trim().isEmpty ? 'anonymous' : namespace.trim();
    if (next == _namespace) return;
    await close();
    _namespace = next;
  }

  Future<Database> get database async {
    final existing = _database;
    if (existing != null) return existing;
    final opened = await _open();
    _database = opened;
    return opened;
  }

  Future<Database> _open() async {
    // sqflite has no desktop implementation; the FFI one has to be installed
    // before the first open. Done here rather than in the app's startup so the
    // package does not depend on being initialised in the right order.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final directory = await getApplicationSupportDirectory();
    final path = p.join(
      directory.path,
      'replica',
      _namespace ?? 'anonymous',
      'paper_local.db',
    );
    await Directory(p.dirname(path)).create(recursive: true);
    return openDatabase(
      path,
      version: schemaVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async => _createSchema(db),
    );
  }

  Future<void> _createSchema(Database db) async {
    for (final statement in schemaStatements) {
      await db.execute(statement);
    }
  }

  Future<void> close() async {
    final open = _database;
    _database = null;
    await open?.close();
  }

  /// Deletes the replica. Used when it cannot be trusted — a schema the app no
  /// longer understands, or a cursor pointing at history the server has pruned.
  /// Recovery is always available because the server can rebuild it.
  Future<void> destroy() async {
    final directory = await getApplicationSupportDirectory();
    final path = p.join(directory.path, 'replica', _namespace ?? 'anonymous');
    await close();
    final folder = Directory(path);
    if (folder.existsSync()) {
      await folder.delete(recursive: true);
    }
  }

  /// The replica's schema.
  ///
  /// Exposed so tests can build the same tables against an in-memory database
  /// without touching the filesystem.
  static const List<String> schemaStatements = <String>[
    // Where the replay is up to, and anything else the sync needs to remember
    // across restarts. Without this the app re-downloads the workspace on every
    // launch, which is the thing being fixed.
    '''
    CREATE TABLE IF NOT EXISTS sync_metadata (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',

    '''
    CREATE TABLE IF NOT EXISTS local_items (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      display_name TEXT NOT NULL DEFAULT '',
      short_code TEXT NOT NULL DEFAULT '',
      group_id INTEGER,
      unit_id INTEGER,
      is_archived INTEGER NOT NULL DEFAULT 0,
      raw_payload_json TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT ''
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_local_items_name ON local_items(name)',
    'CREATE INDEX IF NOT EXISTS idx_local_items_group ON local_items(group_id)',

    // Stored separately from the item, because a variation tree is read on its
    // own by every picker in the app and is 59% of the items payload.
    '''
    CREATE TABLE IF NOT EXISTS local_item_variation_nodes (
      id INTEGER PRIMARY KEY,
      item_id INTEGER NOT NULL,
      parent_node_id INTEGER,
      kind TEXT NOT NULL DEFAULT '',
      name TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      raw_payload_json TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_local_variation_item ON local_item_variation_nodes(item_id)',

    '''
    CREATE TABLE IF NOT EXISTS local_groups (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      parent_group_id INTEGER,
      group_type TEXT NOT NULL DEFAULT '',
      group_structure TEXT NOT NULL DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      raw_payload_json TEXT NOT NULL
    )
    ''',

    // Order LINES, matching /api/orders. Not headers.
    '''
    CREATE TABLE IF NOT EXISTS local_order_items (
      id INTEGER PRIMARY KEY,
      order_no TEXT NOT NULL DEFAULT '',
      client_id INTEGER,
      client_name TEXT NOT NULL DEFAULT '',
      item_id INTEGER,
      item_name TEXT NOT NULL DEFAULT '',
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      variation_path_label TEXT NOT NULL DEFAULT '',
      po_number TEXT NOT NULL DEFAULT '',
      client_code TEXT NOT NULL DEFAULT '',
      quantity REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_local_orders_client ON local_order_items(client_id)',
    'CREATE INDEX IF NOT EXISTS idx_local_orders_status ON local_order_items(status)',
    'CREATE INDEX IF NOT EXISTS idx_local_orders_created ON local_order_items(created_at)',

    '''
    CREATE TABLE IF NOT EXISTS local_delivery_challans (
      id INTEGER PRIMARY KEY,
      challan_no TEXT NOT NULL DEFAULT '',
      challan_date TEXT NOT NULL DEFAULT '',
      type TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT '',
      customer_name TEXT NOT NULL DEFAULT '',
      vendor_name TEXT NOT NULL DEFAULT '',
      order_no TEXT NOT NULL DEFAULT '',
      line_count INTEGER NOT NULL DEFAULT 0,
      total_qty REAL NOT NULL DEFAULT 0,
      total_weight REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_local_challans_no ON local_delivery_challans(challan_no)',
    'CREATE INDEX IF NOT EXISTS idx_local_challans_type ON local_delivery_challans(type)',

    // Lines are fetched with their challan, so they are stored with it — but in
    // their own table, because the list view does not want them and a join is
    // cheaper than parsing a nested array to count rows.
    '''
    CREATE TABLE IF NOT EXISTS local_delivery_challan_items (
      id INTEGER PRIMARY KEY,
      challan_id INTEGER NOT NULL,
      line_no INTEGER NOT NULL DEFAULT 0,
      particulars TEXT NOT NULL DEFAULT '',
      item_id INTEGER,
      quantity_pcs REAL NOT NULL DEFAULT 0,
      weight REAL NOT NULL DEFAULT 0,
      lot_code TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL,
      FOREIGN KEY (challan_id) REFERENCES local_delivery_challans(id) ON DELETE CASCADE
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_local_challan_items_challan ON local_delivery_challan_items(challan_id)',

    '''
    CREATE TABLE IF NOT EXISTS local_materials (
      id INTEGER PRIMARY KEY,
      barcode TEXT NOT NULL DEFAULT '',
      name TEXT NOT NULL DEFAULT '',
      type TEXT NOT NULL DEFAULT '',
      -- The list endpoint orders by `kind ASC, created_at DESC, barcode ASC`,
      -- so both are stored: without them the replica lists materials in a
      -- different order from the server for no reason a user could explain.
      -- `kind` was not on the DTO until the replica needed it.
      kind TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL DEFAULT '',
      linked_item_id INTEGER,
      linked_variation_leaf_node_id INTEGER,
      inventory_state TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_local_materials_barcode ON local_materials(barcode)',

    '''
    CREATE TABLE IF NOT EXISTS local_clients (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      -- The server calls it gstNumber, not gstin. Named to match, so the
      -- mapping is obvious and an extractor reading the wrong key is visible
      -- rather than silently storing empty strings.
      gst_number TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS local_vendors (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      gst_number TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS local_machines (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT '',
      location TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
    '''
    -- A die has no name. dieRowToDto emits toolCode, status, ownership and the
    -- rest; identity is the tool code. A `name` column here would have been
    -- permanently empty and anything sorting on it would have sorted on nothing.
    CREATE TABLE IF NOT EXISTS local_dies (
      id INTEGER PRIMARY KEY,
      tool_code TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT '',
      ownership TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS local_units (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      symbol TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS local_departments (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
    // Text-keyed on the server, so text-keyed here.
    '''
    CREATE TABLE IF NOT EXISTS local_pipeline_templates (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS local_pipeline_runs (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT '',
      template_id TEXT NOT NULL DEFAULT '',
      raw_payload_json TEXT NOT NULL
    )
    ''',
  ];
}
