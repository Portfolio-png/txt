import 'dart:typed_data';

import 'package:core_erp/core/services/company_documents.dart';
import 'package:core_erp/core/services/entity_photos.dart';
import 'package:core_erp/core/services/photo_requests.dart';
import 'package:core_erp/core/widgets/company_documents_box.dart';
import 'package:core_erp/features/clients/data/repositories/client_repository.dart';
import 'package:core_erp/features/clients/data/repositories/sub_contractor_repository.dart';
import 'package:core_erp/features/clients/domain/client_definition.dart';
import 'package:core_erp/features/clients/domain/party_contact.dart';
import 'package:core_erp/features/clients/domain/sub_contractor_definition.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/clients/presentation/providers/sub_contractors_provider.dart';
import 'package:core_erp/features/clients/presentation/widgets/company_view_dialog.dart';
import 'package:core_erp/features/items/domain/developed_for.dart';
import 'package:core_erp/features/items/presentation/widgets/developed_for_form.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

// A company keeps named documents — a PDF, a picture, anything — added from a
// file on the PC or photographed on the phone under the name given here. They
// are the company's, so the sheet, the wizard and the company's view all show
// the same ones.

/// The demo store, with a link to open a document by.
class _Documents extends CompanyDocumentRepository {
  _Documents() : super(baseUrl: 'http://x', useMockResponses: true);

  @override
  Future<String> readUrl(int documentId) async => 'http://x/doc/$documentId';
}

class _Clients implements ClientRepository {
  _Clients(this._clients);
  final List<ClientDefinition> _clients;

  @override
  Future<void> init() async {}

  @override
  Future<List<ClientDefinition>> getClients() async => List.of(_clients);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Contractors implements SubContractorRepository {
  _Contractors(this._rows);
  final List<SubContractorDefinition> _rows;

  @override
  Future<void> init() async {}

  @override
  Future<List<SubContractorDefinition>> getAllSubContractors() async => List.of(_rows);

  @override
  Future<List<SubContractorDefinition>> getSubContractors(int clientId) async =>
      _rows.where((row) => row.clientId == clientId).toList();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _kapoor = ClientDefinition(
  id: 5,
  name: 'Kapoor Papers',
  alias: 'KP',
  gstNumber: '27KPRPA9876Q1Z2',
  address: 'Bhosari, Pune',
  isArchived: false,
  usageCount: 0,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
  contacts: const [
    PartyContact(id: 11, partyId: 5, name: 'Ravi Kapoor', designation: 'Proprietor', phone: '98220 11111', isPrimary: true),
  ],
);

final _shinde = SubContractorDefinition(
  id: 21,
  clientId: 5,
  name: 'Shinde Works',
  phone: '98220 22222',
  clientName: 'Kapoor Papers',
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

/// Named through [path]: off the web an XFile's name is its path's last part,
/// and a picked file always has one.
XFile _file(String name, String mime, int size) =>
    XFile.fromData(Uint8List(size), name: name, path: name, mimeType: mime, length: size);

class _World {
  _World()
    : documents = CompanyDocumentsProvider(repository: _Documents(), listen: false),
      requests = PhotoRequestsProvider(
        repository: PhotoRequestRepository(baseUrl: 'http://x', useMockResponses: true),
        listen: false,
      ),
      clients = ClientsProvider(repository: _Clients([_kapoor])),
      contractors = SubContractorsProvider(repository: _Contractors([_shinde]));

  final CompanyDocumentsProvider documents;
  final PhotoRequestsProvider requests;
  final ClientsProvider clients;
  final SubContractorsProvider contractors;

  Future<void> pump(WidgetTester tester, Widget child) async {
    await clients.refresh();
    await tester.binding.setSurfaceSize(const Size(1300, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CompanyDocumentsProvider>.value(value: documents),
          ChangeNotifierProvider<PhotoRequestsProvider>.value(value: requests),
          ChangeNotifierProvider<ClientsProvider>.value(value: clients),
          ChangeNotifierProvider<SubContractorsProvider>.value(value: contractors),
          ChangeNotifierProvider<EntityPhotosProvider>(
            create: (_) => EntityPhotosProvider(
              repository: EntityPhotoRepository(baseUrl: 'http://x', useMockResponses: true),
              listen: false,
            ),
          ),
        ],
        child: MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 900, child: child)))),
      ),
    );
    await tester.pumpAndSettle();
  }
}

Future<void> _addFromPc(WidgetTester tester, String owner, String id, {String name = ''}) async {
  await tester.tap(find.byKey(ValueKey<String>('document-add-$owner-$id')));
  await tester.pumpAndSettle();
  if (name.isNotEmpty) {
    await tester.enterText(find.byKey(const ValueKey<String>('document-name')), name);
    await tester.pump();
  }
  await tester.tap(find.byKey(const ValueKey<String>('document-choose-file')));
  await tester.pumpAndSettle();
}

void main() {
  late XFile? picked;
  late List<Uri> launched;

  setUp(() {
    picked = null;
    launched = [];
    CompanyDocumentsBox.debugPickFile = () async => picked;
    CompanyDocumentsBox.debugLaunch = (uri) async {
      launched.add(uri);
      return true;
    };
  });
  tearDown(() {
    CompanyDocumentsBox.debugPickFile = null;
    CompanyDocumentsBox.debugLaunch = null;
  });

  testWidgets('no company yet: the box is there, disabled, saying why', (tester) async {
    await _World().pump(
      tester,
      const CompanyDocumentsBox(owner: PhotoOwner.client, id: null, disabledReason: 'Pick the company first'),
    );
    expect(find.text('Documents'), findsOneWidget);
    final add = tester.widget<TextButton>(
      find.ancestor(of: find.text('Add document'), matching: find.byType(TextButton)),
    );
    expect(add.onPressed, isNull);
    expect(
      find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Pick the company first'),
      findsOneWidget,
    );
  });

  testWidgets('a file from the PC is kept under the name given, any kind', (tester) async {
    final world = _World();
    await world.pump(tester, const CompanyDocumentsBox(owner: PhotoOwner.client, id: '5'));
    expect(find.textContaining('None yet'), findsOneWidget);

    picked = _file('gst.pdf', 'application/pdf', 2048);
    await _addFromPc(tester, 'client', '5', name: '  GST   certificate ');
    expect(find.text('GST certificate'), findsOneWidget);
    expect(find.textContaining('PDF · 2 KB · '), findsOneWidget);
    expect(find.text('Documents · 1'), findsOneWidget);

    // Unnamed, it is called by its file name.
    picked = _file('rates 2026.xlsx', 'application/vnd.ms-excel', 900);
    await _addFromPc(tester, 'client', '5');
    expect(find.text('rates 2026'), findsOneWidget);
    expect(find.textContaining('XLSX · 900 B'), findsOneWidget);

    // Too big is refused before anything is sent.
    picked = _file('scan.tiff', 'image/tiff', maxCompanyDocumentBytes + 1);
    await _addFromPc(tester, 'client', '5', name: 'Huge scan');
    expect(find.textContaining('25 MB at most'), findsOneWidget);
    expect(world.documents.documentsOf('client', '5')!.map((d) => d.title), ['rates 2026', 'GST certificate']);
  });

  testWidgets('a PDF opens in the PC\'s own viewer', (tester) async {
    final world = _World();
    await world.pump(tester, const CompanyDocumentsBox(owner: PhotoOwner.client, id: '5'));
    picked = _file('gst.pdf', 'application/pdf', 10);
    await _addFromPc(tester, 'client', '5', name: 'GST certificate');

    await tester.tap(find.text('GST certificate'));
    await tester.pumpAndSettle();
    final id = world.documents.documentsOf('client', '5')!.single.id;
    expect(launched, [Uri.parse('http://x/doc/$id')]);
  });

  testWidgets('the phone is asked by name; the job shows until taken back', (tester) async {
    final world = _World();
    await world.pump(tester, const CompanyDocumentsBox(owner: PhotoOwner.client, id: '5', note: 'for Kapoor Papers'));

    await tester.tap(find.byKey(const ValueKey<String>('document-add-client-5')));
    await tester.pumpAndSettle();
    // Unnamed, the phone would not know what to file it as.
    final phone = find.byKey(const ValueKey<String>('document-take-on-phone'));
    expect(tester.widget<ListTile>(find.descendant(of: phone, matching: find.byType(ListTile))).enabled, isFalse);
    expect(find.textContaining('Name it first'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey<String>('document-name')), 'Visiting card');
    await tester.pump();
    await tester.tap(phone);
    await tester.pumpAndSettle();

    final job = world.requests.pending.single;
    expect((job.owner, job.entityId, job.documentTitle, job.context), ('client', '5', 'Visiting card', 'for Kapoor Papers'));
    expect(find.text('   On phone · waiting', findRichText: true), findsNothing);
    expect(find.textContaining('On phone · waiting', findRichText: true), findsOneWidget);
    // The logo's own slot is not waiting on anything.
    expect(world.requests.pendingFor('client', '5'), isNull);

    await tester.tap(find.byKey(ValueKey<String>('document-waiting-${job.id}')));
    await tester.pumpAndSettle();
    expect(world.requests.pending, isEmpty);
    expect(find.textContaining('On phone · waiting', findRichText: true), findsNothing);
  });

  testWidgets('a document is renamed, and removed after a yes', (tester) async {
    final world = _World();
    await world.pump(tester, const CompanyDocumentsBox(owner: PhotoOwner.client, id: '5'));
    picked = _file('drawing.png', 'image/png', 10);
    await _addFromPc(tester, 'client', '5', name: 'Drawing');

    await tester.tap(find.byTooltip('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey<String>('document-rename')), 'Drawing rev B');
    await tester.tap(find.byKey(const ValueKey<String>('document-rename-save')));
    await tester.pumpAndSettle();
    expect(find.text('Drawing rev B'), findsOneWidget);

    await tester.tap(find.byTooltip('Remove'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('document-remove-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Drawing rev B'), findsNothing);
    expect(world.documents.documentsOf('client', '5'), isEmpty);
  });

  testWidgets('the wizard\'s Developed For keeps the picked company\'s documents', (tester) async {
    final world = _World();
    await world.documents.upload('client', '5', _file('gst.pdf', 'application/pdf', 10), 'GST certificate');
    await world.documents.upload('sub_contractor', '21', _file('c.pdf', 'application/pdf', 10), 'Job-work contract');

    var value = const DevelopedFor(kind: DevelopedForKind.client, clientId: 5, companyName: 'Kapoor Papers');
    await world.pump(
      tester,
      StatefulBuilder(
        builder: (context, setState) => SingleChildScrollView(
          child: DevelopedForForm(value: value, onChanged: (next) => setState(() => value = next)),
        ),
      ),
    );
    expect(find.byKey(const ValueKey<String>('documents-client-5')), findsOneWidget);
    expect(find.text('GST certificate'), findsOneWidget);
  });

  testWidgets('a contractor\'s are its own', (tester) async {
    final world = _World();
    await world.documents.upload('sub_contractor', '21', _file('c.pdf', 'application/pdf', 10), 'Job-work contract');
    await world.pump(
      tester,
      DevelopedForForm(
        value: const DevelopedFor(
          kind: DevelopedForKind.contractor,
          clientId: 5,
          subContractorId: 21,
          subContractorName: 'Shinde Works',
          companyName: 'Kapoor Papers',
        ),
        onChanged: (_) {},
      ),
    );
    expect(find.byKey(const ValueKey<String>('documents-sub_contractor-21')), findsOneWidget);
    expect(find.text('Job-work contract'), findsOneWidget);
  });

  testWidgets('the company view shows details, people, contractors and documents', (tester) async {
    final world = _World();
    await world.documents.upload('client', '5', _file('gst.pdf', 'application/pdf', 10), 'GST certificate');
    await world.pump(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => CompanyView.openClient(context, 5),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Kapoor Papers'), findsOneWidget);
    expect(find.text('Client · KP'), findsOneWidget);
    expect(find.text('27KPRPA9876Q1Z2'), findsOneWidget);
    expect(find.text('Ravi Kapoor  ·  Primary'), findsOneWidget);
    expect(find.text('GST certificate'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('company-view-contractor-21')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('company-view-edit')), findsOneWidget);

    // One company at a time: the contractor opens in its place.
    await tester.tap(find.byKey(const ValueKey<String>('company-view-contractor-21')));
    await tester.pumpAndSettle();
    expect(find.text('Shinde Works'), findsOneWidget);
    expect(find.text('Contractor for Kapoor Papers'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('documents-sub_contractor-21')), findsOneWidget);
    expect(find.text('GST certificate'), findsNothing);
  });
}
