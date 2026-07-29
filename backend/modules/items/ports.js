'use strict';

// ---------------------------------------------------------------------------
// Items module — ports (kernel rule K5).
//
// The ONLY sanctioned surface through which other modules touch items
// territory. Consumers (challans, orders, inventory, production, jobs) call
// these named services instead of items helpers or items tables directly —
// making every cross-border interaction greppable (`itemsPorts.`), meterable
// (per-port call counts feed the territory report), and swappable (the
// implementations still live in legacy server.js and arrive via `impl`; they
// move behind this boundary without consumers noticing).
//
// Port surface (from the coupling survey in
// Docs/architecture/00-kernel-and-items-evacuation.md §3.1):
//   describe(itemId)            -> identity card: name/displayName/unit/etc.
//   resolveSelection(input)     -> validated {leaf, path label, path ids}
//   selectionSnapshot(id, leaf) -> line-item snapshot (particulars, labels)
//   stock.assertLeaf(id, leaf)  -> throws unless leaf is a valid stock leaf
//   stock.applyDelta(input)     -> THE single write path into variation_stock
//   bom.lines(itemId)           -> bill-of-material rows
//   lookupByName(name)          -> (SMELL) item id lookup by exact name match
//   delete(type, id, req)       -> orchestrates item/group cascade deletion
//   groups.ensureReconcilePrimary() -> creates/returns the primary reconcile group
//   groups.ensureReconcileSub() -> creates/returns a subgroup for reconciliation
//   ensureForReconcile()        -> creates/returns an item under a reconcile group
// ---------------------------------------------------------------------------

function createItemsPorts(impl) {
  const counts = {};
  function counted(name, fn) {
    if (typeof fn !== 'function') {
      throw new Error(`items port '${name}' has no implementation`);
    }
    counts[name] = 0;
    return (...args) => {
      counts[name] += 1;
      return fn(...args);
    };
  }

  return {
    describe: counted('describe', impl.describe),
    resolveSelection: counted('resolveSelection', impl.resolveSelection),
    selectionSnapshot: counted('selectionSnapshot', impl.selectionSnapshot),
    stock: {
      assertLeaf: counted('stock.assertLeaf', impl.stockAssertLeaf),
      applyDelta: counted('stock.applyDelta', impl.stockApplyDelta),
    },
    bom: {
      lines: counted('bom.lines', impl.bomLines),
    },
    lookupByName: counted('lookupByName', impl.lookupByName),
    delete: counted('delete', impl.deleteEntity),
    groups: {
      ensureReconcilePrimary: counted('groups.ensureReconcilePrimary', impl.ensureReconcilePrimary),
      ensureReconcileSub: counted('groups.ensureReconcileSub', impl.ensureReconcileSub),
    },
    ensureForReconcile: counted('ensureForReconcile', impl.ensureForReconcile),
    stats: () => ({ ...counts }),
  };
}

module.exports = { createItemsPorts };
