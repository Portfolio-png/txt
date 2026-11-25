'use strict';

// Groups the app ships with, not ones a user made.
//
//   Raw Materials            raw_materials
//   ├── Rivets               raw_materials.rivets
//   └── Springs              raw_materials.springs
//
// They come back after a Clear Data or a Factory Reset: both wipe `groups` and
// then call ensurePrimaryGroupAndUnit (server.js), which calls
// ensureSystemGroups. Boot calls it too, so an existing database gains them.
//
// A system group is found by `groups.system_key`, never by its name. The old
// name checks disagreed with the seed ("Raw material" vs "Raw Materials"), so
// nothing actually recognised the seeded group. Each kind of raw material gets
// its own entry form, keyed to the same system_key.
//
// What a user may NOT do to one: delete it, archive it, rename it, move it
// under another parent, or change its type. Everything else (unit while it is
// empty, description, form sections) stays editable.

const SYSTEM_GROUPS = [
  {
    key: 'raw_materials',
    name: 'Raw Materials',
    parentKey: null,
    // Names this group has gone by, matched case-insensitively at the root, so
    // a database that already has one claims it instead of growing a twin.
    knownNames: ['raw materials', 'raw material'],
    unit: 'primary',
  },
  {
    key: 'raw_materials.rivets',
    name: 'Rivets',
    parentKey: 'raw_materials',
    knownNames: ['rivets', 'rivet'],
    // Rivets are consumed by the piece; a bought weight converts to pieces
    // through the item's own unit conversion.
    unit: 'piece',
  },
  {
    key: 'raw_materials.springs',
    name: 'Springs',
    parentKey: 'raw_materials',
    knownNames: ['springs', 'spring'],
    unit: 'piece',
  },
];

const SYSTEM_GROUP_BY_KEY = new Map(SYSTEM_GROUPS.map((g) => [g.key, g]));

function conflict(message) {
  const error = new Error(message);
  error.statusCode = 409;
  error.code = 'system_group';
  return error;
}

/// Creates the system groups that are missing and stamps the key on any that
/// already exist under a known name. Idempotent. Runs inside the caller's
/// transaction when there is one (Clear Data, Factory Reset).
///
/// `units` = { primary: id, piece: id } — the caller resolves them, because
/// right after a wipe only the caller knows the unit seed has run.
async function ensureSystemGroups({ run, get }, units) {
  const idByKey = new Map();
  for (const def of SYSTEM_GROUPS) {
    const parentId = def.parentKey ? idByKey.get(def.parentKey) : null;
    if (def.parentKey && !parentId) continue;

    let row = await get('SELECT id, is_archived, parent_group_id FROM groups WHERE system_key = ?', [def.key]);

    if (!row) {
      const placeholders = def.knownNames.map(() => '?').join(', ');
      row = await get(
        `SELECT id, is_archived, parent_group_id FROM groups
          WHERE system_key IS NULL
            AND group_type = 'item'
            AND ${parentId == null ? 'parent_group_id IS NULL' : 'parent_group_id = ?'}
            AND LOWER(TRIM(name)) IN (${placeholders})
          ORDER BY is_archived ASC, id ASC
          LIMIT 1`,
        [...(parentId == null ? [] : [parentId]), ...def.knownNames],
      );
      if (row) {
        await run('UPDATE groups SET system_key = ?, updated_at = ? WHERE id = ?', [
          def.key,
          new Date().toISOString(),
          row.id,
        ]);
      }
    }

    if (!row) {
      const now = new Date().toISOString();
      const unitId = units?.[def.unit] ?? units?.primary ?? null;
      const result = await run(
        `INSERT INTO groups (name, group_type, group_structure, description, parent_group_id, unit_id, system_key, is_archived, created_at, updated_at)
         VALUES (?, 'item', 'hierarchical', '', ?, ?, ?, 0, ?, ?)`,
        [def.name, parentId, unitId, def.key, now, now],
      );
      row = { id: result.lastID, is_archived: 0, parent_group_id: parentId };
    } else if (Number(row.is_archived) === 1) {
      // Archived before archiving was refused for these. A default is always there.
      await run('UPDATE groups SET is_archived = 0, updated_at = ? WHERE id = ?', [new Date().toISOString(), row.id]);
    }

    idByKey.set(def.key, row.id);
  }
  return idByKey;
}

function isSystemGroup(row) {
  return Boolean(row && row.system_key);
}

function assertSystemGroupDeletable(row) {
  if (isSystemGroup(row)) {
    throw conflict(`"${row.name}" is a default group and cannot be deleted.`);
  }
}

function assertSystemGroupArchivable(row) {
  if (isSystemGroup(row)) {
    throw conflict(`"${row.name}" is a default group and cannot be archived.`);
  }
}

/// `next` is what saveGroup is about to write.
function assertSystemGroupUpdate(existing, next) {
  if (!isSystemGroup(existing)) return;
  const sameParent =
    (existing.parent_group_id == null ? null : Number(existing.parent_group_id)) ===
    (next.parentGroupId == null ? null : Number(next.parentGroupId));
  if (String(next.name || '').trim() !== String(existing.name || '').trim()) {
    throw conflict(`"${existing.name}" is a default group and cannot be renamed.`);
  }
  if (!sameParent) {
    throw conflict(`"${existing.name}" is a default group and cannot be moved.`);
  }
  if ((next.groupType || 'item') !== (existing.group_type || 'item') ||
      (next.groupStructure || 'hierarchical') !== (existing.group_structure || 'hierarchical')) {
    throw conflict(`"${existing.name}" is a default group and its kind cannot change.`);
  }
}

module.exports = {
  SYSTEM_GROUPS,
  SYSTEM_GROUP_BY_KEY,
  ensureSystemGroups,
  isSystemGroup,
  assertSystemGroupDeletable,
  assertSystemGroupArchivable,
  assertSystemGroupUpdate,
};
