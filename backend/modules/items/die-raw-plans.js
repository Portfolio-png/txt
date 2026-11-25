'use strict';

const { answer, deskRoutes } = require('../../kernel/desk-kit');

// ---------------------------------------------------------------------------
// Raw material per die (owner, 2026-11-25): "one item has many dies — that
// means every die creates new raw material data". A part made on a new die
// after years is a slightly different part (its Part No says which die), and
// what it is cut from — the sheet or strip, its width (the die's Liner Size),
// the yield — is that die's. So a raw plan is kept per (part, die).
//
// The part's own plan (items.pen_paper_baseline) is unchanged: it is the plan
// with no die, the one production and the reports read today. These are the
// plans beside it, one per die, for the shop to fill in die by die.
//
//   GET /api/items/:id/die-raw-plans          every die's plan for the part
//   PUT /api/items/:id/die-raw-plans/:dieId   write one die's plan
//
// The plan is the same PenPaperBaseline JSON the part's own is; it is stored
// whole and read back whole. Gated as `items` (the path is under /api/items).
// ---------------------------------------------------------------------------

const MAX_BYTES = 512 * 1024;

function failWith(status, message, code) {
  const error = new Error(message);
  error.statusCode = status;
  if (code) error.code = code;
  return error;
}

function createDieRawPlanWork({ get, all, run, desk }) {
  const fail = (error) =>
    answer(error.statusCode || 500, {
      success: false,
      ...(error.code ? { code: error.code } : {}),
      error: error.message,
    });

  const toDto = (row) => {
    let baseline = null;
    try {
      baseline = JSON.parse(row.baseline_json);
    } catch (_) {
      baseline = null;
    }
    return {
      itemId: Number(row.item_id),
      dieId: Number(row.die_id),
      baseline,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  };

  async function itemOrFail(id) {
    const item = await get('SELECT id FROM items WHERE id = ?', [id]);
    if (!item) throw failWith(404, 'No such part.');
    return item;
  }

  async function list(req) {
    try {
      const itemId = Number(req.params.id);
      await itemOrFail(itemId);
      const rows = await all(
        'SELECT * FROM item_die_raw_plans WHERE item_id = ? ORDER BY die_id',
        [itemId],
      );
      return answer(200, { success: true, plans: rows.map(toDto) });
    } catch (error) {
      return fail(error);
    }
  }

  async function save(req) {
    try {
      const itemId = Number(req.params.id);
      const dieId = Number(req.params.dieId);
      if (!Number.isInteger(dieId) || dieId <= 0) throw failWith(400, 'Which die?', 'bad_die');
      await itemOrFail(itemId);
      // The die is asked of its own module, not joined.
      const { row: die } = await desk.ask('dies.rows.get', { id: dieId });
      if (!die) throw failWith(404, 'No such die.', 'unknown_die');
      const baseline = (req.body || {}).baseline;
      if (!baseline || typeof baseline !== 'object' || Array.isArray(baseline)) {
        throw failWith(400, 'A raw plan is needed.', 'missing_plan');
      }
      const json = JSON.stringify(baseline);
      if (json.length > MAX_BYTES) throw failWith(413, 'That raw plan is too large.', 'plan_too_large');
      const now = new Date().toISOString();
      const before = await get(
        'SELECT * FROM item_die_raw_plans WHERE item_id = ? AND die_id = ?',
        [itemId, dieId],
      );
      if (before) {
        await run(
          'UPDATE item_die_raw_plans SET baseline_json = ?, updated_at = ? WHERE item_id = ? AND die_id = ?',
          [json, now, itemId, dieId],
        );
      } else {
        await run(
          `INSERT INTO item_die_raw_plans (item_id, die_id, baseline_json, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?)`,
          [itemId, dieId, json, now, now],
        );
      }
      const after = await get(
        'SELECT * FROM item_die_raw_plans WHERE item_id = ? AND die_id = ?',
        [itemId, dieId],
      );
      req.track(before ? 'update' : 'create', 'items', itemId, before, after);
      return answer(200, { success: true, plan: toDto(after) });
    } catch (error) {
      return fail(error);
    }
  }

  return { listDieRawPlans: list, saveDieRawPlan: save };
}

function registerDieRawPlanRoutes(ctx) {
  const { app, desk, requirePermission } = ctx;
  const send = deskRoutes(desk, { create: ctx.trackCreate, update: ctx.trackUpdate, delete: ctx.trackDelete });

  app.get('/api/items/:id/die-raw-plans', requirePermission('items.read'),
    send('items.dieRawPlans.list', (req) => ({ id: req.params.id, query: req.query, data: req.body })));

  app.put('/api/items/:id/die-raw-plans/:dieId', requirePermission('items.update'),
    send('items.dieRawPlans.save', (req) => ({
      id: req.params.id,
      dieId: req.params.dieId,
      query: req.query,
      data: req.body,
    })));
}

module.exports = { createDieRawPlanWork, registerDieRawPlanRoutes };
