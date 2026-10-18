const { seedStandardUnitFamilies, STANDARD_FAMILIES } = require('./service');

function registerUnitRoutes(app, { run, get, all, requirePermission, trackCreate }) {
  // Lists unit families and their ladders
  app.get('/api/units/families', requirePermission('config.read'), async (req, res) => {
    try {
      const groups = await all(
        'SELECT * FROM unit_groups ORDER BY id ASC',
      );
      const units = await all(
        'SELECT * FROM units WHERE is_archived = 0 ORDER BY unit_group_id ASC, factor_to_base ASC',
      );

      const byGroup = {};
      for (const u of units) {
        if (!u.unit_group_id) continue;
        if (!byGroup[u.unit_group_id]) byGroup[u.unit_group_id] = [];
        byGroup[u.unit_group_id].push(u);
      }

      const result = groups.map((g) => ({
        ...g,
        units: byGroup[g.id] || [],
      }));

      res.json({ success: true, families: result, error: null });
    } catch (err) {
      res.status(500).json({ success: false, error: err.message });
    }
  });

  // Seeds standard canonical families and ladders
  app.post(
    '/api/units/seed-standard',
    requirePermission('units.create'),
    async (req, res) => {
      try {
        await seedStandardUnitFamilies({ run, get, all });
        if (typeof trackCreate === 'function') {
          await trackCreate(
            'units',
            'standard-seed',
            { seededFamilies: STANDARD_FAMILIES.map((f) => f.code) },
            req,
          ).catch(() => {});
        }
        res.json({ success: true, message: 'Standard units seeded successfully.' });
      } catch (err) {
        res.status(500).json({ success: false, error: err.message });
      }
    },
  );
}

module.exports = {
  registerUnitRoutes,
};
