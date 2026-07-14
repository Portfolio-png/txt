const fs = require('fs');

const file = 'backend/server.js';
let content = fs.readFileSync(file, 'utf8');

const targetStr = `app.patch('/api/users/:id/status'`;
const targetIndex = content.indexOf(targetStr);

if (targetIndex === -1) {
  console.log("Could not find insertion point.");
  process.exit(1);
}

// Find the end of the app.patch('/api/users/:id/status' block
let insertIndex = content.indexOf('});', targetIndex);
insertIndex = content.indexOf('});', insertIndex + 3); 
// Wait, the block ends with res.status(500).json... } }); Let's just find the `function machineRowToDto` line

const machineIndex = content.indexOf('function machineRowToDto');

if (machineIndex === -1) {
  console.log("Could not find function machineRowToDto");
  process.exit(1);
}

const newRoutes = `
app.get('/api/delete-requests', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const status = String(req.query.status || '').trim();
    const whereClauses = [];
    const params = [];
    if (status && ['pending', 'approved', 'rejected'].includes(status)) {
      whereClauses.push('status = ?');
      params.push(status);
    }
    const whereSql = whereClauses.length > 0 ? \`WHERE \${whereClauses.join(' AND ')}\` : '';
    const { limit, offset } = parsePagination(req.query, { defaultLimit: 50, maxLimit: 100 });
    const countRow = await get(\`SELECT COUNT(*) as count FROM delete_requests \${whereSql}\`, params);
    const total = Number(countRow?.count || 0);
    const rows = await all(\`SELECT * FROM delete_requests \${whereSql} ORDER BY created_at DESC LIMIT ? OFFSET ?\`, [...params, limit, offset]);

    res.json({
      success: true,
      requests: rows.map(r => ({
        id: r.id,
        entityType: r.entity_type,
        entityId: r.entity_id,
        entityLabel: r.entity_label,
        reason: r.reason,
        status: r.status,
        requestedByUserId: r.requested_by_user_id,
        reviewedByUserId: r.reviewed_by_user_id,
        reviewedAt: r.reviewed_at,
        reviewedNote: r.reviewed_note,
        createdAt: r.created_at
      })),
      total
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/delete-requests', requireAuth, async (req, res) => {
  try {
    const { entityType, entityId, entityLabel, reason } = req.body;
    if (!entityType || !entityId) {
       return res.status(400).json({ success: false, error: 'entityType and entityId are required.' });
    }
    const insertResult = await run(
      \`INSERT INTO delete_requests (entity_type, entity_id, entity_label, reason, status, requested_by_user_id, created_at) VALUES (?, ?, ?, ?, 'pending', ?, ?)\`,
      [entityType, entityId, entityLabel || '', reason || '', req.user.id, new Date().toISOString()]
    );
    const r = await get(\`SELECT * FROM delete_requests WHERE id = ?\`, [insertResult.lastID]);
    res.status(201).json({
      success: true,
      request: {
        id: r.id,
        entityType: r.entity_type,
        entityId: r.entity_id,
        entityLabel: r.entity_label,
        reason: r.reason,
        status: r.status,
        requestedByUserId: r.requested_by_user_id,
        reviewedByUserId: r.reviewed_by_user_id,
        reviewedAt: r.reviewed_at,
        reviewedNote: r.reviewed_note,
        createdAt: r.created_at
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/delete-requests/:id/approve', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const reqRow = await get('SELECT * FROM delete_requests WHERE id = ?', [id]);
    if (!reqRow) return res.status(404).json({ success: false, error: 'Not found' });
    if (reqRow.status !== 'pending') return res.status(400).json({ success: false, error: 'Request is not pending.' });

    if (reqRow.entity_type === 'material') {
      await deleteMaterialRecord(reqRow.entity_id);
    } else if (reqRow.entity_type === 'item') {
      await run('DELETE FROM items WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'asset') {
      await deleteAsset(reqRow.entity_id);
    } else if (reqRow.entity_type === 'group') {
      await run('DELETE FROM groups WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'vendor') {
      await run('DELETE FROM vendors WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'inventory_set') {
      await deleteInventorySet(reqRow.entity_id);
    } else if (reqRow.entity_type === 'challan_template') {
      await deleteChallanTemplate(reqRow.entity_id);
    } else if (reqRow.entity_type === 'machine') {
      await run('DELETE FROM machines WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'die') {
      await run('DELETE FROM dies WHERE id = ?', [reqRow.entity_id]);
    } else if (reqRow.entity_type === 'user') {
      await run('DELETE FROM users WHERE id = ?', [reqRow.entity_id]);
    }

    const note = req.body?.note || '';
    const now = new Date().toISOString();
    await run(
      \`UPDATE delete_requests SET status = 'approved', reviewed_by_user_id = ?, reviewed_at = ?, reviewed_note = ? WHERE id = ?\`,
      [req.user.id, now, note, id]
    );
    const r = await get('SELECT * FROM delete_requests WHERE id = ?', [id]);

    res.json({
      success: true,
      request: {
        id: r.id,
        entityType: r.entity_type,
        entityId: r.entity_id,
        entityLabel: r.entity_label,
        reason: r.reason,
        status: r.status,
        requestedByUserId: r.requested_by_user_id,
        reviewedByUserId: r.reviewed_by_user_id,
        reviewedAt: r.reviewed_at,
        reviewedNote: r.reviewed_note,
        createdAt: r.created_at
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/delete-requests/:id/reject', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const reqRow = await get('SELECT * FROM delete_requests WHERE id = ?', [id]);
    if (!reqRow) return res.status(404).json({ success: false, error: 'Not found' });
    if (reqRow.status !== 'pending') return res.status(400).json({ success: false, error: 'Request is not pending.' });

    const note = req.body?.note || '';
    const now = new Date().toISOString();
    await run(
      \`UPDATE delete_requests SET status = 'rejected', reviewed_by_user_id = ?, reviewed_at = ?, reviewed_note = ? WHERE id = ?\`,
      [req.user.id, now, note, id]
    );
    const r = await get('SELECT * FROM delete_requests WHERE id = ?', [id]);

    res.json({
      success: true,
      request: {
        id: r.id,
        entityType: r.entity_type,
        entityId: r.entity_id,
        entityLabel: r.entity_label,
        reason: r.reason,
        status: r.status,
        requestedByUserId: r.requested_by_user_id,
        reviewedByUserId: r.reviewed_by_user_id,
        reviewedAt: r.reviewed_at,
        reviewedNote: r.reviewed_note,
        createdAt: r.created_at
      }
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.get('/api/delete-requests/export', requirePermission('delete_requests.review'), async (req, res) => {
  try {
    const rows = await all(\`SELECT * FROM delete_requests ORDER BY created_at DESC\`);
    const csvHeader = 'id,entityType,entityId,entityLabel,status,createdAt,reviewedAt\\n';
    const csvBody = rows.map(r => \`\${r.id},\${r.entity_type},\${r.entity_id},\${r.entity_label},\${r.status},\${r.created_at},\${r.reviewed_at || ''}\`).join('\\n');
    res.setHeader('Content-Type', 'text/csv');
    res.setHeader('Content-Disposition', 'attachment; filename="delete_requests_export.csv"');
    res.send(csvHeader + csvBody);
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

`;

content = content.slice(0, machineIndex) + newRoutes + content.slice(machineIndex);

fs.writeFileSync(file, content);
console.log("Patched server.js with delete-requests APIs!");

