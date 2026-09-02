'use strict';

// ---------------------------------------------------------------------------
// Material types — the master of what a material IS, as opposed to the
// `materials` table, which is barcoded physical stock: this sheet, from this
// supplier, in this rack. Steel is a type; the steel on rack 3 is stock.
//
// One number per material — its density — and everything that is priced or
// moved by weight follows from it:
//
//     volume (cm³) × density (g/cm³) ÷ 1000 = weight (kg)
//
// Sheet planning already works out the volume. Density is what turns that into
// a weight, and weight is what material is bought by, what scrap is sold by,
// and what a challan is weighed in. Without it a sheet plan can say how many
// parts come off a sheet but not what the sheet cost.
// ---------------------------------------------------------------------------

const CATEGORIES = Object.freeze(['metal', 'plastic', 'other']);

/// Grams per cubic centimetre. Nothing real is outside this, and a density
/// typed in kg/m³ by mistake (7850 instead of 7.85) would put a weight out by a
/// thousand — which is worth refusing rather than storing.
const MIN_DENSITY = 0.01;
const MAX_DENSITY = 30;

function rowToDto(row) {
  if (!row) return null;
  return {
    id: row.id,
    name: row.name,
    densityGCm3: Number(row.density_g_cm3 || 0),
    category: row.category || 'metal',
    notes: row.notes || '',
    isArchived: Number(row.is_archived || 0) === 1,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  };
}

function validate(body) {
  const name = String(body?.name || '').trim();
  if (!name) return { error: 'A material needs a name.' };
  const density = Number(body?.densityGCm3);
  if (!Number.isFinite(density) || density <= 0) {
    return { error: 'A material needs a density greater than zero.' };
  }
  if (density < MIN_DENSITY || density > MAX_DENSITY) {
    return {
      error:
        `A density of ${density} g/cm³ is outside anything real. Densities are ` +
        `in grams per cubic centimetre — steel is 7.85, not 7850.`,
    };
  }
  const category = String(body?.category || 'metal').trim().toLowerCase();
  return {
    name,
    density,
    category: CATEGORIES.includes(category) ? category : 'other',
    notes: String(body?.notes || '').trim(),
  };
}

function registerMaterialTypeRoutes(ctx) {
  const { app, requirePermission, get, all, run, logChange } = ctx;

  app.get('/api/material-types', requirePermission('config.read'), async (req, res) => {
    try {
      const includeArchived = req.query.includeArchived === '1';
      const rows = await all(
        `SELECT * FROM material_types
          ${includeArchived ? '' : 'WHERE is_archived = 0'}
          ORDER BY name COLLATE NOCASE`
      );
      res.json({ success: true, materialTypes: rows.map(rowToDto) });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/material-types', requirePermission('config.write'), async (req, res) => {
    try {
      const parsed = validate(req.body);
      if (parsed.error) {
        res.status(400).json({ success: false, error: parsed.error });
        return;
      }
      const clash = await get(
        'SELECT id FROM material_types WHERE name = ? COLLATE NOCASE',
        [parsed.name]
      );
      if (clash) {
        res.status(409).json({
          success: false,
          error: `"${parsed.name}" is already in the material master.`,
        });
        return;
      }
      const result = await run(
        `INSERT INTO material_types (name, density_g_cm3, category, notes, created_at, updated_at)
         VALUES (?, ?, ?, ?, datetime('now'), datetime('now'))`,
        [parsed.name, parsed.density, parsed.category, parsed.notes]
      );
      const row = await get('SELECT * FROM material_types WHERE id = ?', [
        result.lastID,
      ]);
      if (typeof logChange === 'function') {
        // 'material' is not a table and 'create' is not one of the three event
        // types the changelog's CHECK allows, so this insert was rejected and
        // swallowed on every call. `materials` is trigger-logged now, so this
        // only needs to be valid enough to push the notification.
        await logChange('materials', String(result.lastID), 'INSERT', {
          name: parsed.name,
        });
      }
      res.status(201).json({ success: true, materialType: rowToDto(row) });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.patch(
    '/api/material-types/:id',
    requirePermission('config.write'),
    async (req, res) => {
      try {
        const existing = await get('SELECT * FROM material_types WHERE id = ?', [
          req.params.id,
        ]);
        if (!existing) {
          res.status(404).json({ success: false, error: 'Material type not found' });
          return;
        }
        const parsed = validate({
          name: req.body?.name ?? existing.name,
          densityGCm3: req.body?.densityGCm3 ?? existing.density_g_cm3,
          category: req.body?.category ?? existing.category,
          notes: req.body?.notes ?? existing.notes,
        });
        if (parsed.error) {
          res.status(400).json({ success: false, error: parsed.error });
          return;
        }
        const clash = await get(
          'SELECT id FROM material_types WHERE name = ? COLLATE NOCASE AND id <> ?',
          [parsed.name, req.params.id]
        );
        if (clash) {
          res.status(409).json({
            success: false,
            error: `"${parsed.name}" is already in the material master.`,
          });
          return;
        }
        await run(
          `UPDATE material_types
              SET name = ?, density_g_cm3 = ?, category = ?, notes = ?,
                  is_archived = ?, updated_at = datetime('now')
            WHERE id = ?`,
          [
            parsed.name,
            parsed.density,
            parsed.category,
            parsed.notes,
            req.body?.isArchived === true ? 1 : Number(existing.is_archived || 0),
            req.params.id,
          ]
        );
        const row = await get('SELECT * FROM material_types WHERE id = ?', [
          req.params.id,
        ]);
        if (typeof logChange === 'function') {
          await logChange('materials', String(req.params.id), 'UPDATE', {
            name: parsed.name,
          });
        }
        res.json({ success: true, materialType: rowToDto(row) });
      } catch (error) {
        res.status(500).json({ success: false, error: error.message });
      }
    }
  );

  // Archived rather than deleted: a plan recorded last year names the material
  // it was cut from, and that name has to keep resolving.
  app.delete(
    '/api/material-types/:id',
    requirePermission('config.write'),
    async (req, res) => {
      try {
        const result = await run(
          `UPDATE material_types SET is_archived = 1, updated_at = datetime('now')
            WHERE id = ?`,
          [req.params.id]
        );
        if (result.changes === 0) {
          res.status(404).json({ success: false, error: 'Material type not found' });
          return;
        }
        if (typeof logChange === 'function') {
          await logChange('materials', String(req.params.id), 'UPDATE', {});
        }
        res.json({ success: true });
      } catch (error) {
        res.status(500).json({ success: false, error: error.message });
      }
    }
  );
}

/// The weight of a volume of this material, which is the whole reason the
/// master exists.
function weightKg(volumeCm3, densityGCm3) {
  if (!(volumeCm3 > 0) || !(densityGCm3 > 0)) return 0;
  return (volumeCm3 * densityGCm3) / 1000;
}

module.exports = {
  registerMaterialTypeRoutes,
  rowToDto,
  validate,
  weightKg,
  CATEGORIES,
  MIN_DENSITY,
  MAX_DENSITY,
};
