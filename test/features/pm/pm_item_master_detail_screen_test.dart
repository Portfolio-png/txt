import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:paper/features/pm/presentation/screens/pm_item_master_detail_screen.dart';
import 'package:paper/features/pm/presentation/screens/pm_screen.dart';

void main() {
  group('PMItemMasterDetailScreen Tests', () {
    testWidgets('renders all Item Master 1 tables and derives correct part code', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: PMItemMasterDetailScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Headers & Sections
      expect(find.text('Item Master 1 & Process Tooling Matrix'), findsOneWidget);
      expect(find.text('Item Master 1'), findsOneWidget);
      expect(find.text('Item Details'), findsOneWidget);
      expect(find.text('Item Alloy\nDetails'), findsOneWidget);
      expect(find.text('Item Die\nDetails'), findsOneWidget);
      expect(find.text('Developed For'), findsWidgets);
      expect(find.text('Die'), findsOneWidget);
      expect(find.text('Machine Master'), findsOneWidget);

      // 2. Active Formula Part Code: Switch Action + Dolly + Patti + Brass + 22 Gauge + 48 -> SADPB2248
      expect(find.text('SADPB2248'), findsWidgets);
      expect(find.text('22 Gauge'), findsWidgets);
      expect(find.text('Brass'), findsWidgets);
      expect(find.text('48'), findsWidgets);

      // 3. Developed For Client Quote Table
      expect(find.text('Gold Madel'), findsWidgets);
      expect(find.text('Kissan Jain'), findsWidgets);
      expect(find.text('85000/-'), findsWidgets);

      // 4. Initial Die Process Tables (Cutting, Riveting, Assembly)
      expect(find.text('Cutting'), findsWidgets);
      expect(find.text('CDSADP48'), findsOneWidget);
      expect(find.text('Riveting'), findsWidgets);
      expect(find.text('RSADP48'), findsOneWidget);
      expect(find.text('Assembly'), findsWidgets);
      expect(find.text('ASADP48'), findsOneWidget);

      // 5. Initial Machine Master Tables
      expect(find.text('Power Press'), findsWidgets);
      expect(find.text('Mayank'), findsWidgets);
      expect(find.text('PP-4'), findsWidgets);
    });

    testWidgets('dynamic + button adds a new process table in Die Master', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: PMItemMasterDetailScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Initial count of die tables is 3
      expect(find.text('CDSADP48'), findsOneWidget);
      expect(find.text('RSADP48'), findsOneWidget);
      expect(find.text('ASADP48'), findsOneWidget);

      // Tap "+ Add Die Process Table"
      final addDieBtn = find.byKey(const ValueKey('add_die_process_table_btn'));
      expect(addDieBtn, findsOneWidget);
      await tester.ensureVisible(addDieBtn);
      await tester.tap(addDieBtn);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Add New Die Process Table'), findsOneWidget);
      final confirmBtn = find.widgetWithText(ElevatedButton, 'Add Process Table');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // 4th table is added: Bending -> BDSADP48
      expect(find.text('BDSADP48'), findsOneWidget);
    });

    testWidgets('dynamic + button adds a new machine table in Machine Master', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: PMItemMasterDetailScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "+ Add Machine Table"
      final addMachBtn = find.byKey(const ValueKey('add_machine_table_btn'));
      expect(addMachBtn, findsOneWidget);
      await tester.ensureVisible(addMachBtn);
      await tester.tap(addMachBtn);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Add New Machine Table'), findsOneWidget);
      final confirmBtn = find.widgetWithText(ElevatedButton, 'Add Machine Table');
      await tester.tap(confirmBtn);
      await tester.pumpAndSettle();

      // 4th machine table is added with PP-5
      expect(find.text('PP-5'), findsOneWidget);
    });

    testWidgets('navigates from PMScreen to PMItemMasterDetailScreen on button click', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        const MaterialApp(
          home: PMScreen(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Find navigation banner button on PM screen
      final navBtn = find.byKey(const ValueKey('open_item_master_detail_screen_btn'));
      expect(navBtn, findsOneWidget);
      await tester.ensureVisible(navBtn);
      await tester.tap(navBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Navigated to PMItemMasterDetailScreen
      expect(find.text('Item Master 1 & Process Tooling Matrix'), findsOneWidget);
      expect(find.text('SADPB2248'), findsWidgets);
    });

    testWidgets('Section 1 (Group Item) CRUD: Create, Read, Update, Delete', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: PMItemMasterDetailScreen()));
      await tester.pumpAndSettle();

      // Read: Initial items exist
      expect(find.text('SADP48'), findsWidgets);
      expect(find.text('SADP47'), findsWidgets);
      expect(find.text('SARP10'), findsWidgets);

      // Create: Tap "New Item"
      final newItemBtn = find.byKey(const ValueKey('create_new_item_btn'));
      expect(newItemBtn, findsOneWidget);
      await tester.tap(newItemBtn);
      await tester.pumpAndSettle();

      // SADP49 is created and active
      expect(find.text('SADP49'), findsWidgets);

      // Update: Tap "Edit Item"
      final editBtn = find.byKey(const ValueKey('edit_active_item_btn'));
      expect(editBtn, findsOneWidget);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();
      expect(find.text('Edit Item (SADP49)'), findsOneWidget);

      final updateBtn = find.widgetWithText(ElevatedButton, 'Update Item');
      await tester.tap(updateBtn);
      await tester.pumpAndSettle();

      // Delete: Tap "Delete Item"
      final deleteBtn = find.byKey(const ValueKey('delete_active_item_btn'));
      expect(deleteBtn, findsOneWidget);
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('Delete Item SADP49?'), findsOneWidget);
      final confirmDelete = find.widgetWithText(ElevatedButton, 'Delete');
      await tester.tap(confirmDelete);
      await tester.pumpAndSettle();
    });

    testWidgets('Section 2 (Client / Vendor) CRUD: Create, Read, Update, Delete', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: PMItemMasterDetailScreen()));
      await tester.pumpAndSettle();

      // Read: Initial party
      expect(find.text('Gold Madel'), findsWidgets);

      // Create: Tap "Add Party"
      final addPartyBtn = find.byKey(const ValueKey('add_party_btn'));
      expect(addPartyBtn, findsOneWidget);
      await tester.tap(addPartyBtn);
      await tester.pumpAndSettle();

      expect(find.text('Add Client / Vendor'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Company Name'), 'Schneider Electric');
      final confirmAdd = find.widgetWithText(ElevatedButton, 'Add Party');
      await tester.tap(confirmAdd);
      await tester.pumpAndSettle();

      expect(find.text('Schneider Electric'), findsWidgets);

      // Update: Tap "Edit Party"
      final editPartyBtn = find.byKey(const ValueKey('edit_party_btn'));
      expect(editPartyBtn, findsOneWidget);
      await tester.tap(editPartyBtn);
      await tester.pumpAndSettle();

      expect(find.text('Edit Party (Schneider Electric)'), findsOneWidget);
      final savePartyBtn = find.widgetWithText(ElevatedButton, 'Save Details');
      await tester.tap(savePartyBtn);
      await tester.pumpAndSettle();

      // Delete: Tap "Unlink Party"
      final deletePartyBtn = find.byKey(const ValueKey('delete_party_btn'));
      expect(deletePartyBtn, findsOneWidget);
      await tester.tap(deletePartyBtn);
      await tester.pumpAndSettle();

      expect(find.text('Unlink Party Schneider Electric?'), findsOneWidget);
      final confirmUnlink = find.widgetWithText(ElevatedButton, 'Unlink');
      await tester.tap(confirmUnlink);
      await tester.pumpAndSettle();
    });

    testWidgets('Section 3 & 4 Update and Delete: Die and Machine table actions', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: PMItemMasterDetailScreen()));
      await tester.pumpAndSettle();

      // Section 3 (Die): Edit
      final editDieBtn = find.byKey(const ValueKey('edit_die_btn_cutting'));
      expect(editDieBtn, findsOneWidget);
      await tester.tap(editDieBtn);
      await tester.pumpAndSettle();
      expect(find.text('Edit Die Process (Cutting)'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
      await tester.pumpAndSettle();

      // Section 3 (Die): Delete
      final deleteDieBtn = find.byKey(const ValueKey('delete_die_btn_cutting'));
      expect(deleteDieBtn, findsOneWidget);
      await tester.tap(deleteDieBtn);
      await tester.pumpAndSettle();
      expect(find.text('Delete Process Table Cutting?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('CDSADP48'), findsNothing);

      // Section 4 (Machine): Edit
      final editMachineBtn = find.byKey(const ValueKey('edit_machine_btn_m1'));
      expect(editMachineBtn, findsOneWidget);
      await tester.tap(editMachineBtn);
      await tester.pumpAndSettle();
      expect(find.text('Edit Machine Table (Power Press 1)'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save Changes'));
      await tester.pumpAndSettle();

      // Section 4 (Machine): Delete
      final deleteMachineBtn = find.byKey(const ValueKey('delete_machine_btn_m1'));
      expect(deleteMachineBtn, findsOneWidget);
      await tester.tap(deleteMachineBtn);
      await tester.pumpAndSettle();
      expect(find.text('Delete Machine Table Power Press 1?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('PP-4'), findsNothing);
    });

    testWidgets('tapping + on Properties in Item table adds one more row (SADP49)', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: PMItemMasterDetailScreen()));
      await tester.pumpAndSettle();

      // Before tap: SADP49 does not exist
      expect(find.text('SADP49'), findsNothing);

      // Find the + button on Item Properties mini-table
      final addPropBtn = find.byKey(const ValueKey('mini_table_add_properties_item'));
      expect(addPropBtn, findsOneWidget);
      await tester.ensureVisible(addPropBtn);
      await tester.tap(addPropBtn);
      await tester.pumpAndSettle();

      // After tap: One more row is added with SADP49
      expect(find.text('SADP49'), findsWidgets);
    });

    testWidgets('tapping + on Properties in Client / Vendor adds one more row and + Column creates custom property', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: PMItemMasterDetailScreen()));
      await tester.pumpAndSettle();

      // Scroll to Client / Vendor section
      final cvSectionHeader = find.text('Developed For');
      expect(cvSectionHeader, findsWidgets);
      await tester.ensureVisible(cvSectionHeader.first);

      // 1. Properties header has + button in Client / Vendor
      final addCvPropRowBtn = find.byKey(const ValueKey('mini_table_add_properties_item_party'));
      expect(addCvPropRowBtn, findsOneWidget);
      expect(find.text('Party 4'), findsNothing);

      // Tap + on Properties in Client / Vendor -> adds one more row (Party 4)
      await tester.ensureVisible(addCvPropRowBtn);
      await tester.tap(addCvPropRowBtn);
      await tester.pumpAndSettle();

      expect(find.text('Party 4'), findsWidgets);

      // 2. Tap "+ Column" to create user-defined property in Client / Vendor
      final addCvColBtn = find.byKey(const ValueKey('add_cv_property_column_btn'));
      expect(addCvColBtn, findsOneWidget);
      await tester.ensureVisible(addCvColBtn);
      await tester.tap(addCvColBtn);
      await tester.pumpAndSettle();

      expect(find.text('Add Client / Vendor Property'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Property Name (e.g. GSTIN, Payment Terms)'), 'GSTIN');
      final confirmAddCol = find.widgetWithText(ElevatedButton, 'Add Property');
      await tester.tap(confirmAddCol);
      await tester.pumpAndSettle();

      // Verify the new column header is added
      expect(find.text('GSTIN'), findsWidgets);
    });

    testWidgets('tapping on an unselected row in Item table selects that item', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: PMItemMasterDetailScreen()));
      await tester.pumpAndSettle();

      // Initially active item is index 0: SADP48 (Brass, 22 Gauge, 48) -> SADPB2248
      expect(find.text('SADPB2248'), findsWidgets);

      // Tap on row with SARP10 (row 2)
      final sarpCell = find.text('SARP10').first;
      await tester.ensureVisible(sarpCell);
      await tester.tap(sarpCell);
      await tester.pumpAndSettle();

      // Now SARPA1810 is the active item
      expect(find.text('SARPA1810'), findsWidgets);
    });

    testWidgets('Margin Health Indicator displays percentage and hovering reveals formula & highlights source cells', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 2200));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(const MaterialApp(home: PMItemMasterDetailScreen()));
      await tester.pumpAndSettle();

      // Find the Margin Health Indicator badge in Client / Vendor
      final indicator = find.byKey(const ValueKey('margin_health_indicator'));
      expect(indicator, findsOneWidget);
      await tester.ensureVisible(indicator);

      // Verify percentage is displayed
      expect(find.text('+28.0%'), findsOneWidget);
      expect(find.text('Margin'), findsWidgets);

      // Tap on indicator to toggle the breakdown popover
      await tester.tap(indicator);
      await tester.pumpAndSettle();

      // Formula breakdown is revealed in the popover
      expect(find.text('Margin Health Analysis'), findsOneWidget);
      expect(find.text('Margin % = [(Quotation - Total Cost) / Quotation] × 100'), findsOneWidget);
      expect(find.text('₹85000'), findsWidgets);
      expect(find.text('₹42500'), findsOneWidget);
      expect(find.text('₹18700'), findsOneWidget);
      expect(find.text('₹61200'), findsOneWidget);
      expect(find.text('₹23800'), findsOneWidget);

      // Tapping again hides the popover
      await tester.tap(indicator);
      await tester.pumpAndSettle();
      expect(find.text('Margin Health Analysis'), findsNothing);
    });
  });
}
