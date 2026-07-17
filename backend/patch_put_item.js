const fs = require('fs');
const path = require('path');
const serverJs = path.join(__dirname, 'server.js');

let content = fs.readFileSync(serverJs, 'utf8');

const newEndpoint = `
app.put('/api/items/:id/short-code', requirePermission('config.write'), async (req, res) => {
  try {
    const id = Number(req.params.id);
    const shortCode = req.body.shortCode || '';
    
    if (!id) {
      return res.status(400).json({ success: false, error: 'Invalid ID' });
    }

    const item = await get('SELECT * FROM items WHERE id = ?', [id]);
    if (!item) {
      return res.status(404).json({ success: false, error: 'Item not found' });
    }

    await run('UPDATE items SET short_code = ?, updated_at = ? WHERE id = ?', [shortCode, new Date().toISOString(), id]);
    
    // Notify clients of the change
    await logChange('items', id, 'UPDATE');
    
    const updatedRow = await get('SELECT * FROM items WHERE id = ?', [id]);
    const itemDto = await rowToItemDto(updatedRow);
    
    if (io) {
      io.emit('item_updated', itemDto);
    }
    
    res.json({ success: true, item: itemDto, error: null });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});
`;

if (!content.includes('/api/items/:id/short-code')) {
  content = content.replace("app.post('/api/items'", newEndpoint + "\napp.post('/api/items'");
  fs.writeFileSync(serverJs, content);
  console.log('Added PUT /api/items/:id/short-code');
} else {
  console.log('Endpoint already exists');
}
