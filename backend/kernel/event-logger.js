'use strict';

// ---------------------------------------------------------------------------
// Paper Event Logger — Canonical Append-Only Domain Event Standard
//
// Adheres strictly to design-philosophy §4:
//   - E1. Append-Only (Immutability): Event rows are never updated or deleted.
//   - E2. Floor Time vs Entry Time: occurred_at vs recorded_at.
//   - E3. Single Shared Vocabulary: item_variant_created, party_quote_linked,
//         die_process_linked, machine_allocated.
//   - E4. Payload Minimality: Only relevant facts.
//   - E5. State Rebuildability: Downstream current-state tables are rebuildable.
// ---------------------------------------------------------------------------

const EVENT_VOCABULARY = Object.freeze({
  ITEM_CREATED: 'item_created',
  ITEM_VARIANT_CREATED: 'item_variant_created',
  ITEM_VARIANT_UPDATED: 'item_variant_updated',
  ITEM_VARIANT_DELETED: 'item_variant_deleted',
  PARTY_QUOTE_LINKED: 'party_quote_linked',
  PARTY_QUOTE_UPDATED: 'party_quote_updated',
  PARTY_QUOTE_UNLINKED: 'party_quote_unlinked',
  DIE_PROCESS_LINKED: 'die_process_linked',
  DIE_PROCESS_DELETED: 'die_process_deleted',
  MACHINE_ALLOCATED: 'machine_allocated',
  MACHINE_DEALLOCATED: 'machine_deallocated',
});

/**
 * Ensures the canonical event table exists in SQLite.
 * @param {Function} run - DB execute helper
 */
async function ensureEventTable(run) {
  await run(`
    CREATE TABLE IF NOT EXISTS event (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      occurred_at  TEXT NOT NULL,
      recorded_at  TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%fZ', 'now')),
      entity_type  TEXT NOT NULL,
      entity_id    INTEGER NOT NULL,
      event_type   TEXT NOT NULL,
      payload      TEXT NOT NULL,
      actor_id     INTEGER NOT NULL,
      client_id    INTEGER
    );
  `);
  await run(`CREATE INDEX IF NOT EXISTS idx_event_entity ON event(entity_type, entity_id);`);
  await run(`CREATE INDEX IF NOT EXISTS idx_event_type_occurred ON event(event_type, occurred_at);`);
  await run(`CREATE INDEX IF NOT EXISTS idx_event_recorded ON event(recorded_at);`);
}

/**
 * Records an immutable domain event.
 *
 * @param {Function} run - DB execute helper
 * @param {Object} params
 * @param {string} params.entityType - 'part', 'part_variant', 'party_quote', 'die_tool', 'machine'
 * @param {number} params.entityId - Primary key of entity
 * @param {string} params.eventType - From EVENT_VOCABULARY
 * @param {Object} [params.payload] - JSON factual payload
 * @param {number} [params.actorId=1] - Operator/user ID
 * @param {number|null} [params.clientId=null] - Multi-tenant client ID
 * @param {string|null} [params.occurredAt=null] - ISO-8601 UTC floor time
 */
async function recordEvent(run, {
  entityType,
  entityId,
  eventType,
  payload = {},
  actorId = 1,
  clientId = null,
  occurredAt = null,
} = {}) {
  const occurred = occurredAt || new Date().toISOString();
  const payloadStr = typeof payload === 'string' ? payload : JSON.stringify(payload);

  const result = await run(
    `INSERT INTO event (occurred_at, entity_type, entity_id, event_type, payload, actor_id, client_id)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
    [occurred, entityType, entityId, eventType, payloadStr, actorId, clientId]
  );
  return result;
}

module.exports = {
  EVENT_VOCABULARY,
  ensureEventTable,
  recordEvent,
};
