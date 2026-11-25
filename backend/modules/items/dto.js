'use strict';

// An item and a group as the app shows them.
//
// A factory: `deps` is what server.js still owns (the database helpers and
// a few shared helpers), `api` is the items service being assembled, through
// which these reach the sibling files; both are read at call time.



function createDto(deps, api) {
  const { desk } = deps;
  const { all, get, parseJson } = deps;
  const developedForDto = (...args) => api.developedForDto(...args);
  const getItemPropertySchema = (...args) => api.getItemPropertySchema(...args);
  const getItemVariationTree = (...args) => api.getItemVariationTree(...args);
  const getItemVariationTrees = (...args) => api.getItemVariationTrees(...args);
  const getItemPropertySchemas = (...args) => api.getItemPropertySchemas(...args);

  function rowToGroupDto(row) {
    if (!row) {
      return null;
    }

    return {
      id: row.id,
      name: row.name || '',
      groupType: row.group_type || 'item',
      groupStructure: row.group_structure || 'hierarchical',
      description: row.description || '',
      parentGroupId: row.parent_group_id || null,
      unitId: row.unit_id || null,
      // null when the group has no override and items fall back to the creating
      // user's own default section layout.
      itemFormSections: (() => {
        try {
          return row.item_form_sections ? JSON.parse(row.item_form_sections) : null;
        } catch (e) {
          return null;
        }
      })(),
      isArchived: Boolean(row.is_archived),
      // Set only on a group the app ships (Raw Materials, Rivets, Springs):
      // cannot be deleted, archived, renamed or moved. See system-groups.js.
      systemKey: row.system_key || null,
      usageCount: row.usage_count || 0,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  // What an item's DTO reads from other tables, one query each. Written once
  // and run two ways: for one item (`item_id = ?`), and for a whole list
  // (`item_id IN (...)`, grouped by item) — so the two cannot drift. The
  // tie-breaks make the order total, so a list row and its detail row agree
  // even where two names are equal.
  const RELATED = {
    unitConversions: {
      sql: (where) => `
        SELECT item_unit_conversions.item_id,
               item_unit_conversions.unit_id,
               item_unit_conversions.factor_to_primary,
               units.name AS unit_name,
               units.symbol AS unit_symbol
        FROM item_unit_conversions
        INNER JOIN units ON units.id = item_unit_conversions.unit_id
        WHERE item_unit_conversions.item_id ${where}
        ORDER BY item_unit_conversions.item_id ASC, LOWER(units.name) ASC, LOWER(units.symbol) ASC,
                 item_unit_conversions.unit_id ASC`,
    },
    // Enhancement 2.3 — combination groups this item additionally belongs to
    // (distinct from its primary hierarchical group_id). Empty for most items.
    combinationGroups: {
      sql: (where) => `
        SELECT group_item_memberships.item_id, group_item_memberships.group_id
        FROM group_item_memberships
        INNER JOIN groups ON groups.id = group_item_memberships.group_id
        WHERE group_item_memberships.item_id ${where}
          AND groups.group_structure = 'combination'
          AND groups.is_archived = 0
        ORDER BY group_item_memberships.item_id ASC, group_item_memberships.sort_order ASC,
                 group_item_memberships.group_id ASC`,
    },
    attachments: {
      sql: (where) => `
        SELECT item_id, id, label, object_key, file_name FROM item_attachments
        WHERE item_id ${where} ORDER BY item_id ASC, position ASC, id ASC`,
    },
    machines: {
      sql: (where) => `
        SELECT item_machines.item_id,
               machines.id, machines.name, machines.asset_id, machines.primary_photo_url,
               machines.machine_make, machines.manufactured_year, machines.manufactured_on, machines.feeder_make,
               machines.running_hours, machines.strokes_per_minute,
               machines.capacity_kind, machines.capacity_kgf, machines.die_feed_type,
               machines.group_id, machine_groups.name AS machine_group_name
        FROM item_machines
        INNER JOIN machines ON machines.id = item_machines.machine_id
        LEFT JOIN groups machine_groups ON machine_groups.id = machines.group_id
        WHERE item_machines.item_id ${where}
        ORDER BY item_machines.item_id ASC, LOWER(machines.name) ASC, machines.id ASC`,
    },
    // Every company the part was developed for (item_deals), with the columns
    // developedForDto reads, so each deal reads exactly as the single one does.
    deals: {
      sql: (where) => `
        SELECT item_deals.item_id, item_deals.id AS deal_id, item_deals.position,
               item_deals.kind AS developed_for_kind,
               item_deals.client_id AS developed_for_client_id,
               item_deals.sub_contractor_id AS developed_for_sub_contractor_id,
               item_deals.at AS developed_for_at,
               item_deals.quotation_amount AS developed_for_quotation_amount,
               c.name AS developed_for_client_name,
               c.contact_name AS developed_for_contact_name,
               c.designation AS developed_for_designation,
               c.phone AS developed_for_phone,
               c.email AS developed_for_email,
               sc.name AS developed_for_sub_contractor_name,
               sc.designation AS developed_for_sub_contractor_designation,
               sc.phone AS developed_for_sub_contractor_phone,
               sc.email AS developed_for_sub_contractor_email,
               (
                 SELECT json_group_array(json_object(
                   'id', pc.id, 'name', pc.name, 'designation', pc.designation,
                   'phone', pc.phone, 'email', pc.email, 'isArchived', pc.is_archived
                 ))
                 FROM (
                   SELECT party_contacts.* FROM item_deal_people
                   JOIN party_contacts ON party_contacts.id = item_deal_people.contact_id
                   WHERE item_deal_people.deal_id = item_deals.id
                   ORDER BY party_contacts.is_primary DESC, party_contacts.name COLLATE NOCASE ASC
                 ) pc
               ) AS developed_for_contacts_json
        FROM item_deals
        LEFT JOIN clients c ON c.id = item_deals.client_id
        LEFT JOIN sub_contractors sc ON sc.id = item_deals.sub_contractor_id
        WHERE item_deals.item_id ${where}
        ORDER BY item_deals.item_id ASC, item_deals.position ASC, item_deals.id ASC`,
    },
    dies: {
      sql: (where) => `
        SELECT item_dies.item_id,
               dies.id, dies.tool_code, dies.photo_urls,
               dies.die_type, dies.die_type_label, dies.made_by, dies.die_maker_id,
               dies.po_at, dies.date_in_at,
               dies.liner_size_nm, dies.liner_size_unit, dies.no_of_set,
               dies.number_of_cavities,
               dies.store_area, dies.rack_no
        FROM item_dies
        INNER JOIN dies ON dies.id = item_dies.die_id
        WHERE item_dies.item_id ${where}
        ORDER BY item_dies.item_id ASC, LOWER(dies.tool_code) ASC, dies.id ASC`,
    },
  };

  /// Everything the DTOs of [rows] read from other tables, in a fixed number
  /// of queries however long the list: the list used to issue seven per item
  /// (444 ms for 300 parts; Docs/benchmarks/2026-11-constrained-network-results.md).
  async function preloadRelated(rows) {
    const ids = rows.map((row) => row.id);
    const related = {};
    for (const [name, spec] of Object.entries(RELATED)) {
      const byItem = new Map(ids.map((id) => [id, []]));
      for (let i = 0; i < ids.length; i += 500) {
        const chunk = ids.slice(i, i + 500);
        const found = await all(spec.sql(`IN (${chunk.map(() => '?').join(',')})`), chunk);
        for (const entry of found) byItem.get(entry.item_id)?.push(entry);
      }
      related[name] = byItem;
    }
    related.propertySchema = await getItemPropertySchemas(ids);
    related.variationTree = await getItemVariationTrees(ids);
    return related;
  }

  /// A list of items as DTOs, each exactly what rowToItemDto gives for it.
  async function rowsToItemDtos(rows) {
    const present = rows.filter(Boolean);
    if (!present.length) return [];
    const related = await preloadRelated(present);
    return Promise.all(present.map((row) => rowToItemDto(row, related)));
  }

  async function rowToItemDto(row, related = null) {
    if (!row) {
      return null;
    }
    const one = async (name) => (related
      ? related[name].get(row.id) || []
      : all(RELATED[name].sql('= ?'), [row.id]));

    const unitConversionRows = await one('unitConversions');
    const propertySchema = related
      ? related.propertySchema.get(row.id) || []
      : await getItemPropertySchema(row.id);
    const combinationGroupRows = await one('combinationGroups');
    const attachmentRows = await one('attachments');
    const machineLinkRows = await one('machines');
    const dieLinkRows = await one('dies');
    const dealRows = await one('deals');

    return {
      id: row.id,
      name: row.name || '',
      alias: row.alias || '',
      shortCode: row.short_code || '',
      // The number this part was issued and the code derived from it. Null and
      // '' mean never stamped — most of the catalogue predates them.
      partNo: row.part_no == null ? null : Number(row.part_no),
      partCode: row.part_code || '',
      displayName: row.display_name || '',
      quantity: Number(row.quantity || 0),
      groupId: row.group_id || null,
      unitId: row.unit_id || null,
      unitConversions: unitConversionRows.map((entry) => ({
        unitId: entry.unit_id || 0,
        unitName: entry.unit_name || '',
        unitSymbol: entry.unit_symbol || '',
        factorToPrimary: Number(entry.factor_to_primary || 1),
      })),
      namingFormat: (() => {
        try {
          return row.naming_format ? JSON.parse(row.naming_format) : [];
        } catch (e) {
          return [];
        }
      })(),
      isArchived: Boolean(row.is_archived),
      usageCount: row.usage_count || 0,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      variationTree: related
        ? related.variationTree.get(row.id) || []
        : await getItemVariationTree(row.id),
      propertySchema,
      baseItemId: row.base_item_id || null,
      combinationGroupIds: combinationGroupRows.map((entry) => entry.group_id),
      photoUrl: row.photo_url || null,
      cadFileKey: row.cad_file_key || '',
      cadFileName: row.cad_file_name || '',
      attachments: attachmentRows.map((entry) => ({
        id: entry.id,
        label: entry.label || '',
        objectKey: entry.object_key || '',
        fileName: entry.file_name || '',
      })),
      // The whole sheet per machine, for the same reason as the dies below: a
      // part runs on several, and the screen listing them has to show what tells
      // them apart — the type, the make, the tonnage, the strokes.
      machines: machineLinkRows.map((entry) => ({
        id: String(entry.id),
        name: entry.name || '',
        assetId: entry.asset_id || '',
        photoUrl: entry.primary_photo_url || null,
        groupId: entry.group_id || null,
        machineType: entry.machine_group_name || '',
        machineMake: entry.machine_make || '',
        manufacturedYear:
          entry.manufactured_year == null ? null : Number(entry.manufactured_year),
        manufacturedOn: entry.manufactured_on || null,
        feederMake: entry.feeder_make || '',
        runningHours: entry.running_hours == null ? null : Number(entry.running_hours),
        strokesPerMinute:
          entry.strokes_per_minute == null ? null : Number(entry.strokes_per_minute),
        capacityKind: entry.capacity_kind || '',
        capacityKgf: entry.capacity_kgf == null ? null : Number(entry.capacity_kgf),
        dieFeedType: entry.die_feed_type || '',
      })),
      // The whole sheet per die, not just the code: a part can hold several, and
      // the screen that lists them has to show what tells them apart — the type,
      // the maker, the size, which rack. Columns on a join that was already
      // happening, so listing them costs nothing extra, the same discipline
      // developedFor follows.
      dies: dieLinkRows.map((entry) => {
        const urls = parseJson(entry.photo_urls, []);
        return {
          id: String(entry.id),
          toolCode: entry.tool_code || '',
          photoUrl: urls.length > 0 ? urls[0] : null,
          dieType: entry.die_type || '',
          // Both carried so a die corrected from beside its part does not send
          // back a bare slug and no maker — the upsert would store exactly that.
          dieTypeLabel: entry.die_type_label || '',
          madeBy: entry.made_by || '',
          dieMakerId: entry.die_maker_id == null ? null : Number(entry.die_maker_id),
          poAt: entry.po_at || null,
          dateInAt: entry.date_in_at || null,
          linerSizeNm: entry.liner_size_nm == null ? null : Number(entry.liner_size_nm),
          linerSizeUnit: entry.liner_size_unit || 'mm',
          noOfSet: entry.no_of_set == null ? null : Number(entry.no_of_set),
          numberOfCavities:
            entry.number_of_cavities == null ? null : Number(entry.number_of_cavities),
          storeArea: entry.store_area || '',
          rackNo: entry.rack_no || '',
        };
      }),
      developedFor: developedForDto(row),
      // Every company, in order; the first is developedFor's. The cost is the
      // part's, so it is not repeated per deal.
      deals: dealRows.map((deal) => {
        const { costAmount, ...rest } = developedForDto(deal);
        return { id: deal.deal_id, ...rest };
      }),
      // How the part's item sheet is nested (057); null = the default chain.
      sectionTree: (() => {
        if (!row.section_tree_json) return null;
        try {
          return JSON.parse(row.section_tree_json);
        } catch (_) {
          return null;
        }
      })(),
      // Kept as aliases of the block above: the local replica has these two
      // cached in payloads it already wrote, and an older client still reads them.
      developedForClientId: row.developed_for_client_id || null,
      developedForClientName: row.developed_for_client_name || '',
      availableForPurchase: Boolean(row.available_for_purchase),
      // null until a sample run is recorded on this specific item.
      penPaperBaseline: parseJson(row.pen_paper_baseline_json, null),
      blankWidthMm: Number(row.blank_width_mm || 0),
      blankHeightMm: Number(row.blank_height_mm || 0),
      defaultPipelineId: row.default_pipeline_id || null,
      defaultPipelineName: row.default_pipeline_name
        || (row.default_pipeline_id ? (await desk.ask('pipelines.templates.row', { id: row.default_pipeline_id })).row?.name || null : null),
    };
  }

  return { rowToGroupDto, rowToItemDto, rowsToItemDtos };
}

module.exports = { createDto };
