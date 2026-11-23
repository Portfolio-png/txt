'use strict';

// Saving an item and a group, and the reconcile helpers that make a group
// or an item by name when a challan is settled. saveItem retries once on a
// part-number clash.
//
// A factory: `deps` is what server.js still owns (the database helpers and
// a few shared helpers), `api` is the items service being assembled, through
// which these reach the sibling files; both are read at call time.

const { normalizeUnitValue } = require('../units/master');
const partIdentity = require('./part-identity');
const { buildVariantPartCode, groupLineage, nextPartNo, propertyCodeFor } = partIdentity;
const { mergeItemPropertySchema, normalizePropertyKey } = require('./property-keys');
const sectionTree = require('./section-tree');

function createSave(deps, api) {
  const { desk } = deps;
  const { all, get, logChange, run } = deps;
  const findItemDuplicate = (...args) => api.findItemDuplicate(...args);
  const getEffectiveSchema = (...args) => api.getEffectiveSchema(...args);
  const getGroupRowById = (...args) => api.getGroupRowById(...args);
  const getItemPropertySchema = (...args) => api.getItemPropertySchema(...args);
  const getItemRowById = (...args) => api.getItemRowById(...args);
  const getItemVariationTree = (...args) => api.getItemVariationTree(...args);
  const normalizeDevelopedFor = (...args) => api.normalizeDevelopedFor(...args);
  const normalizeMaterialTypeId = (...args) => api.normalizeMaterialTypeId(...args);
  const persistItemPropertySchema = (...args) => api.persistItemPropertySchema(...args);
  const sanitizeNodes = (...args) => api.sanitizeNodes(...args);
  const writeDealContacts = (...args) => api.writeDealContacts(...args);
  const normalizeDeals = (...args) => api.normalizeDeals(...args);
  const writeDeals = (...args) => api.writeDeals(...args);
  const syncDealsFromMirror = (...args) => api.syncDealsFromMirror(...args);

  async function findGroupDuplicate({ name, parentGroupId = null, excludeId = null }) {
    const rows = await all('SELECT id, name, parent_group_id FROM groups');
    const normalizedName = normalizeUnitValue(name);
    return rows.find((row) => {
      if (excludeId != null && row.id === excludeId) {
        return false;
      }
      return (
        normalizeUnitValue(row.name) === normalizedName &&
        (row.parent_group_id || null) === (parentGroupId || null)
      );
    }) || null;
  }

  async function groupWouldCreateCycle(groupId, parentGroupId) {
    const targetId = Number(groupId);
    // Normalized compare: a string id (e.g. straight off a route param) would
    // slip past a === check and let a cycle through.
    let currentId = parentGroupId == null ? null : Number(parentGroupId);
    const visited = new Set();
    while (currentId != null && Number.isFinite(currentId)) {
      if (currentId === targetId) {
        return true;
      }
      // A loop already present upstream: refuse rather than walk it forever.
      if (visited.has(currentId)) {
        return true;
      }
      visited.add(currentId);
      const row = await get('SELECT parent_group_id FROM groups WHERE id = ?', [currentId]);
      currentId = row?.parent_group_id == null ? null : Number(row.parent_group_id);
    }
    return false;
  }

  async function saveGroup({
    name,
    parentGroupId = null,
    unitId,
    id = null,
    groupType = 'item',
    groupStructure = 'hierarchical',
    description = '',
    // Per-group override of the item-form section layout. null clears it (fall
    // back to the user's own default); undefined leaves what is stored alone.
    itemFormSections,
  }) {
    const trimmedName = String(name || '').trim();
    // 'component' is nestable like an item group — it only differs in intent, so
    // everything downstream keys off isCombination and treats it the same way.
    const requestedStructure = String(groupStructure || 'hierarchical').toLowerCase();
    const normalizedStructure = ['combination', 'component'].includes(requestedStructure)
      ? requestedStructure
      : 'hierarchical';
    const isCombination = normalizedStructure === 'combination';
    // A component holds items that each carry their own unit, so it needs none
    // of its own. Everything else about it behaves like an item group, which is
    // why this is checked separately rather than folded into isCombination.
    const isComponent = normalizedStructure === 'component';
    const trimmedDescription = String(description || '').trim();
    const serializedFormSections =
      itemFormSections && typeof itemFormSections === 'object'
        ? JSON.stringify(itemFormSections)
        : null;
    // A combination group may be nested under a hierarchical group when the
    // caller names one, so a variant set can live inside the item group it
    // belongs to. It is never auto-attached to the Primary Group the way a
    // hierarchical group is — left alone it stays top level — and its unit stays
    // optional (members carry their own).
    let normalizedParentId = parentGroupId == null ? null : Number(parentGroupId);
    let normalizedUnitId = unitId ? Number(unitId) : null;

    if (
      !isCombination &&
      normalizedParentId == null &&
      trimmedName !== 'Primary Group' &&
      trimmedName !== 'Raw material' &&
      trimmedName !== 'Scrap'
    ) {
      const pg = await get('SELECT id FROM groups WHERE name = "Primary Group" AND parent_group_id IS NULL AND group_type = ?', [groupType]);
      if (pg && pg.id !== id) {
        normalizedParentId = pg.id;
      }
    }

    if (!trimmedName) {
      throw new Error('name is required.');
    }
    if (!isCombination && !isComponent && groupType !== 'machine' && !normalizedUnitId) {
      throw new Error('unitId is required for non-machine hierarchical groups.');
    }

    if (normalizedUnitId) {
      const { row: unitRow } = await desk.ask('units.rows.get', { id: normalizedUnitId });
      if (!unitRow || unitRow.is_archived) {
        const error = new Error('Selected unit does not exist or is archived.');
        error.statusCode = 400;
        throw error;
      }
    }

    if (id != null && normalizedParentId === id) {
      const error = new Error('A group cannot be its own parent.');
      error.statusCode = 409;
      throw error;
    }

    if (normalizedParentId != null) {
      const parentRow = await get('SELECT * FROM groups WHERE id = ?', [normalizedParentId]);
      if (!parentRow || parentRow.is_archived) {
        const error = new Error('Selected parent group is not available.');
        error.statusCode = 400;
        throw error;
      }
      if (id != null && await groupWouldCreateCycle(id, normalizedParentId)) {
        const error = new Error('A group cannot move under its own descendant.');
        error.statusCode = 409;
        throw error;
      }
    }

    const duplicate = await findGroupDuplicate({
      name: trimmedName,
      parentGroupId: normalizedParentId,
      excludeId: id,
    });
    if (duplicate) {
      const error = new Error('A group with the same name already exists here.');
      error.statusCode = 409;
      throw error;
    }

    const now = new Date().toISOString();
    if (id == null) {
      const result = await run(
        `
        INSERT INTO groups (name, group_type, group_structure, description, parent_group_id, unit_id, item_form_sections, is_archived, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
        `,
        [trimmedName, groupType, normalizedStructure, trimmedDescription, normalizedParentId, normalizedUnitId, serializedFormSections, now, now],
      );
      return getGroupRowById(result.lastID);
    }

    const existing = await getGroupRowById(id);
    if (!existing) {
      const error = new Error('Group not found.');
      error.statusCode = 404;
      throw error;
    }
    const blockingUsage = await get(
      `
      SELECT
        (SELECT COUNT(*) FROM groups AS child_groups WHERE child_groups.parent_group_id = ? AND child_groups.is_archived = 0) AS active_child_count,
        (SELECT COUNT(*) FROM items WHERE items.group_id = ? AND items.is_archived = 0) AS active_item_count
      `,
      [id, id],
    );
    const nullableEquals = (a, b) =>
      (a == null ? null : Number(a)) === (b == null ? null : Number(b));

    // Used groups are editable: a group legitimately gains and loses fields over
    // its life, and the schema handles that by retaining what it can no longer
    // show (see retireMissingGroupProperties) rather than by freezing the group.
    //
    // The one exception is the unit. Every stock figure, conversion and order
    // line under this group is denominated in it, so swapping it out silently
    // rewrites the meaning of existing numbers rather than just hiding a field.
    const isUnitChange = !nullableEquals(normalizedUnitId, existing.unit_id);
    if (isUnitChange && Number(blockingUsage?.active_item_count || 0) > 0) {
      const error = new Error(
        "This group's unit cannot be changed while it has items — existing " +
          'quantities are recorded in the current unit.',
      );
      error.statusCode = 409;
      throw error;
    }

    await run(
      'UPDATE groups SET name = ?, group_type = ?, group_structure = ?, description = ?, parent_group_id = ?, unit_id = ?, item_form_sections = ?, updated_at = ? WHERE id = ?',
      [
        trimmedName,
        groupType,
        normalizedStructure,
        trimmedDescription,
        normalizedParentId,
        normalizedUnitId,
        itemFormSections !== undefined ? serializedFormSections : (existing.item_form_sections || null),
        now,
        id,
      ],
    );
    return getGroupRowById(id);
  }

  function buildItemDisplayName(name, alias, quantity) {
    const parts = [String(name || '').trim(), String(alias || '').trim()].filter(Boolean);
    return parts.join(' / ');
  }

  /// A create the server stamps is retried when another create took its code
  /// between the free-number check and the insert. That clash is the server's
  /// own race, not the caller's choice, and "an automatic stamp must never block
  /// a save the caller did ask for" — the retry finds the next free number.
  // `options.useTransaction: false` is for a caller that is already inside a
  // transaction (the in-use challan settle creates its scrap items mid-settle):
  // SQLite has no nested BEGIN, and that caller then owns the commit and rollback.
  async function saveItem(input = {}, options = {}) {
    const stamped =
      (input.id === null || input.id === undefined) &&
      input.partNo === undefined &&
      input.partCode === undefined;
    for (let attempt = 0; ; attempt += 1) {
      try {
        return await saveItemOnce(input, options);
      } catch (error) {
        if (!stamped || attempt >= 2 || error?.code !== 'part_code_duplicate') throw error;
      }
    }
  }

  async function saveItemOnce({
    name,
    alias = '',
    displayName = '',
    quantity = 0,
    groupId,
    unitId,
    unitConversions = [],
    namingFormat = [],
    variationTree = [],
    defaultPipelineId = null,
    baseItemId = null,
    photoUrl = null,
    // Left undefined-able on purpose: internal callers (seeds, ensureItemRecord)
    // never send these, and an update must preserve what is already stored.
    cadFileKey,
    cadFileName,
    // Same undefined-preserving contract as the CAD fields: a caller that does
    // not mention these child records must not have them wiped.
    attachments,
    machineIds,
    dieIds,
    developedForClientId,
    availableForPurchase,
    // Same undefined-preserving contract: an update that doesn't mention the
    // sample baseline keeps whatever is already recorded. `null` clears it.
    penPaperBaseline,
    blankWidthMm,
    blankHeightMm,
    // The number this part is issued and the code read off a drawing
    // (migrations/045). Same undefined-preserving contract as everything above:
    // an update that does not mention them keeps what was stamped.
    partNo,
    partCode,
    // Who the part was developed for (migrations/047). Same contract again:
    // absent preserves, and a block with kind 'self' is how it is cleared.
    developedFor,
    // Several companies, each with its quotation (item_deals, 2026-11-24): the
    // whole list in order. Absent preserves; [] clears. The first is mirrored
    // into the flat columns. With it, developedFor speaks only for the cost.
    deals,
    id = null,
  }, { useTransaction = true } = {}) {
    const trimmedName = String(name || '').trim();
    const trimmedAlias = String(alias || '').trim();
    const serializedNamingFormat = JSON.stringify(Array.isArray(namingFormat) ? namingFormat : []);
    const quantityNumber = Number(quantity ?? 0);
    const normalizedQuantity = Number.isFinite(quantityNumber) ? quantityNumber : 0;
    const trimmedDisplayName =
      String(displayName || '').trim() || buildItemDisplayName(name, alias, normalizedQuantity);
    const normalizedGroupId = Number(groupId);
    const normalizedUnitId = Number(unitId);
    const normalizedBaseItemId = baseItemId ? Number(baseItemId) : null;

    if (
      !trimmedName ||
      !normalizedGroupId ||
      !normalizedUnitId ||
      !trimmedDisplayName
    ) {
      throw new Error('name, displayName, groupId, and unitId are required.');
    }

    const groupRow = await get('SELECT * FROM groups WHERE id = ?', [normalizedGroupId]);
    if (!groupRow || groupRow.is_archived) {
      const error = new Error('Selected group does not exist or is archived.');
      error.statusCode = 400;
      throw error;
    }

    const { row: unitRow } = await desk.ask('units.rows.get', { id: normalizedUnitId });
    if (!unitRow || unitRow.is_archived) {
      const error = new Error('Selected unit does not exist or is archived.');
      error.statusCode = 400;
      throw error;
    }

    const normalizedUnitConversions = [];
    const seenConversionUnits = new Set();
    for (const entry of Array.isArray(unitConversions) ? unitConversions : []) {
      const secondaryUnitId = Number(entry?.unitId);
      const factorToPrimary = Number(entry?.factorToPrimary);

      if (!secondaryUnitId || !Number.isFinite(factorToPrimary) || factorToPrimary <= 0) {
        const error = new Error('Secondary unit conversions must include a valid unit and a factor greater than 0.');
        error.statusCode = 400;
        throw error;
      }
      if (secondaryUnitId === normalizedUnitId) {
        continue;
      }
      if (seenConversionUnits.has(secondaryUnitId)) {
        const error = new Error('Each secondary unit can only be added once.');
        error.statusCode = 409;
        throw error;
      }

      const { row: secondaryUnitRow } = await desk.ask('units.rows.get', { id: secondaryUnitId });
      if (!secondaryUnitRow || secondaryUnitRow.is_archived) {
        const error = new Error('Secondary unit does not exist or is archived.');
        error.statusCode = 400;
        throw error;
      }

      seenConversionUnits.add(secondaryUnitId);
      normalizedUnitConversions.push({
        unitId: secondaryUnitId,
        factorToPrimary,
      });
    }

    // Upper-cased on the way in, so the unique index is effectively
    // case-insensitive without redeclaring the column COLLATE NOCASE.
    const normalizedPartCode =
      partCode === undefined ? undefined : String(partCode || '').trim().toUpperCase();
    let normalizedPartNo;
    if (partNo !== undefined) {
      if (partNo === null || partNo === '') {
        normalizedPartNo = null;
      } else {
        const parsed = Number(partNo);
        if (!Number.isInteger(parsed) || parsed <= 0) {
          // Not silently nulled: a number the caller meant is either usable or
          // worth refusing, and the backend is where that is decided.
          const error = new Error('Part number must be a whole number above zero.');
          error.statusCode = 400;
          throw error;
        }
        normalizedPartNo = parsed;
      }
    }

    // Resolved before BEGIN, so a bad party is a 400 that costs nothing and
    // leaves the rest of the edit sitting in the form.
    let normalizedDevelopedFor = await normalizeDevelopedFor(developedFor);
    const normalizedDeals = await normalizeDeals(deals, id);
    if (normalizedDeals !== undefined) {
      // The flat columns are the first deal's; the cost is the part's own.
      const costAmount = normalizedDevelopedFor ? normalizedDevelopedFor.costAmount : undefined;
      const first = normalizedDeals[0];
      normalizedDevelopedFor = first
        ? { ...first, costAmount }
        : {
          kind: '', clientId: null, subContractorId: null, at: null,
          quotationAmount: null, costAmount, contactIds: [],
        };
    }

    // Another Alloy or Thickness under the same name is another part (B):
    // the duplicate is the same name AND the same alloy and thickness.
    const duplicate = await findItemDuplicate({
      name: trimmedName,
      groupId: normalizedGroupId,
      unitId: normalizedUnitId,
      excludeId: id,
      identity: partIdentity.identityOfTree(variationTree),
    });
    if (duplicate) {
      // Named rather than generic, because the rule surprises people: the key is
      // name + group + unit + alloy + thickness, and the SET is not in it.
      // Someone filing "Patti" under Dolly and again under Chakri reads the type
      // as the thing that tells them apart, and it is not.
      const described = partIdentity.describeIdentity(variationTree);
      const error = new Error(
        `"${trimmedName}"${described ? ` with ${described}` : ''} already exists in this group. ` +
          'A part with the same name needs at least one property that differs (alloy, thickness or any other), even across types — ' +
          'change one, or pick the existing part from the list.',
      );
      error.statusCode = 409;
      error.code = 'item_name_duplicate';
      throw error;
    }

    // Checked here so the refusal can name the part that holds the code; the
    // unique index below is the real guard and catches the race this cannot.
    if (normalizedPartCode) {
      const clash = await get(
        `SELECT id, name FROM items
          WHERE group_id = ? AND part_code = ? AND (? IS NULL OR id <> ?)`,
        [normalizedGroupId, normalizedPartCode, id, id],
      );
      if (clash) {
        const error = new Error(
          `Part code "${normalizedPartCode}" is already used by "${clash.name}" in this group.`,
        );
        error.statusCode = 409;
        error.code = 'part_code_duplicate';
        throw error;
      }
    }



    const sanitizedTree = sanitizeNodes(variationTree, 'property');
    const comparableTree = (nodes = []) =>
      (nodes || [])
        .map((node) => ({
          id: node.id || null,
          kind: node.kind,
          name: String(node.name || '').trim(),
          displayName: String(node.displayName || '').trim(),
          // H-1 fix: include 'code' so that renaming a variation node's barcode/
          // naming code on a used item is correctly treated as a structural change.
          code: String(node.code || '').trim(),
          inputType: String(node.inputType || 'Text').trim() || 'Text',

          children: comparableTree(node.children || []),
        }))
        .sort((a, b) => a.name.localeCompare(b.name));

    // Nobody said anything about identity on a create, so stamp one. The rule
    // belongs here rather than in whichever form happened to be open — the
    // wizard sends its own (asked for through /api/items/next-part-identity,
    // which shares this module), and everything else gets the group's next
    // unfiled number.
    //
    // Best effort, deliberately: MAX over the unfiled scope is NOT monotonic,
    // because an item leaves that scope the moment it joins a set, so a number
    // can be handed out twice. A clash here therefore means no code rather than
    // a refused create — an automatic stamp must never block a save the caller
    // did ask for.
    let autoPartNo = normalizedPartNo;
    let autoPartCode = normalizedPartCode;
    if (id == null && partNo === undefined && partCode === undefined) {
      // One code per top-level property, in the order they were declared. The
      // tree is already sanitized, already property-kind at the top, and already
      // ordered by position, so this is the payload's own order.
      //
      // The shop's explicit code on a value wins — that field exists so somebody
      // can say "Brass is B" once — and propertyCodeFor is the answer when
      // nobody did.
      const valueCodes = [];
      for (const property of sanitizedTree) {
        const value = (property?.children || [])[0];
        if (!value) continue;
        const explicit = String(value.code || '').trim();
        const code = explicit || propertyCodeFor(value.name);
        if (code) valueCodes.push(code);
      }

      // The next free number, not simply the next one.
      //
      // Two names in a group can reduce to the same letters — "Patti" and
      // "Plate" are both P — and with the number scoped by name they both start
      // at 1, so both derive one code. This used to leave the second part with NO
      // code at all, silently: a part nothing can look up. Taking the next number
      // keeps the create working and keeps the part findable, and migration 045
      // already says part_no is "a STAMP, not a sequence invariant" whose
      // "durable guard is the unique index on the code".
      const lineage = await groupLineage(normalizedGroupId, { get });
      const firstNo = await nextPartNo(
        { groupId: normalizedGroupId, itemName: trimmedName },
        { get, all },
      );
      for (let attempt = 0; attempt < 50; attempt += 1) {
        const candidateNo = firstNo + attempt;
        const candidateCode = buildVariantPartCode({
          // The whole lineage, not just the group the part sits in. A part filed
          // under "Switch Action › Dolly" is stored against Dolly, so the row in
          // hand names only the child.
          groupName: lineage.slice(0, -1).join(' '),
          setName: lineage.length ? lineage[lineage.length - 1] : '',
          itemName: trimmedName,
          valueCodes,
          partNo: candidateNo,
        });
        if (!candidateCode) break;
        const taken = await get(
          'SELECT id FROM items WHERE group_id = ? AND part_code = ?',
          [normalizedGroupId, candidateCode],
        );
        if (!taken) {
          autoPartNo = candidateNo;
          autoPartCode = candidateCode;
          break;
        }
      }
    } else if (id == null && partNo === undefined && normalizedPartCode) {
      // A code was typed and the number was not: the code is the caller's, the
      // number is still this module's to stamp — a part filed with a code and
      // no number used to be the only way the sheet could save a typed code.
      autoPartNo = await nextPartNo(
        { groupId: normalizedGroupId, itemName: trimmedName },
        { get, all },
      );
    }

    const now = new Date().toISOString();
    if (useTransaction) await run('BEGIN TRANSACTION');
    try {
      let itemId = id;
      let structuralChangeDetected = false;
      if (id == null) {
        const result = await run(
          `
          INSERT INTO items (
            name, alias, display_name, quantity, group_id, unit_id, naming_format, is_archived, default_pipeline_id, base_item_id, photo_url, cad_file_key, cad_file_name, developed_for_client_id, developed_for_kind, developed_for_sub_contractor_id, developed_for_at, developed_for_quotation_amount, developed_for_cost_amount, available_for_purchase, pen_paper_baseline_json, blank_width_mm, blank_height_mm, part_no, part_code, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          `,
          [
            trimmedName,
            trimmedAlias,
            trimmedDisplayName,
            normalizedQuantity,
            normalizedGroupId,
            normalizedUnitId,
            serializedNamingFormat,
            defaultPipelineId || null,
            normalizedBaseItemId,
            photoUrl || null,
            String(cadFileKey || '').trim() || null,
            String(cadFileName || '').trim(),
            // developedForClientId is the pre-047 way of saying the same thing.
            // The block wins where both arrive, because it also carries the kind.
            normalizedDevelopedFor
              ? normalizedDevelopedFor.clientId
              : (developedForClientId ? Number(developedForClientId) : null),
            normalizedDevelopedFor
              ? normalizedDevelopedFor.kind
              : (developedForClientId ? 'client' : ''),
            normalizedDevelopedFor ? normalizedDevelopedFor.subContractorId : null,
            normalizedDevelopedFor ? normalizedDevelopedFor.at : null,
            normalizedDevelopedFor ? normalizedDevelopedFor.quotationAmount : null,
            normalizedDevelopedFor ? (normalizedDevelopedFor.costAmount ?? null) : null,
            availableForPurchase ? 1 : 0,
            penPaperBaseline ? JSON.stringify(penPaperBaseline) : null,
            Number(blankWidthMm || 0),
            Number(blankHeightMm || 0),
            autoPartNo === undefined ? null : autoPartNo,
            autoPartCode === undefined ? '' : autoPartCode,
            now,
            now,
          ],
        );
        itemId = result.lastID;
        if (normalizedDevelopedFor && normalizedDevelopedFor.contactIds) {
          await writeDealContacts(itemId, normalizedDevelopedFor.contactIds);
        }
      } else {
        const existing = await getItemRowById(id);
        if (!existing) {
          const error = new Error('Item not found.');
          error.statusCode = 404;
          throw error;
        }
        if ((existing.usage_count || 0) > 0) {
          const existingTree = await getItemVariationTree(id);
          structuralChangeDetected =
            Number(existing.group_id || 0) !== normalizedGroupId ||
            Number(existing.unit_id || 0) !== normalizedUnitId ||
            JSON.stringify(comparableTree(existingTree)) !==
              JSON.stringify(comparableTree(sanitizedTree));
        }
        await run(
          `
          UPDATE items
          SET name = ?, alias = ?, display_name = ?, quantity = ?, group_id = ?, unit_id = ?, naming_format = ?, default_pipeline_id = ?, base_item_id = ?, photo_url = ?, cad_file_key = ?, cad_file_name = ?, developed_for_client_id = ?, developed_for_kind = ?, developed_for_sub_contractor_id = ?, developed_for_at = ?, developed_for_quotation_amount = ?, developed_for_cost_amount = ?, available_for_purchase = ?, pen_paper_baseline_json = ?, blank_width_mm = ?, blank_height_mm = ?, part_no = ?, part_code = ?, updated_at = ?
          WHERE id = ?
          `,
          [
            trimmedName,
            trimmedAlias,
            trimmedDisplayName,
            normalizedQuantity,
            normalizedGroupId,
            normalizedUnitId,
            serializedNamingFormat,
            defaultPipelineId !== undefined
              ? (defaultPipelineId ? String(defaultPipelineId).trim() : null)
              : (existing.default_pipeline_id || null),
            // Same preservation rule as the CAD fields. The item editor's update
            // payload omits baseItemId, so writing it unconditionally detached
            // every spawned variant from its base on the first save.
            baseItemId !== undefined && baseItemId !== null
              ? normalizedBaseItemId
              : (existing.base_item_id || null),
            // photoUrl was the odd one out: written unconditionally, so ANY patch
            // that did not mention it silently wiped the item's photo. Now
            // undefined-preserving like cad_file_key/cad_file_name beside it.
            // `photoUrl = null` in the signature means it is never `undefined`,
            // so absence is detected as null. Clearing still works: the client
            // sends '' for "no photo", which falls through to null.
            photoUrl !== undefined && photoUrl !== null
              ? (photoUrl || null)
              : (existing.photo_url || null),
            // Same preservation rule as available_for_purchase: an internal
            // re-save that omits the CAD fields must not clear them.
            cadFileKey !== undefined
              ? (String(cadFileKey || '').trim() || null)
              : (existing.cad_file_key || null),
            cadFileName !== undefined
              ? String(cadFileName || '').trim()
              : (existing.cad_file_name || ''),
            // The block, then the legacy single field, then what is stored.
            normalizedDevelopedFor
              ? normalizedDevelopedFor.clientId
              : developedForClientId !== undefined
                ? (developedForClientId ? Number(developedForClientId) : null)
                : (existing.developed_for_client_id || null),
            normalizedDevelopedFor
              ? normalizedDevelopedFor.kind
              : developedForClientId !== undefined
                ? (developedForClientId ? 'client' : '')
                : (existing.developed_for_kind || ''),
            normalizedDevelopedFor
              ? normalizedDevelopedFor.subContractorId
              : developedForClientId !== undefined
                // The legacy field can only ever mean a client, so naming one
                // retires whatever contractor was recorded.
                ? null
                : (existing.developed_for_sub_contractor_id || null),
            normalizedDevelopedFor
              ? normalizedDevelopedFor.at
              : (existing.developed_for_at || null),
            normalizedDevelopedFor
              ? normalizedDevelopedFor.quotationAmount
              : (existing.developed_for_quotation_amount ?? null),
            // `??` not `||`: a cost of 0 is a real figure ("the toolmaker did it
            // for nothing"), and `||` would discard it and re-read the old value.
            normalizedDevelopedFor && normalizedDevelopedFor.costAmount !== undefined
              ? normalizedDevelopedFor.costAmount
              : (existing.developed_for_cost_amount ?? null),
            // Preserve the existing flag when the caller didn't send it (e.g. an
            // internal re-seed via ensureItemRecord) instead of resetting to 0.
            availableForPurchase !== undefined
              ? (availableForPurchase ? 1 : 0)
              : (existing.available_for_purchase ? 1 : 0),
            penPaperBaseline !== undefined
              ? (penPaperBaseline ? JSON.stringify(penPaperBaseline) : null)
              : (existing.pen_paper_baseline_json || null),
            blankWidthMm !== undefined
              ? Number(blankWidthMm || 0)
              : Number(existing.blank_width_mm || 0),
            blankHeightMm !== undefined
              ? Number(blankHeightMm || 0)
              : Number(existing.blank_height_mm || 0),
            // A part's identity is issued once. Every caller that does not speak
            // about it keeps what was stamped — the item editor and every
            // internal re-save go through here.
            normalizedPartNo !== undefined
              ? normalizedPartNo
              : (existing.part_no ?? null),
            normalizedPartCode !== undefined
              ? normalizedPartCode
              : (existing.part_code || ''),
            now,
            id,
          ],
        );

        // The deal's people (056). Sent → replace. Not sent → keep, unless the
        // part no longer belongs to the same client: the ticks were people at
        // the old company and would now name strangers.
        let dealContactIds = normalizedDevelopedFor ? normalizedDevelopedFor.contactIds : undefined;
        if (dealContactIds === undefined) {
          const nextClientId = normalizedDevelopedFor
            ? normalizedDevelopedFor.clientId
            : developedForClientId !== undefined
              ? (developedForClientId ? Number(developedForClientId) : null)
              : (existing.developed_for_client_id || null);
          const nextKind = normalizedDevelopedFor
            ? normalizedDevelopedFor.kind
            : developedForClientId !== undefined
              ? (developedForClientId ? 'client' : '')
              : (existing.developed_for_kind || (existing.developed_for_client_id ? 'client' : ''));
          const sameClient =
            nextKind === 'client' &&
            Number(nextClientId || 0) === Number(existing.developed_for_client_id || 0);
          if (!sameClient) dealContactIds = [];
        }
        if (dealContactIds !== undefined) {
          await writeDealContacts(id, dealContactIds);
        }
      }

      // The deals: written whole when sent; brought into line with the flat
      // columns when only the one deal was spoken about.
      if (normalizedDeals !== undefined) {
        await writeDeals(itemId, normalizedDeals);
      } else if (developedFor !== undefined || developedForClientId !== undefined) {
        await syncDealsFromMirror(itemId);
      }

      if (structuralChangeDetected) {
        await run(
          'UPDATE item_variation_nodes SET is_archived = 1, updated_at = ? WHERE item_id = ? AND is_archived = 0',
          [now, itemId]
        );
      }

      const existingNodesRows = structuralChangeDetected
        ? []
        : await all('SELECT id FROM item_variation_nodes WHERE item_id = ? AND is_archived = 0', [itemId]);
      const existingNodeIds = new Set(existingNodesRows.map(row => row.id));
      const processedNodeIds = new Set();

      const upsertNodes = async (nodes, parentNodeId = null) => {
        for (const node of nodes) {
          let nodeId = node.id;

          if (nodeId && existingNodeIds.has(nodeId)) {
            await run(
              `
              UPDATE item_variation_nodes
              SET parent_node_id = ?, name = ?, code = ?, display_name = ?, input_type = ?, name_join = ?, numeric_min = ?, numeric_max = ?, material_type_id = ?, position = ?, updated_at = ?
              WHERE id = ?
              `,
              [
                parentNodeId,
                node.name,
                node.code || '',
                node.displayName,
                node.inputType || 'Text',
                node.nameJoin || '',
                node.numericMin ?? null,
                node.numericMax ?? null,
                normalizeMaterialTypeId(node.materialTypeId),
                node.position,
                now,
                nodeId,
              ]
            );
          } else {
            const result = await run(
              `
              INSERT INTO item_variation_nodes (
                item_id, parent_node_id, kind, name, code, display_name, input_type, name_join,
                numeric_min, numeric_max, material_type_id, position,
                is_archived, created_at, updated_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
              `,
              [
                itemId,
                parentNodeId,
                node.kind,
                node.name,
                node.code || '',
                node.displayName,
                node.inputType || 'Text',
                node.nameJoin || '',
                node.numericMin ?? null,
                node.numericMax ?? null,
                normalizeMaterialTypeId(node.materialTypeId),
                node.position,
                now,
                now,
              ],
            );
            nodeId = result.lastID;
          }
          processedNodeIds.add(nodeId);

          await upsertNodes(node.children || [], nodeId);
        }
      };

      await upsertNodes(sanitizedTree);

      for (const oldId of existingNodeIds) {
        if (!processedNodeIds.has(oldId)) {
          await run('UPDATE item_variation_nodes SET is_archived = 1, updated_at = ? WHERE id = ?', [now, oldId]);
        }
      }

      if (attachments !== undefined) {
        await run('DELETE FROM item_attachments WHERE item_id = ?', [itemId]);
        const attachmentList = Array.isArray(attachments) ? attachments : [];
        let attachmentPosition = 0;
        for (const attachment of attachmentList) {
          const objectKey = String(attachment?.objectKey || '').trim();
          if (!objectKey) {
            continue;
          }
          await run(
            `
            INSERT INTO item_attachments (
              item_id, label, object_key, file_name, position, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            `,
            [
              itemId,
              String(attachment?.label || '').trim(),
              objectKey,
              String(attachment?.fileName || '').trim(),
              attachmentPosition,
              now,
              now,
            ],
          );
          attachmentPosition += 1;
        }
      }

      if (machineIds !== undefined) {
        await run('DELETE FROM item_machines WHERE item_id = ?', [itemId]);
        const uniqueMachineIds = [
          ...new Set(
            (Array.isArray(machineIds) ? machineIds : [])
              .map((value) => Number(value))
              .filter((value) => Number.isInteger(value) && value > 0),
          ),
        ];
        for (const machineId of uniqueMachineIds) {
          // Skip silently rather than 500 on a machine deleted since the form
          // was opened.
          const { row: machineRow } = await desk.ask('machines.rows.get', { id: machineId });
          if (!machineRow) {
            continue;
          }
          await run(
            'INSERT OR IGNORE INTO item_machines (item_id, machine_id, created_at) VALUES (?, ?, ?)',
            [itemId, machineId, now],
          );
        }
      }

      if (dieIds !== undefined) {
        await run('DELETE FROM item_dies WHERE item_id = ?', [itemId]);
        const uniqueDieIds = [
          ...new Set(
            (Array.isArray(dieIds) ? dieIds : [])
              .map((value) => Number(value))
              .filter((value) => Number.isInteger(value) && value > 0),
          ),
        ];
        for (const dieId of uniqueDieIds) {
          const { row: dieRow } = await desk.ask('dies.rows.get', { id: dieId });
          if (!dieRow) {
            continue;
          }
          await run(
            'INSERT OR IGNORE INTO item_dies (item_id, die_id, created_at) VALUES (?, ?, ?)',
            [itemId, dieId, now],
          );
        }
      }

      await run('DELETE FROM item_unit_conversions WHERE item_id = ?', [itemId]);
      for (const conversion of normalizedUnitConversions) {
        await run(
          `
          INSERT INTO item_unit_conversions (
            item_id,
            unit_id,
            factor_to_primary,
            created_at,
            updated_at
          ) VALUES (?, ?, ?, ?, ?)
          `,
          [
            itemId,
            conversion.unitId,
            conversion.factorToPrimary,
            now,
            now,
          ],
        );
      }

      const existingPropertySchema = await getItemPropertySchema(itemId);
      const effectiveSchema = await getEffectiveSchema(normalizedGroupId);
      const topLevelPropertiesByKey = new Map(
        sanitizedTree
          .filter((node) => node.kind === 'property')
          .map((node) => [
            normalizePropertyKey(node.name),
            node,
          ])
          .filter(([key]) => Boolean(key)),
      );
      for (const draft of effectiveSchema.propertyDrafts || []) {
        if (!draft?.mandatory) {
          continue;
        }
        const propertyKey = normalizePropertyKey(draft.propertyKey || draft.name);
        if (!propertyKey) {
          continue;
        }
        const propertyNode = topLevelPropertiesByKey.get(propertyKey);
        const hasDirectValueChild =
          propertyNode &&
          Array.isArray(propertyNode.children) &&
          propertyNode.children.some(
            (child) => child.kind === 'value' && String(child.name || '').trim(),
          );
        if (!hasDirectValueChild) {
          const error = new Error(
            `Provide at least one value for required property "${draft.name}".`,
          );
          error.statusCode = 400;
          throw error;
        }
      }
      await persistItemPropertySchema(
        itemId,
        mergeItemPropertySchema({
          variationTree: sanitizedTree,
          effectiveDrafts: effectiveSchema.propertyDrafts,
          existingSchema: existingPropertySchema,
        }),
        now,
      );

      await logChange('items', itemId, id == null ? 'INSERT' : 'UPDATE');
      if (useTransaction) await run('COMMIT');
      // The section tree's cross-links follow whatever the save just changed —
      // a new die, a different client, a machine taken off. After the commit and
      // never failing the save: the part is written either way.
      try {
        await sectionTree.reconcileSectionLinks({ get, all, desk }, itemId);
      } catch (error) {
        // Before migration 057 (a seed at first boot) the column is not there.
        if (!/no such (column|table)/.test(String(error?.message || ''))) {
          console.error('[Items] section tree links not reconciled:', error.message);
        }
      }
      return getItemRowById(itemId);
    } catch (error) {
      if (useTransaction) await run('ROLLBACK');
      // The pre-check above cannot see a code another connection wrote between
      // its read and this write. The index can, and a raw SQLITE_CONSTRAINT must
      // not reach a client as a 500.
      if (/UNIQUE constraint failed: items\.group_id, items\.part_code/.test(String(error?.message || ''))) {
        // `autoPartCode` when the save was stamped rather than told. Reading
        // `normalizedPartCode` alone printed `Part code "undefined" was just
        // taken`, because an auto-stamped create never set it.
        const clashed = normalizedPartCode ?? autoPartCode ?? '';
        const conflict = new Error(
          `Part code "${clashed}" was just taken by another part in this group.`,
        );
        conflict.statusCode = 409;
        conflict.code = 'part_code_duplicate';
        throw conflict;
      }
      throw error;
    }
  }

  async function ensureReconcilePrimaryGroup() {
    let primary = await get(
      `SELECT id, unit_id FROM groups WHERE lower(name) = 'primary group' AND parent_group_id IS NULL ORDER BY id LIMIT 1`,
    );
    if (primary) return primary;
    const { row: fallbackUnit } = await desk.ask('units.rows.first', {});
    const dto = {
      name: 'Primary Group',
      groupType: 'item',
      groupStructure: 'hierarchical',
      description: 'Root item group',
      parentGroupId: null,
      unitId: fallbackUnit?.id || null,
    };
    const { id } = await saveGroup(dto);
    return { id, unit_id: fallbackUnit?.id || null };
  }

  async function ensureReconcileSubGroup(name, parentGroupId, unitId) {
    const existing = await get(
      `SELECT id FROM groups WHERE lower(name) = lower(?) AND parent_group_id = ? AND group_type = 'item' ORDER BY id LIMIT 1`,
      [name, parentGroupId],
    );
    if (existing) return existing.id;
    const dto = {
      name,
      groupType: 'item',
      groupStructure: 'hierarchical',
      description: 'Internal-use reconciliation returns',
      parentGroupId,
      unitId,
    };
    const { id } = await saveGroup(dto);
    return id;
  }

  async function ensureReconcileItem(name, groupId, unitId, options = {}) {
    const existing = await get(
      `SELECT id FROM items WHERE lower(name) = lower(?) AND group_id = ? ORDER BY id LIMIT 1`,
      [name, groupId],
    );
    if (existing) return existing.id;
    const dto = {
      name,
      alias: '',
      displayName: name,
      quantity: 0,
      groupId,
      unitId,
    };
    const { id } = await saveItem(dto, options);
    return id;
  }

  return { findGroupDuplicate, groupWouldCreateCycle, saveGroup, buildItemDisplayName, saveItem, saveItemOnce, ensureReconcilePrimaryGroup, ensureReconcileSubGroup, ensureReconcileItem };
}

module.exports = { createSave };
