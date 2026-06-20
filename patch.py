import sys

with open('backend/server.js', 'r', encoding='utf-8') as f:
    content = f.read()

old1 = """app.put('/templates/:id', async (req, res) => {
    try {
      const existing = await get('SELECT * FROM pipeline_templates WHERE id = ?', [
        req.params.id,
      ]);
      if (!existing) {
        res.status(404).json({
          success: false,
          template: null,
          error: 'Template not found.',
        });
        return;
      }
      const payload = req.body || {};
      const nextVersion = (existing.version || 1) + 1;
      const now = new Date().toISOString();"""

new1 = old1 + """
      const archivedId = `${req.params.id}_v${existing.version || 1}_${Date.now()}`;
      await run(`
        INSERT INTO pipeline_templates (id, factory_id, shop_floor_id, name, description, version, status, stage_labels_json, lane_labels_json, nodes_json, flows_json, intermediate_naming_convention, is_archived, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
      `, [
        archivedId, existing.factory_id, existing.shop_floor_id, existing.name, existing.description, existing.version, existing.status, existing.stage_labels_json, existing.lane_labels_json, existing.nodes_json, existing.flows_json, existing.intermediate_naming_convention, existing.created_at, existing.updated_at
      ]);
      await run(`UPDATE pipeline_runs SET template_id = ? WHERE template_id = ?`, [archivedId, req.params.id]);
"""

content = content.replace(old1, new1)

old2 = """app.put('/api/production/pipeline-templates/:id', requirePermission('config.write'), async (req, res) => {
    try {
      const id = req.params.id;
      const data = req.body;
      const now = new Date().toISOString();
  
      const existing = await get('SELECT * FROM pipeline_templates WHERE id = ?', [id]);
      if (!existing) {
        return res.status(404).json({ success: false, template: null, error: 'Not found' });
      }"""

new2 = old2 + """
      const nextVersion = (existing.version || 1) + 1;
      const archivedId = `${id}_v${existing.version || 1}_${Date.now()}`;
      await run(`
        INSERT INTO pipeline_templates (id, factory_id, shop_floor_id, name, description, version, status, stage_labels_json, lane_labels_json, nodes_json, flows_json, intermediate_naming_convention, is_archived, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?)
      `, [
        archivedId, existing.factory_id, existing.shop_floor_id, existing.name, existing.description, existing.version, existing.status, existing.stage_labels_json, existing.lane_labels_json, existing.nodes_json, existing.flows_json, existing.intermediate_naming_convention, existing.created_at, existing.updated_at
      ]);
      await run(`UPDATE pipeline_runs SET template_id = ? WHERE template_id = ?`, [archivedId, id]);
"""

content = content.replace(old2, new2)
content = content.replace('data.version ?? existing.version,', 'data.version ?? nextVersion,')

with open('backend/server.js', 'w', encoding='utf-8') as f:
    f.write(content)
print("done")
