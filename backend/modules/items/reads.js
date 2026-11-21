'use strict';

const partIdentity = require('./part-identity');

// Items and groups as read: by id, with usage, with their sets; and the
// cleaning of a variation tree before it is saved.
//
// A factory: `deps` is what server.js still owns (the database helpers and
// a few shared helpers), `api` is the items service being assembled, through
// which these reach the sibling files; both are read at call time.

const { normalizeUnitValue } = require('../units/master');
const { buildVariationPathLabel } = require('./variation-tree');

function createReads(deps, api) {
  const inventoryPorts = deps.inventory;
  const { desk } = deps;
  const { all, get } = deps;
  const resolveOrderVariationSelection = (...args) => api.resolveOrderVariationSelection(...args);

  async function getGroupRowById(id) {
    return get(
      `
      SELECT
        groups.*,
        (
          (SELECT COUNT(*) FROM groups AS child_groups WHERE child_groups.parent_group_id = groups.id) +
          (SELECT COUNT(*) FROM items WHERE items.group_id = groups.id AND items.is_archived = 0) +
          (SELECT COUNT(*) FROM materials WHERE materials.linked_group_id = groups.id)
        ) AS usage_count
      FROM groups
      WHERE groups.id = ?
      `,
      [id],
    );
  }

  async function getItemRowById(id) {
    return get(
      `
      SELECT
        items.*,
        pipeline_templates.name AS default_pipeline_name,
        developed_for_client.name AS developed_for_client_name,
        developed_for_client.contact_name AS developed_for_contact_name,
        developed_for_client.designation AS developed_for_designation,
        developed_for_client.phone AS developed_for_phone,
        developed_for_client.email AS developed_for_email,
        developed_for_contractor.name AS developed_for_sub_contractor_name,
        developed_for_contractor.designation AS developed_for_sub_contractor_designation,
        developed_for_contractor.phone AS developed_for_sub_contractor_phone,
        developed_for_contractor.email AS developed_for_sub_contractor_email,
        -- The people this part's deal was done with (056), as one JSON column so
        -- the list read stays one statement per page however many parts it has.
        (
          SELECT json_group_array(json_object(
            'id', c.id, 'name', c.name, 'designation', c.designation,
            'phone', c.phone, 'email', c.email, 'isArchived', c.is_archived
          ))
          FROM (
            SELECT pc.* FROM item_deal_contacts idc
            JOIN party_contacts pc ON pc.id = idc.contact_id
            WHERE idc.item_id = items.id
            ORDER BY pc.is_primary DESC, pc.name COLLATE NOCASE ASC
          ) c
        ) AS developed_for_contacts_json,
        (
          (SELECT COUNT(*) FROM order_items WHERE order_items.item_id = items.id) +
          (SELECT COUNT(*) FROM delivery_challan_items WHERE delivery_challan_items.item_id = items.id) +
          (SELECT COUNT(*) FROM order_material_requirements WHERE order_material_requirements.item_id = items.id) +
          (SELECT COUNT(*) FROM materials WHERE materials.linked_item_id = items.id) +
          (SELECT COUNT(*) FROM material_group_item_links WHERE material_group_item_links.item_id = items.id)
        ) AS usage_count
      FROM items
      LEFT JOIN pipeline_templates ON items.default_pipeline_id = pipeline_templates.id
      LEFT JOIN clients developed_for_client ON developed_for_client.id = items.developed_for_client_id
      LEFT JOIN sub_contractors developed_for_contractor ON developed_for_contractor.id = items.developed_for_sub_contractor_id
      WHERE items.id = ?
      `,
      [id],
    );
  }

  async function getItemsWithUsage() {
    return all(`
      SELECT
        items.*,
        pipeline_templates.name AS default_pipeline_name,
        developed_for_client.name AS developed_for_client_name,
        developed_for_client.contact_name AS developed_for_contact_name,
        developed_for_client.designation AS developed_for_designation,
        developed_for_client.phone AS developed_for_phone,
        developed_for_client.email AS developed_for_email,
        developed_for_contractor.name AS developed_for_sub_contractor_name,
        developed_for_contractor.designation AS developed_for_sub_contractor_designation,
        developed_for_contractor.phone AS developed_for_sub_contractor_phone,
        developed_for_contractor.email AS developed_for_sub_contractor_email,
        -- The people this part's deal was done with (056), as one JSON column so
        -- the list read stays one statement per page however many parts it has.
        (
          SELECT json_group_array(json_object(
            'id', c.id, 'name', c.name, 'designation', c.designation,
            'phone', c.phone, 'email', c.email, 'isArchived', c.is_archived
          ))
          FROM (
            SELECT pc.* FROM item_deal_contacts idc
            JOIN party_contacts pc ON pc.id = idc.contact_id
            WHERE idc.item_id = items.id
            ORDER BY pc.is_primary DESC, pc.name COLLATE NOCASE ASC
          ) c
        ) AS developed_for_contacts_json,
        (
          (SELECT COUNT(*) FROM order_items WHERE order_items.item_id = items.id) +
          (SELECT COUNT(*) FROM delivery_challan_items WHERE delivery_challan_items.item_id = items.id) +
          (SELECT COUNT(*) FROM order_material_requirements WHERE order_material_requirements.item_id = items.id) +
          (SELECT COUNT(*) FROM materials WHERE materials.linked_item_id = items.id) +
          (SELECT COUNT(*) FROM material_group_item_links WHERE material_group_item_links.item_id = items.id)
        ) AS usage_count
      FROM items
      LEFT JOIN pipeline_templates ON items.default_pipeline_id = pipeline_templates.id
      LEFT JOIN clients developed_for_client ON developed_for_client.id = items.developed_for_client_id
      LEFT JOIN sub_contractors developed_for_contractor ON developed_for_contractor.id = items.developed_for_sub_contractor_id
      ORDER BY items.is_archived ASC, LOWER(items.name) ASC
    `);
  }

  async function getItemUsageDetails(itemId) {
    const [
      orders,
      challans,
      bomRequirements,
      materials,
      groupLinks
    ] = await (async () => {
      // Each owner says where the item is used in its records.
      const [fromOrders, fromChallans, fromInventory] = await Promise.all([
        desk.ask('orders.items.usageRows', { itemId }),
        desk.ask('challans.items.usageRows', { itemId }),
        desk.ask('inventory.items.usageRows', { itemId }),
      ]);
      return [fromOrders.lines, fromChallans.rows, fromOrders.requirements, fromInventory.materials, fromInventory.groupLinks];
    })();

    const usage = [];

    // The sets this part is a line of. Listed here so the delete confirmation
    // mentions the sets that are about to lose a line — the item editor now
    // shows that membership two cards up, which made the omission visible.
    //
    // Deliberately NOT added to getItemsWithUsage's usage_count: that count gates
    // structuralChangeDetected in saveItem, so counting set members there would
    // start archiving variation nodes on the next group or unit change.
    for (const row of await inventoryPorts.sets.membershipForItem(itemId)) {
      usage.push({
        type: 'inventory_set',
        id: String(row.setId),
        title: `Set ${row.setName}`,
        subtitle: row.variationPathLabel && row.variationPathLabel !== 'Base item'
          ? `${row.variationPathLabel} · × ${row.quantity}`
          : `× ${row.quantity}`,
      });
    }

    orders.forEach(o => {
      usage.push({ type: 'order', id: String(o.id), title: `Order ${o.order_no}`, subtitle: o.client_name || '-', status: o.status, date: o.created_at });
    });

    challans.forEach(c => {
      usage.push({ type: 'delivery_challan', id: String(c.challan_id), title: `Challan ${c.challan_no}`, subtitle: c.customer_name || '-', status: c.status, date: c.date });
    });

    bomRequirements.forEach(b => {
      usage.push({ type: 'bom_requirement', id: String(b.id), title: `BOM for Order ${b.order_no}`, subtitle: b.client_name || '-', status: null, date: null });
    });

    materials.forEach(m => {
      usage.push({ type: 'material', id: String(m.id), title: `Material ${m.barcode}`, subtitle: m.name, status: m.inventory_state, date: null });
    });

    groupLinks.forEach(g => {
      usage.push({ type: 'group_link', id: String(g.id), title: `Group Link for ${g.barcode}`, subtitle: g.name, status: null, date: null });
    });

    return usage;
  }

  // Numeric variation properties may declare an allowed range, captured in the
  // item editor when the input type is switched to 'Numeric'. Either bound may be
  // omitted (open-ended); the range is dropped entirely for non-Numeric types so
  // switching a property back to Text/Gauge doesn't leave a stale range behind.
  function sanitizeNumericRange(node, inputType, propertyName) {
    if (inputType !== 'Numeric') {
      return { numericMin: null, numericMax: null };
    }
    const readBound = (raw, label) => {
      if (raw === null || raw === undefined || raw === '') {
        return null;
      }
      const value = Number(raw);
      if (!Number.isFinite(value)) {
        const error = new Error(`Numeric property '${propertyName}' has an invalid ${label}.`);
        error.statusCode = 400;
        throw error;
      }
      return value;
    };
    const numericMin = readBound(node.numericMin, 'minimum');
    const numericMax = readBound(node.numericMax, 'maximum');
    if (numericMin !== null && numericMax !== null && numericMin > numericMax) {
      const error = new Error(
        `Numeric property '${propertyName}' has a minimum greater than its maximum.`,
      );
      error.statusCode = 400;
      throw error;
    }
    return { numericMin, numericMax };
  }

  /// The material type a value node stands for. Only a positive integer is a
  /// link; anything else — absent, blank, zero, a name someone hand-typed — is no
  /// link at all rather than a guess at one.
  function normalizeMaterialTypeId(raw) {
    if (raw === null || raw === undefined || raw === '') return null;
    const value = Number(raw);
    if (!Number.isFinite(value) || value <= 0) return null;
    return Math.trunc(value);
  }

  function sanitizeNodes(nodes, expectedKind, pathSegments = [], parentPropertyName = '', depth = 0) {
    if (depth > 10) {
      const error = new Error('Variation tree is too deep.');
      error.statusCode = 400;
      throw error;
    }
    const siblingNames = new Set();
    return (nodes || []).map((node, index) => {
      const trimmedName = String(node.name || '').trim();
      if (!trimmedName) {
        const error = new Error('Variation tree node names are required.');
        error.statusCode = 400;
        throw error;
      }
      const kind = String(node.kind || '');
      if (kind !== expectedKind) {
        const error = new Error(`Expected variation tree node of kind '${expectedKind}', but got '${kind}'.`);
        error.statusCode = 409;
        throw error;
      }
      const normalizedName = normalizeUnitValue(trimmedName);
      if (siblingNames.has(normalizedName)) {
        const error = new Error('Sibling variation nodes must have unique names.');
        error.statusCode = 409;
        throw error;
      }
      siblingNames.add(normalizedName);

      const nodeId = node.id || null;

      if (kind === 'property') {
        const hasPropertyChildren = (node.children || []).some(c => c.kind === 'property');
        const expectedChildKind = hasPropertyChildren ? 'property' : 'value';
        const inputType = String(node.inputType || 'Text').trim() || 'Text';
        const { numericMin, numericMax } = sanitizeNumericRange(node, inputType, trimmedName);
        return {
          id: nodeId,
          kind,
          name: trimmedName,
          code: String(node.code || '').trim(),
          displayName: '',
          inputType,
          nameJoin: String(node.nameJoin || '').trim(),
          numericMin,
          numericMax,
          position: index,
          children: sanitizeNodes(node.children || [], expectedChildKind, pathSegments, trimmedName, depth + 1),
        };
      }

      const nextSegments = [...pathSegments, trimmedName];
      const children = sanitizeNodes(node.children || [], 'property', nextSegments, '', depth + 1);
      return {
        id: nodeId,
        kind,
        name: trimmedName,
        code: String(node.code || '').trim(),
        displayName:
          String(node.displayName || '').trim() || buildVariationPathLabel(nextSegments),
        // Carried on the value, not the property: the property says these values
        // are materials, each value says which one.
        materialTypeId: normalizeMaterialTypeId(node.materialTypeId),
        position: index,
        children,
      };
    });
  }

  /// The part a save would duplicate, or null.
  ///
  /// Same group, unit and name — and, when [identity] is given, the same
  /// Alloy and Thickness (part-identity.js: another alloy or thickness is
  /// another part, with its own number). Without [identity] the name alone
  /// decides, as it always did.
  async function findItemDuplicate({ name, groupId, unitId, excludeId = null, identity = null }) {
    const rows = await all('SELECT id, name, group_id, unit_id FROM items');
    const normalizedName = normalizeUnitValue(name);
    const normalizedGroupId = Number(groupId || 0);
    const normalizedUnitId = Number(unitId || 0);

    const sameName = rows.filter((row) =>
      !(excludeId != null && row.id === excludeId) &&
      normalizeUnitValue(row.name) === normalizedName &&
      Number(row.group_id || 0) === normalizedGroupId &&
      Number(row.unit_id || 0) === normalizedUnitId);
    if (!sameName.length || !identity) return sameName[0] || null;

    for (const row of sameName) {
      if (partIdentity.sameIdentity(await storedIdentity(row.id), identity)) return row;
    }
    return null;
  }

  /// A saved part's Alloy and Thickness, read from its variation nodes.
  async function storedIdentity(itemId) {
    const nodes = await all(
      `SELECT id, parent_node_id, kind, name, is_archived FROM item_variation_nodes
        WHERE item_id = ? AND is_archived = 0`,
      [itemId],
    );
    const top = nodes
      .filter((node) => node.parent_node_id == null)
      .map((node) => ({ ...node, children: nodes.filter((child) => child.parent_node_id === node.id) }));
    return partIdentity.identityOfTree(top);
  }

  async function getGroupsWithUsage() {
    return all(`
      SELECT
        groups.*,
        (
          (SELECT COUNT(*) FROM groups AS child_groups WHERE child_groups.parent_group_id = groups.id) +
          (SELECT COUNT(*) FROM items WHERE items.group_id = groups.id AND items.is_archived = 0) +
          (SELECT COUNT(*) FROM materials WHERE materials.linked_group_id = groups.id)
        ) AS usage_count
      FROM groups
      ORDER BY groups.is_archived ASC, LOWER(groups.name) ASC
    `);
  }

  async function getItemSelectionSnapshot(itemId, variationLeafNodeId) {
    const selection = await resolveOrderVariationSelection({
      itemId,
      variationLeafNodeId,
      variationPathNodeIds: [],
      status: 'notStarted',
    });
    return {
      item: selection.item,
      itemId: selection.item.id,
      variationLeafNodeId: selection.variationLeafNodeId,
      variationPathLabel: selection.variationPathLabel,
      variationPathNodeIds: selection.variationPathNodeIds || [],
      particulars: selection.variationPathLabel
        ? `${selection.item.display_name || selection.item.name} - ${selection.variationPathLabel}`
        : (selection.item.display_name || selection.item.name || ''),
    };
  }

  return { getGroupRowById, getItemRowById, getItemsWithUsage, getItemUsageDetails, sanitizeNumericRange, normalizeMaterialTypeId, sanitizeNodes, findItemDuplicate, getGroupsWithUsage, getItemSelectionSnapshot };
}

module.exports = { createReads };
