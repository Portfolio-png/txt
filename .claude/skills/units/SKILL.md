---
name: units
description: Use whenever code in Paper reads, writes, stores, parses, converts, sums, compares or displays a physical quantity (weight, count, length, area, volume, time), touches the units master, or adds a column/field/cell that shows a quantity. Defines the only allowed way to handle units, in Flutter and in the Node backend.
---

# Units — the one way Paper handles quantities

This document is the contract. If existing code disagrees with it, the code is wrong
and gets moved toward this, not the other way round.

**Read §0 first.** Almost none of this is built yet, and a previous draft of this file
described the target as though it were the present. Knowing which is which is the
difference between following the contract and hallucinating an API.

## 0. State of play (audited 2026-10-03)

What exists:

| | |
|---|---|
| `units` table | 9 rows: Primary Unit, Piece, Box, Carton, Meter, Liter, Kilogram, Gram, Archived Unit |
| `unit_groups` table | **0 rows.** Columns `id, name, dimension, base_unit_id` |
| Dart | `packages/core_erp/lib/features/units/` — `UnitDefinition`, `UnitsProvider`, `units_screen.dart`, `unit_converter_widget.dart`, `global_length_units.dart` |
| Backend | no `backend/modules/units/`; unit routes still in `server.js` (registry: `units`, `evacuated: false`) |

What is **not** true yet, and must not be assumed:

- **There are no families.** `unit_group_id` is NULL on all 9 units, and `unit_groups`
  is empty. Nothing knows that kg and g are the same dimension.
- **There are no ladders and no base units.** `conversion_factor` is `REAL` and is
  `1.0` on every row. `conversion_base_unit_id` is NULL on every row. There is no
  `is_base`, no `on_ladder`, no `uqc` column.
- **Quantities are floats nearly everywhere**, which is invariant I1 violated
  wholesale:
  - `delivery_challan_items.quantity_pcs REAL`, `.weight REAL`
  - `materials.on_hand_qty / reserved_qty / available_to_promise_qty / incoming_qty REAL`
  - `variation_stock.quantity REAL`
  - `order_items.total_invoiced_qty REAL`
  - `order_items.quantity` is INTEGER (the one that already complies)
- **A unit is stored as a string in places.** `materials.unit TEXT` alongside
  `materials.unit_id`.
- **`item_unit_conversions` exists but is not §7's shape.** It is
  `(item_id, unit_id, factor_to_primary REAL)` — per-item, per-unit, float, with no
  notion of from/to family.
- **There is no `Quantity` type and no single formatter.** 45 files call
  `toStringAsFixed` directly. That is the per-widget formatting §2/I7 is about.

So every section below describes the **target**. When you touch a quantity, move that
one path toward it; do not pretend the module already exists.

### Where quantities surface (marked in-app, 2026-10-03)

Evidence from a pass over the running app with the mark tool. These are the screens a
migration has to satisfy, not a complete list:

- Inventory → Groups: the **Stock** column
- Challans: "Delivered 1000 Pcs / …", "Received 0 items" on every reception/delivery card
- Edit Delivery Challan: the **Qty** and **Weight** line-item fields
- Order Book: the **Qty** column; Order Details: the **Quantity** column, with **Unit** beside it
- Production reconcile: **Input material**, **Stage Output**, **Leftover**, **Scrap**,
  and the stage row's OUTPUT QTY / LEFTOVER / SCRAP

The reconcile panel currently renders its labels as `Input material ()` — empty
parentheses where the unit belongs. That is this contract's absence, visible on screen.

## 1. What a unit fundamentally is

A unit is **a name for a fixed multiple of a base quantity within one dimension.**
That is all. Everything else follows from three facts:

1. **Every unit belongs to exactly one family (dimension).** Mass, Count, Length,
   Area, Volume, Time. A kilogram and a piece can never be converted by the unit
   master — that needs knowledge about a specific item (see §7).
2. **Every family has exactly one base unit: the smallest unit the factory will ever
   record in it.** Every other unit in the family is a positive whole-number multiple
   of the base. Because the base is the smallest, every factor is an integer and no
   unit ever needs a fractional factor.
3. **A quantity is an integer count of base units, plus its family.** "1.25 kg" is
   not a number with a label; it is `1,250,000 mg` of Mass, shown as kg.

Ladders are not uniform, which is why no rule may ever assume "×1000":

| Family | Base   | Ladder (factor to base)                                         |
|--------|--------|-----------------------------------------------------------------|
| Mass   | mg     | g = 1,000 · kg = 1,000,000 · quintal = 100,000,000 · tonne = 1,000,000,000 |
| Count  | piece  | dozen = 12 · gross = 144                                        |
| Length | µm     | mm = 1,000 · cm = 10,000 · m = 1,000,000 · inch = 25,400 · ft = 304,800 |
| Area   | mm²    | cm² = 100 · m² = 1,000,000                                      |
| Volume | mL     | L = 1,000                                                       |
| Time   | second | min = 60 · hr = 3,600                                           |

1 quintal = 100 kg (not 1000). 1000 kg = 1 tonne.

A unit whose factor is not a whole number of the base (sq ft in mm² = 92,903.04) means
the base is too coarse. Either pick a finer base for that family or leave the unit out.
Never store a fractional factor.

## 2. Invariants (must always hold)

- **I1. No floats anywhere in the quantity path.** Not in SQLite, not in Dart, not in
  JS. Quantities are integers of base units. `double` may appear only at the very last
  step of rendering text, and preferably not even there (§5).
- **I2. Units are data, not code.** Families, units, factors and ladders live in the
  tables. Adding a unit is inserting a row. No `switch` on unit codes, no hardcoded
  `* 1000`, no `if (unit == 'kg')` anywhere in the codebase.
- **I3. Store ids, not strings.** Rows reference `unit_id` / family id, never `'kg'`.
- **I4. Arithmetic only within a family.** Adding Mass to Count is a programming
  error and must throw, not coerce.
- **I5. Display never changes data.** Auto-promotion (1250 g → 1.25 kg) is a rendering
  decision. What is stored is always base units. What a document was *billed in* is
  stored separately and never auto-promoted (§6).
- **I6. Never silently round input.** If what the user typed cannot be expressed as a
  whole number of base units (e.g. 1.1 dozen = 13.2 pieces), reject it with a message.
  Do not round it quietly.
- **I7. A quantity never travels as a bare number.** Between functions, widgets, DTOs
  and table cells it is a `Quantity` (Dart) or `{ base, familyId }` (JSON). A widget
  that accepts a `num` for a quantity is a bug.

I7 is the reason new columns "don't know" about promotion today: each cell gets a
plain number and formats it itself (45 files call `toStringAsFixed`). Once a cell can
only receive a `Quantity`, it can only render it through the one formatter, and every
new column gets promotion for free.

## 3. Schema (target)

The existing tables are `units` and `unit_groups`. **Extend those rather than creating
`unit_families`** — `unit_groups` already has `dimension` and `base_unit_id`, it is
simply unpopulated, and the registry already assigns both tables to the `units` module.

```sql
-- unit_groups: the family. Add if missing, then SEED (it is empty today).
ALTER TABLE unit_groups ADD COLUMN code TEXT;             -- 'mass', 'count', ...
ALTER TABLE unit_groups ADD COLUMN integral_only INTEGER NOT NULL DEFAULT 0;
-- dimension, base_unit_id already exist and must be filled.

-- units: the ladder rung.
ALTER TABLE units ADD COLUMN factor_to_base INTEGER NOT NULL DEFAULT 1;  -- replaces conversion_factor REAL
ALTER TABLE units ADD COLUMN is_base INTEGER NOT NULL DEFAULT 0;
ALTER TABLE units ADD COLUMN on_ladder INTEGER NOT NULL DEFAULT 1;
ALTER TABLE units ADD COLUMN uqc TEXT;                    -- GST Unit Quantity Code, 'KGS'
-- unit_group_id already exists and is NULL on every row; it must be filled.
-- exactly one is_base row per family, and its factor_to_base = 1
```

`conversion_factor REAL`, `conversion_base_unit_id` and `conversion_type` are the old
shape. Leave them in place until readers are migrated, then drop them — do not write
to both.

A table that stores a quantity stores:

```sql
qty_base   INTEGER NOT NULL,                       -- integer count of base units
family_id  INTEGER NOT NULL REFERENCES unit_groups(id)
-- and, only on documents (challans, invoices, POs):
billed_unit_id INTEGER REFERENCES units(id)        -- the unit printed/billed in
```

Where the family is already fixed by context (e.g. an item's stock family), the column
may be omitted and the family read from the owner — but the value is still base units.

Integer range: SQLite and native Dart ints are 64-bit. If any client runs on web
(JS numbers, safe to 2^53 ≈ 9×10^15), mg still covers ~9 million tonnes. Safe.

## 4. The module (single source of truth)

Follow the house layout, not a new top-level folder:

- Dart: `packages/core_erp/lib/features/units/` — the feature already exists. Add
  `domain/quantity.dart`, `domain/unit_family.dart`, `domain/units.dart` (the static
  API) and `presentation/widgets/quantity_text.dart` beside what is there.
- Node: `backend/modules/units/` — new, and it is also the `units` module's evacuation
  out of `server.js` (see `backend/kernel/registry.js`, currently `evacuated: false`).

Both expose the same operations with the same semantics. Everything else imports
these; nothing reimplements them.

### Dart

```dart
class UnitFamily {
  final int id; final String code; final bool integralOnly;
  final List<Unit> units;            // sorted by factorToBase ascending
  Unit get base;
  List<Unit> get ladder;             // units where onLadder, ascending
}

class Unit {
  final int id; final int familyId; final String code, label;
  final int factorToBase; final bool onLadder; final int maxDecimals;
  final String? uqc;
}

class Quantity implements Comparable<Quantity> {
  final int base;                    // integer base units — the truth
  final UnitFamily family;
  const Quantity(this.base, this.family);

  Quantity operator +(Quantity o);   // throws if family differs (I4)
  Quantity operator -(Quantity o);
  Quantity times(int n);
  bool get isZero;
  int compareTo(Quantity o);         // throws if family differs
}

abstract final class Units {
  /// Parse user text in a chosen unit. Pure integer/string arithmetic — never
  /// `double.parse(text) * factor`. Throws UnitParseError if the result is not a
  /// whole number of base units (I6).
  static Quantity parse(String text, Unit unit);

  static Quantity of(int amountInUnit, Unit unit); // exact: amount * factor

  /// The single formatter. Every quantity shown anywhere goes through this.
  static String format(Quantity q, {QtyDisplay display = const QtyDisplay.auto()});

  /// Value in a given unit as exact parts, for printing/export.
  static ({int whole, int remainder, int divisor}) inUnit(Quantity q, Unit u);
}

sealed class QtyDisplay {
  const factory QtyDisplay.auto();          // promote along the ladder
  const factory QtyDisplay.pinned(Unit u);  // documents, billed quantities
  const factory QtyDisplay.base();          // shop floor: never promote
}
```

And one widget, which is the only way a quantity reaches the screen:

```dart
class QuantityText extends StatelessWidget {
  const QuantityText(this.q, {this.display = const QtyDisplay.auto(), super.key});
  final Quantity q; final QtyDisplay display;
}
```

Table/grid column definitions take a `Quantity Function(Row)` accessor, never a
`num Function(Row)`. That is what makes a new column automatically correct.

### Backend (Node)

Same functions in `backend/modules/units/`: `parse(text, unitId)`, `format(qtyBase,
familyId, display)`, `add`, `sub`. Values are JS integers (or BigInt if a family could
exceed 2^53 — none do today). Routes accept and return `{ base, familyId }` and,
where relevant, a `unitId` the user entered in. Routes never accept a pre-converted
float.

## 5. Algorithms (exact)

**Parsing** `parse("1.25", kg)` where kg.factorToBase = 1,000,000:
1. Validate text matches `^-?\d+(\.\d+)?$` (after stripping thousands separators).
2. Split into whole and fraction strings. Fraction has `d` digits → numerator
   `N = whole·10^d + fraction`, denominator `10^d`.
3. `base = N · factor / 10^d`. If `(N · factor) % 10^d != 0` → UnitParseError
   ("1.1 dozen is not a whole number of pieces").
4. If family is integralOnly, the same check is the whole-piece check.
No floating point at any step.

**Auto-promotion** `format(q, auto)`:
1. Candidates = `family.ladder`.
2. Pick the largest unit `u` with `|q.base| >= u.factorToBase`; if none, the
   smallest ladder unit.
3. Render `q.base / u.factorToBase` exactly as whole + remainder, then show the
   fraction in decimal up to `u.maxDecimals`, trimming trailing zeros. If the
   fraction needs more digits than `maxDecimals`, round half-up *for display only*.
   The stored value is untouched.

Examples (Mass, ladder g, kg, quintal, tonne, all on_ladder):
`999,000 mg → "999 g"` · `1,000,000 → "1 kg"` · `1,250,000 → "1.25 kg"` ·
`150,000,000 → "1.5 quintal"` · `2,000,000,000 → "2 tonne"`.
Whether quintal is on the ladder is a per-factory setting (flip `on_ladder`), not code.

**Pinned** `format(q, pinned(kg))`: same rendering, unit fixed. Used for anything a
human signs, bills, or reconciles.

## 6. Where each display mode is used

| Context                                   | Mode                          |
|-------------------------------------------|-------------------------------|
| Challans, invoices, POs, printed docs     | `pinned(billed_unit)` — never auto |
| GST output / e-way bill                   | pinned, and use `uqc`         |
| Inventory views, dashboards, item cards   | `auto`                        |
| Shop-floor phone screens, operator input  | `base` or pinned to the unit the operator counts in — "1,250 kg" beats "1.25 t" for an operator |
| Reports / exports (CSV, Excel)            | pinned to one unit per column, so the column is summable |

A column in a report never mixes units row to row. Auto-promotion is for reading one
number, not for columns of numbers someone will add up.

## 7. Cross-family conversion is NOT the unit master's job

"How many pieces is 50 kg of this bracket" depends on the item (thickness × area ×
density, or a measured weight per piece). That lives on the item/variation.

The existing `item_unit_conversions` is `(item_id, unit_id, factor_to_primary REAL)` —
a float ratio to the item's primary unit, with no from/to family. The target:

```sql
item_id          INTEGER NOT NULL REFERENCES items(id),
from_family_id   INTEGER NOT NULL,
to_family_id     INTEGER NOT NULL,
from_base_qty    INTEGER NOT NULL,   -- e.g. 1 piece
to_base_qty      INTEGER NOT NULL,   -- e.g. 342,000 mg
source           TEXT NOT NULL       -- 'measured' | 'derived'
```

A ratio of two integers, so no float ever enters the conversion. The units module may
*use* such a ratio (`convertVia(q, conversion)`), but it never invents one. If no
conversion exists, the answer is "not convertible", never a guess.

## 8. Rules for a coding agent working in this codebase

MUST
- Use `Quantity` / `{ base, familyId }` for every quantity in code, DTOs and widgets.
- Render every quantity with `QuantityText` or `Units.format`.
- Parse every quantity input with `Units.parse`, showing its error to the user.
- Store `qty_base INTEGER` + family (and `billed_unit_id` on documents).
- Read units, factors and ladders from the units tables via the module.
- Say so plainly when a task needs part of the module that does not exist yet (§0),
  and build that part rather than working around it.

NEVER
- `double` / `REAL` / `parseFloat` for a quantity.
- Hardcode a factor (`* 1000`, `/ 12`) or a unit code comparison.
- Write a local "format weight" helper, extension method or per-widget formatter.
- Store a quantity as text, or a unit as a string.
- Auto-promote a value on a document or in a summable report column.
- Convert across families inside the units module.
- Round user input silently.

When adding a new column, field, cell or report that shows a quantity:
1. Is the underlying value stored as `qty_base` with a known family? If not, fix that first.
2. Does the accessor return `Quantity`? If it returns `num`, change it.
3. Pick the display mode from §6.
4. Render with `QuantityText` / `Units.format`. Done — promotion and precision come free.

When adding a new unit: insert a row in `units` with an integer `factor_to_base` and
decide `on_ladder`. No code change. If the factor isn't an integer, see §1.

## 9. Tests that must exist and stay green

- `parse("1.25", kg) == 1,250,000 mg`; `parse("0.1", g) == 100 mg`.
- `parse("1.1", dozen)` throws; `parse("1.5", dozen) == 18 pieces`.
- `format` examples in §5 exactly.
- `1 quintal == 100 kg`, `1 tonne == 1000 kg`, `1 gross == 144 pieces`.
- Adding Mass to Count throws.
- Round trip: for every unit and many values, `parse(format(q, pinned(u)), u) == q`
  whenever the display was not capped by `max_decimals`.
- Same test vectors run against the Dart and the Node implementations.

## 10. Migrating existing code

Order matters; each step is shippable on its own.

1. **Seed the families.** `unit_groups` is empty and every unit is ungrouped. Create
   Mass/Count/Length/Area/Volume/Time, add the columns in §3, assign all 9 existing
   units to a family with an integer `factor_to_base`, and pick each family's base.
   Until this exists nothing else in this document can be true.
2. **Build the module** (Dart + Node) with §9's tests, against the seeded data.
3. **Per quantity column**, add `qty_base INTEGER` + family, backfill through the
   module (log any value that is not a whole number of base units — that is a data
   problem to look at, not round away), switch readers, then drop the REAL column.
   Start with `delivery_challan_items` (quantity_pcs, weight) — it is both the worst
   offender and the one that prints on documents a client signs.
4. **Kill the formatters.** 45 files call `toStringAsFixed`; grep also for `* 1000`,
   `/ 1000` and unit-code string comparisons. Replace each with the module.
5. **Change grid/table column definitions to take `Quantity` accessors.** The compiler
   then finds every remaining place that passes a bare number.
