'use strict';

// ---------------------------------------------------------------------------
// Master Data — keyed by (variant, pipeline).
//
// A pipeline is shared. The same "Cut → Punch → Deburr" makes dozens of
// variants, and each has its own weights, piece counts, scrap and rejection, so
// a pipeline carries as many Master Data records as there are variants running
// through it. That is what makes the distinction: not the pipeline alone (one
// record could not describe every variant) and not the variant alone (the same
// numbers would silently follow it onto a different pipeline).
//
// Resolving the baseline for a (variant, pipeline) pair:
//
//   1. the exact pair has a record          -> MATCH, source 'pair'
//   2. the variant has its own record       -> MATCH, source 'item'
//   3. the pipeline template has one        -> MATCH, source 'pipeline'
//   4. nothing                              -> NO MATCH, new data is created
//
// Steps 2 and 3 are matches in the user's sense — the data that was attached to
// the variant, or to the pipeline that makes it as output, applies. When
// resolution runs with `adopt`, a match from 2 or 3 is written onto the pair so
// the next run is an exact hit, and step 4 writes a fresh record. `origin`
// records which step produced the row, which is what lets the insight view say
// whether a variant was measured or inherited.
// ---------------------------------------------------------------------------

const ORIGINS = Object.freeze({
  manual: 'manual',
  item: 'item',
  pipeline: 'pipeline',
  fresh: 'new',
});

/// Sources, in the order resolution tries them.
const SOURCE_ORDER = Object.freeze(['pair', 'item', 'pipeline', 'new']);

function parse(value) {
  if (value === null || value === undefined) return null;
  if (typeof value === 'object') return value;
  const text = String(value).trim();
  if (!text || text === '{}' || text === 'null') return null;
  try {
    const parsed = JSON.parse(text);
    if (!parsed || typeof parsed !== 'object') return null;
    // An empty object carries no measurement, so it is not a record.
    return Object.keys(parsed).length === 0 ? null : parsed;
  } catch {
    return null;
  }
}

/// The empty record a step-4 creation starts from. Deliberately zeroed rather
/// than filled with plausible numbers: an unmeasured baseline that looks
/// measured is worse than an obviously blank one.
function blankBaseline({ pipelineId = '', materialType = '' } = {}) {
  return {
    pipelineId,
    mode: 'whole',
    materialType,
    inputKg: 0,
    outputKg: 0,
    inputQty: 0,
    outputQty: 0,
    scrapKg: 0,
    rejectionPercent: 0,
    weightLossKg: 0,
    stageReconciliations: [],
    notes: '',
  };
}

function rowToDto(row) {
  if (!row) return null;
  return {
    id: row.id,
    itemId: row.item_id,
    pipelineId: row.pipeline_id,
    baseline: parse(row.baseline_json) || blankBaseline({ pipelineId: row.pipeline_id }),
    origin: row.origin || ORIGINS.manual,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function createMasterData({ get, all, run }) {
  async function readPair(itemId, pipelineId) {
    return get(
      'SELECT * FROM item_pipeline_baselines WHERE item_id = ? AND pipeline_id = ?',
      [itemId, pipelineId]
    );
  }

  async function writePair({ itemId, pipelineId, baseline, origin }) {
    await run(
      `INSERT INTO item_pipeline_baselines
         (item_id, pipeline_id, baseline_json, origin, created_at, updated_at)
       VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))
       ON CONFLICT(item_id, pipeline_id) DO UPDATE SET
         baseline_json = excluded.baseline_json,
         origin = excluded.origin,
         updated_at = datetime('now')`,
      [itemId, pipelineId, JSON.stringify(baseline || {}), origin || ORIGINS.manual]
    );
    return readPair(itemId, pipelineId);
  }

  /// The rule. Returns `{ matched, source, origin, baseline, pipelineId }`.
  /// `matched` is false only for step 4 — the case where new data is created.
  /// With `adopt: true` an inherited or fresh baseline is persisted onto the
  /// pair, so the same question answers 'pair' next time.
  async function resolve({ itemId, pipelineId, adopt = false }) {
    const item = await get('SELECT * FROM items WHERE id = ?', [itemId]);
    if (!item) {
      const error = new Error('Item not found');
      error.status = 404;
      throw error;
    }
    // No pipeline named, so the variant's own record is the whole answer —
    // there is no pair to key on. This is the raw-material case: weighed, but
    // nothing makes it.
    const targetPipelineId = String(pipelineId || item.default_pipeline_id || '').trim();
    if (!targetPipelineId) {
      const own = parse(item.pen_paper_baseline_json);
      return {
        itemId: item.id,
        pipelineId: '',
        matched: Boolean(own),
        source: own ? 'item' : 'new',
        origin: own ? ORIGINS.item : ORIGINS.fresh,
        baseline: own || blankBaseline({ materialType: materialTypeOf(item) }),
        persisted: false,
      };
    }

    // 1 — the exact pair.
    const pair = await readPair(item.id, targetPipelineId);
    const pairBaseline = parse(pair?.baseline_json);
    if (pairBaseline) {
      return {
        itemId: item.id,
        pipelineId: targetPipelineId,
        matched: true,
        source: 'pair',
        origin: pair.origin || ORIGINS.manual,
        baseline: pairBaseline,
        persisted: true,
      };
    }

    // 2 — data attached to the variant itself.
    const ownBaseline = parse(item.pen_paper_baseline_json);
    if (ownBaseline) {
      const persisted = adopt
        ? await writePair({
            itemId: item.id,
            pipelineId: targetPipelineId,
            baseline: ownBaseline,
            origin: ORIGINS.item,
          })
        : null;
      return {
        itemId: item.id,
        pipelineId: targetPipelineId,
        matched: true,
        source: 'item',
        origin: ORIGINS.item,
        baseline: ownBaseline,
        persisted: Boolean(persisted),
      };
    }

    // 3 — data attached to the pipeline that makes this item as output.
    const template = await get(
      'SELECT id, name, pen_paper_baseline_json FROM pipeline_templates WHERE id = ?',
      [targetPipelineId]
    );
    const templateBaseline = parse(template?.pen_paper_baseline_json);
    if (templateBaseline) {
      const persisted = adopt
        ? await writePair({
            itemId: item.id,
            pipelineId: targetPipelineId,
            baseline: templateBaseline,
            origin: ORIGINS.pipeline,
          })
        : null;
      return {
        itemId: item.id,
        pipelineId: targetPipelineId,
        matched: true,
        source: 'pipeline',
        origin: ORIGINS.pipeline,
        baseline: templateBaseline,
        persisted: Boolean(persisted),
      };
    }

    // 4 — nothing to match, so new data is created for this pair.
    const fresh = blankBaseline({
      pipelineId: targetPipelineId,
      materialType: materialTypeOf(item),
    });
    const persisted = adopt
      ? await writePair({
          itemId: item.id,
          pipelineId: targetPipelineId,
          baseline: fresh,
          origin: ORIGINS.fresh,
        })
      : null;
    return {
      itemId: item.id,
      pipelineId: targetPipelineId,
      matched: false,
      source: 'new',
      origin: ORIGINS.fresh,
      baseline: fresh,
      persisted: Boolean(persisted),
    };
  }

  /// Every record for one item, one per pipeline it runs on.
  async function listForItem(itemId) {
    const rows = await all(
      `SELECT b.*, t.name AS pipeline_name
         FROM item_pipeline_baselines b
         LEFT JOIN pipeline_templates t ON t.id = b.pipeline_id
        WHERE b.item_id = ?
        ORDER BY b.updated_at DESC`,
      [itemId]
    );
    return rows.map((row) => ({
      ...rowToDto(row),
      pipelineName: row.pipeline_name || '',
    }));
  }

  /// The insight roster for one pipeline: every variant that has Master Data on
  /// it, what the numbers say, and whether the variant was measured against
  /// this pipeline or inherited its baseline from elsewhere.
  async function listForPipeline(pipelineId) {
    const rows = await all(
      `SELECT b.*, i.name AS item_name, i.display_name AS item_display_name,
              i.base_item_id AS base_item_id, i.unit_id AS unit_id
         FROM item_pipeline_baselines b
         JOIN items i ON i.id = b.item_id
        WHERE b.pipeline_id = ?
          AND i.is_archived = 0
        ORDER BY i.display_name COLLATE NOCASE`,
      [pipelineId]
    );
    const entries = rows.map((row) => {
      const dto = rowToDto(row);
      const totals = summarise(dto.baseline);
      return {
        ...dto,
        itemName: row.item_name,
        itemDisplayName: row.item_display_name || row.item_name,
        isVariant: row.base_item_id !== null && row.base_item_id !== undefined,
        ...totals,
      };
    });
    return {
      pipelineId,
      count: entries.length,
      // A roster of one is not an average worth quoting, but the caller decides
      // that — the rollup is reported with its sample size.
      measuredCount: entries.filter((entry) => entry.origin === ORIGINS.manual).length,
      inheritedCount: entries.filter(
        (entry) => entry.origin === ORIGINS.item || entry.origin === ORIGINS.pipeline
      ).length,
      blankCount: entries.filter((entry) => entry.origin === ORIGINS.fresh).length,
      entries,
    };
  }

  return {
    ORIGINS,
    SOURCE_ORDER,
    blankBaseline,
    parse,
    resolve,
    readPair,
    writePair,
    listForItem,
    listForPipeline,
    async deletePair(itemId, pipelineId) {
      const result = await run(
        'DELETE FROM item_pipeline_baselines WHERE item_id = ? AND pipeline_id = ?',
        [itemId, pipelineId]
      );
      return result.changes > 0;
    },
  };
}

/// What the material is, read off the variant's own name — a variant of a sheet
/// is a sheet. The same rule the Master Data table uses on the client, so a
/// record created here reads the same as one typed there.
const MATERIAL_NOUNS = Object.freeze([
  'sheet',
  'coil',
  'strip',
  'plate',
  'rod',
  'bar',
  'wire',
  'pipe',
  'tube',
  'patti',
  'angle',
  'channel',
  'ingot',
  'billet',
  'scrap',
  'powder',
  'granule',
]);

function materialTypeOf(item) {
  const haystack = `${item.display_name || ''} ${item.name || ''}`.toLowerCase();
  for (const noun of MATERIAL_NOUNS) {
    if (haystack.includes(noun)) return noun;
  }
  return '';
}

/// Totals a baseline down to the four numbers the roster compares on. Whole
/// pipeline reads straight off the record; stage-by-stage takes input from the
/// first stage and output from the last, because that is the pipeline's own
/// in-and-out however many stages sit between.
function summarise(baseline) {
  if (!baseline) {
    return { inputKg: 0, outputKg: 0, inputQty: 0, outputQty: 0, yieldPercent: 0 };
  }
  const stages = Array.isArray(baseline.stageReconciliations)
    ? baseline.stageReconciliations
    : [];
  const useStages = baseline.mode === 'stages' && stages.length > 0;
  const first = useStages ? stages[0] : baseline;
  const last = useStages ? stages[stages.length - 1] : baseline;
  const inputKg = Number(first?.inputKg || 0);
  const outputKg = Number(last?.outputKg || 0);
  return {
    inputKg,
    outputKg,
    inputQty: Number(first?.inputQty || 0),
    outputQty: Number(last?.outputQty || 0),
    yieldPercent: inputKg > 0 ? Number(((outputKg / inputKg) * 100).toFixed(2)) : 0,
  };
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

function registerMasterDataRoutes(ctx) {
  const { app, requirePermission, get, all, run, logChange } = ctx;
  const masterData = createMasterData({ get, all, run });

  // Every Master Data record for an item, one per pipeline.
  app.get(
    '/api/items/:id/master-data',
    requirePermission('config.read'),
    async (req, res) => {
      try {
        const records = await masterData.listForItem(req.params.id);
        res.json({ success: true, records });
      } catch (error) {
        res.status(error.status || 500).json({ success: false, error: error.message });
      }
    }
  );

  // The rule itself, as a question: does this (variant, pipeline) pair have a
  // match, and if not, what would be created? `?adopt=1` commits the answer.
  app.get(
    '/api/items/:id/master-data/resolve',
    requirePermission('config.read'),
    async (req, res) => {
      try {
        const resolution = await masterData.resolve({
          itemId: req.params.id,
          pipelineId: req.query.pipelineId,
          adopt: req.query.adopt === '1' || req.query.adopt === 'true',
        });
        res.json({ success: true, ...resolution });
      } catch (error) {
        res.status(error.status || 500).json({ success: false, error: error.message });
      }
    }
  );

  // Typed against this pair, so origin is 'manual' however it got here.
  app.put(
    '/api/items/:id/master-data/:pipelineId',
    requirePermission('config.write'),
    async (req, res) => {
      try {
        const itemId = Number(req.params.id);
        const pipelineId = String(req.params.pipelineId || '').trim();
        if (!pipelineId) {
          res.status(400).json({ success: false, error: 'A pipeline is required.' });
          return;
        }
        const item = await get('SELECT id FROM items WHERE id = ?', [itemId]);
        if (!item) {
          res.status(404).json({ success: false, error: 'Item not found' });
          return;
        }
        const baseline = req.body?.baseline ?? req.body;
        const row = await masterData.writePair({
          itemId,
          pipelineId,
          baseline,
          origin: masterData.ORIGINS.manual,
        });
        if (typeof logChange === 'function') {
          await logChange('item_master_data', String(itemId), 'update', {
            pipelineId,
          });
        }
        res.json({ success: true, record: rowToDto(row) });
      } catch (error) {
        res.status(error.status || 500).json({ success: false, error: error.message });
      }
    }
  );

  app.delete(
    '/api/items/:id/master-data/:pipelineId',
    requirePermission('config.write'),
    async (req, res) => {
      try {
        const removed = await masterData.deletePair(
          Number(req.params.id),
          String(req.params.pipelineId || '').trim()
        );
        if (!removed) {
          res.status(404).json({ success: false, error: 'No Master Data for that pair.' });
          return;
        }
        res.json({ success: true });
      } catch (error) {
        res.status(error.status || 500).json({ success: false, error: error.message });
      }
    }
  );

  // The insight view: one pipeline, every variant's Master Data beside it.
  app.get(
    '/api/pipelines/:id/master-data',
    requirePermission('config.read'),
    async (req, res) => {
      try {
        const roster = await masterData.listForPipeline(String(req.params.id));
        res.json({ success: true, ...roster });
      } catch (error) {
        res.status(error.status || 500).json({ success: false, error: error.message });
      }
    }
  );

  return masterData;
}

module.exports = {
  createMasterData,
  registerMasterDataRoutes,
  blankBaseline,
  materialTypeOf,
  summarise,
  ORIGINS,
  SOURCE_ORDER,
};
