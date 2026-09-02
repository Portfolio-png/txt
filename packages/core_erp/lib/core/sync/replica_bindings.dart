/// How a change lands.
///
/// The server announces `(table, record_id)`. Turning that into "which local
/// row, fetched how" is the part where a naive engine silently corrupts the
/// replica, so the whole map is data rather than branches — a wrong entry is
/// then a visible line, and a missing one is a compile-time hole rather than a
/// silent fallthrough.
enum DeltaStrategy {
  /// Fetch the one record by the id the trigger gave us, and upsert it.
  fetchById,

  /// The trigger's key is not the endpoint's key. Look the real key up in the
  /// replica first. Only `materials`: the trigger writes `NEW.id` while
  /// `/api/materials/:barcode` is keyed by barcode.
  fetchByBarcode,

  /// No by-id endpoint. Resolve the parent locally and refresh that instead —
  /// a variation node has no endpoint of its own, but the item that embeds it
  /// does.
  viaParent,

  /// No by-id endpoint and no parent. Refetch the whole list; these are the
  /// small flat ones where that costs a few hundred bytes.
  refetchList,

  /// Cannot be applied, and pretending otherwise is worse than skipping.
  ignore,
}

class ReplicaBinding {
  const ReplicaBinding({
    required this.serverTable,
    required this.strategy,
    this.localTable,
    this.keyColumn = 'id',
    this.keyIsText = false,
    this.parentTable,
    this.parentIdColumn,
    required this.why,
  });

  final String serverTable;
  final DeltaStrategy strategy;

  /// Null for [DeltaStrategy.ignore] and [DeltaStrategy.viaParent] — neither
  /// writes a row of its own.
  final String? localTable;

  final String keyColumn;

  /// pipeline_templates.id is `sheet-metal-flow`; pipeline_runs.id is
  /// `demo-dolly-run-active`. Coercing those to integers maps every one onto 0.
  final bool keyIsText;

  /// For [DeltaStrategy.viaParent]: which server table to refresh instead, and
  /// which column of the local mirror holds its id.
  final String? parentTable;
  final String? parentIdColumn;

  /// Why this strategy and not another. Kept on the binding because the
  /// reasoning is the part that rots.
  final String why;
}

/// Every table the changelog announces.
///
/// Nine have a clean by-id GET. Four needed a fallback. Four are mismatched in
/// ways an engine that assumed `GET /api/<table>/<record_id>` would not notice —
/// it would 404, or worse, fetch a different record.
const Map<String, ReplicaBinding> kReplicaBindings = <String, ReplicaBinding>{
  'items': ReplicaBinding(
    serverTable: 'items',
    localTable: 'local_items',
    strategy: DeltaStrategy.fetchById,
    why: 'GET /api/items/:id runs the same rowToItemDto as the list, so one '
        'record is shape-identical to a list element.',
  ),
  'item_variation_nodes': ReplicaBinding(
    serverTable: 'item_variation_nodes',
    strategy: DeltaStrategy.viaParent,
    parentTable: 'items',
    parentIdColumn: 'item_id',
    why: 'No endpoint fetches a variation node. The tree is nested inside the '
        'item payload anyway, so refreshing the item is both the only way and '
        'the right one.',
  ),
  'delivery_challans': ReplicaBinding(
    serverTable: 'delivery_challans',
    localTable: 'local_delivery_challans',
    strategy: DeltaStrategy.fetchById,
    why: 'GET /api/challans/:id returns the full record including its lines.',
  ),
  'delivery_challan_items': ReplicaBinding(
    serverTable: 'delivery_challan_items',
    strategy: DeltaStrategy.ignore,
    why: 'The trigger key is a LINE id, not a challan id — feeding it to '
        '/api/challans/:id would fetch a DIFFERENT challan. Migration 041 '
        'already announces the parent challan, so that event does the work.',
  ),
  'order_items': ReplicaBinding(
    serverTable: 'order_items',
    localTable: 'local_order_items',
    strategy: DeltaStrategy.fetchById,
    why: 'GET /api/orders/:id, added for exactly this. Same projection as the '
        'list, including the derived status and totalDeliveredQty.',
  ),
  'order_headers': ReplicaBinding(
    serverTable: 'order_headers',
    strategy: DeltaStrategy.ignore,
    why: 'Keyed by order_no (TEXT), no endpoint serves it, and nothing mirrors '
        'it — the app\'s notion of an order is an order_items row. Passing the '
        'text key to /api/orders?ids= used to return the ENTIRE table.',
  ),
  'materials': ReplicaBinding(
    serverTable: 'materials',
    localTable: 'local_materials',
    strategy: DeltaStrategy.fetchByBarcode,
    why: 'The trigger writes NEW.id; /api/materials/:barcode is keyed by '
        'barcode. An id passed straight through 404s — or silently returns a '
        'different material, if some vendor barcode happens to be that number.',
  ),
  'inventory_stock_positions': ReplicaBinding(
    serverTable: 'inventory_stock_positions',
    strategy: DeltaStrategy.ignore,
    why: 'No endpoint anywhere emits this id, so there is nothing to fetch. '
        'Stock reaches the replica through the materials it belongs to.',
  ),
  'groups': ReplicaBinding(
    serverTable: 'groups',
    localTable: 'local_groups',
    strategy: DeltaStrategy.refetchList,
    why: 'No bare by-id endpoint, and the list is ~1.4 KB. A refetch is '
        'cheaper than the machinery to avoid one.',
  ),
  'units': ReplicaBinding(
    serverTable: 'units',
    localTable: 'local_units',
    strategy: DeltaStrategy.refetchList,
    why: 'No by-id endpoint; the list is ~3.7 KB.',
  ),
  'departments': ReplicaBinding(
    serverTable: 'departments',
    localTable: 'local_departments',
    strategy: DeltaStrategy.refetchList,
    why: 'No by-id endpoint; the list is ~1 KB.',
  ),
  'clients': ReplicaBinding(
    serverTable: 'clients',
    localTable: 'local_clients',
    strategy: DeltaStrategy.fetchById,
    why: 'GET /api/clients/:id.',
  ),
  'vendors': ReplicaBinding(
    serverTable: 'vendors',
    localTable: 'local_vendors',
    strategy: DeltaStrategy.fetchById,
    why: 'GET /api/vendors/:id.',
  ),
  'machines': ReplicaBinding(
    serverTable: 'machines',
    localTable: 'local_machines',
    strategy: DeltaStrategy.fetchById,
    why: 'GET /api/machines/:id.',
  ),
  'dies': ReplicaBinding(
    serverTable: 'dies',
    localTable: 'local_dies',
    strategy: DeltaStrategy.fetchById,
    why: 'GET /api/dies/:id.',
  ),
  'pipeline_templates': ReplicaBinding(
    serverTable: 'pipeline_templates',
    localTable: 'local_pipeline_templates',
    strategy: DeltaStrategy.fetchById,
    keyIsText: true,
    why: 'GET /templates/:id. The id is text (`sheet-metal-flow`).',
  ),
  'pipeline_runs': ReplicaBinding(
    serverTable: 'pipeline_runs',
    localTable: 'local_pipeline_runs',
    strategy: DeltaStrategy.fetchById,
    keyIsText: true,
    why: 'GET /runs/:id. The id is text (`demo-dolly-run-active`).',
  ),
};
