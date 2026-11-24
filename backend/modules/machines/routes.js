'use strict';

// ---------------------------------------------------------------------------
// The machine master over HTTP.
//
//   GET    /api/machines                              the list (cached master data)
//   GET    /api/machines/:id                          one
//   POST   /api/machines                              create, or update when `id` is a real one
//   DELETE /api/machines/:id                          remove, unless a live run holds it
//   GET    /api/machines/:id/assets                   its photos
//   POST   /api/machines/:id/assets/upload-intent     ask for somewhere to put one
//   POST   /api/machines/:id/assets/upload-complete   say it arrived
//   GET    /api/machines/:id/photos                   its photos, in order (its gallery)
//   PUT    /api/machines/:id/photos                   their order and the main one
//
// `machines` is the first path segment, so the central CRUD gate maps every
// route here to the machines module. The four master routes ask the module's
// operations (./operations.js) at the kernel desk; the asset routes call the
// kernel's asset service.
//
// NOT here: GET /api/machines/:id/queue. It reads pipeline_runs, so it is in
// modules/production/routes.js.
// ---------------------------------------------------------------------------

const { httpKit } = require('../../kernel/desk-kit');

module.exports = function registerMachineRoutes(ctx) {
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

  // Machines CRUD Endpoints
  app.get('/api/machines', requirePermission('config.read'), cacheMasterData, async (req, res) => {
    try {
      const result = await ask(req, 'machines.list');
      if (!result.ok) return refuse(res, result);
      res.json({ success: true, machines: result.machines, error: null });
    } catch (error) {
      res.status(500).json({ success: false, machines: [], error: error.message });
    }
  });

  app.get('/api/machines/:id', requirePermission('config.read'), async (req, res) => {
    try {
      const result = await ask(req, 'machines.get', { id: req.params.id });
      if (!result.ok) return refuse(res, result);
      res.json({ success: true, machine: result.machine, error: null });
    } catch (error) {
      res.status(500).json({ success: false, machine: null, error: error.message });
    }
  });

  app.post('/api/machines', requirePermission('config.write'), async (req, res) => {
    try {
      const result = await ask(req, 'machines.save', req.body);
      if (!result.ok) return refuse(res, result);
      if (result.isUpdate) {
        trackUpdate('machines', result.resultId, result.before, result.row, req);
      } else {
        trackCreate('machines', result.resultId, result.row, req);
      }
      res.json({ success: true, machine: result.machine, error: null });
    } catch (error) {
      res.status(500).json({ success: false, machine: null, error: error.message });
    }
  });

  app.delete('/api/machines/:id', requirePermission('config.write'), async (req, res) => {
    try {
      const id = req.params.id;
      const result = await ask(req, 'machines.delete', { id });
      if (!result.ok) return refuse(res, result);
      trackDelete('machines', id, result.before, req);
      res.json({ success: true, error: null });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Machines Assets
  app.get('/api/machines/:id/assets', requirePermission('config.read'), async (req, res) => {
    try {
      const assets = await listAssetsForEntity('machine', Number(req.params.id));
      res.json({ success: true, assets, error: null });
    } catch (error) {
      res.status(500).json({ success: false, assets: [], error: error.message });
    }
  });

  // A machine's photos, up to five, as a part's and a die's are (2026-11-24).
  app.get('/api/machines/:id/photos', requirePermission('config.read'), async (req, res) => {
    try {
      const photos = await listEntityPhotos('machine', Number(req.params.id));
      res.json({ success: true, photos, limit: 5, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, photos: [], error: error.message });
    }
  });

  app.put('/api/machines/:id/photos', requirePermission('config.write'), async (req, res) => {
    try {
      const photos = await arrangeEntityPhotos('machine', Number(req.params.id), {
        order: req.body?.order,
        primaryId: req.body?.primaryId,
      });
      res.json({ success: true, photos, limit: 5, error: null });
    } catch (error) {
      res.status(error.statusCode || 500).json({ success: false, photos: [], error: error.message });
    }
  });

  app.post('/api/machines/:id/assets/upload-intent', requirePermission('config.write'), async (req, res) => {
    try {
      const entityId = Number(req.params.id);
      const intent = await createAssetUploadIntent({
        ...(req.body || {}),
        entityType: 'machine',
        entityId,
      });
      res.status(intent.alreadyUploaded ? 200 : 201).json({ success: true, intent, error: null });
    } catch (error) {
      res.status(500).json({ success: false, intent: null, error: error.message });
    }
  });

  app.post('/api/machines/:id/assets/upload-complete', requirePermission('config.write'), async (req, res) => {
    try {
      const asset = await completeAssetUpload(req.body || {});
      res.json({ success: true, asset, error: null });
    } catch (error) {
      res.status(500).json({ success: false, asset: null, error: error.message });
    }
  });
};
