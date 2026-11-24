'use strict';

// ---------------------------------------------------------------------------
// The die master over HTTP.
//
//   GET    /api/dies                              the list (cached master data)
//   GET    /api/dies/:id                          one, with its client
//   POST   /api/dies                              create, or update when `id` is a real one
//   DELETE /api/dies/:id                          remove, unless a live run holds it
//   GET    /api/dies/:id/assets                   its photos
//   POST   /api/dies/:id/assets/upload-intent     ask for somewhere to put one
//   POST   /api/dies/:id/assets/upload-complete   say it arrived
//   GET    /api/dies/:id/photos                   its photos, in order (its gallery)
//   PUT    /api/dies/:id/photos                   their order and the main one
//
// `dies` is the first path segment, so the central CRUD gate maps every route
// here to the dies module. The four master routes ask the module's operations
// (./operations.js) at the kernel desk; the asset routes call the kernel's asset
// service. The die makers master is the sibling file, die-makers.js.
// ---------------------------------------------------------------------------

const { httpKit } = require('../../kernel/desk-kit');

module.exports = function registerDieRoutes(ctx) {
  const {
    app,
    desk,
    requirePermission,
    cacheMasterData,
    trackCreate,
    trackUpdate,
    trackDelete,
    // Assets are a kernel capability still defined in server.js.
    listAssetsForEntity,
    createAssetUploadIntent,
    completeAssetUpload,
    listEntityPhotos,
    arrangeEntityPhotos,
  } = ctx;
  const { ask, refuse } = httpKit(desk);

  // Dies CRUD Endpoints
  app.get('/api/dies', requirePermission('config.read'), cacheMasterData, async (req, res) => {
    try {
      const result = await ask(req, 'dies.list');
      if (!result.ok) return refuse(res, result);
      res.json({ success: true, dies: result.dies, error: null });
    } catch (error) {
      res.status(500).json({ success: false, dies: [], error: error.message });
    }
  });

  app.get('/api/dies/:id', requirePermission('config.read'), async (req, res) => {
    try {
      const result = await ask(req, 'dies.get', { id: req.params.id });
      if (!result.ok) return refuse(res, result);
      res.json({ success: true, die: result.die, error: null });
    } catch (error) {
      res.status(500).json({ success: false, die: null, error: error.message });
    }
  });

  app.post('/api/dies', requirePermission('config.write'), async (req, res) => {
    try {
      const result = await ask(req, 'dies.save', req.body);
      if (!result.ok) return refuse(res, result);
      if (result.isUpdate) {
        trackUpdate('dies', result.resultId, result.before, result.row, req);
      } else {
        trackCreate('dies', result.resultId, result.row, req);
      }
      res.json({ success: true, die: result.die, error: null });
    } catch (error) {
      res.status(500).json({ success: false, die: null, error: error.message });
    }
  });

  app.delete('/api/dies/:id', requirePermission('config.write'), async (req, res) => {
    try {
      const id = req.params.id;
      const result = await ask(req, 'dies.delete', { id });
      if (!result.ok) return refuse(res, result);
      trackDelete('dies', id, result.before, req);
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Dies Assets
  app.get('/api/dies/:id/assets', requirePermission('config.read'), async (req, res) => {
    try {
      const assets = await listAssetsForEntity('die', Number(req.params.id));
      res.json({ success: true, assets, error: null });
    } catch (error) {
      res.status(500).json({ success: false, assets: [], error: error.message });
    }
  });

  // A die's photos, up to five, as a part's are (2026-11-24): what its
  // gallery opens on, and its Save — the order and which one is shown.
  app.get('/api/dies/:id/photos', requirePermission('config.read'), async (req, res) => {
    try {
      const photos = await listEntityPhotos('die', Number(req.params.id));
      res.json({ success: true, photos, limit: 5, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, photos: [], error: error.message });
    }
  });

  app.put('/api/dies/:id/photos', requirePermission('config.write'), async (req, res) => {
    try {
      const photos = await arrangeEntityPhotos('die', Number(req.params.id), {
        order: req.body?.order,
        primaryId: req.body?.primaryId,
      });
      res.json({ success: true, photos, limit: 5, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, photos: [], error: error.message });
    }
  });

  app.post('/api/dies/:id/assets/upload-intent', requirePermission('config.write'), async (req, res) => {
    try {
      const entityId = Number(req.params.id);
      const intent = await createAssetUploadIntent({
        ...(req.body || {}),
        entityType: 'die',
        entityId,
      });
      res.status(intent.alreadyUploaded ? 200 : 201).json({ success: true, intent, error: null });
    } catch (error) {
      res.status(500).json({ success: false, intent: null, error: error.message });
    }
  });

  app.post('/api/dies/:id/assets/upload-complete', requirePermission('config.write'), async (req, res) => {
    try {
      const asset = await completeAssetUpload(req.body || {});
      res.json({ success: true, asset, error: null });
    } catch (error) {
      res.status(500).json({ success: false, asset: null, error: error.message });
    }
  });
};
