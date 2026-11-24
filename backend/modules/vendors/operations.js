'use strict';

// ---------------------------------------------------------------------------
// Vendors — what the module offers at the kernel desk.
//
//   offered to users
//     vendors.list · vendors.get · vendors.purchaseHistory
//     vendors.create · vendors.update · vendors.delete
//
//   internal — asked by other modules
//     vendors.rows.get        a vendor's row, for challans
//
// A write's result also carries the raw rows the Track entry is written from
// (`row`, `before`, `after`); the route writes the entry because Track needs
// the request.
//
// Still reached through hand-wired ports, until those modules publish
// operations: how many challans name a vendor and what a vendor delivered
// (challans), what an item is called (items), the trash (action center).
// ---------------------------------------------------------------------------

const { refusing } = require('../../kernel/desk-kit');

const id = { type: 'integer', required: true, gt: 0 };
const text = { type: 'string', nullable: true };
const object = { type: 'object' };
const vendorFields = {
  // That a vendor needs a name is the service's to say, in its own words.
  name: text,
  alias: text,
  gstNumber: text,
  address: text,
  contactName: text,
  phone: text,
  email: text,
  logoUrl: text,
  photoUrl: text,
  // Absent on an update keeps what is stored.
  suppliesRawMaterial: { type: 'boolean', nullable: true },
  doesOutsourcing: { type: 'boolean', nullable: true },
};
const vendorResult = { fields: { vendor: { ...object, required: true } } };

module.exports = function vendorOperations({
  service,
  get,
  run,
  challans,
  itemsPorts,
  partyDeleteBlockers,
  trashAndDelete,
}) {
  const rawVendor = (vendorId) => get('SELECT * FROM vendors WHERE id = ?', [vendorId]);
  const removeRow = (vendorId) => run('DELETE FROM vendors WHERE id = ?', [vendorId]);

  return {
    'vendors.list': {
      permission: 'vendors.read',
      summary: 'Every vendor, archived last, with how many challans name each.',
      output: { fields: { vendors: { type: 'array', required: true, items: object } } },
      run: async () => ({
        ok: true,
        vendors: (await service.getVendorsWithUsage()).map(service.rowToVendorDto),
      }),
    },

    'vendors.get': {
      permission: 'vendors.read',
      summary: 'One vendor.',
      input: { fields: { id } },
      output: vendorResult,
      run: async (input) => {
        const row = await service.getVendorRowById(input.id);
        if (!row) return { ok: false, status: 404, error: 'Not found' };
        return { ok: true, vendor: service.rowToVendorDto(row) };
      },
    },

    'vendors.purchaseHistory': {
      permission: 'vendors.read',
      summary: 'The distinct items and variations a vendor has delivered.',
      input: { fields: { id } },
      output: { fields: { history: { type: 'array', required: true, items: object } } },
      run: async (input) => {
        const rows = await challans.vendorPurchaseRows(Number(input.id));

        const historyItems = [];
        for (const r of rows) {
          const itemDesc = await itemsPorts.describe(r.item_id);
          historyItems.push({
            itemId: r.item_id,
            variationLeafNodeId: r.variation_leaf_node_id,
            variationPathLabel: r.variation_path_label,
            variationPathNodeIds: JSON.parse(r.variation_path_node_ids_json || '[]'),
            customVariationValues: JSON.parse(r.custom_variation_values_json || '{}'),
            particulars: r.particulars || itemDesc?.name || 'Unknown Item',
          });
        }

        // Deduplicated here as well, in case DISTINCT missed something because
        // of JSON differences.
        const uniqueItems = [];
        const seen = new Set();
        for (const item of historyItems) {
          const key = `${item.itemId}_${item.variationLeafNodeId}`;
          if (!seen.has(key)) {
            seen.add(key);
            uniqueItems.push(item);
          }
        }
        return { ok: true, history: uniqueItems };
      },
    },

    'vendors.create': {
      permission: 'vendors.create',
      summary: 'Add a vendor. One per name or GST number.',
      input: { fields: vendorFields },
      output: { fields: { vendor: { ...object, required: true }, row: { ...object, required: true } } },
      run: (input) =>
        refusing(async () => {
          const row = await service.saveVendor({ ...input, id: null });
          return { ok: true, vendor: service.rowToVendorDto(row), row };
        }),
    },

    'vendors.update': {
      permission: 'vendors.update',
      summary: 'Change a vendor. A logo or photo left out is kept.',
      input: { fields: { id, ...vendorFields } },
      output: vendorResult,
      run: (input) =>
        refusing(async () => {
          const vendorId = Number(input.id);
          const before = await rawVendor(vendorId);
          const row = await service.saveVendor({ ...input, id: vendorId });
          return {
            ok: true,
            vendor: service.rowToVendorDto(row),
            before,
            after: await rawVendor(vendorId),
          };
        }),
    },

    'vendors.delete': {
      permission: 'vendors.delete',
      summary: 'Move a vendor nothing names to the trash.',
      input: { fields: { id } },
      run: async (input, ctx) => {
        const vendorId = Number(input.id);
        const before = await rawVendor(vendorId);
        const blockers = await partyDeleteBlockers('vendors', vendorId);
        if (blockers.length > 0) {
          return {
            ok: false,
            status: 409,
            code: 'vendor_in_use',
            error: `"${before?.name || 'This vendor'}" is still named on ${blockers.join(' and ')}. `
              + 'Archive it instead.',
          };
        }
        await trashAndDelete('vendors', vendorId, { user: ctx.actor?.user || null });
        return { ok: true, before };
      },
    },

    'vendors.rows.remove': {
      internal: true,
      summary: 'Delete a vendor’s row outright: an approved delete request.',
      input: { fields: { id: { type: 'any', required: true } } },
      run: async (input) => {
        await removeRow(input.id);
        return { ok: true };
      },
    },

    'vendors.rows.get': {
      internal: true,
      summary: 'A vendor’s row with its usage count, or nothing.',
      input: { fields: { id: { type: 'any', required: true } } },
      output: { fields: { row: { ...object, nullable: true } } },
      run: async (input) => ({ ok: true, row: await service.getVendorRowById(input.id) }),
    },
  };
};
