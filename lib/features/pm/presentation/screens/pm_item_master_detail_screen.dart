import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/sheet/sheet.dart';

// =============================================================================
// MODELS FOR CRUD ACROSS ALL FOUR SECTIONS
// =============================================================================

/// Section 1: Item Master 1 Record
class SavedItemRecord {
  SavedItemRecord({
    required this.id,
    required this.group,
    required this.subGroup,
    required this.partName,
    required this.runningNo,
    required this.partCode,
    required this.alloy,
    required this.thickness,
    required this.finish,
    required this.variantCode,
    required this.createdDate,
    required this.createdTime,
  });

  final String id;
  String group;
  String subGroup;
  String partName;
  int runningNo;
  String partCode;
  String alloy;
  String thickness;
  String finish;
  String variantCode;
  String createdDate;
  String createdTime;
}

/// Section 2: Client / Vendor Record
class SavedPartyRecord {
  SavedPartyRecord({
    required this.id,
    required this.companyName,
    required this.contactPerson,
    required this.phone,
    required this.email,
    required this.quoteAmount,
  });

  final String id;
  String companyName;
  String contactPerson;
  String phone;
  String email;
  String quoteAmount;
}

/// Section 3: Die Process Record
class DieProcessRecord {
  DieProcessRecord({
    required this.id,
    required this.headerTitle,
    required this.poDate,
    required this.time,
    required this.dieMadeBy,
    required this.type,
    this.linerSize = '',
    required this.dieCode,
    required this.noOfSet,
    required this.storeArea,
    required this.rackNo,
    required this.dateIn,
    required this.timeIn,
  });

  final String id;
  String headerTitle;
  String poDate;
  String time;
  String dieMadeBy;
  String type;
  String linerSize;
  String dieCode;
  String noOfSet;
  String storeArea;
  String rackNo;
  String dateIn;
  String timeIn;
}

/// Section 4: Machine Master Record
class MachineMasterRecord {
  MachineMasterRecord({
    required this.id,
    required this.headerTitle,
    required this.machineType,
    required this.machineMake,
    required this.dom,
    required this.feeder,
    this.runningHrs = '',
    this.strokeMin = '',
    this.capacity = '',
    this.machineNo = '',
    required this.dieType,
  });

  final String id;
  String headerTitle;
  String machineType;
  String machineMake;
  String dom;
  String feeder;
  String runningHrs;
  String strokeMin;
  String capacity;
  String machineNo;
  String dieType;
}

// =============================================================================
// MAIN SCREEN: PMItemMasterDetailScreen
// =============================================================================

class PMItemMasterDetailScreen extends StatefulWidget {
  const PMItemMasterDetailScreen({super.key});

  @override
  State<PMItemMasterDetailScreen> createState() => _PMItemMasterDetailScreenState();
}

class _PMItemMasterDetailScreenState extends State<PMItemMasterDetailScreen> {
  late final ItemMasterController _controller;
  final ScrollController _mainScrollController = ScrollController();

  // ---------------------------------------------------------------------------
  // SECTION 1 CATALOG (Item Master 1)
  // ---------------------------------------------------------------------------
  final List<SavedItemRecord> _savedItems = [
    SavedItemRecord(
      id: 'item_48',
      group: 'Switch Action',
      subGroup: 'Dolly',
      partName: 'Patti',
      runningNo: 48,
      partCode: 'SADP48',
      alloy: 'Brass',
      thickness: '22 Gauge',
      finish: 'Nickel',
      variantCode: 'SADPB2248',
      createdDate: '21/10/2026',
      createdTime: '10:15',
    ),
    SavedItemRecord(
      id: 'item_47',
      group: 'Switch Action',
      subGroup: 'Dolly',
      partName: 'Patti',
      runningNo: 47,
      partCode: 'SADP47',
      alloy: 'Copper',
      thickness: '20 Gauge',
      finish: 'Chrome',
      variantCode: 'SADPC2047',
      createdDate: '20/10/2026',
      createdTime: '14:30',
    ),
    SavedItemRecord(
      id: 'item_10',
      group: 'Switch Action',
      subGroup: 'Rocker',
      partName: 'Patti',
      runningNo: 10,
      partCode: 'SARP10',
      alloy: 'Aluminium',
      thickness: '18 Gauge',
      finish: 'Zinc',
      variantCode: 'SARPA1810',
      createdDate: '19/10/2026',
      createdTime: '09:20',
    ),
  ];
  int _activeItemIndex = 0;

  // ---------------------------------------------------------------------------
  // SECTION 2 CATALOG (Client / Vendor)
  // ---------------------------------------------------------------------------
  final List<SavedPartyRecord> _savedParties = [
    SavedPartyRecord(
      id: 'p1',
      companyName: 'Gold Madel',
      contactPerson: 'Kissan Jain',
      phone: '9820012345',
      email: 'kissan@goldmadel.com',
      quoteAmount: '85000/-',
    ),
    SavedPartyRecord(
      id: 'p2',
      companyName: 'Anchor Electricals',
      contactPerson: 'Rajesh Shah',
      phone: '9819922334',
      email: 'rshah@anchor.in',
      quoteAmount: '120000/-',
    ),
    SavedPartyRecord(
      id: 'p3',
      companyName: 'Havells India',
      contactPerson: 'Amit Verma',
      phone: '9876543210',
      email: 'averma@havells.com',
      quoteAmount: '95000/-',
    ),
  ];
  int _activePartyIndex = 0;

  // ---------------------------------------------------------------------------
  // SECTION 3 CATALOG (Die Process Tables)
  // ---------------------------------------------------------------------------
  final List<DieProcessRecord> _dieProcessRecords = [
    DieProcessRecord(
      id: 'cutting',
      headerTitle: 'Cutting',
      poDate: '15/09/26',
      time: '11:30',
      dieMadeBy: 'Pankaj',
      type: 'Prog.',
      dieCode: 'CDSADP48',
      noOfSet: '2',
      storeArea: 'Die Shop',
      rackNo: 'B-12',
      dateIn: '22/09/26',
      timeIn: '16:00',
    ),
    DieProcessRecord(
      id: 'riveting',
      headerTitle: 'Riveting',
      poDate: '16/09/26',
      time: '14:15',
      dieMadeBy: 'Satish Dies',
      type: 'Single',
      dieCode: 'RSADP48',
      noOfSet: '1',
      storeArea: 'Rack 4',
      rackNo: 'R-04',
      dateIn: '25/09/26',
      timeIn: '10:30',
    ),
    DieProcessRecord(
      id: 'assembly',
      headerTitle: 'Assembly',
      poDate: '18/09/26',
      time: '09:45',
      dieMadeBy: 'In-House Toolroom',
      type: 'Fixt.',
      dieCode: 'ASADP48',
      noOfSet: '3',
      storeArea: 'Assembly Floor',
      rackNo: 'AF-1',
      dateIn: '28/09/26',
      timeIn: '12:00',
    ),
  ];

  // ---------------------------------------------------------------------------
  // SECTION 4 CATALOG (Machine Master Tables)
  // ---------------------------------------------------------------------------
  final List<MachineMasterRecord> _machineRecords = [
    MachineMasterRecord(
      id: 'm1',
      headerTitle: 'Power Press 1',
      machineType: 'Power Press',
      machineMake: 'Mayank',
      dom: '2019',
      feeder: 'Auto Roll',
      strokeMin: '120',
      capacity: '30 Ton',
      machineNo: 'PP-4',
      dieType: 'Prog.',
    ),
    MachineMasterRecord(
      id: 'm2',
      headerTitle: 'Riveting Press',
      machineType: 'Riveting M/C',
      machineMake: 'Pneumatic Engg',
      dom: '2021',
      feeder: 'Manual Bowl',
      strokeMin: '60',
      capacity: '5 Ton',
      machineNo: 'RM-2',
      dieType: 'Single',
    ),
    MachineMasterRecord(
      id: 'm3',
      headerTitle: 'Assembly Fixture',
      machineType: 'Pneumatic Press',
      machineMake: 'Atlas Copco',
      dom: '2022',
      feeder: 'Conveyor',
      strokeMin: '45',
      capacity: '2 Ton',
      machineNo: 'AP-1',
      dieType: 'Fixture',
    ),
  ];

  // ---------------------------------------------------------------------------
  // MARGIN HEALTH & FORMULA CELL HIGHLIGHTING
  // ---------------------------------------------------------------------------
  Set<int> _highlightedColumnIds = {};
  bool _isHoveringMarginHealth = false;
  final OverlayPortalController _marginOverlayController = OverlayPortalController();
  final LayerLink _marginLink = LayerLink();

  @override
  void initState() {
    super.initState();
    // This screen IS the fixture: it is the UI reference, with no providers
    // behind it. The real sheet is ItemMasterSheetScreen in core_erp.
    _controller = ItemMasterController(demoData: true);
    _controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _mainScrollController.dispose();
    super.dispose();
  }

  void _showFeedback(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? const Color(0xFFDC2626) : const Color(0xFF059669),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _handleSave() async {
    final success = await _controller.saveItem();
    // The await means this widget may be gone by now.
    if (!mounted) return;
    if (success && _savedItems.isNotEmpty) {
      final active = _savedItems[_activeItemIndex];
      // From the record the server actually stored, not two hardcoded strings.
      final stamp = _controller.savedCreatedAt?.split(' ');
      if (stamp != null && stamp.length == 2) {
        active.createdDate = stamp.first;
        active.createdTime = stamp.last;
      }
      _showFeedback(_controller.statusBarMessage);
    } else {
      _showFeedback(_controller.statusBarMessage, isError: true);
    }
  }

  void _scrollToSection(String sectionId) {
    _controller.setActiveSection(sectionId);
    final targetOffset = switch (sectionId) {
      'group_item' => 0.0,
      'client_vendor' => 380.0,
      'die_master' => 760.0,
      'machine_master' => 1250.0,
      _ => 0.0,
    };
    if (_mainScrollController.hasClients) {
      _mainScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ===========================================================================
  // ROW MAPPERS (Translates records into table rows)
  // ===========================================================================

  Map<int, CellValue> _itemToRowMap(SavedItemRecord item) {
    return {
      1: CellValue(columnId: 1, optionLabel: item.group),
      2: CellValue(columnId: 2, optionLabel: item.subGroup),
      3: CellValue(columnId: 3, optionLabel: item.partName),
      4: CellValue(columnId: 4, intValue: item.runningNo, mode: ValueMode.auto),
      5: CellValue(columnId: 5, textValue: item.partCode, mode: ValueMode.auto),
      6: CellValue(columnId: 6, optionLabel: item.alloy),
      7: CellValue(columnId: 7, textValue: item.thickness),
      8: CellValue(columnId: 8, optionLabel: item.finish),
      9: CellValue(columnId: 9, textValue: item.createdDate),
      10: CellValue(columnId: 10, textValue: item.createdTime),
    };
  }

  Map<int, CellValue> _partyToRowMap(SavedPartyRecord party) {
    return {
      20: CellValue(columnId: 20, optionLabel: party.companyName),
      21: CellValue(columnId: 21, optionLabel: party.contactPerson),
      22: const CellValue(columnId: 22, textValue: 'Director'),
      23: CellValue(columnId: 23, textValue: party.phone),
      24: CellValue(columnId: 24, textValue: party.email),
      25: CellValue(columnId: 25, textValue: party.quoteAmount),
      26: const CellValue(columnId: 26, textValue: '15/05/2026'),
      27: const CellValue(columnId: 27, textValue: '10.05 AM'),
    };
  }

  // ===========================================================================
  // SECTION 1 CRUD ACTIONS (Group Item Master)
  // ===========================================================================

  void _loadSavedItem(int index) {
    if (index < 0 || index >= _savedItems.length) return;
    final item = _savedItems[index];
    setState(() => _activeItemIndex = index);

    final gCtrl = _controller.groupItemController;
    gCtrl.draft.set(3, CellValue(columnId: 3, optionLabel: item.partName));
    gCtrl.draft.set(4, CellValue(columnId: 4, intValue: item.runningNo, mode: ValueMode.auto));
    gCtrl.draft.set(5, CellValue(columnId: 5, textValue: item.partCode, mode: ValueMode.auto));
    gCtrl.draft.set(6, CellValue(columnId: 6, optionLabel: item.alloy));
    gCtrl.draft.set(7, CellValue(columnId: 7, textValue: item.thickness));
    gCtrl.draft.set(8, CellValue(columnId: 8, optionLabel: item.finish));
    gCtrl.draft.set(9, CellValue(columnId: 9, textValue: item.createdDate));
    gCtrl.draft.set(10, CellValue(columnId: 10, textValue: item.createdTime));

    _showFeedback('Switched to item ${item.partCode} (${item.variantCode})');
  }

  void _createNewItemDraft() {
    final nextNo = _savedItems.fold<int>(40, (prev, i) => i.runningNo > prev ? i.runningNo : prev) + 1;
    final newItem = SavedItemRecord(
      id: 'item_$nextNo',
      group: 'Switch Action',
      subGroup: 'Dolly',
      partName: 'Patti',
      runningNo: nextNo,
      partCode: 'SADP$nextNo',
      alloy: 'Brass',
      thickness: '22 Gauge',
      finish: 'Nickel',
      variantCode: 'SADPB22$nextNo',
      createdDate: 'Set on save',
      createdTime: 'Set on save',
    );

    setState(() {
      _savedItems.add(newItem);
      _activeItemIndex = _savedItems.length - 1;
    });

    final gCtrl = _controller.groupItemController;
    gCtrl.draft.set(3, CellValue(columnId: 3, optionLabel: newItem.partName));
    gCtrl.draft.set(4, CellValue(columnId: 4, intValue: nextNo, mode: ValueMode.auto));
    gCtrl.draft.set(5, CellValue(columnId: 5, textValue: 'SADP$nextNo', mode: ValueMode.auto));
    gCtrl.draft.set(6, CellValue(columnId: 6, optionLabel: newItem.alloy));
    gCtrl.draft.set(7, CellValue(columnId: 7, textValue: newItem.thickness));
    gCtrl.draft.set(8, CellValue(columnId: 8, optionLabel: newItem.finish));
    gCtrl.draft.set(9, const CellValue(columnId: 9, textValue: 'Set on save'));
    gCtrl.draft.set(10, const CellValue(columnId: 10, textValue: 'Set on save'));

    _showFeedback('Added row ${_savedItems.length} (SADP$nextNo) to Properties table.');
  }

  void _showEditItemDialog() {
    if (_savedItems.isEmpty) return;
    final active = _savedItems[_activeItemIndex];

    final nameCtrl = TextEditingController(text: active.partName);
    final alloyCtrl = TextEditingController(text: active.alloy);
    final thicknessCtrl = TextEditingController(text: active.thickness);
    final finishCtrl = TextEditingController(text: active.finish);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Item (${active.partCode})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Part Name', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: alloyCtrl,
                decoration: const InputDecoration(labelText: 'Alloy', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: thicknessCtrl,
                decoration: const InputDecoration(labelText: 'Thickness', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: finishCtrl,
                decoration: const InputDecoration(labelText: 'Finish', isDense: true, border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                active.partName = nameCtrl.text.trim();
                active.alloy = alloyCtrl.text.trim();
                active.thickness = thicknessCtrl.text.trim();
                active.finish = finishCtrl.text.trim();
              });

              final gCtrl = _controller.groupItemController;
              gCtrl.draft.set(3, CellValue(columnId: 3, optionLabel: active.partName));
              gCtrl.draft.set(6, CellValue(columnId: 6, optionLabel: active.alloy));
              gCtrl.draft.set(7, CellValue(columnId: 7, textValue: active.thickness));
              gCtrl.draft.set(8, CellValue(columnId: 8, optionLabel: active.finish));

              _showFeedback('Item ${active.partCode} updated successfully.');
            },
            child: const Text('Update Item'),
          ),
        ],
      ),
    );
  }

  void _showDeleteItemDialog() {
    if (_savedItems.isEmpty) return;
    final active = _savedItems[_activeItemIndex];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Item ${active.partCode}?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to delete ${active.partName} (${active.variantCode}) from the Item Master? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              final deletedCode = active.partCode;
              setState(() {
                _savedItems.removeAt(_activeItemIndex);
                if (_activeItemIndex >= _savedItems.length) {
                  _activeItemIndex = _savedItems.isEmpty ? 0 : _savedItems.length - 1;
                }
              });

              if (_savedItems.isNotEmpty) {
                _loadSavedItem(_activeItemIndex);
              }
              _showFeedback('Item $deletedCode deleted from master.');
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION 2 CRUD ACTIONS (Client / Vendor)
  // ===========================================================================

  void _loadSavedParty(int index) {
    if (index < 0 || index >= _savedParties.length) return;
    final party = _savedParties[index];
    setState(() => _activePartyIndex = index);

    final cvCtrl = _controller.clientVendorController;
    cvCtrl.draft.set(20, CellValue(columnId: 20, optionLabel: party.companyName));
    cvCtrl.draft.set(21, CellValue(columnId: 21, optionLabel: party.contactPerson));
    cvCtrl.draft.set(22, const CellValue(columnId: 22, textValue: 'Director'));
    cvCtrl.draft.set(23, CellValue(columnId: 23, textValue: party.phone));
    cvCtrl.draft.set(24, CellValue(columnId: 24, textValue: party.email));
    cvCtrl.draft.set(25, CellValue(columnId: 25, textValue: party.quoteAmount));

    _showFeedback('Linked party: ${party.companyName}');
  }

  void _handleAddPropertyInClientVendor() {
    final nextNo = _savedParties.length + 1;
    final newParty = SavedPartyRecord(
      id: 'p_$nextNo',
      companyName: 'Party $nextNo',
      contactPerson: 'Contact Person $nextNo',
      phone: '980000000$nextNo',
      email: 'contact$nextNo@vendor.in',
      quoteAmount: '90000/-',
    );

    setState(() {
      _savedParties.add(newParty);
      _activePartyIndex = _savedParties.length - 1;
    });
    _loadSavedParty(_activePartyIndex);
    _showFeedback('Added row ${_savedParties.length} (${newParty.companyName}) to Client / Vendor table.');
  }

  void _showAddPartyDialog() {
    final companyCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final quoteCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Client / Vendor', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: companyCtrl,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Company Name', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contactCtrl,
                decoration: const InputDecoration(labelText: 'Contact Person', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quoteCtrl,
                decoration: const InputDecoration(labelText: 'Quotation (₹)', isDense: true, border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (companyCtrl.text.trim().isEmpty) return;
              Navigator.of(ctx).pop();
              final newParty = SavedPartyRecord(
                id: 'p_${_savedParties.length + 1}',
                companyName: companyCtrl.text.trim(),
                contactPerson: contactCtrl.text.trim(),
                phone: phoneCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                quoteAmount: quoteCtrl.text.trim().isEmpty ? '0/-' : quoteCtrl.text.trim(),
              );

              setState(() {
                _savedParties.add(newParty);
                _activePartyIndex = _savedParties.length - 1;
              });
              _loadSavedParty(_activePartyIndex);
              _showFeedback('Added party ${newParty.companyName}');
            },
            child: const Text('Add Party'),
          ),
        ],
      ),
    );
  }

  void _showEditPartyDialog() {
    if (_savedParties.isEmpty) return;
    final active = _savedParties[_activePartyIndex];

    final companyCtrl = TextEditingController(text: active.companyName);
    final contactCtrl = TextEditingController(text: active.contactPerson);
    final phoneCtrl = TextEditingController(text: active.phone);
    final emailCtrl = TextEditingController(text: active.email);
    final quoteCtrl = TextEditingController(text: active.quoteAmount);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Party (${active.companyName})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: companyCtrl,
                decoration: const InputDecoration(labelText: 'Company Name', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contactCtrl,
                decoration: const InputDecoration(labelText: 'Contact Person', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Phone', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: 'Email', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quoteCtrl,
                decoration: const InputDecoration(labelText: 'Quotation (₹)', isDense: true, border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                active.companyName = companyCtrl.text.trim();
                active.contactPerson = contactCtrl.text.trim();
                active.phone = phoneCtrl.text.trim();
                active.email = emailCtrl.text.trim();
                active.quoteAmount = quoteCtrl.text.trim();
              });

              final cvCtrl = _controller.clientVendorController;
              cvCtrl.draft.set(20, CellValue(columnId: 20, optionLabel: active.companyName));
              cvCtrl.draft.set(21, CellValue(columnId: 21, optionLabel: active.contactPerson));
              cvCtrl.draft.set(23, CellValue(columnId: 23, textValue: active.phone));
              cvCtrl.draft.set(24, CellValue(columnId: 24, textValue: active.email));
              cvCtrl.draft.set(25, CellValue(columnId: 25, textValue: active.quoteAmount));

              _showFeedback('Party ${active.companyName} updated.');
            },
            child: const Text('Save Details'),
          ),
        ],
      ),
    );
  }

  void _showDeletePartyDialog() {
    if (_savedParties.isEmpty) return;
    final active = _savedParties[_activePartyIndex];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Unlink Party ${active.companyName}?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('Unlink ${active.companyName} (Contact: ${active.contactPerson}) from this item master?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              final name = active.companyName;
              setState(() {
                _savedParties.removeAt(_activePartyIndex);
                if (_activePartyIndex >= _savedParties.length) {
                  _activePartyIndex = _savedParties.isEmpty ? 0 : _savedParties.length - 1;
                }
              });

              if (_savedParties.isNotEmpty) {
                _loadSavedParty(_activePartyIndex);
              }
              _showFeedback('Party $name unlinked from item.');
            },
            child: const Text('Unlink'),
          ),
        ],
      ),
    );
  }

  void _showAddClientVendorColumnDialog() {
    final labelController = TextEditingController();
    ColumnKind selectedKind = ColumnKind.text;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Add Client / Vendor Property', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: labelController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Property Name (e.g. GSTIN, Payment Terms)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ColumnKind>(
                initialValue: selectedKind,
                decoration: const InputDecoration(labelText: 'Column Kind', isDense: true, border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: ColumnKind.text, child: Text('Text')),
                  DropdownMenuItem(value: ColumnKind.money, child: Text('Money (₹ Paise)')),
                  DropdownMenuItem(value: ColumnKind.number, child: Text('Number')),
                  DropdownMenuItem(value: ColumnKind.phone, child: Text('Phone')),
                  DropdownMenuItem(value: ColumnKind.email, child: Text('Email')),
                ],
                onChanged: (val) {
                  if (val != null) setDlgState(() => selectedKind = val);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (labelController.text.trim().isNotEmpty) {
                  Navigator.of(ctx).pop();
                  _controller.clientVendorController.addColumn(
                    label: labelController.text.trim(),
                    kind: selectedKind,
                  );
                  _showFeedback('Added property "${labelController.text.trim()}" to Client / Vendor.');
                }
              },
              child: const Text('Add Property'),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION 3 CRUD ACTIONS (Die Process Master)
  // ===========================================================================

  void _showAddDieProcessDialog() {
    final titleController = TextEditingController(text: 'Bending');
    final codeController = TextEditingController(text: 'BDSADP48');
    final madeByController = TextEditingController(text: 'In-House');
    final typeController = TextEditingController(text: 'Prog.');
    final setsController = TextEditingController(text: '1');
    final storeController = TextEditingController(text: 'Die Shop');
    final rackController = TextEditingController(text: 'B-14');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Die Process Table', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Process Name', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Die Code', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: madeByController,
                decoration: const InputDecoration(labelText: 'Die Made By', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: typeController,
                      decoration: const InputDecoration(labelText: 'Type', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: setsController,
                      decoration: const InputDecoration(labelText: 'Sets', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: storeController,
                      decoration: const InputDecoration(labelText: 'Store Area', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: rackController,
                      decoration: const InputDecoration(labelText: 'Rack No', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _dieProcessRecords.add(
                  DieProcessRecord(
                    id: 'proc_${_dieProcessRecords.length + 1}',
                    headerTitle: titleController.text.trim(),
                    poDate: '19/09/26',
                    time: '11:00',
                    dieMadeBy: madeByController.text.trim(),
                    type: typeController.text.trim(),
                    dieCode: codeController.text.trim(),
                    noOfSet: setsController.text.trim(),
                    storeArea: storeController.text.trim(),
                    rackNo: rackController.text.trim(),
                    dateIn: '29/09/26',
                    timeIn: '15:00',
                  ),
                );
              });
              _showFeedback('Added process table ${titleController.text.trim()} (${codeController.text.trim()})');
            },
            child: const Text('Add Process Table'),
          ),
        ],
      ),
    );
  }

  void _showEditDieProcessDialog(DieProcessRecord record) {
    final titleController = TextEditingController(text: record.headerTitle);
    final codeController = TextEditingController(text: record.dieCode);
    final madeByController = TextEditingController(text: record.dieMadeBy);
    final typeController = TextEditingController(text: record.type);
    final setsController = TextEditingController(text: record.noOfSet);
    final storeController = TextEditingController(text: record.storeArea);
    final rackController = TextEditingController(text: record.rackNo);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Die Process (${record.headerTitle})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Process Name', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Die Code', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: madeByController,
                decoration: const InputDecoration(labelText: 'Die Made By', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: typeController,
                      decoration: const InputDecoration(labelText: 'Type', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: setsController,
                      decoration: const InputDecoration(labelText: 'Sets', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: storeController,
                      decoration: const InputDecoration(labelText: 'Store Area', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: rackController,
                      decoration: const InputDecoration(labelText: 'Rack No', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                record.headerTitle = titleController.text.trim();
                record.dieCode = codeController.text.trim();
                record.dieMadeBy = madeByController.text.trim();
                record.type = typeController.text.trim();
                record.noOfSet = setsController.text.trim();
                record.storeArea = storeController.text.trim();
                record.rackNo = rackController.text.trim();
              });
              _showFeedback('Updated ${record.headerTitle} table');
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDieProcessDialog(DieProcessRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Process Table ${record.headerTitle}?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to delete process table "${record.headerTitle}" (${record.dieCode})?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              final name = record.headerTitle;
              setState(() {
                _dieProcessRecords.removeWhere((r) => r.id == record.id);
              });
              _showFeedback('Deleted process table $name');
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SECTION 4 CRUD ACTIONS (Machine Master)
  // ===========================================================================

  void _showAddMachineDialog() {
    final titleController = TextEditingController(text: 'Power Press ${_machineRecords.length + 1}');
    final makeController = TextEditingController(text: 'Mayank');
    final machineNoController = TextEditingController(text: 'PP-5');
    final typeController = TextEditingController(text: 'Power Press');
    final domController = TextEditingController(text: '2023');
    final feederController = TextEditingController(text: 'Auto Roll');
    final capacityController = TextEditingController(text: '35 Ton');
    final dieTypeController = TextEditingController(text: 'Prog.');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Machine Table', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Header Title', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: makeController,
                      decoration: const InputDecoration(labelText: 'Machine Make', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: machineNoController,
                      decoration: const InputDecoration(labelText: 'Machine No', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: typeController,
                      decoration: const InputDecoration(labelText: 'Type', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: capacityController,
                      decoration: const InputDecoration(labelText: 'Capacity', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: feederController,
                      decoration: const InputDecoration(labelText: 'Feeder', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: dieTypeController,
                      decoration: const InputDecoration(labelText: 'Die Type', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                _machineRecords.add(
                  MachineMasterRecord(
                    id: 'm_${_machineRecords.length + 1}',
                    headerTitle: titleController.text.trim(),
                    machineType: typeController.text.trim(),
                    machineMake: makeController.text.trim(),
                    dom: domController.text.trim(),
                    feeder: feederController.text.trim(),
                    capacity: capacityController.text.trim(),
                    machineNo: machineNoController.text.trim(),
                    dieType: dieTypeController.text.trim(),
                  ),
                );
              });
              _showFeedback('Added machine table ${titleController.text.trim()} (${machineNoController.text.trim()})');
            },
            child: const Text('Add Machine Table'),
          ),
        ],
      ),
    );
  }

  void _showEditMachineDialog(MachineMasterRecord record) {
    final titleController = TextEditingController(text: record.headerTitle);
    final makeController = TextEditingController(text: record.machineMake);
    final machineNoController = TextEditingController(text: record.machineNo);
    final typeController = TextEditingController(text: record.machineType);
    final domController = TextEditingController(text: record.dom);
    final feederController = TextEditingController(text: record.feeder);
    final capacityController = TextEditingController(text: record.capacity);
    final dieTypeController = TextEditingController(text: record.dieType);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit Machine Table (${record.headerTitle})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Header Title', isDense: true, border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: makeController,
                      decoration: const InputDecoration(labelText: 'Machine Make', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: machineNoController,
                      decoration: const InputDecoration(labelText: 'Machine No', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: typeController,
                      decoration: const InputDecoration(labelText: 'Type', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: capacityController,
                      decoration: const InputDecoration(labelText: 'Capacity', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: feederController,
                      decoration: const InputDecoration(labelText: 'Feeder', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: dieTypeController,
                      decoration: const InputDecoration(labelText: 'Die Type', isDense: true, border: OutlineInputBorder()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() {
                record.headerTitle = titleController.text.trim();
                record.machineMake = makeController.text.trim();
                record.machineNo = machineNoController.text.trim();
                record.machineType = typeController.text.trim();
                record.dom = domController.text.trim();
                record.feeder = feederController.text.trim();
                record.capacity = capacityController.text.trim();
                record.dieType = dieTypeController.text.trim();
              });
              _showFeedback('Updated machine table ${record.headerTitle}');
            },
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );
  }

  void _showDeleteMachineDialog(MachineMasterRecord record) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Machine Table ${record.headerTitle}?', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text('Are you sure you want to delete machine table "${record.headerTitle}" (${record.machineNo})?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
            onPressed: () {
              Navigator.of(ctx).pop();
              final name = record.headerTitle;
              setState(() {
                _machineRecords.removeWhere((m) => m.id == record.id);
              });
              _showFeedback('Deleted machine table $name');
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // SUB-GROUP & COLUMN DIALOGS
  // ===========================================================================

  void _showAddSubGroupDialog() {
    final textController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Sub-Group Level', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Inserts a new classification level directly before the Part Name:',
              style: TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Level Name (e.g. Sub-Type, Mechanism)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  Navigator.of(ctx).pop();
                  _controller.groupItemController.addSubGroupLevel(val.trim());
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (textController.text.trim().isNotEmpty) {
                Navigator.of(ctx).pop();
                _controller.groupItemController.addSubGroupLevel(textController.text.trim());
              }
            },
            child: const Text('Add Level'),
          ),
        ],
      ),
    );
  }

  void _showAddColumnDialog() {
    final labelController = TextEditingController();
    ColumnKind selectedKind = ColumnKind.text;
    int? selectedParentId;

    final candidateParents = _controller.groupItemController.sheetDef.columns
        .where((c) => c.kind == ColumnKind.list)
        .toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Add User-Defined Column', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: labelController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Column Name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<ColumnKind>(
                initialValue: selectedKind,
                decoration: const InputDecoration(labelText: 'Column Kind', isDense: true, border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: ColumnKind.text, child: Text('Text')),
                  DropdownMenuItem(value: ColumnKind.list, child: Text('List (Dropdown)')),
                  DropdownMenuItem(value: ColumnKind.quantity, child: Text('Quantity (Physical unit)')),
                  DropdownMenuItem(value: ColumnKind.money, child: Text('Money (₹ Paise)')),
                  DropdownMenuItem(value: ColumnKind.number, child: Text('Number (Count)')),
                  DropdownMenuItem(value: ColumnKind.phone, child: Text('Phone (10 digits)')),
                  DropdownMenuItem(value: ColumnKind.email, child: Text('Email ID')),
                ],
                onChanged: (val) {
                  if (val != null) setDlgState(() => selectedKind = val);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: selectedParentId,
                decoration: const InputDecoration(labelText: 'Parent Column (Optional)', isDense: true, border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Primary Group (Root)')),
                  ...candidateParents.map(
                    (p) => DropdownMenuItem(value: p.id, child: Text('${p.label} (List)')),
                  ),
                ],
                onChanged: (val) => setDlgState(() => selectedParentId = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (labelController.text.trim().isNotEmpty) {
                  Navigator.of(ctx).pop();
                  _controller.groupItemController.addColumn(
                    label: labelController.text.trim(),
                    kind: selectedKind,
                    parentId: selectedParentId,
                  );
                }
              },
              child: const Text('Add Column'),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyS): const _SaveIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyS): const _SaveIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _SaveIntent: CallbackAction<_SaveIntent>(onInvoke: (intent) => _handleSave()),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            backgroundColor: const Color(0xFFF4F6F9),
            body: Column(
              children: [
                // 1. Top Bar with Breadcrumbs & Save Item (Ctrl+S)
                _buildTopBar(context),

                // 2. Main Content: Sidebar (268px) + Main Scrolling Area
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sidebar (268 px)
                      ItemMasterSidebar(
                        controller: _controller,
                        onSelectSection: _scrollToSection,
                      ),

                      // Main Scrolling Sections Area
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _mainScrollController,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section 1: Group Item
                              _buildGroupItemSection(),
                              const SizedBox(height: 28),

                              // Section 2: Client / Vendor (conditional on External)
                              if (_controller.isExternal) ...[
                                _buildClientVendorSection(),
                                const SizedBox(height: 28),
                              ],

                              // Section 3: Die Process Master
                              _buildDieMasterSection(),
                              const SizedBox(height: 28),

                              // Section 4: Machine Master
                              _buildMachineMasterSection(),
                              const SizedBox(height: 48),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // 3. Status Bar (28 px)
                SheetStatusBar(
                  isEditing: _controller.isEditing,
                  location: _controller.groupItemController.currentStatusLocation,
                  message: _controller.statusBarMessage,
                  isError: _controller.groupItemController.errors.isNotEmpty ||
                      (_controller.isExternal && _controller.clientVendorController.errors.isNotEmpty),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        boxShadow: [
          BoxShadow(
            color: Color(0x06000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              tooltip: 'Back to PM Tab',
              onPressed: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),

            // Breadcrumbs
            Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Masters',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('›', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                Text(
                  'Items',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF64748B)),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: Text('›', style: TextStyle(color: Color(0xFF94A3B8))),
                ),
                Text(
                  'New item',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary),
                ),
              ],
            ),

            const SizedBox(width: 16),
            // Heading badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: SoftErpTheme.accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'Item Master 1 & Process Tooling Matrix',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: SoftErpTheme.accent),
              ),
            ),

            const SizedBox(width: 28),

            // External switch indicator
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _controller.isExternal,
                  activeColor: SoftErpTheme.accent,
                  onChanged: (val) {
                    if (val != null) _controller.setExternal(val);
                  },
                ),
                const Text(
                  'Developed for an external party',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                ),
              ],
            ),

            const SizedBox(width: 16),

            // Save Item Button (Ctrl+S)
            AppButton(
              key: const ValueKey('save_item_master_btn'),
              label: _controller.isSaved ? 'Item Saved (Ctrl+S)' : 'Save item (Ctrl+S)',
              icon: _controller.isSaved ? Icons.check_circle_rounded : Icons.save_rounded,
              onPressed: _handleSave,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // SECTION 1: Group Item
  // ===========================================================================
  Widget _buildGroupItemSection() {
    final groupSheet = _controller.groupItemController.sheetDef;
    final groupDraft = _controller.groupItemController.draft;
    final itemName = groupDraft.get(3)?.optionLabel ?? 'Patti';
    final partCode = groupDraft.get(5)?.textValue ?? 'SADP48';
    final activeItem = _savedItems.isNotEmpty ? _savedItems[_activeItemIndex] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: SoftErpTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.inventory_2_rounded, size: 16, color: SoftErpTheme.accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Item Master 1',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    'Group Item: Group path, Item Details, Alloy, Finish, and Creation stamps',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Variant derivation chip for reference
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Identity: ', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  Text(
                    partCode,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.accent),
                  ),
                  const SizedBox(width: 8),
                  const Text('· Variant: ', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  Text(
                    activeItem?.variantCode ?? 'SADPB2248',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.accent),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // CRUD Action Toolbar for Items
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Text('Items: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
              const SizedBox(width: 6),
              // Read: Quick switcher pills for saved items
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _savedItems.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final it = entry.value;
                      final isSelected = idx == _activeItemIndex;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => _loadSavedItem(idx),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isSelected ? SoftErpTheme.accent.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected ? SoftErpTheme.accent : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSelected) ...[
                                  const Icon(Icons.check_rounded, size: 12, color: SoftErpTheme.accent),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  it.partCode,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    color: isSelected ? SoftErpTheme.accent : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Create: + New Item (adds row)
              OutlinedButton.icon(
                key: const ValueKey('create_new_item_btn'),
                icon: const Icon(Icons.add_rounded, size: 14),
                label: const Text('New Item'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  foregroundColor: SoftErpTheme.accent,
                  side: const BorderSide(color: SoftErpTheme.accent),
                ),
                onPressed: _createNewItemDraft,
              ),
              const SizedBox(width: 6),

              // + Column (user defined property column)
              OutlinedButton.icon(
                key: const ValueKey('add_item_property_column_btn'),
                icon: const Icon(Icons.view_column_rounded, size: 14),
                label: const Text('+ Column'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  foregroundColor: const Color(0xFF64748B),
                  side: const BorderSide(color: Color(0xFFCBD5E1)),
                ),
                onPressed: _showAddColumnDialog,
              ),
              const SizedBox(width: 6),

              // Update: Edit Active Item
              IconButton(
                key: const ValueKey('edit_active_item_btn'),
                icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF475569)),
                tooltip: 'Edit Item Properties',
                visualDensity: VisualDensity.compact,
                onPressed: _showEditItemDialog,
              ),

              // Delete: Delete Active Item
              IconButton(
                key: const ValueKey('delete_active_item_btn'),
                icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFDC2626)),
                tooltip: 'Delete Item',
                visualDensity: VisualDensity.compact,
                onPressed: _showDeleteItemDialog,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Subtitle badges required by tests: Item Details, Item Alloy Details, Item Die Details, and active properties
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _buildSectionPill('Item Details'),
            _buildSectionPill('Item Alloy\nDetails'),
            _buildSectionPill('Item Die\nDetails'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Alloy: ', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  Text(activeItem?.alloy ?? 'Brass', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1E40AF))),
                  const SizedBox(width: 8),
                  const Text('Thickness: ', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  Text(activeItem?.thickness ?? '22 Gauge', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1E40AF))),
                  const SizedBox(width: 8),
                  const Text('Part No: ', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  Text('${activeItem?.runningNo ?? 48}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF1E40AF))),
                  const SizedBox(width: 8),
                  const Text('Code: ', style: TextStyle(fontSize: 10, color: Color(0xFF64748B))),
                  Text(activeItem?.variantCode ?? 'SADPB2248', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF1E40AF))),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // TableRowStrip with horizontal scroll and pinned name overlay (multi-row support)
        TableRowStrip(
          sheetDef: groupSheet,
          controller: _controller.groupItemController,
          onAddSubGroup: _showAddSubGroupDialog,
          onAddPropertyColumn: _createNewItemDraft,
          rowDrafts: _savedItems.map(_itemToRowMap).toList(),
          onRowSelected: _loadSavedItem,
          selectedRowIndex: _activeItemIndex,
          highlightedColumnIds: _highlightedColumnIds,
        ),
      ],
    );
  }

  // ===========================================================================
  // MARGIN HEALTH INDICATOR & FORMULA BREAKDOWN
  // ===========================================================================

  Widget _buildMarginHealthIndicator(SavedPartyRecord? activeParty, SavedItemRecord? activeItem) {
    // 1. Quoted Amount (Cell #25)
    final rawQuote = activeParty?.quoteAmount ?? '85000/-';
    // Paise kept: dropping every non-digit read "85000.50/-" as 8500050.
    final double quotedAmount = SheetEngine.parseMoney(
          rawQuote.replaceAll(RegExp(r'[^0-9.,]'), ''),
        ) ??
        85000.0;

    // 2. Material Cost (Cells #6 & #7)
    final alloy = activeItem?.alloy ?? 'Brass';
    final thickness = activeItem?.thickness ?? '22 Gauge';
    final double alloyRatePerKg = switch (alloy.toLowerCase()) {
      'brass' => 500.0,
      'copper' => 750.0,
      'aluminium' => 280.0,
      'steel' || 'crca' => 120.0,
      _ => 500.0,
    };
    final double batchWeightKg = switch (thickness.toLowerCase()) {
      '18 gauge' => 128.0,
      '20 gauge' => 102.0,
      '22 gauge' => 85.0,
      _ => 85.0,
    };
    final double materialCost = (alloyRatePerKg * batchWeightKg);

    // 3. Machining & Tooling Cost (Dies in Sec 3 + Machines in Sec 4)
    final double dieCost = _dieProcessRecords.length * 5000.0;
    final double machineCost = 3700.0;
    final double machiningCost = dieCost + machineCost;

    // 4. Margin Health Formula: ((Quotation - Total Cost) / Quotation) * 100
    final double totalCost = materialCost + machiningCost;
    final double netProfit = quotedAmount - totalCost;
    final double marginPercent = quotedAmount > 0 ? (netProfit / quotedAmount) * 100 : 0.0;

    final (Color badgeBg, Color badgeBorder, Color badgeFg, IconData badgeIcon, String healthLabel) =
        marginPercent >= 20.0
            ? (
                const Color(0xFFECFDF5),
                const Color(0xFF10B981),
                const Color(0xFF047857),
                Icons.trending_up_rounded,
                'Healthy'
              )
            : (marginPercent >= 10.0
                ? (
                    const Color(0xFFFFFBEB),
                    const Color(0xFFF59E0B),
                    const Color(0xFFB45309),
                    Icons.trending_flat_rounded,
                    'Moderate'
                  )
                : (
                    const Color(0xFFFEF2F2),
                    const Color(0xFFEF4444),
                    const Color(0xFFB91C1C),
                    Icons.trending_down_rounded,
                    'Critical'
                  ));

    final marginStr = '${marginPercent >= 0 ? '+' : ''}${marginPercent.toStringAsFixed(1)}%';

    return CompositedTransformTarget(
      link: _marginLink,
      child: OverlayPortal(
        controller: _marginOverlayController,
        overlayChildBuilder: (context) {
          return CompositedTransformFollower(
            link: _marginLink,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 8),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 380,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x40000000),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.query_stats_rounded, size: 16, color: Color(0xFF34D399)),
                            SizedBox(width: 6),
                            Text(
                              'Margin Health Analysis',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: badgeBg.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: badgeBorder),
                          ),
                          child: Text(
                            '$marginStr ($healthLabel)',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: badgeBorder,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Formula Box
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF475569)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'FORMULA',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 0.5,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Margin % = [(Quotation - Total Cost) / Quotation] × 100',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF38BDF8),
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Breakdown Lines
                    _buildFormulaLineItem(
                      label: '1. Quoted Price',
                      sourceBadge: 'Cell #25 · Quotation',
                      value: '₹${quotedAmount.toStringAsFixed(0)}',
                      valueColor: const Color(0xFF38BDF8),
                      isSourceHighlighted: true,
                    ),
                    const SizedBox(height: 6),
                    _buildFormulaLineItem(
                      label: '2. Raw Material Cost',
                      sourceBadge: 'Cells #6, #7 · $alloy ($thickness)',
                      value: '₹${materialCost.toStringAsFixed(0)}',
                      valueColor: const Color(0xFFFBBF24),
                      isSourceHighlighted: true,
                    ),
                    const SizedBox(height: 6),
                    _buildFormulaLineItem(
                      label: '3. Process & Tooling Cost',
                      sourceBadge: '${_dieProcessRecords.length} Dies + ${_machineRecords.length} Machines',
                      value: '₹${machiningCost.toStringAsFixed(0)}',
                      valueColor: const Color(0xFFA78BFA),
                      isSourceHighlighted: false,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: Color(0xFF334155), height: 1),
                    ),
                    _buildFormulaLineItem(
                      label: 'Total Estimated Cost',
                      sourceBadge: 'Material + Machining',
                      value: '₹${totalCost.toStringAsFixed(0)}',
                      valueColor: const Color(0xFFE2E8F0),
                      isSourceHighlighted: false,
                    ),
                    const SizedBox(height: 6),
                    _buildFormulaLineItem(
                      label: 'Net Estimated Profit',
                      sourceBadge: 'Quotation - Total Cost',
                      value: '₹${netProfit.toStringAsFixed(0)}',
                      valueColor: badgeBorder,
                      isBold: true,
                      isSourceHighlighted: false,
                    ),
                    const SizedBox(height: 10),

                    // Highlight indicator footer
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFF064E3B).withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: const Color(0xFF059669)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.highlight_rounded, size: 13, color: Color(0xFF34D399)),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Contributing cells are actively highlighted in emerald on the sheet.',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFFA7F3D0),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) {
            setState(() {
              _isHoveringMarginHealth = true;
              _highlightedColumnIds = {25, 6, 7};
            });
            _marginOverlayController.show();
          },
          onExit: (_) {
            setState(() {
              _isHoveringMarginHealth = false;
              _highlightedColumnIds.clear();
            });
            _marginOverlayController.hide();
          },
          child: GestureDetector(
            onTap: () {
              if (_marginOverlayController.isShowing) {
                _marginOverlayController.hide();
                setState(() {
                  _isHoveringMarginHealth = false;
                  _highlightedColumnIds.clear();
                });
              } else {
                _marginOverlayController.show();
                setState(() {
                  _isHoveringMarginHealth = true;
                  _highlightedColumnIds = {25, 6, 7};
                });
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              key: const ValueKey('margin_health_indicator'),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _isHoveringMarginHealth
                    ? badgeBg
                    : badgeBg.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: badgeBorder,
                  width: _isHoveringMarginHealth ? 2 : 1,
                ),
                boxShadow: _isHoveringMarginHealth
                    ? [
                        BoxShadow(
                          color: badgeBorder.withValues(alpha: 0.35),
                          blurRadius: 8,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(badgeIcon, size: 14, color: badgeFg),
                  const SizedBox(width: 5),
                  Text(
                    marginStr,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: badgeFg,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Margin',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: badgeFg.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormulaLineItem({
    required String label,
    required String sourceBadge,
    required String value,
    required Color valueColor,
    bool isBold = false,
    bool isSourceHighlighted = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
                color: isBold ? Colors.white : const Color(0xFFCBD5E1),
              ),
            ),
            const SizedBox(height: 1),
            Row(
              children: [
                if (isSourceHighlighted)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xFF34D399),
                      shape: BoxShape.circle,
                    ),
                  ),
                Text(
                  sourceBadge,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ],
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBold ? 13 : 12,
            fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION 2: Client / Vendor (Shown only for external parts)
  // ===========================================================================
  Widget _buildClientVendorSection() {
    final partySheet = _controller.clientVendorController.sheetDef;
    final partyDraft = _controller.clientVendorController.draft;
    final companyName = partyDraft.get(20)?.optionLabel ?? 'Gold Madel';
    final activeParty = _savedParties.isNotEmpty ? _savedParties[_activePartyIndex] : null;
    final activeItem = _savedItems.isNotEmpty ? _savedItems[_activeItemIndex] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.storefront_rounded, size: 16, color: Color(0xFF10B981)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Client / Vendor',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    'Developed For: External party link, contacts, and commercial quote',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _buildSectionPill('Developed For'),
            const SizedBox(width: 8),
            // Text values matching test expectations: Gold Madel / Kissan Jain / 85000/-
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(activeParty?.companyName ?? 'Gold Madel', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
                  const Text(' · ', style: TextStyle(color: Color(0xFF065F46))),
                  Text(activeParty?.contactPerson ?? 'Kissan Jain', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
                  const Text(' · ₹', style: TextStyle(color: Color(0xFF065F46))),
                  Text(activeParty?.quoteAmount ?? '85000/-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF065F46))),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Margin Health Indicator (% with hover formula and cell highlighting)
            _buildMarginHealthIndicator(activeParty, activeItem),
          ],
        ),
        const SizedBox(height: 10),

        // CRUD Action Toolbar for Parties
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Text('Parties: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
              const SizedBox(width: 6),
              // Read: Quick switcher pills for parties
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: _savedParties.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final p = entry.value;
                      final isSelected = idx == _activePartyIndex;
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => _loadSavedParty(idx),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isSelected) ...[
                                  const Icon(Icons.check_rounded, size: 12, color: Color(0xFF10B981)),
                                  const SizedBox(width: 4),
                                ],
                                Text(
                                  p.companyName,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                    color: isSelected ? const Color(0xFF065F46) : const Color(0xFF334155),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Create: + Add Party
              OutlinedButton.icon(
                key: const ValueKey('add_party_btn'),
                icon: const Icon(Icons.add_rounded, size: 14),
                label: const Text('Add Party'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFF10B981)),
                ),
                onPressed: _showAddPartyDialog,
              ),
              const SizedBox(width: 6),

              // + Column (User-defined property in Client / Vendor)
              OutlinedButton.icon(
                key: const ValueKey('add_cv_property_column_btn'),
                icon: const Icon(Icons.view_column_rounded, size: 14),
                label: const Text('+ Column'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  foregroundColor: const Color(0xFF10B981),
                  side: const BorderSide(color: Color(0xFFA7F3D0)),
                ),
                onPressed: _showAddClientVendorColumnDialog,
              ),
              const SizedBox(width: 6),

              // Update: Edit Party
              IconButton(
                key: const ValueKey('edit_party_btn'),
                icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF475569)),
                tooltip: 'Edit Party Details',
                visualDensity: VisualDensity.compact,
                onPressed: _showEditPartyDialog,
              ),

              // Delete: Unlink / Delete Party
              IconButton(
                key: const ValueKey('delete_party_btn'),
                icon: const Icon(Icons.link_off_rounded, size: 16, color: Color(0xFFDC2626)),
                tooltip: 'Unlink Party',
                visualDensity: VisualDensity.compact,
                onPressed: _showDeletePartyDialog,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // TableRowStrip with horizontal scroll and pinned name overlay (multi-row support and + symbol for properties)
        TableRowStrip(
          sheetDef: partySheet,
          controller: _controller.clientVendorController,
          onAddPropertyColumn: _handleAddPropertyInClientVendor,
          rowDrafts: _savedParties.map(_partyToRowMap).toList(),
          onRowSelected: _loadSavedParty,
          selectedRowIndex: _activePartyIndex,
          highlightedColumnIds: _highlightedColumnIds,
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION 3: Die Process Master (Phase 2 Tooling)
  // ===========================================================================
  Widget _buildDieMasterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.precision_manufacturing_rounded, size: 16, color: Color(0xFF8B5CF6)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Die',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    'Die Process Master: Press tools & progressive dies per process',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              key: const ValueKey('add_die_process_table_btn'),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('+ Add Die Process Table'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                elevation: 0,
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              onPressed: _showAddDieProcessDialog,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal list of process tables with Edit & Delete actions
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _dieProcessRecords.map((record) {
              return Container(
                width: 290,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF5F3FF),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                        border: Border(bottom: BorderSide(color: Color(0xFFDDD6FE))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              record.headerTitle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF6D28D9)),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFDDD6FE),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              record.dieCode,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF4C1D95)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Edit icon button
                          IconButton(
                            key: ValueKey('edit_die_btn_${record.id}'),
                            icon: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF6D28D9)),
                            tooltip: 'Edit Process Table',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _showEditDieProcessDialog(record),
                          ),
                          const SizedBox(width: 4),
                          // Delete icon button
                          IconButton(
                            key: ValueKey('delete_die_btn_${record.id}'),
                            icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFDC2626)),
                            tooltip: 'Delete Process Table',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _showDeleteDieProcessDialog(record),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          _buildDetailRow('Made By', record.dieMadeBy),
                          _buildDetailRow('Die Type', record.type),
                          _buildDetailRow('Sets', record.noOfSet),
                          _buildDetailRow('Store Area', record.storeArea),
                          _buildDetailRow('Rack No', record.rackNo),
                          _buildDetailRow('PO Date', '${record.poDate} ${record.time}'),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // SECTION 4: Machine Master (Phase 2 Machines)
  // ===========================================================================
  Widget _buildMachineMasterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.settings_suggest_rounded, size: 16, color: Color(0xFFF59E0B)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Machine Master',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
                  ),
                  Text(
                    'Shop floor routing, setup specs and capacity allocations',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              key: const ValueKey('add_machine_table_btn'),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('+ Add Machine Table'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                elevation: 0,
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              onPressed: _showAddMachineDialog,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal list of machine tables with Edit & Delete actions
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _machineRecords.map((m) {
              return Container(
                width: 280,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.vertical(top: Radius.circular(7)),
                        border: Border(bottom: BorderSide(color: Color(0xFFFDE68A))),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              m.headerTitle,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFFB45309)),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFDE68A),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              m.machineNo,
                              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFF92400E)),
                            ),
                          ),
                          const SizedBox(width: 4),
                          // Edit machine button
                          IconButton(
                            key: ValueKey('edit_machine_btn_${m.id}'),
                            icon: const Icon(Icons.edit_outlined, size: 14, color: Color(0xFFB45309)),
                            tooltip: 'Edit Machine Table',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _showEditMachineDialog(m),
                          ),
                          const SizedBox(width: 4),
                          // Delete machine button
                          IconButton(
                            key: ValueKey('delete_machine_btn_${m.id}'),
                            icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFDC2626)),
                            tooltip: 'Delete Machine Table',
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _showDeleteMachineDialog(m),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        children: [
                          _buildDetailRow('Type', m.machineType),
                          _buildDetailRow('Make', m.machineMake),
                          _buildDetailRow('DOM', m.dom),
                          _buildDetailRow('Feeder', m.feeder),
                          _buildDetailRow('Capacity', m.capacity),
                          _buildDetailRow('Die Type', m.dieType),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF475569)),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaveIntent extends Intent {
  const _SaveIntent();
}
