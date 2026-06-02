const fs = require('fs');

let serverCode = fs.readFileSync('backend/server.js', 'utf8');

const endpoints = `
app.get('/api/production/pipeline-templates', requirePermission('config.read'), async (req, res) => {
  try {
    const factoryId = req.query.factoryId || '';
    const rows = await all(
      'SELECT * FROM pipeline_templates WHERE factory_id = ? OR factory_id = "" ORDER BY created_at DESC',
      [factoryId]
    );
    res.json({ success: true, templates: rows.map(rowToTemplate), error: null });
  } catch (error) {
    res.status(500).json({ success: false, templates: [], error: error.message });
  }
});

app.post('/api/production/pipeline-templates', requirePermission('config.write'), async (req, res) => {
  try {
    const data = req.body;
    const now = new Date().toISOString();
    
    await run(
      \`
      INSERT INTO pipeline_templates (
        id, factory_id, shop_floor_id, name, description, version, status,
        stage_labels_json, lane_labels_json, nodes_json, flows_json, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      \`,
      [
        data.id,
        data.factoryId || '',
        data.shopFloorId || '',
        data.name || 'Untitled',
        data.description || '',
        data.version || 1,
        data.status || 'draft',
        JSON.stringify(data.stageLabels || []),
        JSON.stringify(data.laneLabels || []),
        JSON.stringify(data.nodes || []),
        JSON.stringify(data.flows || []),
        now,
        now
      ]
    );

    const row = await get('SELECT * FROM pipeline_templates WHERE id = ?', [data.id]);
    res.json({ success: true, template: rowToTemplate(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, template: null, error: error.message });
  }
});

app.put('/api/production/pipeline-templates/:id', requirePermission('config.write'), async (req, res) => {
  try {
    const id = req.params.id;
    const data = req.body;
    const now = new Date().toISOString();

    const existing = await get('SELECT * FROM pipeline_templates WHERE id = ?', [id]);
    if (!existing) {
      return res.status(404).json({ success: false, template: null, error: 'Not found' });
    }
    
    await run(
      \`
      UPDATE pipeline_templates
      SET factory_id = ?, shop_floor_id = ?, name = ?, description = ?, version = ?, status = ?,
          stage_labels_json = ?, lane_labels_json = ?, nodes_json = ?, flows_json = ?, updated_at = ?
      WHERE id = ?
      \`,
      [
        data.factoryId ?? existing.factory_id,
        data.shopFloorId ?? existing.shop_floor_id,
        data.name ?? existing.name,
        data.description ?? existing.description,
        data.version ?? existing.version,
        data.status ?? existing.status,
        data.stageLabels ? JSON.stringify(data.stageLabels) : existing.stage_labels_json,
        data.laneLabels ? JSON.stringify(data.laneLabels) : existing.lane_labels_json,
        data.nodes ? JSON.stringify(data.nodes) : existing.nodes_json,
        data.flows ? JSON.stringify(data.flows) : existing.flows_json,
        now,
        id
      ]
    );

    const row = await get('SELECT * FROM pipeline_templates WHERE id = ?', [id]);
    res.json({ success: true, template: rowToTemplate(row), error: null });
  } catch (error) {
    res.status(500).json({ success: false, template: null, error: error.message });
  }
});

`;

serverCode = serverCode.replace(
  "app.get('/api/production-runs/completed'",
  endpoints + "\napp.get('/api/production-runs/completed'"
);

fs.writeFileSync('backend/server.js', serverCode);
console.log('Patched server.js with pipeline_templates endpoints');
