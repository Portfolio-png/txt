# Variation trees beyond items, and the version rule

*Added 2026-10-02. Backend and the die editor's Variations section are complete
and tested. The last section is what was deliberately left for later.*

## Why a second store

`item_variation_nodes` is keyed by `item_id`, so a die cannot carry a tree
without either a fourth near-identical table or a column that lies.
`entity_variation_nodes` (migration `044`) is the general form, keyed by
`(entity_type, entity_id)` — the same move `entity_links` made, for the same
reason: the shape is one shape and only the owner differs. The entity catalog
is **shared with the links module** (`modules/links/catalog.js`), so a master
that can be linked can carry a tree, and neither feature had to learn about the
other for that to be true.

**Items are not migrated onto it.** Their tree is read and written by a dozen
paths in `items_screen.dart` and the items module; two stores both claiming to
hold an item's properties would drift the first time one was missed. The column
set is deliberately identical to `item_variation_nodes`', so that migration is
a copy rather than a redesign when someone is ready to move those paths.

## The version rule

For the client this was built for, **items are derived from dies**. A die
saying it cuts 2 and 4 cavities is a statement every item struck from it was
made under, so the tree is *fixed within a version*:

- **Adding** a property or value is always allowed, in place, no ceremony. It
  takes nothing away from what was already derived, and it is the edit the shop
  floor actually makes — "after creation they can still add values".
- **Changing or removing** anything already there is refused with `409`, which
  names what it would have changed. A new version is how that change gets
  declared out loud.

### A declared version is spent by the save that follows it

Nodes carry the version they were last written in. The tree is locked while its
newest node is already at the owner's current version — the current version
describes the tree as it stands, so changing it would rewrite that description.
Declaring a version puts the current version ahead of every node; the next save
may then change anything, stamps what it touches, and locks again.

So **one bump buys one editing pass**. That is what a form does anyway — open
it, make the changes, save once — but it does mean a corrective second pass
needs a second version. For a record items are derived from, saying so twice is
the right cost, and the alternative (an open-ended unlock) would quietly make
the rule meaningless.

Removed nodes are **archived, not deleted**, so what was derived under an
earlier version can still be read against the tree it was derived from.

### Where it is enforced

In `modules/variations/routes.js`, not in SQL: whether an edit is an append or
a rewrite is a fact about two versions of a tree, and a `CHECK` on one row
cannot see it. The route compares the incoming tree against the stored one
field by field (`TRACKED_FIELDS`) and reports every break at once rather than
failing on the first.

`/api/variations` is excluded from the central CRUD gate and bypassed in
`requireApiWritePermission`, because the module it belongs to is named by the
entity type *in the path* (`/variations/die/7` is the dies module) — which the
segment map cannot express. The route asks for `<owner module>.read` /
`.update` itself, and a test pins that staff with `dies.update` can edit a die's
tree while staff without it cannot.

## The editor

`VariationTreeEditor` (`core_erp/lib/features/variations/`) is a section inside
someone else's form, not a screen. It renders the lock rather than hiding it:
fixed fields are disabled with a padlock, their remove buttons are dead, the
version chip says which version is in force, and **Add value stays live on every
property whatever the version says**. When something is locked it offers
"New version", which asks for a name and a note — a version nobody can account
for is not much of a declaration.

The die form holds the controller and saves the tree straight after the die,
because a die being created has no id to hang a tree on until its own save
returns one. A refused tree does not roll back the die: they are separate
records, and losing the die because its tree was locked would be the wrong
trade.

## Deliberately not built yet

The client asked for all three of these; this is the first.

- **Deriving items from a die's tree.** Items are derived from dies here, so
  the spawn direction is die → item, not die → die. The combination engine for
  that lives in `items_screen.dart` today and is bound to an item as its base;
  pointing it at a die's tree is the next piece.
- **Moving items onto the shared store.** The reason to wait is above; the
  reason to do it is that two trees will otherwise drift in what a property can
  be. The column sets match so the migration stays a copy.
- **The richer input types.** Items support Gauge, Material and numeric ranges;
  this editor offers Text and Numeric. The columns are already there
  (`input_type`, `numeric_min/max`, `material_type_id`) so adding them is UI
  work, not a migration.
