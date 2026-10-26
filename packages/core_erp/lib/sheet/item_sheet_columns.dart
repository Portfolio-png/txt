import 'column_def.dart';
import 'sheet_binding.dart';

/// The item sheet's nine columns, and what each one feeds.
///
/// Hoisted out of `ItemMasterController._initControllers` because the layout is
/// a fact about this sheet while the fixture values beside it were a demo. The
/// controller used to declare these inline **with no `bindsTo` on any of
/// them**, so a binding handed this sheet could map nothing: the save would
/// have written an item with no name and no group. The bindings are the
/// load-bearing part of this file.
///
/// `Alloy` and `Thickness` carry [ColumnKind.material] and [ColumnKind.gauge]
/// rather than `list` and `quantity`. Those mirror
/// `ItemVariationNodeDefinition.inputType`'s own `'Material'` and `'Gauge'`,
/// and a gauge is deliberately **not** a quantity — `Units.parse` rejects the
/// suffix and vendor gauge values are recorded verbatim.
const List<ColumnDef> itemSheetColumns = [
  ColumnDef(
    id: 1,
    sheetId: 1,
    label: 'Group',
    kind: ColumnKind.list,
    role: ColumnRole.group,
    position: 0,
    bindsTo: SheetBindsTo.group,
  ),
  ColumnDef(
    id: 2,
    sheetId: 1,
    label: 'Type',
    kind: ColumnKind.list,
    parentId: 1,
    position: 1,
    bindsTo: SheetBindsTo.set,
  ),
  ColumnDef(
    id: 3,
    sheetId: 1,
    label: 'Part Name',
    kind: ColumnKind.list,
    role: ColumnRole.item,
    parentId: 2,
    position: 2,
    bindsTo: SheetBindsTo.name,
  ),
  ColumnDef(
    id: 4,
    sheetId: 1,
    label: 'Part No',
    kind: ColumnKind.seq,
    parentId: 3,
    position: 3,
    bindsTo: SheetBindsTo.partNo,
  ),
  ColumnDef(
    id: 6,
    sheetId: 1,
    label: 'Alloy',
    kind: ColumnKind.material,
    position: 4,
    bindsTo: '${SheetBindsTo.variationPrefix}Alloy',
  ),
  ColumnDef(
    id: 7,
    sheetId: 1,
    label: 'Thickness',
    kind: ColumnKind.gauge,
    position: 5,
    bindsTo: '${SheetBindsTo.variationPrefix}Thickness',
  ),
  // Last, always — the code is built FROM the properties beside it, so it
  // belongs at the end of the run it summarises. A property added with the +
  // lands before it and is folded in.
  ColumnDef(
    id: 5,
    sheetId: 1,
    label: 'Part Code',
    kind: ColumnKind.code,
    position: 6,
    bindsTo: SheetBindsTo.partCode,
  ),
  ColumnDef(
    id: 9,
    sheetId: 1,
    label: 'Date',
    kind: ColumnKind.date,
    role: ColumnRole.stamp,
    position: 7,
    bindsTo: SheetBindsTo.createdDate,
  ),
  ColumnDef(
    id: 10,
    sheetId: 1,
    label: 'Time',
    kind: ColumnKind.time,
    role: ColumnRole.stamp,
    position: 8,
    bindsTo: SheetBindsTo.createdTime,
  ),
];

/// The PROTOTYPE's development-deal sheet: one company and one person on a
/// single row. Kept for the PM prototype screen and the shared demo vectors,
/// which are written against it. The live item sheet uses [dealSheetColumns]
/// over [peopleSheetColumns] instead, because a company has many people and a
/// deal may involve several of them (migration 056).
///
/// Only Company Name and Quotation are written. The three contact columns are
/// **read-only projections** — `DevelopedFor` resolves `contactName`,
/// `designation`, `phone` and `email` server-side on every read, so writing
/// them is a no-op, and a sheet that pretended otherwise would silently drop
/// what was typed.
///
/// There is no Development Cost column. `items.developed_for_cost_amount` and
/// `SheetBindsTo.developedForCost` both remain — the field is still on the
/// item and the binding still writes it when something supplies it — but this
/// sheet does not collect it, so [MarginHealthBadge] has only the quotation
/// from here. A null cost must keep reading as "not known", never as zero.
const List<ColumnDef> partySheetColumns = [
  ColumnDef(
    id: 20,
    sheetId: 2,
    label: 'Company Name',
    kind: ColumnKind.list,
    role: ColumnRole.group,
    position: 0,
    source: ColumnSource.party,
    bindsTo: SheetBindsTo.developedForParty,
  ),
  ColumnDef(
    id: 21,
    sheetId: 2,
    label: 'Client Name',
    kind: ColumnKind.list,
    role: ColumnRole.item,
    parentId: 20,
    position: 1,
    source: ColumnSource.contact,
    bindsTo: SheetBindsTo.developedForContact,
  ),
  ColumnDef(
    id: 22,
    sheetId: 2,
    label: 'Designation',
    kind: ColumnKind.text,
    position: 2,
    bindsTo: SheetBindsTo.developedForDesignation,
  ),
  ColumnDef(
    id: 23,
    sheetId: 2,
    label: 'Contact No',
    kind: ColumnKind.phone,
    position: 3,
    bindsTo: SheetBindsTo.developedForPhone,
  ),
  ColumnDef(
    id: 24,
    sheetId: 2,
    label: 'Email ID',
    kind: ColumnKind.email,
    position: 4,
    bindsTo: SheetBindsTo.developedForEmail,
  ),
  ColumnDef(
    id: 25,
    sheetId: 2,
    label: 'Quotation',
    kind: ColumnKind.money,
    position: 5,
    bindsTo: SheetBindsTo.developedForQuotation,
  ),
  ColumnDef(
    id: 26,
    sheetId: 2,
    label: 'Date',
    kind: ColumnKind.date,
    role: ColumnRole.stamp,
    position: 6,
    bindsTo: SheetBindsTo.createdDate,
  ),
  ColumnDef(
    id: 27,
    sheetId: 2,
    label: 'Time',
    kind: ColumnKind.time,
    role: ColumnRole.stamp,
    position: 7,
    bindsTo: SheetBindsTo.createdTime,
  ),
];

/// The live development-deal strip: one row — the company, the quotation, and
/// when it was recorded. The quotation is ONE figure per part however many
/// people at the company were spoken to.
///
/// Column ids match [partySheetColumns] so a draft means the same thing on
/// either; the person columns (21–24) moved to [peopleSheetColumns].
const List<ColumnDef> dealSheetColumns = [
  ColumnDef(
    id: 20,
    sheetId: 2,
    label: 'Company Name',
    kind: ColumnKind.list,
    role: ColumnRole.group,
    position: 0,
    source: ColumnSource.party,
    bindsTo: SheetBindsTo.developedForParty,
  ),
  ColumnDef(
    id: 25,
    sheetId: 2,
    label: 'Quotation',
    kind: ColumnKind.money,
    position: 1,
    bindsTo: SheetBindsTo.developedForQuotation,
  ),
  ColumnDef(
    id: 26,
    sheetId: 2,
    label: 'Date',
    kind: ColumnKind.date,
    role: ColumnRole.stamp,
    position: 2,
    bindsTo: SheetBindsTo.createdDate,
  ),
  ColumnDef(
    id: 27,
    sheetId: 2,
    label: 'Time',
    kind: ColumnKind.time,
    role: ColumnRole.stamp,
    position: 3,
    bindsTo: SheetBindsTo.createdTime,
  ),
];

/// The people at the deal's company — one row each, as many as it has.
///
/// Every cell is editable and writes to the COMPANY's record of that person,
/// so all parts for that company see the same people. "Dealt with" is the one
/// column that belongs to this part: ticked rows are the people this part's
/// deal involved.
const List<ColumnDef> peopleSheetColumns = [
  ColumnDef(
    id: 30,
    sheetId: 3,
    label: 'Dealt with',
    kind: ColumnKind.check,
    position: 0,
    bindsTo: SheetBindsTo.personDealtWith,
  ),
  ColumnDef(
    id: 31,
    sheetId: 3,
    label: 'Name',
    kind: ColumnKind.text,
    position: 1,
    bindsTo: SheetBindsTo.personName,
  ),
  ColumnDef(
    id: 32,
    sheetId: 3,
    label: 'Designation',
    kind: ColumnKind.text,
    position: 2,
    bindsTo: SheetBindsTo.personDesignation,
  ),
  ColumnDef(
    id: 33,
    sheetId: 3,
    label: 'Contact No',
    kind: ColumnKind.phone,
    position: 3,
    bindsTo: SheetBindsTo.personPhone,
  ),
  ColumnDef(
    id: 34,
    sheetId: 3,
    label: 'Email ID',
    kind: ColumnKind.email,
    position: 4,
    bindsTo: SheetBindsTo.personEmail,
  ),
];
