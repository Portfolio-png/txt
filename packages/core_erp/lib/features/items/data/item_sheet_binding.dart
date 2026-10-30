import '../../../sheet/column_def.dart';
import '../../../sheet/column_option.dart';
import '../../../sheet/sheet_binding.dart';
import '../../../sheet/sheet_def.dart';
import '../../../sheet/sheet_engine.dart';
import '../../../sheet/sheet_draft.dart';
import '../../clients/domain/client_definition.dart';
import '../../clients/domain/client_inputs.dart';
import '../../clients/domain/party_contact.dart';
import '../../clients/presentation/providers/clients_provider.dart';
import '../../materials/presentation/providers/materials_provider.dart';
import '../../groups/domain/group_inputs.dart';
import '../../groups/domain/group_definition.dart';
import '../../groups/presentation/providers/groups_provider.dart';
import '../domain/developed_for.dart';
import '../domain/item_definition.dart';
import '../domain/sheet_property.dart';
import '../domain/item_inputs.dart';
import '../domain/swg_gauge_table.dart';
import '../presentation/providers/items_provider.dart';

/// Turns the item sheet's rows into real items.
///
/// Everything entity-shaped about the sheet lives here, so the engine stays
/// generic and a die sheet is a second binding rather than a second engine.
class ItemSheetBinding extends SheetBinding<ItemDefinition> {
  ItemSheetBinding({
    required this.items,
    required this.groups,
    this.clients,
    this.materials,
    required this.itemSheet,
    this.liveItemSheet,
    this.sheetProperties,
    this.partySheet,
    this.dealDraft,
    this.dealContactIds,
    this.peopleSheet,
  });

  final ItemsProvider items;
  final GroupsProvider groups;
  final ClientsProvider? clients;
  final MaterialsProvider? materials;

  /// The sheet whose rows are parts, as it was built.
  final SheetDef itemSheet;

  /// The sheet as it is NOW. A property added with the + exists only on the
  /// controller's copy, so reading [itemSheet] alone left its column out of
  /// every save and every picker.
  final SheetDef Function()? liveItemSheet;

  SheetDef get _sheet => liveItemSheet?.call() ?? itemSheet;

  /// The sheet's saved property columns (061), read live: a column's own
  /// option list comes first in its dropdown, ahead of values parts carry.
  final List<SheetProperty> Function()? sheetProperties;

  /// The development deal, which is one record for the whole screen rather
  /// than one per part — so it arrives as a sheet plus its single row.
  final SheetDef? partySheet;

  /// The deal row, read LIVE at each save rather than handed over once: the
  /// binding is built before anyone has typed into it. Null — or answering
  /// null — means the part says nothing about who it was developed for.
  final SheetDraft? Function()? dealDraft;

  /// The people ticked on the deal. Answering null says nothing (the server
  /// keeps what is ticked) — which is what the host must answer until the
  /// people table has actually loaded for the chosen company, or a save would
  /// clear ticks it never showed.
  final List<int>? Function()? dealContactIds;

  /// The people table: one row per person at the deal's company.
  final SheetDef? peopleSheet;

  String? _lastError;

  @override
  String? get lastError => _lastError;

  @override
  Future<List<ItemDefinition>?> save(List<SheetDraft> rows) async {
    _lastError = null;
    final saved = <ItemDefinition>[];

    for (final row in rows) {
      if (_isBlank(row)) continue;
      final result = await saveRow(row);
      // Stop at the first refusal, but hand back what DID land. Returning null
      // here is what left rows on the server that the sheet believed were
      // unsaved; the caller needs them to mark those rows committed.
      if (result == null) {
        return saved.isEmpty ? null : saved;
      }
      saved.add(result);
    }

    if (saved.isEmpty) {
      _lastError = 'There is nothing filled in to save.';
      return null;
    }
    return saved;
  }

  @override
  Future<ItemDefinition?> saveRow(SheetDraft row) async {
    _lastError = null;
    if (_isBlank(row)) {
      _lastError = 'There is nothing filled in on this row.';
      return null;
    }

    final groupId = await _resolveGroupId(row);
    if (groupId == null) {
      // Keep the server's reason when there is one. This sentence used to
      // replace it, so "unitId is required" reached the user as a shrug.
      _lastError ??= 'Could not file this part under a group.';
      return null;
    }

    final name = _text(row, SheetBindsTo.name);
    if (name.isEmpty) {
      _lastError = 'A part needs a name.';
      return null;
    }

    final identity = _partIdentity(row);
    final existing = row.entityId == null ? null : _liveItem(row.entityId!);
    if (row.entityId != null && existing == null) {
      _lastError =
          'That part is no longer in the catalogue, so the edit '
          'cannot be saved. Reload the sheet.';
      return null;
    }

    // A part keeps its own unit unless it moves group. The sheet has no unit
    // column, so taking the group's on every edit reset a part whose unit had
    // been set apart from its group's.
    final unitId = existing != null && existing.groupId == groupId
        ? existing.unitId
        : _unitFor(groupId);
    if (unitId == null) {
      _lastError =
          'This group has no unit, so a part cannot be saved under it.';
      return null;
    }

    final result = existing == null
        ? await items.createItem(
            CreateItemInput(
              name: name,
              displayName: name,
              groupId: groupId,
              unitId: unitId,
              variationTree: _variationTree(row),
              developedFor: _developedFor(),
              // Both keys or neither: the server auto-stamps a part code only
              // when NEITHER arrives, so sending one turns the stamp off and
              // leaves the part half-named. `CreateItemInput` has no
              // `partIdentitySpecified`.
              partNo: identity?.$1,
              partCode: identity?.$2,
            ),
          )
        : await items.updateItem(
            _updateFor(
              existing: existing,
              name: name,
              groupId: groupId,
              unitId: unitId,
              row: row,
              identity: identity,
            ),
          );

    if (result == null) {
      // `ItemsProvider._save` answers null with NO error set when a save is
      // already in flight. Saying "failed" there would be a guess, and saying
      // "saved" would be a lie.
      _lastError =
          items.errorMessage ??
          'That save did not run — another one was still finishing.';
      return null;
    }
    return result;
  }

  /// A saved variation tree back into inputs, whole.
  ///
  /// `ItemsProvider` has a private converter of its own that drops
  /// `inputType`, `nameJoin`, both numeric bounds and `materialTypeId`, so a
  /// tree round-tripped through it comes back with every Gauge and Material
  /// property reset to 'Text'. This one carries all of them.
  static List<ItemVariationNodeInput> _treeToInputs(
    List<ItemVariationNodeDefinition> nodes,
  ) => [
    for (final node in nodes)
      ItemVariationNodeInput(
        id: node.id,
        parentNodeId: node.parentNodeId,
        kind: node.kind,
        name: node.name,
        code: node.code,
        displayName: node.displayName,
        inputType: node.inputType,
        nameJoin: node.nameJoin,
        numericMin: node.numericMin,
        numericMax: node.numericMax,
        materialTypeId: node.materialTypeId,
        children: _treeToInputs(node.children),
      ),
  ];

  /// The stored tree with the sheet's values written into it.
  ///
  /// The sheet sees one value per property it has a column for. Replacing the
  /// whole tree with that dropped every other property (a Finish set in the
  /// item editor), every second value of a property, and every node id —
  /// orphaning whatever pointed at them. So only the first value of a
  /// property the sheet shows is touched; everything else goes back as it was.
  List<ItemVariationNodeInput> _mergeTree(
    List<ItemVariationNodeDefinition> stored,
    List<ItemVariationNodeInput> fromSheet,
  ) {
    final shown = <String>{
      for (final column in _sheet.columns)
        if (SheetBindsTo.isVariation(column.bindsTo))
          _normalize(SheetBindsTo.variationProperty(column.bindsTo!)),
    };
    final typed = <String, ItemVariationNodeInput>{
      for (final node in fromSheet) _normalize(node.name): node,
    };

    final out = <ItemVariationNodeInput>[];
    final placed = <String>{};
    for (final node in stored) {
      final key = _normalize(node.name);
      final isShownProperty =
          node.kind == ItemVariationNodeKind.property && shown.contains(key);
      if (!isShownProperty || placed.contains(key)) {
        out.addAll(_treeToInputs([node]));
        continue;
      }
      placed.add(key);
      final incoming = typed[key];
      // Shown, and the cell is blank: the value was cleared on the sheet.
      if (incoming == null) continue;

      final value = incoming.children.isEmpty ? null : incoming.children.first;
      final kept = _treeToInputs(node.children);
      final alreadyThere =
          value != null &&
          node.children.any(
            (child) => _normalize(child.name) == _normalize(value.name),
          );
      List<ItemVariationNodeInput> children;
      if (value == null || alreadyThere) {
        children = kept;
      } else if (kept.isEmpty) {
        children = [value];
      } else {
        // The first value is the one the cell showed, so it is the one that
        // was changed. Its id is kept so references to it survive the edit.
        final first = kept.first;
        children = [
          ItemVariationNodeInput(
            id: first.id,
            parentNodeId: first.parentNodeId,
            kind: first.kind,
            name: value.name,
            code: first.code,
            displayName: value.displayName,
            inputType: first.inputType,
            nameJoin: first.nameJoin,
            numericMin: first.numericMin,
            numericMax: first.numericMax,
            materialTypeId: value.materialTypeId,
            children: first.children,
          ),
          ...kept.skip(1),
        ];
      }
      out.add(
        ItemVariationNodeInput(
          id: node.id,
          parentNodeId: node.parentNodeId,
          kind: node.kind,
          name: node.name,
          code: node.code,
          displayName: node.displayName,
          inputType: node.inputType,
          nameJoin: node.nameJoin,
          numericMin: node.numericMin,
          numericMax: node.numericMax,
          materialTypeId: node.materialTypeId,
          children: children,
        ),
      );
    }
    // Properties the part did not have before.
    for (final node in fromSheet) {
      if (!placed.contains(_normalize(node.name))) out.add(node);
    }
    return out;
  }

  @override
  ItemDefinition? entityById(int id) => _liveItem(id);

  @override
  SheetDraft? draftForId(int id) {
    final item = _liveItem(id);
    return item == null ? null : toDrafts([item]).firstOrNull;
  }

  ItemDefinition? _liveItem(int id) {
    for (final item in items.items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// An update that changes only what the sheet owns.
  ///
  /// `UpdateItemInput` is a **full replace** — every field it does not carry
  /// takes its default, so an update built from the sheet alone would wipe the
  /// part's photo, CAD file, attachments, pipeline, linked dies and machines
  /// and its blank size. The sheet owns the name, the group, the part
  /// identity, the variation tree and the development deal; everything else is
  /// read off the live record and handed straight back.
  ///
  /// `partIdentitySpecified` exists on update and not on create. It must be
  /// true only when both keys are being sent, otherwise a typed code would be
  /// silently dropped — and false when neither is, so the server keeps the
  /// stamp it already made rather than clearing it.
  UpdateItemInput _updateFor({
    required ItemDefinition existing,
    required String name,
    required int groupId,
    required int unitId,
    required SheetDraft row,
    required (int?, String?)? identity,
  }) {
    final tree = _variationTree(row);
    final deal = _developedFor(existing: existing);
    // A display name set apart from the name is not the sheet's to overwrite;
    // one that merely mirrored the name follows a rename.
    final displayName =
        existing.displayName.trim().isEmpty ||
            existing.displayName.trim() == existing.name.trim()
        ? name
        : existing.displayName;
    return UpdateItemInput(
      id: existing.id,
      name: name,
      alias: existing.alias,
      displayName: displayName,
      groupId: groupId,
      unitId: unitId,
      unitConversions: [
        for (final c in existing.unitConversions)
          ItemUnitConversionInput(
            unitId: c.unitId,
            factorToPrimary: c.factorToPrimary,
          ),
      ],
      namingFormat: existing.namingFormat,
      // An empty tree means the sheet's recipe columns were all blank, which
      // is not the same as "this part has no variations" — keep what is there.
      variationTree: tree.isEmpty
          ? _treeToInputs(existing.variationTree)
          : _mergeTree(existing.variationTree, tree),
      defaultPipelineId: existing.defaultPipelineId,
      baseItemId: existing.baseItemId,
      photoUrl: existing.photoUrl,
      cadFileKey: existing.cadFileKey,
      cadFileName: existing.cadFileName,
      attachments: [
        for (final a in existing.attachments)
          ItemAttachmentInput(
            label: a.label,
            objectKey: a.objectKey,
            fileName: a.fileName,
          ),
      ],
      availableForPurchase: existing.availableForPurchase,
      penPaperBaseline: existing.penPaperBaseline,
      blankWidthMm: existing.blankWidthMm,
      blankHeightMm: existing.blankHeightMm,
      partNo: identity?.$1,
      partCode: identity?.$2,
      partIdentitySpecified: identity != null,
      developedFor: deal ?? existing.developedFor,
      // A full replace drops anything it does not carry, and these three are
      // not the sheet's to drop: a part's linked machines and dies live on the
      // die and machine sheets, and the client id is resolved from the deal.
      machineIds: [for (final m in existing.machines) m.id],
      dieIds: [for (final d in existing.dies) d.id],
      developedForClientId: existing.developedForClientId,
    );
  }

  /// Real options, parties and uniqueness sets, from the providers.
  ///
  /// The prototype passed literals here: 25 hardcoded options, four parties,
  /// four contacts, and `counters: {'Switch Action › Dolly › Patti': 47}`.
  @override
  Future<SheetReferenceData> referenceData() async {
    final live = items.items.where((item) => !item.isArchived).toList();

    return SheetReferenceData(
      options: _options(live),
      parties: _parties(),
      contacts: _contacts(),
      counters: _counters(live),
      existingCodes: {
        for (final item in live)
          if (item.partCode.trim().isNotEmpty) item.partCode.trim(),
      },
      // Lower-cased: the engine looks a path up lower-cased, so a stored
      // "Dolly › Patti" never matched and the duplicate check never fired.
      existingPaths: {
        for (final item in live)
          '${_pathOf(item.groupId)} › ${item.name}'.toLowerCase(),
      },
    );
  }

  /// One option per real record, keyed to the column that offers it.
  List<ColumnOption> _options(List<ItemDefinition> live) {
    final out = <ColumnOption>[];

    for (final column in _sheet.columns) {
      switch (column.bindsTo) {
        case SheetBindsTo.group:
          // A Group is a group a part's Type can sit in: every top-level group
          // (Primary Group, Raw Materials…), and any group that has sub-groups
          // of its own. A Type is a sub-group — "Type" is the shop's word for
          // one — so das under Primary Group is offered as Primary Group's Type,
          // not as a Group of its own.
          final parents = {
            for (final group in groups.filableItemGroups)
              if (group.parentGroupId != null && !group.isArchived) group.parentGroupId,
          };
          for (final group in groups.filableItemGroups) {
            if (group.isArchived) continue;
            if (group.parentGroupId != null && !parents.contains(group.id)) continue;
            out.add(
              ColumnOption(
                id: group.id,
                columnId: column.id,
                label: group.name,
              ),
            );
          }
        case SheetBindsTo.set:
          // Cascaded: a Type belongs under the Group picked beside it, which is
          // what `parentOptionId` drives.
          for (final group in groups.filableItemGroups) {
            if (group.parentGroupId == null || group.isArchived) continue;
            out.add(
              ColumnOption(
                id: group.id,
                columnId: column.id,
                parentOptionId: group.parentGroupId,
                label: group.name,
              ),
            );
          }
        case SheetBindsTo.name:
          // One per PART, scoped to its group: picking one loads that very
          // part into the row. A name can repeat — in another group, set or
          // unit — so they are told apart by code rather than folded into one
          // option that could only ever load the first of them.
          for (final item in live) {
            final code = item.partCode.trim();
            out.add(
              ColumnOption(
                id: item.id,
                columnId: column.id,
                parentOptionId: item.groupId,
                label: item.name,
                detail: code.isEmpty ? 'Part #${item.id}' : code,
              ),
            );
          }
        default:
          if (SheetBindsTo.isVariation(column.bindsTo)) {
            out.addAll(_variationOptions(column, live));
          }
      }
    }
    return out;
  }

  /// What a recipe column offers.
  ///
  /// A Gauge column offers the SWG table — the house rule being that the table
  /// fills the field when a gauge is picked, while a typed value stays verbatim.
  /// A Material column offers the materials master. Anything else offers the
  /// values parts already carry, so the vocabulary grows from use.
  List<ColumnOption> _variationOptions(
    ColumnDef column,
    List<ItemDefinition> live,
  ) {
    if (column.kind == ColumnKind.gauge) {
      return [
        for (final entry in swgGaugeTable)
          ColumnOption(
            id: 90000 + entry.gauge,
            columnId: column.id,
            label: '${entry.gauge} Gauge',
          ),
      ];
    }

    if (column.kind == ColumnKind.material) {
      final list = materials?.materials ?? const [];
      return [
        for (final material in list)
          ColumnOption(
            id: 91000 + (material.id),
            columnId: column.id,
            label: material.name,
          ),
      ];
    }

    final property = SheetBindsTo.variationProperty(column.bindsTo!);
    final seen = <String>{};
    final out = <ColumnOption>[];
    // The column's own list first, in the order it was given. Its own id
    // band, so a value parts carry (92000s) never takes one of these ids.
    final stored = sheetProperties?.call() ?? const <SheetProperty>[];
    final wanted = _normalize(property);
    final own = stored.where((p) => p.key == wanted).firstOrNull;
    for (final label in own?.options ?? const <String>[]) {
      if (!seen.add(_normalize(label))) continue;
      out.add(ColumnOption(
        id: 93000000 + column.id * 1000 + out.length,
        columnId: column.id,
        label: label,
      ));
    }
    for (final item in live) {
      final value = _valueOfProperty(item, property);
      if (value == null || !seen.add(_normalize(value))) continue;
      out.add(
        ColumnOption(id: 92000 + out.length, columnId: column.id, label: value),
      );
    }
    return out;
  }

  /// Every active company. Not `filteredClients`: that carries the Clients
  /// SCREEN's search box and status filter, so searching "acme" there left
  /// only Acme in this dropdown.
  List<Party> _parties() => [
    for (final client in clients?.clients ?? const [])
      if (!client.isArchived)
        Party(
          id: client.id,
          name: client.name,
          type: 'client',
          gstin: client.gstNumber,
        ),
  ];

  @override
  Future<Party?> addParty(String name) async {
    _lastError = null;
    final provider = clients;
    if (provider == null) {
      _lastError = 'Companies cannot be added from here.';
      return null;
    }
    final made = await provider.createClient(
      CreateClientInput(name: name.trim()),
    );
    if (made == null) {
      _lastError = provider.errorMessage ?? 'Could not add that company.';
      return null;
    }
    return Party(
      id: made.id,
      name: made.name,
      type: 'client',
      gstin: made.gstNumber,
    );
  }

  /// Everyone at every client, archived people left out — what a contact
  /// picker offers. Each person is their own record (migration 056).
  List<Contact> _contacts() => [
    for (final client in clients?.clients ?? const [])
      if (!client.isArchived)
        for (final person in client.activeContacts)
          if (person.id != null)
            Contact(
              id: person.id!,
              partyId: client.id,
              name: person.name,
              designation: person.designation,
              phone: person.phone,
              email: person.email,
            ),
  ];

  // --- the people at the deal's company -------------------------------------

  ClientDefinition? _client(int partyId) {
    for (final client in clients?.clients ?? const []) {
      if (client.id == partyId) return client;
    }
    return null;
  }

  @override
  bool knowsParty(int partyId) => _client(partyId) != null;

  @override
  List<SheetDraft> peopleRows(int partyId, {Set<int> ticked = const {}}) {
    final sheet = peopleSheet;
    final client = _client(partyId);
    if (sheet == null || client == null) return const [];

    // Archived people stay listed only where this part ticked them: they are
    // part of what this deal records, but nobody should be offered them anew.
    final people = [
      for (final person in client.contacts)
        if (!person.isArchived || ticked.contains(person.id)) person,
    ];
    return [for (final person in people) _personDraft(sheet, person, ticked)];
  }

  SheetDraft _personDraft(
    SheetDef sheet,
    PartyContact person,
    Set<int> ticked,
  ) {
    final draft = SheetDraft(sheetKey: sheet.key, entityId: person.id);
    void put(String binds, CellValue Function(int columnId) value) {
      final column = sheet.columnBoundTo(binds);
      if (column != null) draft.set(column.id, value(column.id));
    }

    if (ticked.contains(person.id)) {
      put(
        SheetBindsTo.personDealtWith,
        (id) => CellValue(columnId: id, intValue: 1),
      );
    }
    put(
      SheetBindsTo.personName,
      (id) => CellValue(columnId: id, textValue: person.name),
    );
    put(
      SheetBindsTo.personDesignation,
      (id) => CellValue(columnId: id, textValue: person.designation),
    );
    put(
      SheetBindsTo.personPhone,
      (id) => CellValue(columnId: id, textValue: person.phone),
    );
    put(
      SheetBindsTo.personEmail,
      (id) => CellValue(columnId: id, textValue: person.email),
    );
    // Loaded, not typed: nothing to write until someone changes it.
    draft.markClean();
    return draft;
  }

  @override
  Future<int?> savePerson(int partyId, SheetDraft row) async {
    _lastError = null;
    final sheet = peopleSheet;
    final provider = clients;
    if (sheet == null || provider == null) {
      _lastError = 'This sheet cannot save people.';
      return null;
    }

    String text(String binds) {
      final column = sheet.columnBoundTo(binds);
      final value = column == null ? null : row.get(column.id);
      return (value?.textValue ?? value?.optionLabel ?? '').trim();
    }

    final person = PartyContact(
      id: row.entityId,
      partyId: partyId,
      name: text(SheetBindsTo.personName),
      designation: text(SheetBindsTo.personDesignation),
      phone: text(SheetBindsTo.personPhone),
      email: text(SheetBindsTo.personEmail),
    );
    if (person.name.isEmpty) {
      _lastError = 'Every person needs a name.';
      return null;
    }

    // A row whose only change is the tick is not a change to the person, and
    // the PATCH would be traffic with nothing in it.
    if (person.id != null) {
      final stored = _client(
        partyId,
      )?.contacts.where((c) => c.id == person.id).firstOrNull;
      if (stored != null &&
          stored.name == person.name &&
          stored.designation == person.designation &&
          stored.phone == person.phone &&
          stored.email == person.email) {
        return person.id;
      }
    }

    final saved = person.id == null
        ? await provider.addContact(partyId, person, refreshAfter: false)
        : await provider.updateContact(partyId, person, refreshAfter: false);
    if (saved == null) {
      _lastError = provider.errorMessage ?? 'That person did not save.';
      return null;
    }
    return saved.id;
  }

  @override
  Future<void> peopleSaved() async {
    await clients?.refresh();
  }

  @override
  ({SheetDraft deal, Set<int> ticked})? dealOf(ItemDefinition entity) {
    final sheet = partySheet;
    final block = entity.developedFor;
    if (sheet == null) return null;
    if (block.kind != DevelopedForKind.client &&
        block.kind != DevelopedForKind.contractor) {
      return null;
    }

    final draft = SheetDraft(sheetKey: sheet.key);
    final party = sheet.columnBoundTo(SheetBindsTo.developedForParty);
    if (party != null && block.clientId != null) {
      draft.set(
        party.id,
        CellValue(
          columnId: party.id,
          refId: block.clientId,
          optionLabel: block.companyName.isNotEmpty
              ? block.companyName
              : block.clientName,
        ),
      );
    }
    final quotation = sheet.columnBoundTo(SheetBindsTo.developedForQuotation);
    final amount = block.quotationAmount;
    if (quotation != null && amount != null) {
      // As stored, paise included. Rounding here wrote the rounded figure
      // back on the next save of any part on the sheet.
      final whole = amount == amount.truncateToDouble();
      draft.set(
        quotation.id,
        CellValue(
          columnId: quotation.id,
          intValue: whole ? amount.toInt() : null,
          textValue: whole ? '${amount.toInt()}' : amount.toString(),
        ),
      );
    }
    draft.markClean();
    return (deal: draft, ticked: {...?block.contactIds});
  }

  /// The last running number used under each group path.
  ///
  /// Derived from the parts that exist rather than asked for per scope:
  /// `nextPartIdentity` is one request per (group, set) and the sheet needs
  /// every scope at once to validate a typed number.
  Map<String, int> _counters(List<ItemDefinition> live) {
    final out = <String, int>{};
    for (final item in live) {
      final no = item.partNo;
      if (no == null) continue;
      final scope = '${_pathOf(item.groupId)} › ${item.name}';
      final current = out[scope] ?? 0;
      if (no > current) out[scope] = no;
    }
    return out;
  }

  /// "Switch Action › Dolly" for a group, walking up one level.
  String _pathOf(int groupId) {
    final group = groups.findById(groupId);
    if (group == null) return '';
    // The path as the SHEET writes it, Group › Type.
    if (group.parentGroupId == null) return group.name;
    final parent = groups.findById(group.parentGroupId);
    return parent == null ? group.name : '${parent.name} › ${group.name}';
  }

  @override
  List<SheetDraft> toDrafts(List<ItemDefinition> entities) {
    return [for (final item in entities) _draftOf(item)];
  }

  // --- identity -------------------------------------------------------------

  /// `(partNo, partCode)` when BOTH are filled, else null so the server stamps.
  (int?, String?)? _partIdentity(SheetDraft row) {
    // Only what the user TYPED. The sheet derives a running number and a code
    // into these cells as soon as a group is picked, and sending that
    // suppressed the server's stamp on every row — handing it a guess instead.
    //
    // The guess is also wrong in a way that only shows up in bulk. `derive`
    // scopes the running number by the path INCLUDING the part name, while the
    // server counts `MAX(part_no)` over (group, set). So every new name under
    // one group derives 1, and two names sharing initials derive the identical
    // code: "Patti" and "Plate" under Primary Group both come out PGP1. The
    // first saves, the rest are refused by the unique index.
    //
    // The sequence rule belongs to `backend/modules/items/part-identity.js`,
    // which is the one place that can count authoritatively. An auto cell is a
    // preview; only an edited one is a commitment.
    final noCell = _cell(row, SheetBindsTo.partNo);
    final codeCell = _cell(row, SheetBindsTo.partCode);
    final typed =
        noCell?.mode == ValueMode.edit || codeCell?.mode == ValueMode.edit;
    if (!typed) return null;

    final no = noCell?.intValue;
    final code = (codeCell?.textValue ?? '').trim();
    if (no == null || code.isEmpty) return null;
    return (no, code);
  }

  /// The group this row's part belongs to: the Type when there is one, else the
  /// Group. Both are rows in one hierarchy — Type's `parentGroupId` is Group's
  /// `id` — so a part files under the deepest one named.
  Future<int?> _resolveGroupId(SheetDraft row) async {
    final groupName = _label(row, SheetBindsTo.group);
    if (groupName.isEmpty) return null;

    final parent = await _ensureGroup(name: groupName, parentGroupId: null);
    if (parent == null) return null;

    final typeName = _label(row, SheetBindsTo.set);
    if (typeName.isEmpty) return parent.id;

    final child = await _ensureGroup(name: typeName, parentGroupId: parent.id);
    // Null, not the parent: filing the part under its Group when its Type
    // could not be made is a save that reports success in the wrong place.
    return child?.id;
  }

  /// Finds a group by name among its siblings, creating it if missing.
  ///
  /// Scoped by `parentGroupId` because group names are unique only among
  /// siblings — two parents may each have a "Dolly". `GroupsProvider` has no
  /// name lookup and no create-if-missing, so this is it.
  Future<GroupDefinition?> _ensureGroup({
    required String name,
    required int? parentGroupId,
  }) async {
    final wanted = _normalize(name);
    // The server files a new top-level group under "Primary Group", so a
    // group typed here last time lives there now. Looking only at
    // parentless groups missed it, and the second save collided with it.
    final primary = _primaryGroup();
    bool sameLevel(GroupDefinition group) => parentGroupId == null
        ? group.parentGroupId == null ||
              (primary != null && group.parentGroupId == primary.id)
        : group.parentGroupId == parentGroupId;
    for (final group in groups.filableItemGroups) {
      if (sameLevel(group) && _normalize(group.name) == wanted) {
        return group;
      }
    }
    final created = await groups.createGroup(
      CreateGroupInput(
        name: name.trim(),
        groupType: 'item',
        parentGroupId: parentGroupId,
        // The server refuses an item group with no unit, and the sheet has no
        // unit column — without this no group typed here could ever be made.
        unitId: _unitForNewGroup(parentGroupId),
        description: 'Created from the item sheet',
      ),
    );
    if (created == null) {
      _lastError = groups.errorMessage ?? 'Could not create the group "$name".';
    }
    return created;
  }

  GroupDefinition? _primaryGroup() {
    for (final group in groups.filableItemGroups) {
      if (group.parentGroupId == null &&
          _normalize(group.name) == 'primary group') {
        return group;
      }
    }
    return null;
  }

  /// The unit a group typed on the sheet is created with: its parent's for a
  /// Type, else Primary Group's (where the server files a new top-level group
  /// anyway), else the unit most item groups use. Null only on a system with
  /// no unit anywhere, in which case the server's refusal is shown as is.
  int? _unitForNewGroup(int? parentGroupId) {
    if (parentGroupId != null) {
      final inherited = _unitFor(parentGroupId);
      if (inherited != null) return inherited;
    }
    final primary = _primaryGroup()?.unitId;
    if (primary != null) return primary;
    final counts = <int, int>{};
    for (final group in groups.filableItemGroups) {
      final unit = group.unitId;
      if (unit != null) counts[unit] = (counts[unit] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  /// A group's unit, or its parent's. The sheet has no unit column, and an item
  /// write is refused without one.
  int? _unitFor(int groupId) {
    final group = groups.findById(groupId);
    if (group == null) return null;
    if (group.unitId != null) return group.unitId;
    final parent = groups.findById(group.parentGroupId);
    return parent?.unitId;
  }

  // --- the recipe -----------------------------------------------------------

  /// One top-level property per variation column, each holding its value.
  ///
  /// The column's kind becomes the property's `inputType`, which is why the
  /// sheet gained `gauge` and `material` rather than forcing either into being
  /// a quantity.
  ///
  /// **Every property carries its value as a child node, Gauge included.**
  /// Gauge and Numeric used to be sent with no children, on the stated grounds
  /// that "the value lives on the property itself". It does not: the server
  /// blanks `displayName` on a property (`sanitizeNodes`), so a childless
  /// property reads back as its own NAME — a saved part showed the word
  /// "Thickness" in its Thickness cell and the typed gauge was gone. It also
  /// put the value out of reach of the part code, which is built from the
  /// property values.
  List<ItemVariationNodeInput> _variationTree(SheetDraft row) {
    final out = <ItemVariationNodeInput>[];
    for (final column in _sheet.columns) {
      if (!SheetBindsTo.isVariation(column.bindsTo)) continue;
      final value = _label(row, column.bindsTo!);
      if (value.isEmpty) continue;

      final inputType = _inputTypeFor(column.kind);
      final property = SheetBindsTo.variationProperty(column.bindsTo!);
      out.add(
        ItemVariationNodeInput(
          kind: ItemVariationNodeKind.property,
          name: property,
          displayName: property,
          inputType: inputType,
          children: [
            ItemVariationNodeInput(
              kind: ItemVariationNodeKind.value,
              name: value,
              displayName: value,
              materialTypeId: column.kind == ColumnKind.material
                  ? _materialIdFor(value)
                  : null,
            ),
          ],
        ),
      );
    }
    return out;
  }

  /// The materials-master row a chosen Alloy names, or null.
  ///
  /// Without this the saved value node had `material_type_id = NULL` and the
  /// items screen's variation panel rendered it as "material missing" — the
  /// cell looked right and pointed at nothing.
  ///
  /// Matched on the name rather than by decoding the `91000 + id` option band,
  /// because `material_types.name` is `UNIQUE COLLATE NOCASE` so the name IS a
  /// key, and matching on it also catches a value that was typed rather than
  /// picked. A name no material answers to stays null, which is correct — the
  /// master is the authority on what is a material.
  int? _materialIdFor(String value) => materials?.byName(value)?.id;

  static String _inputTypeFor(ColumnKind kind) => switch (kind) {
    ColumnKind.gauge => 'Gauge',
    ColumnKind.material => 'Material',
    ColumnKind.number => 'Numeric',
    _ => 'Text',
  };

  // --- the development deal -------------------------------------------------

  /// Only the writable half.
  ///
  /// `companyName`, `contactName`, `designation`, `phone` and `email` are
  /// resolved server-side on every read, so writing them is a no-op. The sheet
  /// shows them as projections of the chosen party, which is what the party
  /// columns bound to them are for.
  ///
  /// Built over the part's stored deal, not from nothing: the sheet has no
  /// cost column and no contractor, so a block made from the cells alone
  /// cleared the cost, turned a contractor deal into a client one, and moved
  /// the deal date to whenever any field on the part was last edited.
  DevelopedFor? _developedFor({ItemDefinition? existing}) {
    final sheet = partySheet;
    final draft = dealDraft?.call();
    if (sheet == null || draft == null) return null;

    int? clientId;
    double? quotation;
    double? cost;
    for (final column in sheet.columns) {
      final value = draft.get(column.id);
      if (value == null) continue;
      switch (column.bindsTo) {
        case SheetBindsTo.developedForParty:
          clientId = value.refId;
        case SheetBindsTo.developedForQuotation:
          quotation = _money(value.textValue, value.intValue);
        case SheetBindsTo.developedForCost:
          cost = _money(value.textValue, value.intValue);
      }
    }
    if (clientId == null && quotation == null && cost == null) return null;

    final prior = existing?.developedFor;
    final contractor =
        prior != null &&
        prior.kind == DevelopedForKind.contractor &&
        clientId != null &&
        prior.clientId == clientId;
    final kind = contractor
        ? DevelopedForKind.contractor
        : clientId == null
        ? DevelopedForKind.self
        : DevelopedForKind.client;
    final hasCostColumn =
        sheet.columnBoundTo(SheetBindsTo.developedForCost) != null;
    final unchanged =
        prior != null &&
        prior.kind == kind &&
        prior.clientId == clientId &&
        prior.quotationAmount == quotation;

    return DevelopedFor(
      kind: kind,
      clientId: clientId,
      subContractorId: contractor ? prior.subContractorId : null,
      // Only a client's people can be ticked; self has nobody to speak to,
      // and a sub-contractor is the person.
      contactIds: kind == DevelopedForKind.client
          ? dealContactIds?.call()
          : const [],
      at: unchanged && prior.at != null ? prior.at : DateTime.now(),
      quotationAmount: quotation,
      costAmount: hasCostColumn ? cost : prior?.costAmount,
    );
  }

  static double? _money(String? text, int? intValue) =>
      SheetEngine.parseMoney(text) ?? intValue?.toDouble();

  // --- reading back ---------------------------------------------------------

  SheetDraft _draftOf(ItemDefinition item) {
    final draft = SheetDraft(sheetKey: _sheet.key, entityId: item.id);
    for (final column in _sheet.columns) {
      final binds = column.bindsTo;
      if (binds == null) continue;

      if (binds == SheetBindsTo.name) {
        // The option id is what the cells below look their choices up by;
        // a label alone left a loaded row unable to validate its own name.
        draft.set(
          column.id,
          CellValue(
            columnId: column.id,
            optionId: item.id,
            textValue: item.name,
          ),
        );
      } else if (binds == SheetBindsTo.partNo) {
        draft.set(
          column.id,
          CellValue(
            columnId: column.id,
            intValue: item.partNo,
            textValue: item.partNo?.toString(),
            // The stored stamp, not a preview — so derive leaves it alone and
            // re-saving does not offer the server a different one.
            mode: ValueMode.ok,
          ),
        );
      } else if (binds == SheetBindsTo.partCode) {
        draft.set(
          column.id,
          CellValue(
            columnId: column.id,
            textValue: item.partCode,
            mode: ValueMode.ok,
          ),
        );
      } else if (binds == SheetBindsTo.group) {
        final group = groups.findById(item.groupId);
        // A part filed under a Type (a sub-group) shows the Type's parent here
        // and the Type beside it: Primary Group › das. Under a top-level group
        // it shows that group and no Type. Treating everything under Primary
        // Group as top level read Primary Group › das back as Group "das",
        // Type "—".
        final top = group == null || group.parentGroupId == null
            ? group
            : groups.findById(group.parentGroupId);
        draft.set(
          column.id,
          CellValue(
            columnId: column.id,
            optionId: top?.id,
            optionLabel: top?.name,
          ),
        );
      } else if (binds == SheetBindsTo.set) {
        final group = groups.findById(item.groupId);
        final isType = group != null && group.parentGroupId != null;
        draft.set(
          column.id,
          CellValue(
            columnId: column.id,
            optionId: isType ? group.id : null,
            optionLabel: isType ? group.name : null,
          ),
        );
      } else if (SheetBindsTo.isVariation(binds)) {
        final property = SheetBindsTo.variationProperty(binds);
        draft.set(
          column.id,
          CellValue(
            columnId: column.id,
            optionLabel: _valueOfProperty(item, property),
          ),
        );
      } else if (binds == SheetBindsTo.createdDate) {
        draft.set(
          column.id,
          CellValue(columnId: column.id, textValue: _dateOf(item.createdAt)),
        );
      } else if (binds == SheetBindsTo.createdTime) {
        draft.set(
          column.id,
          CellValue(columnId: column.id, textValue: _timeOf(item.createdAt)),
        );
      }
    }
    return draft;
  }

  /// The value [item] carries for the top-level property [property], or
  /// null — how the sheet tells whether a list option is still in use.
  static String? propertyValueOf(ItemDefinition item, String property) =>
      _valueOfProperty(item, property);

  static String? _valueOfProperty(ItemDefinition item, String property) {
    final wanted = _normalize(property);
    for (final node in item.topLevelProperties) {
      if (_normalize(node.name) != wanted) continue;
      if (node.children.isEmpty) {
        return node.displayName.trim().isEmpty ? node.name : node.displayName;
      }
      final value = node.children.first;
      return value.displayName.trim().isEmpty ? value.name : value.displayName;
    }
    return null;
  }

  static String _dateOf(DateTime at) {
    final local = at.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    // Two-digit year, the shape a just-saved row is stamped with
    // (ItemMasterController._stampsOf). Four here made every saved row differ
    // from its own reload, so it was replaced on each provider notification.
    final y = (local.year % 100).toString().padLeft(2, '0');
    return '$d/$m/$y';
  }

  static String _timeOf(DateTime at) {
    final local = at.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  // --- cell access ----------------------------------------------------------

  CellValue? _cell(SheetDraft row, String binds) {
    for (final column in _sheet.columns) {
      if (column.bindsTo == binds) return row.get(column.id);
    }
    return null;
  }

  String _text(SheetDraft row, String binds) {
    final value = _cell(row, binds);
    return (value?.textValue ?? value?.optionLabel ?? '').trim();
  }

  String _label(SheetDraft row, String binds) {
    final value = _cell(row, binds);
    return (value?.optionLabel ?? value?.textValue ?? '').trim();
  }

  /// A row nobody has touched is skipped rather than refused — a sheet opens
  /// with blank rows and saving should not complain about them.
  bool _isBlank(SheetDraft row) =>
      row.values.values.every((value) => value.isEmpty);

  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
}
