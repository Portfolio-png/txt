CREATE TABLE materials (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      barcode TEXT NOT NULL UNIQUE,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      grade TEXT,
      thickness TEXT,
      supplier TEXT,
      unit TEXT,
      notes TEXT,
      created_at TEXT NOT NULL,
      kind TEXT NOT NULL,
      parent_barcode TEXT,
      number_of_children INTEGER NOT NULL DEFAULT 0,
      linked_child_barcodes TEXT,
      scan_count INTEGER NOT NULL DEFAULT 0
    , unit_id INTEGER, linked_group_id INTEGER, linked_item_id INTEGER, display_stock TEXT DEFAULT '', created_by TEXT DEFAULT '', workflow_status TEXT DEFAULT 'notStarted', location TEXT DEFAULT '', group_mode TEXT, inheritance_enabled INTEGER NOT NULL DEFAULT 0, material_class TEXT DEFAULT 'raw_material', inventory_state TEXT DEFAULT 'available', procurement_state TEXT DEFAULT 'not_ordered', traceability_mode TEXT DEFAULT 'bulk', on_hand_qty REAL NOT NULL DEFAULT 0, reserved_qty REAL NOT NULL DEFAULT 0, available_to_promise_qty REAL NOT NULL DEFAULT 0, incoming_qty REAL NOT NULL DEFAULT 0, linked_order_count INTEGER NOT NULL DEFAULT 0, linked_pipeline_count INTEGER NOT NULL DEFAULT 0, pending_alert_count INTEGER NOT NULL DEFAULT 0, updated_at TEXT, last_scanned_at TEXT, linked_variation_leaf_node_id INTEGER);
CREATE TABLE sqlite_sequence(name,seq);
CREATE TABLE pipeline_templates (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT DEFAULT '',
      version INTEGER NOT NULL DEFAULT 1,
      status TEXT DEFAULT 'draft',
      stage_labels_json TEXT NOT NULL,
      lane_labels_json TEXT NOT NULL,
      nodes_json TEXT NOT NULL,
      flows_json TEXT NOT NULL,
      created_at TEXT DEFAULT (datetime('now')),
      updated_at TEXT DEFAULT (datetime('now'))
    , factory_id TEXT DEFAULT '', shop_floor_id TEXT DEFAULT '', intermediate_naming_convention TEXT DEFAULT '');
CREATE TABLE pipeline_runs (
      id TEXT PRIMARY KEY,
      template_id TEXT NOT NULL REFERENCES pipeline_templates(id),
      template_version INTEGER NOT NULL,
      name TEXT,
      status TEXT DEFAULT 'planned',
      overrides_json TEXT,
      node_status_json TEXT,
      started_at TEXT,
      completed_at TEXT,
      created_at TEXT DEFAULT (datetime('now'))
    );
CREATE TABLE run_barcode_inputs (
      id TEXT PRIMARY KEY,
      run_id TEXT NOT NULL REFERENCES pipeline_runs(id),
      node_id TEXT NOT NULL,
      barcode TEXT NOT NULL,
      material_id TEXT,
      material_payload_json TEXT NOT NULL,
      scanned_at TEXT DEFAULT (datetime('now'))
    );
CREATE TABLE units (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      symbol TEXT NOT NULL,
      notes TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    , unit_group_id INTEGER, conversion_factor REAL NOT NULL DEFAULT 1, conversion_base_unit_id INTEGER);
CREATE TABLE groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      parent_group_id INTEGER REFERENCES groups(id),
      unit_id INTEGER NOT NULL REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      display_name TEXT NOT NULL,
      group_id INTEGER NOT NULL REFERENCES groups(id),
      unit_id INTEGER NOT NULL REFERENCES units(id),
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    , quantity REAL NOT NULL DEFAULT 0, naming_format TEXT NOT NULL DEFAULT '');
CREATE TABLE item_variations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      display_name TEXT NOT NULL,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE clients (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      gst_number TEXT DEFAULT '',
      address TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    , logo_url TEXT DEFAULT '', photo_url TEXT DEFAULT '');
CREATE TABLE item_variation_dimensions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      position INTEGER NOT NULL DEFAULT 0
    );
CREATE TABLE item_variation_values (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      variation_id INTEGER NOT NULL REFERENCES item_variations(id) ON DELETE CASCADE,
      dimension_id INTEGER NOT NULL REFERENCES item_variation_dimensions(id) ON DELETE CASCADE,
      value TEXT NOT NULL
    );
CREATE TABLE item_variation_nodes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      parent_node_id INTEGER REFERENCES item_variation_nodes(id) ON DELETE CASCADE,
      kind TEXT NOT NULL,
      name TEXT NOT NULL,
      display_name TEXT NOT NULL DEFAULT '',
      position INTEGER NOT NULL DEFAULT 0,
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    , code TEXT NOT NULL DEFAULT '');
CREATE TABLE orders (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_no TEXT NOT NULL,
      client_id INTEGER NOT NULL REFERENCES clients(id),
      client_name TEXT NOT NULL DEFAULT '',
      po_number TEXT DEFAULT '',
      client_code TEXT DEFAULT '',
      item_id INTEGER NOT NULL REFERENCES items(id),
      item_name TEXT NOT NULL DEFAULT '',
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      variation_path_label TEXT DEFAULT '',
      variation_path_node_ids_json TEXT NOT NULL DEFAULT '[]',
      quantity INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'notStarted',
      created_at TEXT NOT NULL,
      start_date TEXT,
      end_date TEXT
    , previous_status TEXT, hold_reason TEXT, cancel_reason TEXT, confirmed_at TEXT, allocated_at TEXT, production_started_at TEXT, completed_at TEXT, dispatched_at TEXT, closed_at TEXT, updated_by TEXT DEFAULT 'system', priority TEXT NOT NULL DEFAULT 'normal', updated_at TEXT NOT NULL DEFAULT '', unit_price REAL NOT NULL DEFAULT 0, total_invoiced_qty REAL NOT NULL DEFAULT 0, unit_id INTEGER, unit_name TEXT NOT NULL DEFAULT 'Pieces', unit_symbol TEXT NOT NULL DEFAULT 'Pieces');
CREATE TABLE unit_groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE scan_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      barcode TEXT NOT NULL,
      scanned_at TEXT NOT NULL
    );
CREATE TABLE material_activity (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      barcode TEXT NOT NULL,
      event_type TEXT NOT NULL,
      event_label TEXT NOT NULL,
      event_description TEXT DEFAULT '',
      actor TEXT DEFAULT '',
      created_at TEXT NOT NULL
    );
CREATE TABLE users (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      email TEXT NOT NULL UNIQUE,
      password_hash TEXT NOT NULL,
      role TEXT NOT NULL,
      is_active INTEGER NOT NULL DEFAULT 1,
      failed_login_attempts INTEGER NOT NULL DEFAULT 0,
      first_failed_login_at TEXT,
      lockout_until TEXT,
      last_login_at TEXT,
      last_login_ip TEXT DEFAULT '',
      created_by_user_id INTEGER REFERENCES users(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE auth_sessions (
      id TEXT PRIMARY KEY,
      user_id INTEGER NOT NULL REFERENCES users(id),
      token_hash TEXT NOT NULL,
      created_at TEXT NOT NULL,
      last_used_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      revoked_at TEXT,
      revoked_reason TEXT DEFAULT '',
      ip_address TEXT DEFAULT '',
      user_agent TEXT DEFAULT ''
    );
CREATE INDEX idx_auth_sessions_user ON auth_sessions(user_id);
CREATE INDEX idx_auth_sessions_revoked ON auth_sessions(revoked_at);
CREATE TABLE delete_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      entity_label TEXT DEFAULT '',
      reason TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending',
      requested_by_user_id INTEGER NOT NULL REFERENCES users(id),
      reviewed_by_user_id INTEGER REFERENCES users(id),
      reviewed_at TEXT,
      created_at TEXT NOT NULL
    , reviewed_note TEXT DEFAULT '');
CREATE TABLE auth_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_type TEXT NOT NULL,
      actor_user_id INTEGER REFERENCES users(id),
      target_user_id INTEGER REFERENCES users(id),
      ip_address TEXT DEFAULT '',
      user_agent TEXT DEFAULT '',
      metadata_json TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL
    );
CREATE INDEX idx_auth_events_created ON auth_events(created_at);
CREATE INDEX idx_auth_events_target ON auth_events(target_user_id);
CREATE TABLE material_group_item_links (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL REFERENCES materials(id),
      item_id INTEGER NOT NULL REFERENCES items(id),
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(material_id, item_id)
    );
CREATE TABLE material_group_properties (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL REFERENCES materials(id),
      property_key TEXT NOT NULL,
      display_name TEXT NOT NULL,
      input_type TEXT NOT NULL DEFAULT 'Text',
      mandatory INTEGER NOT NULL DEFAULT 0,
      source_type TEXT NOT NULL DEFAULT 'manual',
      source_item_ids_json TEXT NOT NULL DEFAULT '[]',
      state TEXT NOT NULL DEFAULT 'active',
      override_locked INTEGER NOT NULL DEFAULT 0,
      has_type_conflict INTEGER NOT NULL DEFAULT 0,
      coverage_count INTEGER NOT NULL DEFAULT 0,
      selected_item_count_at_resolution INTEGER NOT NULL DEFAULT 0,
      resolution_source TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL, unit_id INTEGER, unit_symbol TEXT, unit_label TEXT, source_group_id INTEGER, source_group_name TEXT,
      UNIQUE(material_id, property_key)
    );
CREATE TABLE material_group_units (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL REFERENCES materials(id),
      unit_id INTEGER NOT NULL REFERENCES units(id),
      state TEXT NOT NULL DEFAULT 'active',
      is_primary INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(material_id, unit_id)
    );
CREATE TABLE material_group_preferences (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_id INTEGER NOT NULL REFERENCES materials(id),
      common_only_mode INTEGER NOT NULL DEFAULT 1,
      show_partial_matches INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL, discarded_property_keys_json TEXT NOT NULL DEFAULT '[]',
      UNIQUE(material_id)
    );
CREATE TABLE inventory_stock_positions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_barcode TEXT NOT NULL,
      location_id TEXT NOT NULL DEFAULT 'MAIN',
      lot_code TEXT NOT NULL DEFAULT '',
      unit_id INTEGER,
      on_hand_qty REAL NOT NULL DEFAULT 0,
      reserved_qty REAL NOT NULL DEFAULT 0,
      damaged_qty REAL NOT NULL DEFAULT 0,
      updated_at TEXT NOT NULL,
      UNIQUE(material_barcode, location_id, lot_code)
    );
CREATE TABLE inventory_movements (
      id TEXT PRIMARY KEY,
      material_barcode TEXT NOT NULL,
      movement_type TEXT NOT NULL,
      qty REAL NOT NULL,
      from_location_id TEXT,
      to_location_id TEXT,
      reason_code TEXT,
      reference_type TEXT,
      reference_id TEXT,
      actor TEXT DEFAULT '',
      lot_code TEXT DEFAULT '',
      created_at TEXT NOT NULL
    , source_challan_id INTEGER, source_challan_type TEXT, source_challan_line_id INTEGER, primary_qty REAL, uom TEXT, reverses_movement_id TEXT);
CREATE TABLE inventory_reservations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_barcode TEXT NOT NULL,
      reference_type TEXT NOT NULL,
      reference_id TEXT NOT NULL,
      reserved_qty REAL NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE inventory_alerts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      material_barcode TEXT NOT NULL,
      alert_type TEXT NOT NULL,
      severity TEXT NOT NULL DEFAULT 'warning',
      message TEXT NOT NULL DEFAULT '',
      is_open INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE role_permissions (
      role TEXT NOT NULL,
      permission_key TEXT NOT NULL,
      is_allowed INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(role, permission_key)
    );
CREATE TABLE user_permission_overrides (
      user_id INTEGER NOT NULL REFERENCES users(id),
      permission_key TEXT NOT NULL,
      is_allowed INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(user_id, permission_key)
    );
CREATE INDEX idx_user_permission_overrides_user ON user_permission_overrides(user_id);
CREATE TABLE permission_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      description TEXT DEFAULT '',
      is_system_default INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE permission_template_permissions (
      template_id INTEGER NOT NULL REFERENCES permission_templates(id),
      permission_key TEXT NOT NULL,
      is_allowed INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY(template_id, permission_key)
    );
CREATE TABLE user_permission_templates (
      user_id INTEGER NOT NULL REFERENCES users(id),
      template_id INTEGER NOT NULL REFERENCES permission_templates(id),
      created_at TEXT NOT NULL,
      PRIMARY KEY(user_id, template_id)
    );
CREATE INDEX idx_user_permission_templates_user ON user_permission_templates(user_id);
CREATE TABLE order_activity_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      event_type TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT DEFAULT '',
      actor_user_id INTEGER REFERENCES users(id),
      actor_name TEXT DEFAULT '',
      actor_role TEXT DEFAULT '',
      old_value TEXT,
      new_value TEXT,
      metadata_json TEXT DEFAULT '{}',
      source TEXT DEFAULT 'api',
      created_at TEXT NOT NULL
    , activity_type TEXT NOT NULL DEFAULT '', details_json TEXT);
CREATE INDEX idx_order_activity_log_order_id ON order_activity_log(order_id, created_at DESC);
CREATE TABLE item_bom_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      material_barcode TEXT NOT NULL,
      material_name TEXT DEFAULT '',
      quantity_per_unit REAL NOT NULL DEFAULT 1,
      wastage_percent REAL NOT NULL DEFAULT 0,
      unit_id INTEGER REFERENCES units(id),
      unit_symbol TEXT DEFAULT '',
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, material_barcode)
    );
CREATE TABLE order_material_requirements (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      material_barcode TEXT NOT NULL,
      material_name TEXT DEFAULT '',
      required_qty REAL NOT NULL DEFAULT 0,
      allocated_qty REAL NOT NULL DEFAULT 0,
      consumed_qty REAL NOT NULL DEFAULT 0,
      available_qty REAL NOT NULL DEFAULT 0,
      shortage_qty REAL NOT NULL DEFAULT 0,
      unit_id INTEGER REFERENCES units(id),
      unit_symbol TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'pending',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(order_id, material_barcode)
    );
CREATE TABLE order_material_allocations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      requirement_id INTEGER NOT NULL REFERENCES order_material_requirements(id) ON DELETE CASCADE,
      material_barcode TEXT NOT NULL,
      allocated_qty REAL NOT NULL DEFAULT 0,
      consumed_qty REAL NOT NULL DEFAULT 0,
      reservation_id INTEGER REFERENCES inventory_reservations(id),
      status TEXT NOT NULL DEFAULT 'active',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE INDEX idx_item_bom_lines_item_id ON item_bom_lines(item_id, sort_order ASC, id ASC);
CREATE INDEX idx_order_material_requirements_order_id ON order_material_requirements(order_id, id ASC);
CREATE INDEX idx_order_material_allocations_order_id ON order_material_allocations(order_id, id ASC);
CREATE TABLE procurement_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      request_number TEXT NOT NULL UNIQUE,
      supplier_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'draft',
      expected_date TEXT,
      notes TEXT DEFAULT '',
      cancel_reason TEXT,
      created_by_user_id INTEGER REFERENCES users(id),
      created_by_name TEXT DEFAULT '',
      created_by_role TEXT DEFAULT '',
      raised_by_user_id INTEGER REFERENCES users(id),
      raised_by_name TEXT DEFAULT '',
      raised_by_role TEXT DEFAULT '',
      cancelled_by_user_id INTEGER REFERENCES users(id),
      cancelled_by_name TEXT DEFAULT '',
      cancelled_by_role TEXT DEFAULT '',
      closed_by_user_id INTEGER REFERENCES users(id),
      closed_by_name TEXT DEFAULT '',
      closed_by_role TEXT DEFAULT '',
      raised_at TEXT,
      cancelled_at TEXT,
      closed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE procurement_request_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      procurement_request_id INTEGER NOT NULL REFERENCES procurement_requests(id) ON DELETE CASCADE,
      material_barcode TEXT NOT NULL,
      material_name TEXT DEFAULT '',
      requested_qty REAL NOT NULL DEFAULT 0,
      received_qty REAL NOT NULL DEFAULT 0,
      pending_qty REAL NOT NULL DEFAULT 0,
      unit_id INTEGER REFERENCES units(id),
      unit_symbol TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'draft',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(procurement_request_id, material_barcode)
    );
CREATE TABLE procurement_request_line_sources (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      procurement_request_id INTEGER NOT NULL REFERENCES procurement_requests(id) ON DELETE CASCADE,
      procurement_request_line_id INTEGER NOT NULL REFERENCES procurement_request_lines(id) ON DELETE CASCADE,
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      requirement_id INTEGER NOT NULL REFERENCES order_material_requirements(id) ON DELETE CASCADE,
      material_barcode TEXT NOT NULL,
      linked_qty REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      UNIQUE(procurement_request_line_id, requirement_id)
    );
CREATE TABLE procurement_activity_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      procurement_request_id INTEGER NOT NULL REFERENCES procurement_requests(id) ON DELETE CASCADE,
      procurement_request_line_id INTEGER REFERENCES procurement_request_lines(id) ON DELETE CASCADE,
      event_type TEXT NOT NULL,
      title TEXT NOT NULL,
      description TEXT DEFAULT '',
      actor_user_id INTEGER REFERENCES users(id),
      actor_name TEXT DEFAULT '',
      actor_role TEXT DEFAULT '',
      metadata_json TEXT DEFAULT '{}',
      source TEXT DEFAULT 'api',
      created_at TEXT NOT NULL
    );
CREATE INDEX idx_procurement_requests_status ON procurement_requests(status, updated_at DESC);
CREATE INDEX idx_procurement_request_lines_request_id ON procurement_request_lines(procurement_request_id, id ASC);
CREATE INDEX idx_procurement_line_sources_requirement_id ON procurement_request_line_sources(requirement_id, id ASC);
CREATE INDEX idx_procurement_line_sources_request_id ON procurement_request_line_sources(procurement_request_id, id ASC);
CREATE INDEX idx_procurement_activity_request_id ON procurement_activity_log(procurement_request_id, created_at DESC);
CREATE TABLE po_documents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL UNIQUE,
      object_key TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'uploaded',
      created_at TEXT NOT NULL,
      uploaded_at TEXT
    );
CREATE TABLE po_upload_sessions (
      id TEXT PRIMARY KEY,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL,
      object_key TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      expires_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      completed_at TEXT
    );
CREATE TABLE order_po_documents (
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      document_id INTEGER NOT NULL REFERENCES po_documents(id) ON DELETE CASCADE,
      linked_at TEXT NOT NULL,
      PRIMARY KEY (order_id, document_id)
    );
CREATE INDEX idx_order_po_documents_order_id ON order_po_documents(order_id);
CREATE INDEX idx_po_upload_sessions_sha256 ON po_upload_sessions(sha256);
CREATE TABLE company_profiles (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      company_name TEXT NOT NULL,
      mobile TEXT DEFAULT '',
      business_description TEXT DEFAULT '',
      address TEXT DEFAULT '',
      state_code TEXT DEFAULT '',
      gstin TEXT DEFAULT '',
      logo_url TEXT DEFAULT '',
      signature_label TEXT DEFAULT '',
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE delivery_challans (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      challan_no TEXT NOT NULL UNIQUE,
      date TEXT NOT NULL,
      customer_name TEXT NOT NULL DEFAULT '',
      customer_gstin TEXT DEFAULT '',
      company_profile_snapshot TEXT,
      notes TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'draft',
      created_by INTEGER REFERENCES users(id),
      updated_by INTEGER REFERENCES users(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    , order_id INTEGER, order_no TEXT DEFAULT '', type TEXT NOT NULL DEFAULT 'delivery', location TEXT DEFAULT '', vendor_id INTEGER, vendor_name TEXT DEFAULT '', vendor_gstin TEXT DEFAULT '', source_reference TEXT DEFAULT '', template_snapshot_json TEXT, material_owner_client_id INTEGER, material_owner_client_name TEXT DEFAULT '', material_owner_gstin TEXT DEFAULT '', maintain_stocks INTEGER NOT NULL DEFAULT 1, used_in_report INTEGER NOT NULL DEFAULT 0, purpose TEXT NOT NULL DEFAULT 'trading');
CREATE TABLE delivery_challan_activity_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
      activity_type TEXT NOT NULL,
      actor_user_id INTEGER,
      actor_name TEXT,
      actor_role TEXT,
      details_json TEXT,
      created_at TEXT NOT NULL
    );
CREATE INDEX idx_delivery_challans_status ON delivery_challans(status);
CREATE INDEX idx_delivery_challans_date ON delivery_challans(date);
CREATE INDEX idx_delivery_challan_activity_challan_id_created_at ON delivery_challan_activity_log(challan_id, created_at);
CREATE INDEX idx_order_material_requirements_material_barcode ON order_material_requirements(material_barcode);
CREATE INDEX idx_order_activity_log_order_id_created_at ON order_activity_log(order_id, created_at);
CREATE INDEX idx_delivery_challans_order_id ON delivery_challans(order_id);
CREATE TABLE item_unit_conversions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      unit_id INTEGER NOT NULL REFERENCES units(id),
      factor_to_primary REAL NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, unit_id)
    );
CREATE INDEX idx_item_unit_conversions_item_id ON item_unit_conversions(item_id);
CREATE TABLE uploaded_assets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      entity_type TEXT NOT NULL,
      entity_id INTEGER NOT NULL,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL,
      object_key TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'uploaded',
      is_primary INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      uploaded_at TEXT
    );
CREATE TABLE asset_upload_sessions (
      id TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL,
      entity_id INTEGER NOT NULL,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL,
      object_key TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      is_primary INTEGER NOT NULL DEFAULT 0,
      expires_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      completed_at TEXT
    );
CREATE INDEX idx_uploaded_assets_entity ON uploaded_assets(entity_type, entity_id, status, is_primary);
CREATE INDEX idx_asset_upload_sessions_entity ON asset_upload_sessions(entity_type, entity_id);
CREATE TABLE delivery_challan_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
        order_item_id INTEGER,
        item_id INTEGER,
        line_no INTEGER NOT NULL DEFAULT 1,
        particulars TEXT NOT NULL DEFAULT '',
        hsn_code TEXT DEFAULT '',
        quantity_pcs REAL NOT NULL DEFAULT 0,
        weight REAL NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      , variation_leaf_node_id INTEGER NOT NULL DEFAULT 0, production_run_id INTEGER, note TEXT DEFAULT '');
CREATE INDEX idx_delivery_challan_items_challan_id ON delivery_challan_items(challan_id);
CREATE TABLE item_property_schema (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL REFERENCES items(id) ON DELETE CASCADE,
      property_key TEXT NOT NULL,
      display_name TEXT NOT NULL,
      input_type TEXT NOT NULL DEFAULT 'Text',
      mandatory INTEGER NOT NULL DEFAULT 0,
      unit_id INTEGER,
      unit_symbol TEXT,
      unit_label TEXT,
      source_type TEXT NOT NULL DEFAULT 'manual',
      source_group_id INTEGER,
      source_group_name TEXT,
      source_item_ids_json TEXT NOT NULL DEFAULT '[]',
      sort_order INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, property_key)
    );
CREATE INDEX idx_item_property_schema_item_id ON item_property_schema(item_id);
CREATE TABLE inventory_sets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE INDEX idx_materials_linked_group_id ON materials(linked_group_id);
CREATE INDEX idx_materials_linked_item_id ON materials(linked_item_id);
CREATE INDEX idx_materials_parent_barcode ON materials(parent_barcode);
CREATE INDEX idx_inventory_sets_name ON inventory_sets(name);
CREATE TABLE vendors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      alias TEXT DEFAULT '',
      gst_number TEXT DEFAULT '',
      address TEXT DEFAULT '',
      contact_name TEXT DEFAULT '',
      phone TEXT DEFAULT '',
      email TEXT DEFAULT '',
      is_archived INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    , logo_url TEXT DEFAULT '', photo_url TEXT DEFAULT '');
CREATE TABLE inventory_set_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        set_id INTEGER NOT NULL REFERENCES inventory_sets(id) ON DELETE CASCADE,
        item_id INTEGER NOT NULL REFERENCES items(id),
        variation_leaf_node_id INTEGER REFERENCES item_variation_nodes(id),
        quantity INTEGER NOT NULL DEFAULT 1,
        position INTEGER NOT NULL DEFAULT 0,
        UNIQUE(set_id, item_id, variation_leaf_node_id)
      );
CREATE INDEX idx_inventory_set_lines_set_id ON inventory_set_lines(set_id);
CREATE INDEX idx_inventory_set_lines_item_id ON inventory_set_lines(item_id);
CREATE INDEX idx_inventory_set_lines_item_lookup ON inventory_set_lines(item_id, variation_leaf_node_id);
CREATE INDEX idx_delivery_challans_vendor_id ON delivery_challans(vendor_id);
CREATE INDEX idx_delivery_challans_type ON delivery_challans(type);
CREATE INDEX idx_materials_inventory_state ON materials(inventory_state);
CREATE INDEX idx_materials_stock_quantities ON materials(on_hand_qty, available_to_promise_qty, reserved_qty);
CREATE INDEX idx_inventory_movements_health_query ON inventory_movements(movement_type, created_at);
CREATE INDEX idx_inventory_alerts_is_open ON inventory_alerts(is_open);
CREATE INDEX idx_materials_item_variation_lookup ON materials(linked_item_id, linked_variation_leaf_node_id);
CREATE INDEX idx_inventory_movements_source_challan ON inventory_movements(source_challan_id, source_challan_type);
CREATE TABLE delivery_challan_orders (
      challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (challan_id, order_id)
    );
CREATE INDEX idx_delivery_challan_orders_challan_id ON delivery_challan_orders(challan_id);
CREATE INDEX idx_delivery_challan_orders_order_id ON delivery_challan_orders(order_id);
CREATE TABLE challan_template_upload_sessions (
      id TEXT PRIMARY KEY,
      file_name TEXT NOT NULL,
      content_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL DEFAULT 0,
      sha256 TEXT NOT NULL,
      object_key TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      expires_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      completed_at TEXT
    , upload_type TEXT NOT NULL DEFAULT 'CHALLAN_TEMPLATE_BACKGROUND', canvas_width INTEGER NOT NULL DEFAULT 0, canvas_height INTEGER NOT NULL DEFAULT 0);
CREATE TABLE challan_templates (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      party_type TEXT NOT NULL,
      party_id INTEGER NOT NULL,
      challan_type TEXT NOT NULL,
      background_object_key TEXT NOT NULL,
      canvas_width INTEGER NOT NULL,
      canvas_height INTEGER NOT NULL,
      rotation_degrees REAL NOT NULL DEFAULT 0,
      global_offset_x_mm REAL NOT NULL DEFAULT 0,
      global_offset_y_mm REAL NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    , stock_size TEXT NOT NULL DEFAULT 'A4', paper_size TEXT NOT NULL DEFAULT 'A4', n_up_layout INTEGER NOT NULL DEFAULT 1);
CREATE TABLE challan_template_mappings (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      template_id INTEGER NOT NULL REFERENCES challan_templates(id) ON DELETE CASCADE,
      field_key TEXT NOT NULL,
      x_percent REAL NOT NULL,
      y_percent REAL NOT NULL,
      font_size REAL NOT NULL DEFAULT 10,
      font_weight TEXT NOT NULL DEFAULT 'normal',
      alignment TEXT NOT NULL DEFAULT 'left',
      letter_spacing REAL NOT NULL DEFAULT 0,
      max_chars INTEGER NOT NULL DEFAULT 0,
      max_rows INTEGER NOT NULL DEFAULT 0,
      row_height_mm REAL NOT NULL DEFAULT 6,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL, field_type TEXT NOT NULL DEFAULT 'DYNAMIC', field_value TEXT NOT NULL DEFAULT '', asset_object_key TEXT NOT NULL DEFAULT '', asset_width_px INTEGER NOT NULL DEFAULT 0, asset_height_px INTEGER NOT NULL DEFAULT 0, image_width_mm REAL NOT NULL DEFAULT 35, image_height_mm REAL NOT NULL DEFAULT 20, lock_aspect_ratio INTEGER NOT NULL DEFAULT 1, text_color TEXT NOT NULL DEFAULT 'black', max_width_mm REAL NOT NULL DEFAULT 80, width_mm REAL NOT NULL DEFAULT 80, height_mm REAL NOT NULL DEFAULT 12, min_font_size REAL NOT NULL DEFAULT 6, min_rows INTEGER NOT NULL DEFAULT 0, table_height_mm REAL NOT NULL DEFAULT 60, x_mm REAL NOT NULL DEFAULT 0, y_mm REAL NOT NULL DEFAULT 0,
      UNIQUE(template_id, field_key)
    );
CREATE INDEX idx_challan_template_upload_sessions_sha256 ON challan_template_upload_sessions(sha256);
CREATE INDEX idx_challan_templates_party ON challan_templates(party_type, party_id, challan_type, is_active);
CREATE INDEX idx_challan_template_mappings_template_id ON challan_template_mappings(template_id);
CREATE TABLE production_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      run_code TEXT NOT NULL UNIQUE,
      status TEXT NOT NULL DEFAULT 'completed',
      completed_at TEXT,
      item_id INTEGER NOT NULL REFERENCES items(id),
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      variation_path_label TEXT DEFAULT '',
      output_quantity REAL NOT NULL DEFAULT 0,
      uom TEXT DEFAULT 'pcs',
      location TEXT DEFAULT '',
      source_metadata_json TEXT DEFAULT '{}',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE INDEX idx_production_runs_status ON production_runs(status, completed_at);
CREATE INDEX idx_production_runs_item ON production_runs(item_id, variation_leaf_node_id);
CREATE TABLE invoice_headers (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_no TEXT NOT NULL UNIQUE,
      client_id INTEGER REFERENCES clients(id),
      client_name TEXT NOT NULL DEFAULT '',
      gstin TEXT DEFAULT '',
      status TEXT NOT NULL DEFAULT 'draft',
      invoice_date TEXT NOT NULL,
      total_quantity REAL NOT NULL DEFAULT 0,
      taxable_value REAL NOT NULL DEFAULT 0,
      cgst_amount REAL NOT NULL DEFAULT 0,
      sgst_amount REAL NOT NULL DEFAULT 0,
      total_amount REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE invoice_lines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER NOT NULL REFERENCES invoice_headers(id) ON DELETE CASCADE,
      order_id INTEGER,
      challan_id INTEGER REFERENCES delivery_challans(id),
      challan_item_id INTEGER REFERENCES delivery_challan_items(id),
      item_id INTEGER,
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      item_name TEXT NOT NULL DEFAULT '',
      hsn_code TEXT DEFAULT '',
      quantity REAL NOT NULL DEFAULT 0,
      unit_price REAL NOT NULL DEFAULT 0,
      taxable_value REAL NOT NULL DEFAULT 0,
      cgst_rate REAL NOT NULL DEFAULT 0,
      sgst_rate REAL NOT NULL DEFAULT 0,
      cgst_amount REAL NOT NULL DEFAULT 0,
      sgst_amount REAL NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE reconciliation_conversion_overrides (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      item_id INTEGER NOT NULL,
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      conversion_ratio REAL NOT NULL DEFAULT 1,
      from_unit TEXT NOT NULL DEFAULT 'kg',
      to_unit_label TEXT NOT NULL DEFAULT 'units',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      UNIQUE(item_id, variation_leaf_node_id)
    );
CREATE TABLE reconciliation_waste_audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_id INTEGER,
      client_name TEXT NOT NULL DEFAULT '',
      item_id INTEGER,
      variation_leaf_node_id INTEGER NOT NULL DEFAULT 0,
      item_name TEXT NOT NULL DEFAULT '',
      challan_id INTEGER REFERENCES delivery_challans(id),
      challan_no TEXT DEFAULT '',
      input_weight_kg REAL NOT NULL DEFAULT 0,
      shipped_weight_kg REAL NOT NULL DEFAULT 0,
      waste_weight_kg REAL NOT NULL DEFAULT 0,
      waste_percentage REAL NOT NULL DEFAULT 0,
      source TEXT NOT NULL DEFAULT 'report_snapshot',
      created_at TEXT NOT NULL
    );
CREATE INDEX idx_invoice_lines_invoice_id ON invoice_lines(invoice_id);
CREATE INDEX idx_invoice_lines_challan_item ON invoice_lines(challan_item_id);
CREATE INDEX idx_invoice_lines_order_id ON invoice_lines(order_id);
CREATE INDEX idx_reconciliation_conversion_item ON reconciliation_conversion_overrides(item_id, variation_leaf_node_id);
CREATE INDEX idx_reconciliation_waste_client_item ON reconciliation_waste_audit(client_id, item_id, variation_leaf_node_id);
CREATE INDEX idx_delivery_challans_material_owner ON delivery_challans(material_owner_client_id);
CREATE TABLE order_status_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
      previous_status TEXT,
      new_status TEXT NOT NULL,
      changed_by_user_id INTEGER,
      changed_at TEXT NOT NULL
    );
CREATE INDEX idx_order_status_history_order_id_changed_at ON order_status_history(order_id, changed_at);
CREATE TABLE report_groups (
      code TEXT PRIMARY KEY,
      label TEXT DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE delivery_challan_report_groups (
      challan_id INTEGER NOT NULL REFERENCES delivery_challans(id) ON DELETE CASCADE,
      report_group_code TEXT NOT NULL REFERENCES report_groups(code) ON DELETE CASCADE,
      created_at TEXT NOT NULL,
      PRIMARY KEY (challan_id, report_group_code)
    );
CREATE INDEX idx_delivery_challan_report_groups_challan_id ON delivery_challan_report_groups(challan_id);
CREATE INDEX idx_delivery_challan_report_groups_code ON delivery_challan_report_groups(report_group_code);
CREATE TABLE machines (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      asset_id TEXT NOT NULL UNIQUE,
      primary_photo_url TEXT,
      group_id INTEGER REFERENCES groups(id),
      make_model TEXT,
      serial_number TEXT,
      location TEXT,
      installation_date TEXT,
      status TEXT NOT NULL,
      custom_properties TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
CREATE TABLE dies (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      tool_code TEXT NOT NULL UNIQUE,
      produced_part_numbers TEXT NOT NULL DEFAULT '[]',
      photo_urls TEXT NOT NULL DEFAULT '[]',
      operational_notes TEXT,
      compatible_machine_group_ids TEXT NOT NULL DEFAULT '[]',
      storage_location TEXT,
      number_of_cavities INTEGER,
      stroke_count INTEGER NOT NULL DEFAULT 0,
      max_strokes INTEGER NOT NULL DEFAULT 0,
      physical_specs TEXT NOT NULL DEFAULT '{}',
      status TEXT NOT NULL,
      ownership TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );
