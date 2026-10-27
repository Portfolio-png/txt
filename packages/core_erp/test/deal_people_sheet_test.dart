import 'package:core_erp/features/clients/data/repositories/client_repository.dart';
import 'package:core_erp/features/clients/domain/client_definition.dart';
import 'package:core_erp/features/clients/domain/client_inputs.dart';
import 'package:core_erp/features/clients/domain/party_contact.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/groups/data/repositories/group_repository.dart';
import 'package:core_erp/features/groups/domain/group_definition.dart';
import 'package:core_erp/features/groups/presentation/providers/groups_provider.dart';
import 'package:core_erp/features/items/data/item_sheet_binding.dart';
import 'package:core_erp/features/items/data/repositories/item_repository.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/domain/item_definition.dart';
import 'package:core_erp/features/items/domain/item_inputs.dart';
import 'package:core_erp/features/items/presentation/widgets/deal_people_form.dart';
import 'package:flutter/material.dart';
import 'package:core_erp/features/items/presentation/providers/items_provider.dart';
import 'package:core_erp/sheet/sheet.dart';
import 'package:flutter_test/flutter_test.dart';

// A company has many people, and a part's deal ticks which of them it was
// done with (migration 056). The quotation stays one figure per part.
//
// The sheet splits the deal (one row) from the people (one row each). People
// save to the COMPANY before the part, so a tick on somebody typed a moment ago
// has an id to send; and a people table that has not loaded must say nothing
// about ticks rather than clear the ones the part already has.

class _FakeGroupRepository implements GroupRepository {
  _FakeGroupRepository(this.groups);
  final List<GroupDefinition> groups;

  @override
  Future<void> init() async {}

  @override
  Future<List<GroupDefinition>> getGroups({bool withCovers = false}) async =>
      List.of(groups);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeItemRepository implements ItemRepository {
  final List<ItemDefinition> stored = [];
  final List<CreateItemInput> created = [];
  final List<UpdateItemInput> updated = [];
  int _nextId = 700;

  @override
  Future<void> init() async {}

  @override
  Future<List<ItemDefinition>> getItems() async => List.of(stored);

  @override
  Future<ItemDefinition> createItem(CreateItemInput input) async {
    created.add(input);
    final item = _item(id: _nextId++, name: input.name, groupId: input.groupId);
    stored.add(item);
    return item;
  }

  @override
  Future<ItemDefinition> updateItem(UpdateItemInput input) async {
    updated.add(input);
    return _item(id: input.id, name: input.name, groupId: input.groupId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeClientRepository implements ClientRepository {
  _FakeClientRepository(this.clients);
  final List<ClientDefinition> clients;
  final List<PartyContact> added = [];
  final List<PartyContact> changed = [];
  int _nextContact = 900;

  @override
  Future<void> init() async {}

  @override
  Future<List<ClientDefinition>> getClients() async => List.of(clients);

  final List<String> createdNames = [];

  @override
  Future<ClientDefinition> createClient(CreateClientInput input) async {
    createdNames.add(input.name);
    final made = ClientDefinition(
      id: 50 + createdNames.length,
      name: input.name,
      alias: '',
      gstNumber: '',
      address: '',
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    clients.add(made);
    return made;
  }

  @override
  Future<PartyContact> addContact(int clientId, PartyContact contact) async {
    final made = contact.copyWith(id: _nextContact++, partyId: clientId);
    added.add(made);
    final index = clients.indexWhere((c) => c.id == clientId);
    clients[index] = clients[index]
        .copyWith(contacts: [...clients[index].contacts, made]);
    return made;
  }

  @override
  Future<PartyContact> updateContact(int clientId, PartyContact contact) async {
    changed.add(contact);
    final index = clients.indexWhere((c) => c.id == clientId);
    clients[index] = clients[index].copyWith(contacts: [
      for (final c in clients[index].contacts)
        c.id == contact.id ? contact.copyWith(partyId: clientId) : c,
    ]);
    return contact;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ItemDefinition _item({
  required int id,
  required String name,
  required int groupId,
  DevelopedFor developedFor = DevelopedFor.empty,
}) {
  return ItemDefinition(
    id: id,
    name: name,
    alias: '',
    displayName: name,
    partNo: 48,
    partCode: 'SADP$id',
    quantity: 0,
    groupId: groupId,
    unitId: 7,
    developedFor: developedFor,
    variationTree: const [],
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026, 5, 15, 10, 5),
    updatedAt: DateTime(2026, 5, 15, 10, 5),
  );
}

GroupDefinition _group({required int id, required String name, int? parentGroupId}) {
  return GroupDefinition(
    id: id,
    name: name,
    groupType: 'item',
    groupStructure: 'Standard',
    description: '',
    parentGroupId: parentGroupId,
    unitId: 7,
    isArchived: false,
    usageCount: 0,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );
}

ClientDefinition _goldMedal() => ClientDefinition(
      id: 5,
      name: 'Gold Medal',
      alias: '',
      gstNumber: '',
      address: '',
      isArchived: false,
      usageCount: 0,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      contactName: 'Kissan Jain',
      contacts: const [
        PartyContact(
          id: 11,
          partyId: 5,
          name: 'Kissan Jain',
          designation: 'Director',
          isPrimary: true,
        ),
        PartyContact(id: 12, partyId: 5, name: 'Ravi Shah', designation: 'Purchase'),
        PartyContact(id: 13, partyId: 5, name: 'Old Hand', isArchived: true),
      ],
    );

final _dealSheet = SheetDef(id: 2, key: 'item_party', title: 'Deal', columns: dealSheetColumns);
final _peopleSheet =
    SheetDef(id: 3, key: 'item_people', title: 'People', columns: peopleSheetColumns);

void main() {
  group('DevelopedFor.contactIds', () {
    test('null says nothing on the wire; a list is sent whole', () {
      const quiet = DevelopedFor(kind: DevelopedForKind.client, clientId: 5);
      expect(quiet.toJson().containsKey('contactIds'), isFalse,
          reason: 'a save that never showed people must keep the ticks');
      const ticked = DevelopedFor(
        kind: DevelopedForKind.client,
        clientId: 5,
        contactIds: [11, 12],
      );
      expect(ticked.toJson()['contactIds'], [11, 12]);
    });

    test('reads the ticked people back, and compares them', () {
      final block = DevelopedFor.fromJson({
        'kind': 'client',
        'clientId': 5,
        'contactIds': [12],
        'contacts': [
          {'id': 12, 'name': 'Ravi Shah', 'designation': 'Purchase'},
        ],
        'quotationAmount': 45000,
      });
      expect(block.contactIds, [12]);
      expect(block.contacts.single.name, 'Ravi Shah');
      expect(block.quotationAmount, 45000);
      expect(block, DevelopedFor.fromJson(block.toJson()..['contacts'] = [
        {'id': 12, 'name': 'Ravi Shah', 'designation': 'Purchase'},
      ]));
      expect(block == block.copyWith(contactIds: [11]), isFalse);
    });

    test('moving to another company drops the old company\'s people', () {
      const block = DevelopedFor(
        kind: DevelopedForKind.client,
        clientId: 5,
        contactIds: [11],
      );
      expect(block.copyWith(quotationAmount: 1).contactIds, [11]);
      expect(block.copyWith(clientId: 6).contactIds, isNull,
          reason: 'they would be strangers at the new company');
      expect(block.withKind(DevelopedForKind.self).contactIds, isEmpty);
      expect(block.withKind(DevelopedForKind.contractor).contactIds, isEmpty);
    });
  });

  group('the live deal sheet', () {
    test('the deal is one row and the people are their own sheet', () {
      expect(_dealSheet.columnBoundTo(SheetBindsTo.developedForParty), isNotNull);
      expect(_dealSheet.columnBoundTo(SheetBindsTo.developedForQuotation), isNotNull);
      expect(_dealSheet.columnBoundTo(SheetBindsTo.developedForDesignation), isNull,
          reason: 'one person per deal is what this replaces');
      expect(
        peopleSheetColumns.map((c) => c.label),
        ['Dealt with', 'Name', 'Designation', 'Contact No', 'Email ID'],
      );
      expect(_peopleSheet.columnBoundTo(SheetBindsTo.personDealtWith)!.kind,
          ColumnKind.check);
    });
  });

  group('the deal and its people, through the controller', () {
    late _FakeItemRepository itemsRepo;
    late _FakeClientRepository clientsRepo;
    late ClientsProvider clientsProvider;
    late ItemMasterController controller;

    Future<void> open({List<ItemDefinition> existing = const []}) async {
      final groups = GroupsProvider(
        repository: _FakeGroupRepository([
          _group(id: 10, name: 'Switch Action'),
          _group(id: 11, name: 'Dolly', parentGroupId: 10),
        ]),
      );
      await groups.refresh();
      itemsRepo = _FakeItemRepository()..stored.addAll(existing);
      final items = ItemsProvider(repository: itemsRepo);
      await items.refresh();
      clientsRepo = _FakeClientRepository([
        _goldMedal(),
        ClientDefinition(
          id: 6,
          name: 'Gone Ltd',
          alias: '',
          gstNumber: '',
          address: '',
          isArchived: true,
          usageCount: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      ]);
      final clients = ClientsProvider(repository: clientsRepo);
      clientsProvider = clients;
      await clients.refresh();

      late ItemMasterController made;
      final binding = ItemSheetBinding(
        items: items,
        groups: groups,
        clients: clients,
        itemSheet: SheetDef(
          id: 1,
          key: 'item',
          title: 'Item',
          columns: itemSheetColumns,
        ),
        partySheet: _dealSheet,
        dealDraft: () => made.dealDraftForSave(),
        dealContactIds: () => made.dealContactIdsForSave(),
        peopleSheet: _peopleSheet,
      );
      made = ItemMasterController.live(binding: binding);
      controller = made;
      await controller.loadReferenceData();
    }

    void typePart(String name) {
      final sheet = controller.groupItemController;
      sheet.updateValue(
        1,
        const CellValue(columnId: 1, optionId: 10, optionLabel: 'Switch Action'),
      );
      sheet.updateValue(
        2,
        const CellValue(columnId: 2, optionId: 11, optionLabel: 'Dolly'),
      );
      sheet.updateValue(3, CellValue(columnId: 3, optionLabel: name, isNew: true));
    }

    void pickGoldMedal() {
      controller.clientVendorController.updateValue(
        20,
        const CellValue(columnId: 20, refId: 5, optionLabel: 'Gold Medal'),
      );
    }

    test('choosing a company lists its people, archived ones left out', () async {
      await open();
      expect(controller.peopleLoaded, isFalse);
      pickGoldMedal();
      expect(controller.peopleLoaded, isTrue);
      final names = [
        for (final d in controller.peopleController.drafts) d.get(31)?.textValue,
      ];
      expect(names, ['Kissan Jain', 'Ravi Shah']);
    });

    testWidgets('the form keeps every character typed (it used to keep one)',
        (tester) async {
      await tester.runAsync(open);
      pickGoldMedal();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, child) => DealPeopleForm(controller: controller),
            ),
          ),
        ),
      ));

      // One key at a time, as a person types — each keystroke rebuilds.
      final quotation = find.byKey(const ValueKey('deal_quotation'));
      await tester.tap(quotation);
      for (final text in ['8', '85', '850', '8500', '85000']) {
        await tester.enterText(quotation, text);
        await tester.pump();
      }
      expect(tester.widget<TextField>(quotation).controller!.text, '85000');
      expect(controller.clientVendorController.draft.get(25)?.intValue, 85000);

      // The company's people are text fields, and a new one keeps its name.
      expect(find.text('Kissan Jain'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('deal_add_person')));
      await tester.pump();
      final name = find.byKey(const ValueKey('deal_person_2_person.name'));
      await tester.tap(name);
      for (final text in ['M', 'Me', 'Mee', 'Meena']) {
        await tester.enterText(name, text);
        await tester.pump();
      }
      expect(tester.widget<TextField>(name).controller!.text, 'Meena');
      expect(controller.peopleController.draftAt(2).get(31)?.textValue, 'Meena');

      // Ticking someone marks them on the deal.
      await tester.tap(find.byKey(const ValueKey('deal_person_1_tick')));
      await tester.pump();
      expect(controller.dealContactIdsForSave(), [12]);
    });

    test('the Clients screen\'s search does not hide companies here', () async {
      await open();
      // Somebody searched the Clients screen for something else entirely.
      clientsProvider.setSearchQuery('zzz');
      await controller.loadReferenceData();
      final names = controller.clientVendorController.parties.map((p) => p.name);
      expect(names, contains('Gold Medal'));
      expect(names, isNot(contains('Gone Ltd')), reason: 'archived stays hidden');
    });

    testWidgets('a company can be added from the dropdown, by name', (tester) async {
      await tester.runAsync(open);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, child) => DealPeopleForm(controller: controller),
            ),
          ),
        ),
      ));

      await tester.tap(find.byKey(const ValueKey('deal_company_tap')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'gold medal');
      await tester.pumpAndSettle();
      expect(find.textContaining('Add company'), findsNothing,
          reason: 'an existing name is that company, never a second one');

      await tester.enterText(find.byType(TextField).last, 'Havells');
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Add company “Havells”'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();

      expect(clientsRepo.createdNames, ['Havells']);
      expect(controller.dealPartyName, 'Havells');
    });

    testWidgets('a person line has its own Save, then Edit', (tester) async {
      await tester.runAsync(open);
      pickGoldMedal();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, child) => DealPeopleForm(controller: controller),
            ),
          ),
        ),
      ));
      // People on file come in saved: Edit, not Save.
      expect(find.byKey(const ValueKey('deal_person_0_edit')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('deal_add_person')));
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('deal_person_2_person.name')), 'Meena');
      await tester.pump();
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('deal_person_2_save')));
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pump();

      expect(clientsRepo.added.single.name, 'Meena');
      expect(find.byKey(const ValueKey('deal_person_2_edit')), findsOneWidget);
    });

    testWidgets('Designation offers what people were given before, and takes a new one',
        (tester) async {
      await tester.runAsync(open);
      pickGoldMedal();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, child) => DealPeopleForm(controller: controller),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const ValueKey('deal_add_person')));
      await tester.pump();

      final designation =
          find.byKey(const ValueKey('deal_person_2_person.designation'));
      await tester.tap(designation);
      await tester.pumpAndSettle();
      // Ravi Shah's, from the client list — not only the stock ones.
      expect(find.text('Purchase'), findsWidgets);
      await tester.enterText(find.byType(TextField).last, 'Plant Head');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use "Plant Head"'));
      await tester.pumpAndSettle();

      expect(controller.peopleController.draftAt(2).get(32)?.textValue, 'Plant Head');
    });

    test('a saved part changed elsewhere refreshes its closed row, not an open one',
        () async {
      final saved = _item(id: 500, name: 'Patti', groupId: 11);
      await open(existing: [saved]);
      controller.loadItems(<ItemDefinition>[saved]);
      expect(controller.groupItemController.isRowLocked(0), isTrue);

      final renamed = _item(id: 500, name: 'Patti Mk2', groupId: 11);
      controller.refreshLockedRows(<ItemDefinition>[renamed]);
      expect(controller.groupItemController.draftAt(0).get(3)?.textValue ??
          controller.groupItemController.draftAt(0).get(3)?.optionLabel, 'Patti Mk2');

      // Opened for editing: someone else's change does not land under the cursor.
      controller.groupItemController.setRowLocked(0, false);
      controller.refreshLockedRows(<ItemDefinition>[_item(id: 500, name: 'Patti Mk3', groupId: 11)]);
      expect(controller.groupItemController.draftAt(0).get(3)?.textValue ??
          controller.groupItemController.draftAt(0).get(3)?.optionLabel, 'Patti Mk2');
    });

    test('a background reload does not replace the rows being typed into',
        () async {
      // The masters notify often (every save, every sync). Each reload used to
      // re-list the people, replacing the very cell under the cursor — the
      // field flickered and lost focus.
      await open();
      pickGoldMedal();
      final before = controller.peopleController.drafts.first;

      await controller.loadReferenceData();
      expect(identical(controller.peopleController.drafts.first, before), isTrue,
          reason: 'same people, so the rows are left alone');

      // An empty row just added, about to be typed into, survives a reload.
      final added = controller.peopleController.addRow();
      await controller.loadReferenceData();
      expect(controller.peopleController.rowCount, added + 1);
    });

    test('a new person saves to the company first, and both ticks reach the part',
        () async {
      await open();
      typePart('Patti');
      pickGoldMedal();
      controller.clientVendorController.updateTextValue(25, '45000');

      final people = controller.peopleController;
      // Tick Ravi (row 1)...
      people.updateValue(30, const CellValue(columnId: 30, intValue: 1), row: 1);
      // ...and add Meena, ticked, who is not on file yet.
      final row = people.addRow();
      people.updateTextValue(31, 'Meena Patil', row: row);
      people.updateTextValue(32, 'Accounts', row: row);
      people.updateValue(30, const CellValue(columnId: 30, intValue: 1), row: row);

      final written = await controller.commitAllRows();
      expect(written, 1, reason: '${controller.rowError(0)}');

      expect(clientsRepo.added.single.name, 'Meena Patil');
      expect(clientsRepo.changed, isEmpty,
          reason: 'ticking Ravi is not a change to Ravi');

      final deal = itemsRepo.created.single.developedFor!;
      expect(deal.kind, DevelopedForKind.client);
      expect(deal.clientId, 5);
      expect(deal.quotationAmount, 45000, reason: 'one figure for the part');
      expect(deal.contactIds, unorderedEquals([12, clientsRepo.added.single.id]));
    });

    test('editing a person on file updates the company record', () async {
      await open();
      typePart('Patti');
      pickGoldMedal();
      controller.peopleController.updateTextValue(33, '9820012345', row: 1);

      await controller.commitAllRows();
      expect(clientsRepo.changed.single.id, 12);
      expect(clientsRepo.changed.single.phone, '9820012345');
      expect(itemsRepo.created.single.developedFor!.contactIds, isEmpty);
    });

    test('a person typed without a name stops the save and says why', () async {
      await open();
      typePart('Patti');
      pickGoldMedal();
      final people = controller.peopleController;
      final row = people.addRow();
      people.updateTextValue(32, 'Accounts', row: row);

      final written = await controller.commitAllRows();
      expect(written, 0);
      expect(itemsRepo.created, isEmpty);
      expect(controller.rowError(0), contains('name'));
    });

    test('opening a part restores its company, quotation and ticks', () async {
      final saved = _item(
        id: 500,
        name: 'Patti',
        groupId: 11,
        developedFor: const DevelopedFor(
          kind: DevelopedForKind.client,
          clientId: 5,
          companyName: 'Gold Medal',
          contactIds: [12],
          quotationAmount: 85000,
        ),
      );
      await open(existing: [saved]);
      controller.loadItems(<ItemDefinition>[saved]);

      expect(controller.isExternal, isTrue);
      expect(controller.dealPartyId, 5);
      expect(controller.clientVendorController.draft.get(25)?.intValue, 85000);
      expect(controller.dealContactIdsForSave(), [12]);
    });

    test('a part for nobody opens with the deal off and sends nothing', () async {
      final saved = _item(id: 501, name: 'Patti', groupId: 11);
      await open(existing: [saved]);
      controller.loadItems(<ItemDefinition>[saved]);
      expect(controller.isExternal, isFalse);
      expect(controller.dealDraftForSave(), isNull);
      expect(controller.dealContactIdsForSave(), isNull);
    });

    test('before the company\'s people are known, the ticks say nothing', () async {
      await open();
      // A company the clients master has not loaded.
      controller.clientVendorController.updateValue(
        20,
        const CellValue(columnId: 20, refId: 77, optionLabel: 'Unknown Co'),
      );
      expect(controller.peopleLoaded, isFalse);
      expect(controller.dealContactIdsForSave(), isNull,
          reason: 'an empty list here would clear ticks the part already has');
    });
  });
}
