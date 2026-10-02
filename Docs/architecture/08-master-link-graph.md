# The master link graph

*Added 2026-10-02. Backend complete and tested; the column UI ships behind
`masters.linkColumns`. The last section is the open question.*

## What this replaces

A link between two masters used to mean a new table. There were three:
`item_dies`, `item_machines`, `material_group_item_links` — three shapes, three
read paths, and each one answerable in exactly one direction. `item_dies` is
read as *the dies of this item* by the item DTO and written only by the item
PUT. Nothing anywhere could answer *which items does this die make?*, although
that is the same row seen from the other side.

Adding die ↔ machine would have been a fourth table, and *what is this die set
up to run on?* would still have had one answer in one direction.

## The store

`entity_links` (migration `043-entity-links.sql`) holds a link as
`(type, id) ↔ (type, id)` — one row, no privileged end.

**The pair is stored in canonical order**, sorted by type and then by id, so
`die↔machine` and `machine↔die` are the same row and `UNIQUE` actually catches a
duplicate. A `CHECK` enforces the ordering at the schema level rather than
trusting every writer to normalise first, and its strict `<` on the same-type
branch makes a record linked to itself unrepresentable. A reader asks from
whichever end it is holding:

```sql
WHERE (left_type = ?1 AND left_id = ?2) OR (right_type = ?1 AND right_id = ?2)
```

and an index serves either branch. Ids are `TEXT` because materials are keyed by
barcode and pipeline templates by a text id; an `INTEGER` column would have put
those two masters outside the general case.

### The two legacy pairs are not folded in

`item_dies` and `item_machines` stay where they are, and **nothing was
backfilled**. The item DTO reads them and the item PUT rewrites them wholesale;
copying their rows into `entity_links` would leave two stores both claiming to
hold item↔die, and the first write path anyone forgot would split them.

Instead `modules/links/catalog.js` declares those two pairs as legacy and the
routes read and write the legacy table for them. One store per pair, no dual
write — and because the routes read *both* columns of those tables, *which items
does this die make?* is answerable now without a single row moving.

## The API

| | |
|---|---|
| `GET /api/links/schema` | what can be linked, and what this user may attach |
| `GET /api/links/:type` | the records of one master (the first column) |
| `GET /api/links/:type/:id` | that record's links, grouped by master |
| `GET /api/links/:type/:id/candidates?type=…&q=` | what it could link to and has not |
| `POST /api/links` | `{from:{type,id}, to:{type,id}, relation?}` |
| `DELETE /api/links/:type/:id/:otherType/:otherId` | unlink |

`POST` is direction-blind (either side gives the same row) and idempotent
(posting a pair twice returns the link already there), because *make sure these
two are linked* is what every caller means.

### Permissions

A link spans two modules, so there is no single `(module, op)` to map the path
to and the central CRUD gate skips `/links` — the same exclusion `/assets` has,
for the same reason. The gate lives in the module and asks about **both sides**:
reading a record's links needs `read` on its module; linking needs `update` on
both. A link whose far end the user cannot read is left out of the group list
rather than shown as a nameless row, and the `+` menu only offers masters they
can actually attach.

`requireApiWritePermission` bypasses `/links` so this stricter guard is the one
answering — without that bypass no staff user could ever link anything.

## Adding a master

One entry in `LINKABLE_TYPES` (`backend/modules/links/catalog.js`): table, id
column, label and subtitle SQL, kernel module key, and the archived column if it
has one. No migration, no table, no route. The column UI reads the catalog over
`/api/links/schema`, so it appears in every other master's `+` menu without an
app release.

Archived records are excluded from the **candidate picker** but not from links
that already exist — archiving a die must not make the link to it silently
vanish.

Orphans (a record deleted out from under a link) are skipped on read, because
the label is the whole content of the row and an orphan has none. The delete
cascades for items, dies and machines call `purgeLinksFor` by hand; nothing can
declare a foreign key against a polymorphic pair.

## The column UI

`LinkColumns` (`core_erp/lib/features/links/`) is Miller columns over the graph:
picking a record opens a column of everything it is linked to, grouped by
master; picking one of those opens *its* links, and so on rightwards. Each
column carries a `+` that attaches an existing record or — via the host's
`onCreate` — opens that master's real editor and links what it saves in the same
gesture.

It runs in two shapes:

- **Rooted** (`anchor: null`): the first column lists one master, with a
  switcher in its header, and the chain grows from a pick there.
- **Anchored** (`anchor: someRef`): no browse column at all. The host already
  has a record in hand, so the first column shown is *that record's* links.

### Where it sits in the creation window

Anchored, and branching off the **first** column — not the last. The lineup
(Item / Die / Machine, plus whatever the `+` has added) is already a list of
records being worked on, so a second list beside it would ask the same question
twice. Instead each tile remembers the record it stands for once it has saved
or opened one, and the selected tile's links open immediately to its right —
a **1.1 and 1.2 to the lineup's 1**.

**Two columns, not one.** The chain the window exists to make is three deep:
an item, its dies, and what one of those dies runs on. Two columns read it
without walking anywhere — and because nothing in the store privileges a
direction, the same pair of columns reads a die's items then that item's
machines, or a machine's dies then that die's items. Each column carries its
own `+` at the foot, where the lineup's own `+` is (`addAtBottom: true`), so a
machine is attached to the die in 1.2 without losing the item in 1.1.

The second column stands open before anything is picked in it
(`minColumns: 2`), saying what would fill it rather than appearing only once
used — Finder does the same, and it is what makes the cascade legible before
you have tried it.

### The way in is a button, not an empty column

The columns wait until the selected record actually has links. Before that the
entry point is a **link button on the lineup row itself**, beside the `+`, the
`×` and the drag handle. It opens the same master menu a column's `+` does —
literally the same code, `showLinkAttach`, which is public for exactly this
reason: two gestures that mean the same thing must not be two implementations
that drift.

An empty column teaches less than a button that says what it does, and costs
the editor its width to do it. The count behind that rule is read by the
workspace itself (`_ensureLinkCount`), not by the columns — the columns are
only built once the answer is known to be more than zero, so asking them would
mean they never appeared at all.

**The chevron.** Two columns cost the editor the best part of 300px, so they
shut away behind a rail down their left edge. The rail is deliberately outside
them: a chevron placed inside the columns would go away with them and leave no
way back. The V turns to point at what the click does. A drag forces the
columns open regardless, so the place to let go is on screen before the pointer
gets there.

A tile can also be **dragged sideways onto that column** to link what it stands
for to whatever the lineup has selected — the quickest way to say "this die
belongs to that item" when both were just made in this window. The gesture is
`Draggable(affinity: Axis.horizontal)`, which is what lets it share the tile
with everything else already on it: a vertical pan still scrolls the lineup, a
tap still selects, and the small handle inside the tile still reorders. The
column rises on drag-start rather than on drop, so the place to let go is on
screen before the pointer gets there. A tile with nothing saved in it does not
drag at all, rather than dragging to a refusal.

### Who gives up the width

Gated by `masters.linkColumns`. Columns are **sized, not fixed**: `_branchFit`
divides what is left after the lineup, the gaps and a 620pt floor for the
editor, clamped to 218–300pt each. A fixed width is what went wrong first — 288
fits a 1760pt window and silently falls back to one column on a 1710pt laptop,
with nothing on screen to say why the second one is missing.

**The reference tile stands down while the columns are open.** Its width is
most of what a second readable column costs, and the editor cannot give that
up. So the chevron swaps between the two — reference tile, or link columns —
rather than trying to fit both. A test pumps the real item editor at 1710×1070
with the strip open, because every version of this that was wrong was wrong
silently.

Three measured constraints hold this row together, and none of them is a taste
call:

- **The editor's footer overflows below ~1016pt** when it is the only panel
  beside the lineup and the reference tile. The editor is the one panel with no
  give, so every other width is taken around it.
- **The lineup needs ~296pt.** Its rows carry a drag handle, icon, label,
  chevron, count and three buttons. At 264 the label's `Expanded` was squeezed
  to about 44pt, which pushed the link button onto the row's *centre* — so
  clicking the middle of a tile to select it opened the link menu instead. A
  row has to leave its label enough space that its buttons stay at the end of
  it, where they look like they are.
- **The reference tile pays for that**, at 356pt rather than 380, because the
  editor could not.

> **Do not measure that with a `LayoutBuilder` around the row.** It was written
> that way first, and it put the lineup's `ReorderableListView` inside a layout
> callback. Rebuilding those items during layout reactivates each one's global
> key, which carries their tooltips' `OverlayPortal`s with it and marks the
> overlay dirty mid-`performLayout` — Flutter asserts, and the window dies on
> an ordinary drag or resize. The width comes from `MediaQuery` instead, via
> `_creationDialogWidth`, which the dialog also sizes itself from so the two
> cannot drift. For the same reason the tiles keep a fixed element-tree shape:
> the `Draggable` and its `Opacity` are always there, and only
> `maxSimultaneousDrags` and the opacity value change. A test asserts the
> workspace introduces no `LayoutBuilder` at all; the crash itself would not
> reproduce under `flutter test`. A host that has not wired
the link service shows the lineup exactly as before — the same rule the editor
hooks follow — and the reference tile on the right keeps its place either way.

The columns read through the API, not through the local replica, so the
post-write stale-read trap in `05-tier3-readiness-audit.md` does not apply to
them. `entity_links` does log to the changelog, so a replica reader can be added
later without touching the write paths.

## Open: how to sort this out cleanly

Deliberately unanswered until there is real data in it. Everything above is
shape, not opinion — the graph will take any pair of masters, and we do not yet
know which pairs people actually use or how they want them read back.

What to look at once links exist:

- **Which pairs get used, and how densely.** A die with forty items wants a
  different presentation from a die with one. The column list is flat and
  alphabetical today; it may want grouping, or a count-first summary.
- **Whether `relation` earns its keep.** It defaults to a bare `'linked'`
  because the type pair carries the sense in every case so far. If one pair
  turns out to need two senses (a die that *cuts* an item vs one that *forms*
  it), the column needs to show it and the `+` needs to ask.
- **Whether `metadata` gets used.** It is there (per-link JSON, no migration
  needed) and nothing reads it. A cavity count or a setup note on the
  die↔machine link is the obvious first customer.
- **Whether the legacy pairs should finally fold in.** They stay separate
  because the item PUT owns them. If the links API becomes the only way anyone
  attaches a die, that reason expires and `item_dies` / `item_machines` can be
  migrated in and the item DTO pointed at the graph.
