// ==========================================
// PAYROLL APIs
// ==========================================

app.get('/api/payroll/components', requirePermission('config.read'), async (req, res) => {
  try {
    const components = await all('SELECT * FROM payroll_components ORDER BY name ASC');
    res.json({ success: true, components });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/payroll/components', requirePermission('config.write'), async (req, res) => {
  try {
    const { name, type, calculation_method, is_statutory, config_json } = req.body;
    if (!name || !type || !calculation_method) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }
    
    const result = await run(`
      INSERT INTO payroll_components (name, type, calculation_method, is_statutory, config_json)
      VALUES (?, ?, ?, ?, ?)
    `, [name, type, calculation_method, is_statutory ? 1 : 0, config_json || '{}']);
    
    res.json({ success: true, id: result.lastID });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/payroll/employees/:id/salary-structure', requirePermission('config.read'), async (req, res) => {
  try {
    const userId = Number(req.params.id);
    const structure = await get('SELECT * FROM employee_salary_structures WHERE user_id = ?', [userId]);
    if (!structure) {
      return res.json({ success: true, structure: null, lines: [] });
    }
    const lines = await all('SELECT * FROM employee_salary_structure_lines WHERE structure_id = ?', [structure.id]);
    res.json({ success: true, structure, lines });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.put('/api/payroll/employees/:id/salary-structure', requirePermission('config.write'), async (req, res) => {
  try {
    const userId = Number(req.params.id);
    const { base_salary, effective_date, lines } = req.body;
    
    await run('BEGIN TRANSACTION');
    let structure = await get('SELECT * FROM employee_salary_structures WHERE user_id = ?', [userId]);
    if (structure) {
      await run('UPDATE employee_salary_structures SET base_salary = ?, effective_date = ?, updated_at = ? WHERE id = ?', 
        [base_salary, effective_date, new Date().toISOString(), structure.id]);
    } else {
      const resStruct = await run('INSERT INTO employee_salary_structures (user_id, base_salary, effective_date, created_at, updated_at) VALUES (?, ?, ?, ?, ?)',
        [userId, base_salary, effective_date, new Date().toISOString(), new Date().toISOString()]);
      structure = { id: resStruct.lastID };
    }
    
    await run('DELETE FROM employee_salary_structure_lines WHERE structure_id = ?', [structure.id]);
    if (lines && lines.length > 0) {
      for (const line of lines) {
        await run(`
          INSERT INTO employee_salary_structure_lines (structure_id, component_id, amount, is_active)
          VALUES (?, ?, ?, ?)
        `, [structure.id, line.component_id, line.amount, line.is_active ? 1 : 0]);
      }
    }
    
    await run('COMMIT');
    res.json({ success: true });
  } catch (error) {
    await run('ROLLBACK').catch(() => {});
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/payroll/runs', requirePermission('config.read'), async (req, res) => {
  try {
    const runs = await all('SELECT * FROM payroll_runs ORDER BY created_at DESC');
    res.json({ success: true, runs });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/payroll/runs', requirePermission('config.write'), async (req, res) => {
  try {
    const { period_start, period_end, remarks } = req.body;
    if (!period_start || !period_end) {
      return res.status(400).json({ success: false, error: 'Missing period start/end' });
    }
    const result = await run(`
      INSERT INTO payroll_runs (period_start, period_end, status, total_gross, total_net, created_by, remarks, created_at, updated_at)
      VALUES (?, ?, 'draft', 0, 0, ?, ?, ?, ?)
    `, [period_start, period_end, req.user?.id || null, remarks || '', new Date().toISOString(), new Date().toISOString()]);
    
    res.json({ success: true, id: result.lastID });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/payroll/runs/:id', requirePermission('config.read'), async (req, res) => {
  try {
    const runId = Number(req.params.id);
    const payrollRun = await get('SELECT * FROM payroll_runs WHERE id = ?', [runId]);
    if (!payrollRun) return res.status(404).json({ success: false, error: 'Not found' });
    
    const details = await all('SELECT * FROM payroll_run_details WHERE run_id = ?', [runId]);
    res.json({ success: true, run: payrollRun, details });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/payroll/runs/:id/finalize', requirePermission('config.write'), async (req, res) => {
  try {
    const runId = Number(req.params.id);
    await run('UPDATE payroll_runs SET status = "finalized", updated_at = ? WHERE id = ?', [new Date().toISOString(), runId]);
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/payroll/runs/:id/summary', requirePermission('config.read'), async (req, res) => {
  try {
    const runId = Number(req.params.id);
    const payrollRun = await get('SELECT * FROM payroll_runs WHERE id = ?', [runId]);
    if (!payrollRun) return res.status(404).send('Not found');
    
    const details = await all('SELECT * FROM payroll_run_details WHERE run_id = ?', [runId]);
    
    let csv = 'Employee ID,Gross Pay,Deductions,Net Pay\\n';
    details.forEach(d => {
      csv += `${d.user_id},${d.gross_pay},${d.deductions},${d.net_pay}\\n`;
    });
    
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', \`attachment; filename="payroll_summary_\${runId}.csv"\`);
    res.send(csv);
  } catch (error) {
    res.status(500).send('Error generating summary');
  }
});

// ==========================================
// B2B PORTAL APIs
// ==========================================

app.get('/api/portal/catalog', async (req, res) => {
  try {
    // Only return items that aren't archived
    const items = await all('SELECT id, name, display_name, alias, quantity, naming_format FROM items WHERE is_archived = 0 ORDER BY display_name ASC');
    res.json({ success: true, items });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/portal/cart', async (req, res) => {
  try {
    const { portal_user_id, item_id, quantity } = req.body;
    if (!portal_user_id || !item_id) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }
    
    const existing = await get('SELECT * FROM portal_carts WHERE portal_user_id = ? AND item_id = ?', [portal_user_id, item_id]);
    if (existing) {
      await run('UPDATE portal_carts SET quantity = quantity + ?, updated_at = ? WHERE id = ?', [quantity, new Date().toISOString(), existing.id]);
    } else {
      await run('INSERT INTO portal_carts (portal_user_id, item_id, quantity, created_at, updated_at) VALUES (?, ?, ?, ?, ?)', 
        [portal_user_id, item_id, quantity, new Date().toISOString(), new Date().toISOString()]);
    }
    res.json({ success: true });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/portal/orders', async (req, res) => {
  try {
    const { portal_user_id, items, notes } = req.body;
    if (!portal_user_id || !items || !items.length) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }
    
    const pUser = await get('SELECT * FROM portal_users WHERE id = ?', [portal_user_id]);
    if (!pUser) return res.status(404).json({ success: false, error: 'Portal user not found' });
    
    await run('BEGIN TRANSACTION');
    
    const orderNo = \`B2B-ORD-\${Date.now()}\`;
    
    // Create header
    await run('INSERT INTO order_headers (order_no, client_id, created_at, updated_at) VALUES (?, ?, ?, ?)', 
      [orderNo, pUser.client_id, new Date().toISOString(), new Date().toISOString()]);
      
    // Save items
    for (const item of items) {
      await saveOrder({
        orderNo,
        clientId: pUser.client_id,
        itemId: item.item_id,
        quantity: item.quantity,
        status: 'draft',
        createdByPortalUserId: portal_user_id,
      }, { returnMeta: false });
    }
    
    // Clear cart
    await run('DELETE FROM portal_carts WHERE portal_user_id = ?', [portal_user_id]);
    
    await run('COMMIT');
    res.json({ success: true, orderNo });
  } catch (error) {
    await run('ROLLBACK').catch(() => {});
    res.status(500).json({ success: false, error: error.message });
  }
});
