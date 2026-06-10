app.put('/runs/:id/node-metrics', async (req, res) => {
  try {
    const { nodeId, metrics } = req.body;
    if (!nodeId || !metrics) {
      return res.status(400).json({ success: false, run: null, error: 'nodeId and metrics are required.' });
    }
    const runRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    if (!runRow) {
      return res.status(404).json({ success: false, run: null, error: 'Run not found.' });
    }
    
    const nodeMetrics = parseJson(runRow.node_metrics_json, {});
    nodeMetrics[nodeId] = { ...(nodeMetrics[nodeId] || {}), ...metrics };
    
    await run('UPDATE pipeline_runs SET node_metrics_json = ? WHERE id = ?', [
      JSON.stringify(nodeMetrics),
      req.params.id,
    ]);
    
    const updatedRow = await get('SELECT * FROM pipeline_runs WHERE id = ?', [req.params.id]);
    res.json({ success: true, run: await rowToRun(updatedRow) });
  } catch (error) {
    res.status(500).json({ success: false, run: null, error: error.message });
  }
});

app.post('/api/production-scrap', requirePermission('config.write'), async (req, res) => {
  try {
    const { pipelineRunId, nodeId, orderNo, materialBarcode, scrapQty } = req.body;
    if (!pipelineRunId || !nodeId || !materialBarcode) {
      return res.status(400).json({ success: false, error: 'pipelineRunId, nodeId, and materialBarcode are required.' });
    }
    await run(`
      INSERT INTO production_scrap (pipeline_run_id, node_id, order_no, material_barcode, scrap_qty, logged_by)
      VALUES (?, ?, ?, ?, ?, ?)
    `, [pipelineRunId, nodeId, orderNo, materialBarcode, scrapQty, actorFromRequest(req)]);
    res.status(201).json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/production-scrap', requirePermission('config.read'), async (req, res) => {
  try {
    const { pipelineRunId, nodeId } = req.query;
    let query = 'SELECT * FROM production_scrap WHERE 1=1';
    const params = [];
    if (pipelineRunId) {
      query += ' AND pipeline_run_id = ?';
      params.push(pipelineRunId);
    }
    if (nodeId) {
      query += ' AND node_id = ?';
      params.push(nodeId);
    }
    query += ' ORDER BY created_at DESC';
    const rows = await all(query, params);
    res.json({ success: true, data: rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});
