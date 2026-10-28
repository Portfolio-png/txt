'use strict';

// ---------------------------------------------------------------------------
// Process routing — the validator and the persistence for a part's route.
//
// The model and all three rules come from Docs/architecture/10-design-philosophy
// .md's worked example, which prescribed them and was never built. They live
// HERE rather than in SQL or in a widget because of principle 2 ("rules live in
// the data layer, not in widgets") and because SQL cannot see any of them:
//
//   * contiguity of `seq` is a property of the whole set, not of one row;
//   * "a stage at most once per route unless repeatable" needs the stage's
//     flag, which is in another table;
//   * "version rather than edit" depends on whether the route is active.
//
// The payload is the doc's payload — an ordered list of stage ids — so the
// Classic dropdown-per-step view and the drag-to-reorder List view send the
// same body and inherit the same rules. That is the whole point of putting them
// here: a second view cannot route around them.
// ---------------------------------------------------------------------------

const STATUSES = new Set(['draft', 'active', 'retired']);

/// Reads the ordered stage list out of whatever shape the caller sent.
///
/// Accepts `[1, 2, 3]`, `[{stageId: 1}, …]` or `[{stage_id: 1}, …]` — the
/// three spellings a Dart client, a hand-written curl and the Dart DTO
/// respectively produce. Anything else is a 400, not a guess.
function readSteps(raw) {
  if (!Array.isArray(raw)) return null;
  const out = [];
  for (const entry of raw) {
    if (entry === null || entry === undefined) return null;
    if (typeof entry === 'number' || typeof entry === 'string') {
      const id = Number(entry);
      if (!Number.isInteger(id) || id <= 0) return null;
      out.push({ stageId: id, seq: null, notes: '', machineId: null, dieId: null });
      continue;
    }
    if (typeof entry !== 'object') return null;
    const id = Number(entry.stageId ?? entry.stage_id);
    if (!Number.isInteger(id) || id <= 0) return null;
    const rawSeq = entry.seq;
    let seq = null;
    if (rawSeq !== undefined && rawSeq !== null && rawSeq !== '') {
      seq = Number(rawSeq);
      if (!Number.isInteger(seq)) return null;
    }
    out.push({
      stageId: id,
      seq,
      notes: String(entry.notes ?? '').trim(),
      machineId: intOrNull(entry.machineId ?? entry.machine_id),
      dieId: intOrNull(entry.dieId ?? entry.die_id),
    });
  }
  return out;
}

function intOrNull(value) {
  if (value === undefined || value === null || value === '') return null;
  const n = Number(value);
  return Number.isInteger(n) && n > 0 ? n : null;
}

/// The doc's three step rules. Pure, so it is testable without a database.
///
/// `stages` is the stage master as rows: `{id, name, repeatable, active}`.
/// Returns `{ok: true, steps}` with `seq` filled in 1..n, or `{ok: false,
/// error, code}` naming what was wrong in words a user could act on.
function validateRouteSteps(steps, stages) {
  if (!Array.isArray(steps) || steps.length === 0) {
    return { ok: false, code: 'route_empty', error: 'A route needs at least one step.' };
  }

  const byId = new Map();
  for (const stage of stages || []) byId.set(Number(stage.id), stage);

  // A caller may send explicit seqs or rely on list order, but not half of
  // each — a mixture means two different intentions about the same ordering.
  const given = steps.filter((s) => s.seq !== null).length;
  if (given !== 0 && given !== steps.length) {
    return {
      ok: false,
      code: 'route_seq_partial',
      error: 'Either every step carries a seq or none does.',
    };
  }

  let ordered = steps;
  if (given === steps.length) {
    ordered = [...steps].sort((a, b) => a.seq - b.seq);
    // seq is contiguous from 1, with no gaps.
    for (let i = 0; i < ordered.length; i += 1) {
      if (ordered[i].seq !== i + 1) {
        return {
          ok: false,
          code: 'route_seq_gap',
          error: `Steps must be numbered 1 to ${ordered.length} with no gaps.`,
        };
      }
    }
  }

  const seen = new Map();
  const out = [];
  for (let i = 0; i < ordered.length; i += 1) {
    const step = ordered[i];
    const stage = byId.get(step.stageId);
    if (!stage) {
      return {
        ok: false,
        code: 'route_stage_unknown',
        error: `Step ${i + 1} names a stage that does not exist.`,
      };
    }
    if (Number(stage.active) !== 1) {
      return {
        ok: false,
        code: 'route_stage_inactive',
        error: `${stage.name} is no longer in use and cannot be added to a route.`,
      };
    }
    // A stage appears at most once per route, unless that stage is flagged as
    // repeatable. This is the client's "one stage per dropdown" rule, moved to
    // where every view inherits it.
    const count = (seen.get(step.stageId) || 0) + 1;
    seen.set(step.stageId, count);
    if (count > 1 && Number(stage.repeatable) !== 1) {
      return {
        ok: false,
        code: 'route_stage_repeated',
        error: `${stage.name} is already in this route and cannot repeat.`,
      };
    }
    out.push({ ...step, seq: i + 1 });
  }

  return { ok: true, steps: out };
}

module.exports = function createProcessRouteService({ get, all, run }) {
  /// Routes still standing on a stage: drafts and active ones. A retired
  /// route is history and keeps its steps whatever happens to the stage.
  const USES = `(SELECT COUNT(DISTINCT s.route_id)
                   FROM process_route_steps s
                   JOIN process_routes r ON r.id = s.route_id
                  WHERE s.stage_id = g.id AND r.status <> 'retired') AS uses`;

  async function listStages({ includeInactive = false } = {}) {
    const where = includeInactive ? '' : 'WHERE g.active = 1';
    return all(
      `SELECT g.id, g.code, g.name, g.position, g.repeatable, g.active, ${USES}
         FROM process_stages g ${where}
        ORDER BY g.position, g.id`,
    );
  }

  async function stepsFor(routeId) {
    return all(
      `SELECT s.id, s.seq, s.stage_id, s.notes, s.machine_id, s.die_id,
              g.code AS stage_code, g.name AS stage_name
         FROM process_route_steps s
         JOIN process_stages g ON g.id = s.stage_id
        WHERE s.route_id = ?
        ORDER BY s.seq`,
      [routeId],
    );
  }

  /// Every version of a part's route, active first then newest.
  ///
  /// Active first because every caller that wants one route wants the active
  /// one, and making them scan is how a draft ends up on a shop floor.
  async function routesFor(partId) {
    const rows = await all(
      `SELECT id, part_id, version, status, note, created_at, updated_at
         FROM process_routes
        WHERE part_id = ?
        ORDER BY CASE status WHEN 'active' THEN 0 WHEN 'draft' THEN 1 ELSE 2 END,
                 version DESC`,
      [partId],
    );
    const out = [];
    for (const row of rows) out.push({ ...row, steps: await stepsFor(row.id) });
    return out;
  }

  async function activeRoute(partId) {
    return get(
      `SELECT id, part_id, version, status, note FROM process_routes
        WHERE part_id = ? AND status = 'active'`,
      [partId],
    );
  }

  async function writeSteps(routeId, steps) {
    await run('DELETE FROM process_route_steps WHERE route_id = ?', [routeId]);
    for (const step of steps) {
      await run(
        `INSERT INTO process_route_steps (route_id, seq, stage_id, notes, machine_id, die_id)
         VALUES (?, ?, ?, ?, ?, ?)`,
        [routeId, step.seq, step.stageId, step.notes || '', step.machineId, step.dieId],
      );
    }
  }

  async function nextVersion(partId) {
    const row = await get(
      'SELECT MAX(version) AS v FROM process_routes WHERE part_id = ?',
      [partId],
    );
    return Number(row?.v || 0) + 1;
  }

  /// Create a route, or replace the steps of the part's existing DRAFT.
  ///
  /// Refuses to touch an active route: that is the doc's third rule, and the
  /// refusal names the route to version so the caller has somewhere to go.
  async function saveRoute(partId, rawSteps, { status = 'active', note = '', userId = null } = {}) {
    if (!STATUSES.has(status) || status === 'retired') {
      return { ok: false, status: 400, code: 'route_status_invalid', error: "status must be 'draft' or 'active'." };
    }
    const parsed = readSteps(rawSteps);
    if (!parsed) {
      return { ok: false, status: 400, code: 'route_steps_malformed', error: 'steps must be an ordered list of stage ids.' };
    }
    const check = validateRouteSteps(parsed, await listStages({ includeInactive: true }));
    if (!check.ok) return { ok: false, status: 400, code: check.code, error: check.error };

    const existingActive = await activeRoute(partId);
    if (existingActive && status === 'active') {
      return {
        ok: false,
        status: 409,
        code: 'route_active',
        error: 'This part already has an active route. Declare a new version to change it.',
        routeId: existingActive.id,
        version: existingActive.version,
      };
    }

    const draft = await get(
      "SELECT id, version FROM process_routes WHERE part_id = ? AND status = 'draft' ORDER BY version DESC LIMIT 1",
      [partId],
    );

    if (draft) {
      await run(
        "UPDATE process_routes SET status = ?, note = ?, updated_at = datetime('now') WHERE id = ?",
        [status, note, draft.id],
      );
      await writeSteps(draft.id, check.steps);
      return { ok: true, created: false, routeId: draft.id, version: draft.version, status };
    }

    const version = await nextVersion(partId);
    const result = await run(
      `INSERT INTO process_routes (part_id, version, status, note, created_by)
       VALUES (?, ?, ?, ?, ?)`,
      [partId, version, status, note, userId],
    );
    const routeId = result.lastID;
    await writeSteps(routeId, check.steps);
    return { ok: true, created: true, routeId, version, status };
  }

  /// Declare a new version of an active route. The old one is RETIRED, never
  /// edited and never deleted, so jobs that already ran keep their history.
  async function declareVersion(partId, rawSteps, { note = '', userId = null } = {}) {
    const parsed = readSteps(rawSteps);
    if (!parsed) {
      return { ok: false, status: 400, code: 'route_steps_malformed', error: 'steps must be an ordered list of stage ids.' };
    }
    const check = validateRouteSteps(parsed, await listStages({ includeInactive: true }));
    if (!check.ok) return { ok: false, status: 400, code: check.code, error: check.error };

    const current = await activeRoute(partId);
    if (!current) {
      return {
        ok: false,
        status: 409,
        code: 'route_not_active',
        error: 'There is no active route to version. Save one first.',
      };
    }

    // Retire before inserting: the partial unique index allows exactly one
    // active route per part, so the order here is load-bearing, not stylistic.
    await run(
      "UPDATE process_routes SET status = 'retired', updated_at = datetime('now') WHERE id = ?",
      [current.id],
    );
    const version = await nextVersion(partId);
    const result = await run(
      `INSERT INTO process_routes (part_id, version, status, note, created_by)
       VALUES (?, ?, 'active', ?, ?)`,
      [partId, version, note, userId],
    );
    const routeId = result.lastID;
    await writeSteps(routeId, check.steps);
    return { ok: true, routeId, version, retiredRouteId: current.id, previousVersion: current.version };
  }

  /// Adds a stage to the factory's master — a pipeline node the seeded nine
  /// do not cover, named by whoever is authoring a route.
  ///
  /// Only a name is asked for. The code is derived (slug, uniquified), the
  /// stage goes to the END of the order, and it is not repeatable — the same
  /// defaults every seeded stage has. A name already in the master, in any
  /// case, is answered with that stage rather than a second one: typing
  /// "bending" after someone made "Bending" means the same stage.
  async function createStage({ name } = {}) {
    const clean = String(name || '').trim().replace(/\s+/g, ' ');
    if (!clean) {
      return { ok: false, status: 400, code: 'stage_name_required', error: 'A stage needs a name.' };
    }
    if (clean.length > 60) {
      return { ok: false, status: 400, code: 'stage_name_long', error: 'Keep a stage name under 60 characters.' };
    }

    const existing = await get(
      `SELECT id, code, name, position, repeatable, active
         FROM process_stages WHERE name = ? COLLATE NOCASE`,
      [clean],
    );
    // A name somebody deleted and now wants back is that same stage, brought
    // back — its code is taken, so a second one could not be made anyway.
    if (existing && Number(existing.active) !== 1) {
      await run(
        "UPDATE process_stages SET active = 1, updated_at = datetime('now') WHERE id = ?",
        [existing.id],
      );
      return { ok: true, stage: { ...existing, active: 1 } };
    }
    if (existing) {
      return {
        ok: false,
        status: 409,
        code: 'stage_exists',
        error: `"${existing.name}" is already a stage.`,
        stage: existing,
      };
    }

    // Same slug rule as die types (dies/die-identity.js slugifyDieType).
    const base = clean.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') || 'stage';
    let code = base;
    for (let n = 2; await get('SELECT 1 FROM process_stages WHERE code = ?', [code]); n += 1) {
      code = `${base}-${n}`;
    }

    const last = await get('SELECT COALESCE(MAX(position), 0) AS position FROM process_stages');
    // Two adds of the same new name at once both pass the checks above, and
    // the second hit UNIQUE(code) as a 500. Answered as the existing stage
    // instead, which is what a caller already reuses on stage_exists.
    let result;
    try {
      result = await run(
        `INSERT INTO process_stages (code, name, position, repeatable, active)
         VALUES (?, ?, ?, 0, 1)`,
        [code, clean, Number(last?.position || 0) + 1],
      );
    } catch (error) {
      if (!/UNIQUE constraint failed: process_stages\.code/.test(String(error?.message || ''))) {
        throw error;
      }
      const raced = await get(
        `SELECT id, code, name, position, repeatable, active
           FROM process_stages WHERE name = ? COLLATE NOCASE OR code = ?`,
        [clean, code],
      );
      return {
        ok: false,
        status: 409,
        code: 'stage_exists',
        error: raced ? `"${raced.name}" is already a stage.` : 'That stage was just added.',
        stage: raced || undefined,
      };
    }
    const stage = await get(
      'SELECT id, code, name, position, repeatable, active FROM process_stages WHERE id = ?',
      [result.lastID],
    );
    return { ok: true, stage };
  }

  /// Deletes a stage from the master — the delete in the step dropdown.
  ///
  /// Retired, never removed: a retired route still names it in its steps,
  /// and those must read the same tomorrow. Refused while a draft or active
  /// route stands on it, because the next save of that route would then be
  /// refused for naming a stage no longer in use.
  async function retireStage(id) {
    const stageId = Number(id);
    if (!Number.isInteger(stageId) || stageId <= 0) {
      return { ok: false, status: 400, code: 'stage_id_invalid', error: 'Invalid stage id.' };
    }
    const stage = await get(
      `SELECT g.id, g.code, g.name, g.position, g.repeatable, g.active, ${USES}
         FROM process_stages g WHERE g.id = ?`,
      [stageId],
    );
    if (!stage || Number(stage.active) !== 1) {
      return { ok: false, status: 404, code: 'stage_not_found', error: 'That stage is not in the list.' };
    }
    const uses = Number(stage.uses || 0);
    if (uses > 0) {
      return {
        ok: false,
        status: 409,
        code: 'stage_in_use',
        uses,
        error: `${stage.name} is in ${uses} route${uses === 1 ? '' : 's'}. Take it out of ${uses === 1 ? 'that route' : 'them'} first.`,
      };
    }
    await run(
      "UPDATE process_stages SET active = 0, updated_at = datetime('now') WHERE id = ?",
      [stageId],
    );
    return { ok: true, stage: { ...stage, active: 0 } };
  }

  return {
    listStages,
    createStage,
    retireStage,
    routesFor,
    activeRoute,
    stepsFor,
    saveRoute,
    declareVersion,
  };
};

module.exports.validateRouteSteps = validateRouteSteps;
module.exports.readSteps = readSteps;
