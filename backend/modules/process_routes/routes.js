'use strict';

// ---------------------------------------------------------------------------
// Process routing module — HTTP.
//
//   GET  /api/process-stages                   the factory's stage master
//   POST /api/process-stages                   add a stage — a name is all it takes
//   DELETE /api/process-stages/:id             retire one no route stands on
//   GET  /api/items/:id/routes                 every version, active first
//   POST /api/items/:id/routes                 save a route (draft or active)
//   POST /api/items/:id/routes/versions        declare a new version
//
// PATHS. The doc calls the owner a "part"; this schema calls it an item and
// every existing endpoint is /api/items. `/api/parts/...` would have been both
// a second name for one thing AND an ungated one: moduleOpForRequest maps the
// FIRST path segment to a module, and an unmapped segment returns null, which
// means no per-module CRUD check at all (the hole pattern that let payroll
// reads through). Nesting under /api/items inherits items.read / items.create
// and, because recordIdForRequest reads the segment after the module, the
// per-record grants as well. `process-stages` is a new segment, so it is
// declared in that map — one line, in the ['items', 'groups'] list.
//
// Every save goes through one endpoint and one validator, whichever screen sent
// it: the Classic dropdown view and the List drag view both POST the same
// ordered list of stage ids.
// ---------------------------------------------------------------------------

const createProcessRouteService = require('./service');

module.exports = function registerProcessRoutesModule(ctx) {
  const {
    app, get, all, run,
    requirePermission,
    trackCreate,
    trackUpdate,
  } = ctx;

  const service = createProcessRouteService({ get, all, run });

  /// The part must exist before it can be routed. Checked explicitly so the
  /// answer is a 404 about the part rather than a foreign-key error about a
  /// table the caller has never heard of.
  async function partOr404(req, res) {
    const id = Number(req.params.id);
    if (!Number.isInteger(id) || id <= 0) {
      res.status(400).json({ success: false, error: 'Invalid part id.' });
      return null;
    }
    const row = await get('SELECT id, name, display_name FROM items WHERE id = ?', [id]);
    if (!row) {
      res.status(404).json({ success: false, error: 'That part no longer exists.' });
      return null;
    }
    return row;
  }

  function refuse(res, result) {
    res.status(result.status || 400).json({
      success: false,
      error: result.error,
      code: result.code,
      ...(result.routeId ? { routeId: result.routeId, version: result.version } : {}),
    });
  }

  app.get('/api/process-stages', requirePermission('items.read'), async (req, res) => {
    try {
      const includeInactive = String(req.query.includeInactive || '') === 'true';
      res.json({ success: true, stages: await service.listStages({ includeInactive }) });
    } catch (error) {
      console.error('[Routes] stage master failed:', error);
      res.status(500).json({ success: false, error: 'Could not read the stage master.' });
    }
  });

  app.post('/api/process-stages', requirePermission('items.create'), async (req, res) => {
    try {
      const result = await service.createStage({ name: req.body?.name });
      if (!result.ok) {
        // The 409 carries the stage that already has this name, so the
        // caller can simply use it.
        res.status(result.status || 400).json({
          success: false,
          error: result.error,
          code: result.code,
          ...(result.stage ? { stage: result.stage } : {}),
        });
        return;
      }
      if (trackCreate) trackCreate('process_stages', result.stage.id, result.stage, req);
      res.status(201).json({ success: true, stage: result.stage });
    } catch (error) {
      console.error('[Routes] stage create failed:', error);
      res.status(500).json({ success: false, error: 'Could not add the stage.' });
    }
  });

  app.delete('/api/process-stages/:id', requirePermission('items.delete'), async (req, res) => {
    try {
      const result = await service.retireStage(req.params.id);
      if (!result.ok) {
        res.status(result.status || 400).json({
          success: false,
          error: result.error,
          code: result.code,
          ...(result.uses ? { uses: result.uses } : {}),
        });
        return;
      }
      if (trackUpdate) {
        trackUpdate('process_stages', result.stage.id, { ...result.stage, active: 1 }, result.stage, req);
      }
      res.json({ success: true, stage: result.stage });
    } catch (error) {
      console.error('[Routes] stage delete failed:', error);
      res.status(500).json({ success: false, error: 'Could not delete the stage.' });
    }
  });

  app.get('/api/items/:id/routes', requirePermission('items.read'), async (req, res) => {
    try {
      const part = await partOr404(req, res);
      if (!part) return;
      res.json({ success: true, routes: await service.routesFor(part.id) });
    } catch (error) {
      console.error('[Routes] read failed:', error);
      res.status(500).json({ success: false, error: 'Could not read this part’s routes.' });
    }
  });

  app.post('/api/items/:id/routes', requirePermission('items.update'), async (req, res) => {
    try {
      const part = await partOr404(req, res);
      if (!part) return;
      const result = await service.saveRoute(part.id, req.body?.steps, {
        status: String(req.body?.status || 'active'),
        note: String(req.body?.note || '').trim(),
        userId: req.user?.id || null,
      });
      if (!result.ok) {
        refuse(res, result);
        return;
      }
      // A route is a part attribute with its own lifecycle, so it is logged
      // against the PART — that is the record somebody opens the Track tab on.
      // `route_created` / `route_versioned` in the doc's metric map are entity
      // lifecycle, which entity_activity_log already carries (and with them a
      // sitting, free, via logEntityActivity). The floor transitions
      // stage_entered / stage_exited belong to Stage tracking and are not this.
      const label = { name: `${part.display_name || part.name} route v${result.version}` };
      if (result.created) trackCreate('items', part.id, label, req);
      else trackUpdate('items', part.id, { name: 'route' }, label, req);
      res.json({ success: true, ...result, routes: await service.routesFor(part.id) });
    } catch (error) {
      console.error('[Routes] save failed:', error);
      res.status(500).json({ success: false, error: 'Could not save the route.' });
    }
  });

  app.post('/api/items/:id/routes/versions', requirePermission('items.update'), async (req, res) => {
    try {
      const part = await partOr404(req, res);
      if (!part) return;
      const result = await service.declareVersion(part.id, req.body?.steps, {
        note: String(req.body?.note || '').trim(),
        userId: req.user?.id || null,
      });
      if (!result.ok) {
        refuse(res, result);
        return;
      }
      trackUpdate(
        'items',
        part.id,
        { name: `route v${result.previousVersion}` },
        { name: `route v${result.version}` },
        req,
      );
      res.json({ success: true, ...result, routes: await service.routesFor(part.id) });
    } catch (error) {
      console.error('[Routes] version failed:', error);
      res.status(500).json({ success: false, error: 'Could not declare a new version.' });
    }
  });

  return service;
};
