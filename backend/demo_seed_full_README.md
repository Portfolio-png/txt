# Complete Demo Seed Dataset

The complete structured seed dataset is in:

```text
backend/demo_seed_full.json
```

It is designed for the Paper ERP demo flow:

```text
order -> inventory -> production -> challan -> reporting
```

## Validate

Run:

```bash
node backend/scripts/validate-full-seed-data.js
```

The validator checks IDs and relationships across units, clients, vendors,
items, machines, dies, pipelines, inventory stock, orders, purchase orders,
production runs, and challans.

## Existing Demo Reset Flow

The current backend reset path is:

```text
backend/scripts/reseed-demo-data.js
  -> backend/server.js resetAndSeedDemoData()
  -> reseedDemoData()
  -> ensureDemoDataset()
  -> ensureFullDemoSeedDataset()
```

The app seeds its existing built-in demo records first, then loads
`backend/demo_seed_full.json` through `ensureFullDemoSeedDataset()`. The loader
translates stable string IDs from JSON into the SQLite numeric IDs used by the
app tables.

Reseed with:

```bash
cd backend
node scripts/reseed-demo-data.js
```

Or from the app UI in demo/admin mode:

```text
Settings & Preferences -> Reset + Reseed Demo
```

## Mapping Notes

- `inventory` rows map to material/stock records and include scanner-ready
  stock barcodes.
- `productionRuns.assignedStock` maps stock lots to pipeline stages.
- `challans` include delivery and reception examples, printed/cancelled flags,
  and links to orders, purchase orders, production runs, and report groups.
- `purchaseOrders` are included for realistic reception challan testing. If the
  backend PO workflow remains document-only, keep them as seed fixture data or
  map them to the closest PO document/order reference tables.
