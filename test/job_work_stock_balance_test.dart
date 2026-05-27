import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/app/preferences/preferences_provider.dart';
import 'package:paper/app/shell/navigation_provider.dart';
import 'package:core_erp/features/clients/domain/client_definition.dart';
import 'package:core_erp/features/delivery_challans/domain/delivery_challan.dart';
import 'package:core_erp/features/clients/presentation/providers/clients_provider.dart';
import 'package:core_erp/features/delivery_challans/presentation/providers/delivery_challan_provider.dart';
import 'package:paper/main.dart';

import 'widget_test.dart';

void main() {
  testWidgets('Job Work Stock Balance calculates and filters correctly', (WidgetTester tester) async {
    // 1. Seed clients
    final testClients = [
      ClientDefinition(
        id: 1,
        name: 'Client Acme',
        alias: 'Acme',
        gstNumber: 'GST123',
        address: 'Acme Street',
        isArchived: false,
        usageCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      ClientDefinition(
        id: 2,
        name: 'Client Zebra',
        alias: 'Zebra',
        gstNumber: 'GST456',
        address: 'Zebra Road',
        isArchived: false,
        usageCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    // 2. Seed job work challans
    final testChallans = [
      // Job Work Inward: Client Acme, 1000 Pcs Plain Cups
      DeliveryChallan(
        id: 1,
        type: ChallanType.reception, // Reception is Inward
        purpose: ChallanPurpose.jobWork,
        orderId: null,
        orderIds: const [],
        clientId: 1,
        orderNo: '',
        orderNos: const [],
        challanNo: 'JW-IN-001',
        date: DateTime.now(),
        location: '',
        customerName: 'Client Acme',
        customerGstin: '',
        vendorId: null,
        vendorName: '',
        vendorGstin: '',
        sourceReference: '',
        companyProfileSnapshot: null,
        notes: '',
        maintainStocks: true,
        status: DeliveryChallanStatus.issued, // Must be issued to be tracked
        itemsCount: 1,
        items: const [
          DeliveryChallanItem(
            id: 101,
            orderItemId: null,
            productionRunId: null,
            itemId: 50,
            variationLeafNodeId: 0,
            lineNo: 1,
            particulars: 'Plain Cups',
            hsnCode: '',
            variationPathLabel: 'White / 250ml',
            note: '',
            quantityPcs: '1000',
            weight: '',
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      // Job Work Outward: Client Acme, 800 Pcs Printed Cups (returned)
      DeliveryChallan(
        id: 2,
        type: ChallanType.delivery, // Delivery is Outward
        purpose: ChallanPurpose.jobWork,
        orderId: null,
        orderIds: const [],
        clientId: 1,
        orderNo: '',
        orderNos: const [],
        challanNo: 'JW-OUT-001',
        date: DateTime.now(),
        location: '',
        customerName: 'Client Acme',
        customerGstin: '',
        vendorId: null,
        vendorName: '',
        vendorGstin: '',
        sourceReference: '',
        companyProfileSnapshot: null,
        notes: '',
        maintainStocks: true,
        status: DeliveryChallanStatus.issued, // Must be issued
        itemsCount: 1,
        items: const [
          DeliveryChallanItem(
            id: 102,
            orderItemId: null,
            productionRunId: null,
            itemId: 50,
            variationLeafNodeId: 0,
            lineNo: 1,
            particulars: 'Plain Cups',
            hsnCode: '',
            variationPathLabel: 'White / 250ml',
            note: '',
            quantityPcs: '800',
            weight: '',
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
      // Job Work Inward: Client Zebra, 500 Pcs Paper Bowls
      DeliveryChallan(
        id: 3,
        type: ChallanType.reception,
        purpose: ChallanPurpose.jobWork,
        orderId: null,
        orderIds: const [],
        clientId: 2,
        orderNo: '',
        orderNos: const [],
        challanNo: 'JW-IN-002',
        date: DateTime.now(),
        location: '',
        customerName: 'Client Zebra',
        customerGstin: '',
        vendorId: null,
        vendorName: '',
        vendorGstin: '',
        sourceReference: '',
        companyProfileSnapshot: null,
        notes: '',
        maintainStocks: true,
        status: DeliveryChallanStatus.issued,
        itemsCount: 1,
        items: const [
          DeliveryChallanItem(
            id: 103,
            orderItemId: null,
            productionRunId: null,
            itemId: 60,
            variationLeafNodeId: 0,
            lineNo: 1,
            particulars: 'Paper Bowls',
            hsnCode: '',
            variationPathLabel: 'Brown',
            note: '',
            quantityPcs: '500',
            weight: '',
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    ];

    final clientRepository = FakeClientRepository(seedClients: testClients);
    final challanRepository = FakeDeliveryChallanRepository(seedChallans: testChallans);
    final authProvider = FakeAuthProvider(authenticated: true);
    final inventoryRepository = FakeInventoryRepository();
    final groupRepository = FakeGroupRepository();
    final unitRepository = FakeUnitRepository();
    final vendorRepository = FakeVendorRepository();
    final itemRepository = FakeItemRepository();
    final orderRepository = FakeOrderRepository();

    // Pump the entire app with all fake repositories
    await tester.pumpWidget(
      MyApp(
        demoModeOverride: true,
        authProvider: authProvider,
        inventoryRepository: inventoryRepository,
        groupRepository: groupRepository,
        unitRepository: unitRepository,
        clientRepository: clientRepository,
        vendorRepository: vendorRepository,
        deliveryChallanRepository: challanRepository,
        itemRepository: itemRepository,
        orderRepository: orderRepository,
      ),
    );

    await tester.pumpAndSettle();

    // Select inventory tab
    final context = tester.element(find.byType(Scaffold).first);
    context.read<NavigationProvider>().select(
      'inventory',
      skipTransition: true,
    );
    await tester.pumpAndSettle();

    // Toggle service/job work mode to true
    context.read<PreferencesProvider>().toggleServiceMode(true);
    await tester.pumpAndSettle();

    // Verify "Job Work Stock" tab / header option is visible
    expect(find.text('Job Work Stock'), findsOneWidget);

    // Tap on Job Work Stock
    await tester.tap(find.text('Job Work Stock'));
    await tester.pumpAndSettle();

    // Verify headers
    expect(find.text('Customer / Owner'), findsOneWidget);
    expect(find.text('Item / Particulars'), findsOneWidget);
    expect(find.text('Variation'), findsOneWidget);
    expect(find.text('Inward Qty (Pcs)'), findsOneWidget);
    expect(find.text('Returned Qty (Pcs)'), findsOneWidget);
    expect(find.text('Balance on Hand'), findsOneWidget);

    // Verify row data for Client Acme: 1000 inward, 800 returned, 200 balance
    expect(find.text('Client Acme / Acme'), findsOneWidget);
    expect(find.text('Plain Cups'), findsOneWidget);
    expect(find.text('White / 250ml'), findsOneWidget);
    expect(find.text('1000'), findsOneWidget);
    expect(find.text('800'), findsOneWidget);
    expect(find.text('200'), findsOneWidget);

    // Verify row data for Client Zebra: 500 inward, 0 returned, 500 balance
    expect(find.text('Client Zebra / Zebra'), findsOneWidget);
    expect(find.text('Paper Bowls'), findsOneWidget);
    expect(find.text('Brown'), findsOneWidget);
    expect(find.text('500'), findsNWidgets(2));
  });
}
