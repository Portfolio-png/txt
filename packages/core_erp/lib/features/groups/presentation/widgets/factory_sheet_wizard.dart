import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../clients/domain/client_inputs.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
import '../../../inventory/domain/inventory_set_definition.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../items/domain/developed_for.dart';
import '../../../items/domain/item_definition.dart';
import '../../../items/domain/item_inputs.dart';
import '../../../items/domain/part_code.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../domain/group_inputs.dart';
import '../providers/groups_provider.dart';

/// The Unified Factory Sheet Wizard (Devised Edition).
///
/// Multiples ("Many in One") Architecture:
/// 1. Group (1) -> Many Types / Sets (Dolly, Italya, Rocker)
/// 2. Type / Set (1) -> Many Parts / Items (Patti, Dabbi, Threading Patti)
/// 3. Company (1) -> Many Contact Persons (Kissan Jain, Kapil, Bhisan)
/// 4. Concrete Part (1) -> Single Recipe (Brass 22G -> SADPB2248, 228 pcs/sheet, 1.238 kg scrap)
/// 5. Part -> Many Tooling Dies (CDSADP48 Cutting, RSADP48 Riveting, ASADP48 Assembly)
/// 6. Part -> 9-Stage Sequential Workflow Ribbon with Machine Assignments
///
/// Features:
/// - In-dropdown creation for every master (Group, Type/Set, Part, Company, Contact, Alloy, Gauge, Vendor, Die, Machine).
/// - 1-Click "Clone for Another Material" (e.g. Mild Steel -> SADPMS2248) matching Page 4 & 5.
/// - Sibling part navigation tray in the active Set.
class FactorySheetWizard extends StatefulWidget {
  const FactorySheetWizard({
    super.key,
    required this.onSwitchToBench,
    this.onSaved,
    this.initialGroupName,
  });

  final VoidCallback onSwitchToBench;
  final ValueChanged<ItemDefinition>? onSaved;
  final String? initialGroupName;

  @override
  State<FactorySheetWizard> createState() => _FactorySheetWizardState();
}

class _DieSpec {
  _DieSpec({
    required this.type,
    required this.prefix,
    required this.maker,
    required this.storeArea,
    required this.rackNo,
    this.linerSize = '94.50 mm',
    this.hasPhoto = false,
    this.hasCad = false,
  });

  final String type;
  final String prefix;
  String maker;
  String storeArea;
  String rackNo;
  String linerSize;
  bool included = true;
  bool hasPhoto;
  bool hasCad;
}

class _ContactPerson {
  _ContactPerson({
    required this.name,
    required this.designation,
    required this.phone,
    required this.email,
  });

  final String name;
  final String designation;
  final String phone;
  final String email;
}

class _AlloySpec {
  _AlloySpec({
    required this.name,
    required this.dnaCode,
    required this.density,
  });

  final String name;
  final String dnaCode;
  final double density; // g/cm³
}

class _GaugeSpec {
  _GaugeSpec({
    required this.label,
    required this.mm,
    required this.dnaCode,
  });

  final String label;
  final double mm;
  final String dnaCode;
}

/// Sibling part in the current Type / Set.
class _SetSiblingPart {
  _SetSiblingPart({
    required this.partName,
    required this.partNo,
    required this.alloy,
    required this.thickness,
    required this.rawSheetWt,
    required this.linerSize,
    required this.grossCount,
    required this.dozenCount,
    required this.pieceCount,
    required this.finishedItemWt,
    required this.dies,
    required this.stages,
    required this.assignedMachine,
  });

  String partName;
  String partNo;
  String alloy;
  String thickness;
  String rawSheetWt;
  String linerSize;
  int grossCount;
  int dozenCount;
  int pieceCount;
  String finishedItemWt;
  List<_DieSpec> dies;
  List<String> stages;
  String assignedMachine;
  bool isSaved = false;
}

class _FactorySheetWizardState extends State<FactorySheetWizard> {
  // Level 1: Group
  late String _selectedGroup = widget.initialGroupName ?? 'Switch Action';
  late String _groupPrefix = 'SA';
  final List<String> _groupOptions = [
    'Switch Action',
    'Cutout',
    'Double Pole',
    'Socket',
    'Others',
  ];

  // Level 2: Type / Set (What client calls Type is Set in Paper ERP)
  String _selectedTypeSet = 'Dolly';
  String _typeSetCode = 'D';
  final Map<String, List<String>> _setsByGroup = {
    'Switch Action': ['Dolly', 'Italya', 'Rocker', 'Ram Ban', 'TC No'],
    'Cutout': ['Porcelain Cutout', 'Deluxe Cutout', 'Heavy Duty Cutout'],
    'Double Pole': ['32A DP', '63A DP'],
    'Socket': ['2-in-1 Socket', 'Modular 3-Pin Socket'],
  };

  // Level 3: Set Components (Sibling Parts)
  late final List<_SetSiblingPart> _siblings = [
    _SetSiblingPart(
      partName: 'Patti',
      partNo: '48',
      alloy: 'Brass',
      thickness: '22 Gauge',
      rawSheetWt: '2.080',
      linerSize: '94.50',
      grossCount: 1,
      dozenCount: 7,
      pieceCount: 0,
      finishedItemWt: '0.842',
      dies: [
        _DieSpec(type: 'Cutting', prefix: 'C', maker: 'Atul Mestry', storeArea: 'F206', rackNo: '23-4', linerSize: '94.50 mm', hasPhoto: true, hasCad: true),
        _DieSpec(type: 'Riveting', prefix: 'R', maker: 'SKA', storeArea: 'F206', rackNo: '23-4', hasPhoto: true),
        _DieSpec(type: 'Assembly', prefix: 'A', maker: 'SKA', storeArea: 'F206', rackNo: '23-4'),
      ],
      stages: List.of(_defaultStages),
      assignedMachine: 'Mayank 35T Power Press (PP-4)',
    ),
  ];
  int _activeSiblingIndex = 0;

  // Active Part Controllers
  late final TextEditingController _partNameCtrl = TextEditingController(text: _siblings[0].partName);
  late final TextEditingController _partNoCtrl = TextEditingController(text: _siblings[0].partNo);
  final List<String> _partNameOptions = ['Patti', 'Dabbi', 'Threading Patti', 'Cam', 'Spring'];

  // Media
  bool _hasPartPhoto = true;
  final String _partPhotoName = 'dolly_patti_brass_sample.webp';
  bool _hasPartCad = true;
  final String _partCadName = 'SADP48_Rev2.step';

  // Commercial: Developed For
  DevelopedForKind _devKind = DevelopedForKind.client;
  String _selectedCompany = 'Gold Madel';
  final List<String> _companyOptions = ['Gold Madel', 'Anchor', 'Benteck', 'Cona', 'GM'];
  final Map<String, List<_ContactPerson>> _contactsByCompany = {
    'Gold Madel': [
      _ContactPerson(name: 'Kissan Jain', designation: 'Director', phone: '9865656565', email: 'director@goldmadel.com'),
      _ContactPerson(name: 'Kapil', designation: 'Engineer', phone: '9876543210', email: 'kapil@goldmadel.com'),
      _ContactPerson(name: 'Bhisan', designation: 'Supervisor', phone: '9822334455', email: 'bhisan@goldmadel.com'),
    ],
    'Anchor': [
      _ContactPerson(name: 'Vinod', designation: 'Manager', phone: '9811223344', email: 'vinod@anchor.com'),
    ],
    'Benteck': [
      _ContactPerson(name: 'Rakesh', designation: 'Proprietor', phone: '9844556677', email: 'rakesh@benteck.com'),
    ],
  };
  late _ContactPerson _selectedContact = _contactsByCompany['Gold Madel']![0];
  final TextEditingController _quotationCtrl = TextEditingController(text: '85000');

  // Concrete Material & Sheet Yield (Single Recipe)
  String _selectedAlloy = 'Brass';
  final List<_AlloySpec> _allAlloys = [
    _AlloySpec(name: 'Brass', dnaCode: 'B', density: 8.50),
    _AlloySpec(name: 'Mild Steel', dnaCode: 'MS', density: 7.85),
    _AlloySpec(name: 'Aluminium', dnaCode: 'AL', density: 2.70),
    _AlloySpec(name: 'Copper', dnaCode: 'C', density: 8.96),
    _AlloySpec(name: 'P-Bronze', dnaCode: 'PB', density: 8.80),
    _AlloySpec(name: 'EN9', dnaCode: 'EN9', density: 7.85),
  ];

  String _selectedThickness = '22 Gauge';
  final List<_GaugeSpec> _allGauges = [
    _GaugeSpec(label: '22 Gauge', mm: 0.71, dnaCode: '22'),
    _GaugeSpec(label: '18 Gauge', mm: 1.22, dnaCode: '18'),
    _GaugeSpec(label: '19 Gauge', mm: 1.06, dnaCode: '19'),
    _GaugeSpec(label: '20 Gauge', mm: 0.91, dnaCode: '20'),
    _GaugeSpec(label: '21 Gauge', mm: 0.81, dnaCode: '21'),
    _GaugeSpec(label: '23 Gauge', mm: 0.61, dnaCode: '23'),
    _GaugeSpec(label: '0.5mm', mm: 0.50, dnaCode: '05'),
  ];

  String _selectedVendor = 'Vardhaman';
  final List<String> _vendorOptions = ['Vardhaman', 'Ashok', 'Agarwal'];

  late final TextEditingController _rawSheetWtCtrl = TextEditingController(text: _siblings[0].rawSheetWt);
  late final TextEditingController _linerSizeCtrl = TextEditingController(text: _siblings[0].linerSize);
  late int _grossCount = _siblings[0].grossCount;
  late int _dozenCount = _siblings[0].dozenCount;
  late int _pieceCount = _siblings[0].pieceCount;
  late final TextEditingController _finishedItemWtCtrl = TextEditingController(text: _siblings[0].finishedItemWt);

  // 9-Stage Process Ribbon
  static const List<String> _defaultStages = [
    'Die',
    'Shearing',
    'Cutting',
    'Riveting',
    'Assembly',
    'Packing',
    'Barcode',
    'Billing',
    'Delivery',
  ];
  late List<String> _stages = List.of(_siblings[0].stages);
  int _selectedStageIndex = 2; // Cutting
  late String _assignedMachine = _siblings[0].assignedMachine;
  final List<String> _machineOptions = [
    'Mayank 35T Power Press (PP-4)',
    'SKA 25T Power Press (PP-1)',
    'Devson 60T Progressive (PP-4)',
    'Saraswati Free Hand',
  ];

  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _partNameCtrl.addListener(_onPartChanged);
    _partNoCtrl.addListener(_onPartChanged);
    _rawSheetWtCtrl.addListener(_update);
    _finishedItemWtCtrl.addListener(_update);
    _quotationCtrl.addListener(_update);
    _linerSizeCtrl.addListener(_update);
  }

  void _onPartChanged() {
    _saveActiveSiblingData();
    if (mounted) setState(() {});
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _partNameCtrl.dispose();
    _partNoCtrl.dispose();
    _quotationCtrl.dispose();
    _rawSheetWtCtrl.dispose();
    _linerSizeCtrl.dispose();
    _finishedItemWtCtrl.dispose();
    super.dispose();
  }

  T? _maybeRead<T>(BuildContext context) {
    try {
      return context.read<T>();
    } catch (_) {
      return null;
    }
  }

  // DNA Code Calculations
  String get _trunkCode {
    final g = _groupPrefix.trim();
    final t = _typeSetCode.trim();
    final initials = partCodeInitials(_partNameCtrl.text.trim());
    final p = initials.isNotEmpty ? initials : 'P';
    final num = _partNoCtrl.text.trim().isEmpty ? '48' : _partNoCtrl.text.trim();
    return '$g$t$p$num';
  }

  String get _fullPartCode {
    final base = _trunkCode;
    final alloyCode = _allAlloys.where((a) => a.name == _selectedAlloy).map((a) => a.dnaCode).firstOrNull ?? 'B';
    final gaugeCode = _allGauges.where((g) => g.label == _selectedThickness).map((g) => g.dnaCode).firstOrNull ?? '22';
    return variantCodeFromPartCode(base, valueCodes: [alloyCode, gaugeCode]);
  }

  String _dieCodeFor(_DieSpec die) {
    final base = _trunkCode;
    if (die.type == 'Cutting') return 'CD$base';
    return '${die.prefix}$base';
  }

  int get _totalPieces => (_grossCount * 144) + (_dozenCount * 12) + _pieceCount;

  double get _scrapWeight {
    final raw = double.tryParse(_rawSheetWtCtrl.text.trim()) ?? 0;
    final finished = double.tryParse(_finishedItemWtCtrl.text.trim()) ?? 0;
    final val = raw - finished;
    return val > 0 ? val : 0;
  }

  // Sibling Part Management
  void _saveActiveSiblingData() {
    if (_activeSiblingIndex < 0 || _activeSiblingIndex >= _siblings.length) return;
    final s = _siblings[_activeSiblingIndex];
    s.partName = _partNameCtrl.text.trim();
    s.partNo = _partNoCtrl.text.trim();
    s.alloy = _selectedAlloy;
    s.thickness = _selectedThickness;
    s.rawSheetWt = _rawSheetWtCtrl.text.trim();
    s.linerSize = _linerSizeCtrl.text.trim();
    s.grossCount = _grossCount;
    s.dozenCount = _dozenCount;
    s.pieceCount = _pieceCount;
    s.finishedItemWt = _finishedItemWtCtrl.text.trim();
    s.assignedMachine = _assignedMachine;
  }

  void _loadSiblingData(int index) {
    if (index < 0 || index >= _siblings.length) return;
    _saveActiveSiblingData();
    final s = _siblings[index];
    _activeSiblingIndex = index;
    _partNameCtrl.text = s.partName;
    _partNoCtrl.text = s.partNo;
    _selectedAlloy = s.alloy;
    _selectedThickness = s.thickness;
    _rawSheetWtCtrl.text = s.rawSheetWt;
    _linerSizeCtrl.text = s.linerSize;
    _grossCount = s.grossCount;
    _dozenCount = s.dozenCount;
    _pieceCount = s.pieceCount;
    _finishedItemWtCtrl.text = s.finishedItemWt;
    _stages = List.of(s.stages);
    _assignedMachine = s.assignedMachine;
    setState(() {});
  }

  void _addSiblingPart() {
    _saveActiveSiblingData();
    final nextName = _siblings.length == 1 ? 'Dabbi' : (_siblings.length == 2 ? 'Threading Patti' : 'Part ${_siblings.length + 1}');
    final newPart = _SetSiblingPart(
      partName: nextName,
      partNo: _partNoCtrl.text.trim().isEmpty ? '48' : _partNoCtrl.text.trim(),
      alloy: _selectedAlloy,
      thickness: _selectedThickness,
      rawSheetWt: _rawSheetWtCtrl.text.trim(),
      linerSize: _linerSizeCtrl.text.trim(),
      grossCount: _grossCount,
      dozenCount: _dozenCount,
      pieceCount: _pieceCount,
      finishedItemWt: _finishedItemWtCtrl.text.trim(),
      dies: [
        _DieSpec(type: 'Cutting', prefix: 'C', maker: 'Atul Mestry', storeArea: 'F206', rackNo: '23-4', linerSize: '94.50 mm', hasPhoto: true, hasCad: true),
        _DieSpec(type: 'Riveting', prefix: 'R', maker: 'SKA', storeArea: 'F206', rackNo: '23-4', hasPhoto: true),
        _DieSpec(type: 'Assembly', prefix: 'A', maker: 'SKA', storeArea: 'F206', rackNo: '23-4'),
      ],
      stages: List.of(_defaultStages),
      assignedMachine: _assignedMachine,
    );
    setState(() {
      _siblings.add(newPart);
      _loadSiblingData(_siblings.length - 1);
    });
    showAppToast(context, 'Added "$nextName" to $_selectedTypeSet set.');
  }

  Future<void> _cloneForNewMaterial() async {
    _saveActiveSiblingData();
    final candidateAlloys = _allAlloys.where((a) => a.name != _selectedAlloy).toList();
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Clone recipe for another material:', style: TextStyle(fontWeight: FontWeight.w800)),
        children: [
          for (final a in candidateAlloys)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(a.name),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.layers_outlined, size: 16, color: SoftErpTheme.accent),
                    const SizedBox(width: 8),
                    Text('${a.name} (${a.dnaCode}) · Density: ${a.density} g/cm³'),
                  ],
                ),
              ),
            ),
        ],
      ),
    );

    if (chosen != null) {
      final active = _siblings[_activeSiblingIndex];
      final cloned = _SetSiblingPart(
        partName: active.partName,
        partNo: active.partNo,
        alloy: chosen,
        thickness: active.thickness,
        rawSheetWt: active.rawSheetWt,
        linerSize: active.linerSize,
        grossCount: active.grossCount,
        dozenCount: active.dozenCount,
        pieceCount: active.pieceCount,
        finishedItemWt: active.finishedItemWt,
        dies: [
          _DieSpec(type: 'Cutting', prefix: 'C', maker: 'Atul Mestry', storeArea: 'F206', rackNo: '23-4', linerSize: '${active.linerSize} mm', hasPhoto: true, hasCad: true),
          _DieSpec(type: 'Riveting', prefix: 'R', maker: 'SKA', storeArea: 'F206', rackNo: '23-4', hasPhoto: true),
          _DieSpec(type: 'Assembly', prefix: 'A', maker: 'SKA', storeArea: 'F206', rackNo: '23-4'),
        ],
        stages: List.of(active.stages),
        assignedMachine: active.assignedMachine,
      );
      setState(() {
        _siblings.add(cloned);
        _loadSiblingData(_siblings.length - 1);
      });
      if (!mounted) return;
      showAppToast(context, 'Cloned recipe for $chosen ($_fullPartCode).');
    }
  }

  // Micro-Creation Dialog Helper
  Future<T?> _showMicroDialog<T>({
    required BuildContext context,
    required String title,
    required Widget child,
    required Future<T?> Function() onSave,
  }) {
    return showDialog<T>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
        content: SizedBox(width: 420, child: child),
        actions: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(dialogCtx).pop(),
          ),
          AppButton(
            label: 'Save & Select',
            onPressed: () async {
              final res = await onSave();
              if (dialogCtx.mounted && res != null) {
                Navigator.of(dialogCtx).pop(res);
              }
            },
          ),
        ],
      ),
    );
  }

  // Inline Creation Handlers
  Future<SearchableSelectOption<String>?> _createGroupInline(String query) async {
    final nameCtrl = TextEditingController(text: query.trim());
    final initials = partCodeInitials(query);
    final prefixCtrl = TextEditingController(
      text: initials.isNotEmpty
          ? initials
          : (query.trim().length >= 2 ? query.trim().substring(0, 2).toUpperCase() : query.trim().toUpperCase()),
    );

    return _showMicroDialog<SearchableSelectOption<String>>(
      context: context,
      title: 'Add New Item Group',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFieldInput(label: 'Group Name', controller: nameCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'Code Prefix (2-3 Chars)', controller: prefixCtrl),
          const SizedBox(height: 8),
          const Text('This prefix forms the first 2 letters of all part codes in this group.', style: TextStyle(fontSize: 11, color: SoftErpTheme.textSecondary)),
        ],
      ),
      onSave: () async {
        final name = nameCtrl.text.trim();
        final pfx = prefixCtrl.text.trim().toUpperCase();
        if (name.isEmpty) return null;
        final groups = _maybeRead<GroupsProvider>(context);
        if (groups != null) {
          await groups.createGroup(CreateGroupInput(name: name, groupType: 'item', description: 'Prefix: $pfx'));
        }
        setState(() {
          if (!_groupOptions.contains(name)) _groupOptions.add(name);
          _selectedGroup = name;
          _groupPrefix = pfx;
        });
        return SearchableSelectOption<String>(value: name, label: name);
      },
    );
  }

  Future<SearchableSelectOption<String>?> _createTypeSetInline(String query) async {
    final nameCtrl = TextEditingController(text: query.trim());
    final codeCtrl = TextEditingController(
      text: query.trim().isNotEmpty ? query.trim().substring(0, 1).toUpperCase() : 'X',
    );

    return _showMicroDialog<SearchableSelectOption<String>>(
      context: context,
      title: 'Add Type / Set to "$_selectedGroup"',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFieldInput(label: 'Type (Set) Name', controller: nameCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'DNA Letter (1-2 Chars)', controller: codeCtrl),
          const SizedBox(height: 8),
          Text('Forms segment 2 of the part code under $_selectedGroup (e.g. $_groupPrefix + ${codeCtrl.text.trim()}).', style: const TextStyle(fontSize: 11, color: SoftErpTheme.textSecondary)),
        ],
      ),
      onSave: () async {
        final name = nameCtrl.text.trim();
        final code = codeCtrl.text.trim().toUpperCase();
        if (name.isEmpty) return null;
        final inventory = _maybeRead<InventoryProvider>(context);
        if (inventory != null) {
          await inventory.saveSet(SaveInventorySetInput(name: name, lines: const [], groupIdSpecified: false));
        }
        setState(() {
          _setsByGroup.putIfAbsent(_selectedGroup, () => []).add(name);
          _selectedTypeSet = name;
          _typeSetCode = code;
        });
        return SearchableSelectOption<String>(value: name, label: name);
      },
    );
  }

  Future<SearchableSelectOption<String>?> _createPartNameInline(String query) async {
    final nameCtrl = TextEditingController(text: query.trim());
    return _showMicroDialog<SearchableSelectOption<String>>(
      context: context,
      title: 'Add Stamped Part Name',
      child: _buildFieldInput(label: 'Part Name (e.g. Patti, Dabbi)', controller: nameCtrl),
      onSave: () async {
        final name = nameCtrl.text.trim();
        if (name.isEmpty) return null;
        setState(() {
          if (!_partNameOptions.contains(name)) _partNameOptions.add(name);
          _partNameCtrl.text = name;
        });
        return SearchableSelectOption<String>(value: name, label: name);
      },
    );
  }

  Future<SearchableSelectOption<String>?> _createCompanyInline(String query) async {
    final nameCtrl = TextEditingController(text: query.trim());
    final contactCtrl = TextEditingController(text: 'Director Person');
    final phoneCtrl = TextEditingController(text: '9800000000');
    final cityCtrl = TextEditingController(text: 'Mumbai');

    return _showMicroDialog<SearchableSelectOption<String>>(
      context: context,
      title: 'Add Commercial Company',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFieldInput(label: 'Company Name', controller: nameCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'City / Industrial Hub', controller: cityCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'Primary Contact Person', controller: contactCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'Phone Number', controller: phoneCtrl),
        ],
      ),
      onSave: () async {
        final name = nameCtrl.text.trim();
        if (name.isEmpty) return null;
        final clients = _maybeRead<ClientsProvider>(context);
        if (clients != null) {
          await clients.createClient(CreateClientInput(name: name, contactName: contactCtrl.text.trim(), phone: phoneCtrl.text.trim(), address: cityCtrl.text.trim()));
        }
        setState(() {
          if (!_companyOptions.contains(name)) _companyOptions.add(name);
          _selectedCompany = name;
          _contactsByCompany[name] = [
            _ContactPerson(name: contactCtrl.text.trim(), designation: 'Director', phone: phoneCtrl.text.trim(), email: 'info@${name.toLowerCase().replaceAll(' ', '')}.com'),
          ];
          _selectedContact = _contactsByCompany[name]![0];
        });
        return SearchableSelectOption<String>(value: name, label: name);
      },
    );
  }

  Future<SearchableSelectOption<String>?> _createContactInline(String query) async {
    final nameCtrl = TextEditingController(text: query.trim());
    final desigCtrl = TextEditingController(text: 'Manager');
    final phoneCtrl = TextEditingController(text: '9876500000');
    final emailCtrl = TextEditingController(text: 'contact@${_selectedCompany.toLowerCase().replaceAll(' ', '')}.com');

    return _showMicroDialog<SearchableSelectOption<String>>(
      context: context,
      title: 'Add Contact Person to "$_selectedCompany"',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFieldInput(label: 'Person Name', controller: nameCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'Designation (e.g. Director, Engineer)', controller: desigCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'Mobile Number', controller: phoneCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'Email', controller: emailCtrl),
        ],
      ),
      onSave: () async {
        final name = nameCtrl.text.trim();
        if (name.isEmpty) return null;
        final newContact = _ContactPerson(name: name, designation: desigCtrl.text.trim(), phone: phoneCtrl.text.trim(), email: emailCtrl.text.trim());
        setState(() {
          _contactsByCompany.putIfAbsent(_selectedCompany, () => []).add(newContact);
          _selectedContact = newContact;
        });
        return SearchableSelectOption<String>(value: name, label: '$name (${newContact.designation})');
      },
    );
  }

  Future<SearchableSelectOption<String>?> _createAlloyInline(String query) async {
    final nameCtrl = TextEditingController(text: query.trim());
    final codeCtrl = TextEditingController(
      text: query.trim().length >= 2 ? query.trim().substring(0, 2).toUpperCase() : query.trim().toUpperCase(),
    );
    final densityCtrl = TextEditingController(text: '8.50');

    return _showMicroDialog<SearchableSelectOption<String>>(
      context: context,
      title: 'Add Raw Material Alloy',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFieldInput(label: 'Alloy Name (e.g. Phosphor Bronze)', controller: nameCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'DNA Alloy Code (e.g. PB, B, MS)', controller: codeCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'Density (g/cm³ for scrap math)', controller: densityCtrl),
        ],
      ),
      onSave: () async {
        final name = nameCtrl.text.trim();
        if (name.isEmpty) return null;
        final dens = double.tryParse(densityCtrl.text.trim()) ?? 8.0;
        setState(() {
          _allAlloys.add(_AlloySpec(name: name, dnaCode: codeCtrl.text.trim().toUpperCase(), density: dens));
          _selectedAlloy = name;
        });
        return SearchableSelectOption<String>(value: name, label: name);
      },
    );
  }

  Future<SearchableSelectOption<String>?> _createGaugeInline(String query) async {
    final labelCtrl = TextEditingController(text: query.trim());
    final mmCtrl = TextEditingController(text: '0.70');
    final codeCtrl = TextEditingController(text: query.replaceAll(RegExp(r'[^0-9]+'), ''));

    return _showMicroDialog<SearchableSelectOption<String>>(
      context: context,
      title: 'Add Thickness / Gauge',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildFieldInput(label: 'Gauge Label (e.g. 24 Gauge, 0.8mm)', controller: labelCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'Thickness in mm', controller: mmCtrl),
          const SizedBox(height: 12),
          _buildFieldInput(label: 'DNA Numeric Suffix (e.g. 24)', controller: codeCtrl),
        ],
      ),
      onSave: () async {
        final label = labelCtrl.text.trim();
        if (label.isEmpty) return null;
        setState(() {
          _allGauges.add(_GaugeSpec(label: label, mm: double.tryParse(mmCtrl.text.trim()) ?? 0.7, dnaCode: codeCtrl.text.trim()));
          _selectedThickness = label;
        });
        return SearchableSelectOption<String>(value: label, label: label);
      },
    );
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    final partName = _partNameCtrl.text.trim();
    if (partName.isEmpty) {
      showAppToast(context, 'Please specify Part Name.', kind: AppToastKind.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final groups = _maybeRead<GroupsProvider>(context);
      final items = _maybeRead<ItemsProvider>(context);
      final units = _maybeRead<UnitsProvider>(context);
      final inventory = _maybeRead<InventoryProvider>(context);

      // Ensure Group exists
      var group = groups?.groups.where((g) => g.name.toLowerCase() == _selectedGroup.toLowerCase()).firstOrNull;
      if (group == null && groups != null) {
        group = await groups.createGroup(
          CreateGroupInput(
            name: _selectedGroup,
            groupType: 'item',
            description: 'Created from Factory Sheet Wizard',
          ),
        );
      }
      final groupId = group?.id ?? 1;

      // Ensure Set exists in Inventory
      if (inventory != null) {
        final setMatch = inventory.sets.where((s) => s.name.toLowerCase() == _selectedTypeSet.toLowerCase()).firstOrNull;
        if (setMatch == null) {
          await inventory.saveSet(
            SaveInventorySetInput(
              name: _selectedTypeSet,
              lines: const [],
              groupId: groupId,
              groupIdSpecified: true,
            ),
          );
        }
      }

      // Unit
      final pieceUnit = units?.units.where((u) => u.symbol == 'pcs' || u.name == 'piece').firstOrNull;
      final unitId = pieceUnit?.id ?? 1;

      // Commercial Origin
      final dev = DevelopedFor(
        kind: _devKind,
        companyName: _selectedCompany,
        contactName: _selectedContact.name,
        designation: _selectedContact.designation,
        quotationAmount: double.tryParse(_quotationCtrl.text.trim()),
        phone: _selectedContact.phone,
        email: _selectedContact.email,
        at: DateTime.now(),
      );

      final partNo = int.tryParse(_partNoCtrl.text.trim()) ?? 48;
      final partCode = _trunkCode;

      // Single Concrete Recipe Item Save
      final input = CreateItemInput(
        name: partName,
        displayName: '$_selectedTypeSet $partName',
        groupId: groupId,
        unitId: unitId,
        partNo: partNo,
        partCode: partCode,
        developedFor: dev,
        variationTree: const [], // Concrete Single Item Recipe
        photoUrl: _hasPartPhoto ? _partPhotoName : '',
        cadFileName: _hasPartCad ? _partCadName : '',
        blankWidthMm: double.tryParse(_linerSizeCtrl.text.trim()) ?? 94.5,
        blankHeightMm: 0,
      );

      ItemDefinition? saved;
      if (items != null) {
        saved = await items.createItem(input);
      } else {
        saved = ItemDefinition(
          id: 999,
          name: partName,
          alias: '',
          displayName: '$_selectedTypeSet $partName',
          quantity: 0,
          partCode: partCode,
          groupId: groupId,
          unitId: unitId,
          isArchived: false,
          usageCount: 0,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          variationTree: const [],
        );
      }

      if (!mounted) return;

      if (saved != null) {
        _siblings[_activeSiblingIndex].isSaved = true;
        showAppToast(context, 'Saved ${saved.displayName} ($partCode) & recipe.');
        widget.onSaved?.call(saved);
        widget.onSwitchToBench();
      } else {
        showAppToast(context, items?.errorMessage ?? 'Could not save item.', kind: AppToastKind.error);
      }
    } catch (e) {
      if (mounted) showAppToast(context, 'Error saving: $e', kind: AppToastKind.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trunk = _trunkCode;
    final fullCode = _fullPartCode;

    return Container(
      color: SoftErpTheme.shellSurface,
      child: Column(
        children: [
          // Sub-header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(
              color: SoftErpTheme.cardSurface,
              border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.table_chart_outlined, color: SoftErpTheme.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Factory Sheet Wizard',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary),
                      ),
                      Text(
                        'Lazy Trunk & Sibling Parts Entry for Group "$_selectedGroup" · Set "$_selectedTypeSet"',
                        style: const TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.accentSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SoftErpTheme.accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Text('Trunk: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SoftErpTheme.textSecondary)),
                      Text(trunk, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: SoftErpTheme.accent)),
                      const Text(' · Code: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: SoftErpTheme.textSecondary)),
                      Text(fullCode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: SoftErpTheme.accentDark)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                AppButton(
                  key: const ValueKey('wizard_switch_to_bench'),
                  label: 'Switch to Power Bench',
                  variant: AppButtonVariant.secondary,
                  onPressed: widget.onSwitchToBench,
                ),
              ],
            ),
          ),

          // Scrollable Blueprint Body
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                // SECTION 0: Multiples Sibling Tray (Set Components)
                _buildSetComponentsTray(),
                const SizedBox(height: 20),

                // SECTION 1: Page 1 (Group + Type/Set + Part Trunk + Developed For)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Trunk Card
                    Expanded(
                      flex: 6,
                      child: _buildCard(
                        title: 'Group Item (Trunk Identity)',
                        badge: 'Page 1',
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: SearchableSelectField<String>(
                                    key: const ValueKey('wizard_group_select'),
                                    decoration: const InputDecoration(labelText: 'Group', isDense: true, border: OutlineInputBorder()),
                                    value: _selectedGroup,
                                    options: _groupOptions.map((g) => SearchableSelectOption(value: g, label: g)).toList(),
                                    canCreateOption: (q, _) => q.trim().isNotEmpty,
                                    createOptionLabelBuilder: (q) => '+ Add "$q" as new Group',
                                    onCreateOption: _createGroupInline,
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _selectedGroup = val;
                                          _selectedTypeSet = _setsByGroup[val]?.firstOrNull ?? 'Default';
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SearchableSelectField<String>(
                                    decoration: const InputDecoration(labelText: 'Type (Set)', isDense: true, border: OutlineInputBorder()),
                                    value: _selectedTypeSet,
                                    options: (_setsByGroup[_selectedGroup] ?? ['Dolly', 'Italya', 'Rocker'])
                                        .map((t) => SearchableSelectOption(value: t, label: t))
                                        .toList(),
                                    canCreateOption: (q, _) => q.trim().isNotEmpty,
                                    createOptionLabelBuilder: (q) => '+ Add "$q" to $_selectedGroup',
                                    onCreateOption: _createTypeSetInline,
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedTypeSet = val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: SearchableSelectField<String>(
                                    decoration: const InputDecoration(labelText: 'Part Name (Item)', isDense: true, border: OutlineInputBorder()),
                                    value: _partNameCtrl.text,
                                    options: _partNameOptions.map((p) => SearchableSelectOption(value: p, label: p)).toList(),
                                    canCreateOption: (q, _) => q.trim().isNotEmpty,
                                    createOptionLabelBuilder: (q) => '+ Add "$q" as Part',
                                    onCreateOption: _createPartNameInline,
                                    onChanged: (val) {
                                      if (val != null) _partNameCtrl.text = val;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildFieldInput(label: 'Part No', controller: _partNoCtrl),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            // Media Bar
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: SoftErpTheme.cardSurfaceAlt,
                                borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                                border: Border.all(color: SoftErpTheme.border),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => setState(() => _hasPartPhoto = !_hasPartPhoto),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: _hasPartPhoto ? SoftErpTheme.successBg : SoftErpTheme.cardSurface,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: _hasPartPhoto ? SoftErpTheme.successText : SoftErpTheme.border),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.camera_alt, size: 16, color: _hasPartPhoto ? SoftErpTheme.successText : SoftErpTheme.textSecondary),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(_hasPartPhoto ? _partPhotoName : 'Add Photo', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _hasPartPhoto ? SoftErpTheme.successText : SoftErpTheme.textSecondary)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () => setState(() => _hasPartCad = !_hasPartCad),
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: _hasPartCad ? SoftErpTheme.infoBg : SoftErpTheme.cardSurface,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: _hasPartCad ? SoftErpTheme.infoText : SoftErpTheme.border),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.architecture, size: 16, color: _hasPartCad ? SoftErpTheme.infoText : SoftErpTheme.textSecondary),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(_hasPartCad ? _partCadName : 'Add CAD (.step/.dwg)', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _hasPartCad ? SoftErpTheme.infoText : SoftErpTheme.textSecondary)),
                                            ),
                                          ],
                                        ),
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
                    const SizedBox(width: 16),
                    // Developed For Card
                    Expanded(
                      flex: 6,
                      child: _buildCard(
                        title: 'Developed For (Commercial Origin)',
                        badge: 'Page 1',
                        child: Column(
                          children: [
                            Row(
                              children: [
                                SegmentedButton<DevelopedForKind>(
                                  segments: const [
                                    ButtonSegment(value: DevelopedForKind.client, label: Text('Client')),
                                    ButtonSegment(value: DevelopedForKind.self, label: Text('Self')),
                                    ButtonSegment(value: DevelopedForKind.contractor, label: Text('Contractor')),
                                  ],
                                  selected: {_devKind},
                                  onSelectionChanged: (s) => setState(() => _devKind = s.first),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SearchableSelectField<String>(
                                    decoration: const InputDecoration(labelText: 'Company Name', isDense: true, border: OutlineInputBorder()),
                                    value: _selectedCompany,
                                    options: _companyOptions.map((c) => SearchableSelectOption(value: c, label: c)).toList(),
                                    canCreateOption: (q, _) => q.trim().isNotEmpty,
                                    createOptionLabelBuilder: (q) => '+ Add Company "$q"',
                                    onCreateOption: _createCompanyInline,
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _selectedCompany = val;
                                          _selectedContact = _contactsByCompany[val]?.firstOrNull ?? _selectedContact;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: SearchableSelectField<String>(
                                    decoration: const InputDecoration(labelText: 'Contact Person', isDense: true, border: OutlineInputBorder()),
                                    value: _selectedContact.name,
                                    options: (_contactsByCompany[_selectedCompany] ?? [_selectedContact])
                                        .map((c) => SearchableSelectOption(value: c.name, label: '${c.name} (${c.designation})'))
                                        .toList(),
                                    canCreateOption: (q, _) => q.trim().isNotEmpty,
                                    createOptionLabelBuilder: (q) => '+ Add Contact "$q" to $_selectedCompany',
                                    onCreateOption: _createContactInline,
                                    onChanged: (val) {
                                      if (val != null) {
                                        final found = _contactsByCompany[_selectedCompany]?.where((c) => c.name == val).firstOrNull;
                                        if (found != null) setState(() => _selectedContact = found);
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildReadonlyBadge(label: 'Designation', value: _selectedContact.designation),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildFieldInput(label: 'Quotation (₹)', controller: _quotationCtrl),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(child: _buildReadonlyBadge(label: 'Contact No', value: _selectedContact.phone)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildReadonlyBadge(label: 'Email ID', value: _selectedContact.email)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // SECTION 2: Pages 4 & 5 (Concrete Material Recipe & Sheet Yield)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Concrete Material Recipe Card
                    Expanded(
                      flex: 6,
                      child: _buildCard(
                        title: 'Concrete Material Recipe (Single Item)',
                        badge: 'Pages 4 & 5',
                        trailing: SoftActionLink(
                          label: '📋 Clone for Another Material',
                          onTap: _cloneForNewMaterial,
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: SearchableSelectField<String>(
                                    decoration: const InputDecoration(labelText: 'Alloy', isDense: true, border: OutlineInputBorder()),
                                    value: _selectedAlloy,
                                    options: _allAlloys.map((a) => SearchableSelectOption(value: a.name, label: '${a.name} (${a.dnaCode})')).toList(),
                                    canCreateOption: (q, _) => q.trim().isNotEmpty,
                                    createOptionLabelBuilder: (q) => '+ Add Alloy "$q"',
                                    onCreateOption: _createAlloyInline,
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedAlloy = val);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: SearchableSelectField<String>(
                                    decoration: const InputDecoration(labelText: 'Thickness / Gauge', isDense: true, border: OutlineInputBorder()),
                                    value: _selectedThickness,
                                    options: _allGauges.map((g) => SearchableSelectOption(value: g.label, label: '${g.label} (${g.mm}mm)')).toList(),
                                    canCreateOption: (q, _) => q.trim().isNotEmpty,
                                    createOptionLabelBuilder: (q) => '+ Add Gauge "$q"',
                                    onCreateOption: _createGaugeInline,
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedThickness = val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: SearchableSelectField<String>(
                                    decoration: const InputDecoration(labelText: 'Material Vendor', isDense: true, border: OutlineInputBorder()),
                                    value: _selectedVendor,
                                    options: _vendorOptions.map((v) => SearchableSelectOption(value: v, label: v)).toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _selectedVendor = val);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: SoftErpTheme.accentSoft,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: SoftErpTheme.accent.withValues(alpha: 0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Text('Part Code: ', style: TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary)),
                                        Flexible(
                                          child: Text(
                                            fullCode,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: SoftErpTheme.accent),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Sheet Yield & Scrap Card
                    Expanded(
                      flex: 6,
                      child: _buildCard(
                        title: 'Physical Sheet Yield & Scrap',
                        badge: 'Page 4 Bottom',
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: _buildFieldInput(label: 'Raw Sheet Weight (kg)', controller: _rawSheetWtCtrl)),
                                const SizedBox(width: 12),
                                Expanded(child: _buildFieldInput(label: 'Liner Size (mm)', controller: _linerSizeCtrl)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: SoftErpTheme.cardSurfaceAlt,
                                borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
                                border: Border.all(color: SoftErpTheme.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Text('Units Contract Ladder: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SoftErpTheme.accent)),
                                      Text('$_totalPieces Items / Sheet', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: SoftErpTheme.textPrimary)),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _buildYieldCounter('Gross (144)', _grossCount, (v) => setState(() => _grossCount = v)),
                                      const SizedBox(width: 10),
                                      _buildYieldCounter('Dozen (12)', _dozenCount, (v) => setState(() => _dozenCount = v)),
                                      const SizedBox(width: 10),
                                      _buildYieldCounter('Pieces (1)', _pieceCount, (v) => setState(() => _pieceCount = v)),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(child: _buildFieldInput(label: 'Finished Item Wt (kg)', controller: _finishedItemWtCtrl)),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: SoftErpTheme.warningBg,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: SoftErpTheme.warningText.withValues(alpha: 0.3)),
                                        ),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text('Scrap Kg (Derived)', style: TextStyle(fontSize: 11, color: SoftErpTheme.warningText)),
                                            Text(
                                              '${_scrapWeight.toStringAsFixed(3)} kg',
                                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: SoftErpTheme.warningText),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // SECTION 3: Page 2 (Tooling Dies & Jigs)
                _buildCard(
                  title: 'Tooling Suite: Derived Dies & Jigs',
                  badge: 'Page 2',
                  child: Row(
                    children: [
                      for (final die in _siblings[_activeSiblingIndex].dies)
                        Expanded(
                          child: Container(
                            margin: const EdgeInsets.only(right: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: SoftErpTheme.cardSurfaceAlt,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: die.included ? SoftErpTheme.accent : SoftErpTheme.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: die.included,
                                      onChanged: (v) => setState(() => die.included = v ?? true),
                                    ),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('${die.type} Die', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
                                          Text(_dieCodeFor(die), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: SoftErpTheme.accent)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                                Text('Maker: ${die.maker}', style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: SoftErpTheme.cardSurface,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: SoftErpTheme.borderStrong),
                                      ),
                                      child: Text(
                                        'Area: ${die.storeArea} · Rack: ${die.rackNo}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // Media buttons
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () => setState(() => die.hasPhoto = !die.hasPhoto),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: die.hasPhoto ? SoftErpTheme.successBg : SoftErpTheme.cardSurface,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: die.hasPhoto ? SoftErpTheme.successText : SoftErpTheme.border),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(Icons.camera_alt, size: 14, color: die.hasPhoto ? SoftErpTheme.successText : SoftErpTheme.textSecondary),
                                            const SizedBox(width: 4),
                                            Text(die.hasPhoto ? 'Photo' : '+ Photo', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: die.hasPhoto ? SoftErpTheme.successText : SoftErpTheme.textSecondary)),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (die.type == 'Cutting') ...[
                                      const SizedBox(width: 8),
                                      InkWell(
                                        onTap: () => setState(() => die.hasCad = !die.hasCad),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: die.hasCad ? SoftErpTheme.infoBg : SoftErpTheme.cardSurface,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: die.hasCad ? SoftErpTheme.infoText : SoftErpTheme.border),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.architecture, size: 14, color: die.hasCad ? SoftErpTheme.infoText : SoftErpTheme.textSecondary),
                                              const SizedBox(width: 4),
                                              Text(die.hasCad ? 'CAD' : '+ CAD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: die.hasCad ? SoftErpTheme.infoText : SoftErpTheme.textSecondary)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION 4: Pages 6 & 7 (9-Stage Process Routing Ribbon)
                _buildCard(
                  title: '9-Stage Workflow Ribbon',
                  badge: 'Pages 6 & 7',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (int i = 0; i < _stages.length; i++) ...[
                              InkWell(
                                onTap: () => setState(() => _selectedStageIndex = i),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: _selectedStageIndex == i ? SoftErpTheme.accent : SoftErpTheme.cardSurfaceAlt,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _selectedStageIndex == i ? SoftErpTheme.accent : SoftErpTheme.border,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        'Stage ${i + 1}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: _selectedStageIndex == i ? Colors.white70 : SoftErpTheme.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _stages[i],
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: _selectedStageIndex == i ? Colors.white : SoftErpTheme.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (i < _stages.length - 1)
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Icon(Icons.arrow_forward, size: 16, color: SoftErpTheme.textSecondary),
                                ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      // Machine selector for active stage
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: SoftErpTheme.cardSurfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: SoftErpTheme.border),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Assigned Machine for Stage ${_selectedStageIndex + 1} (${_stages[_selectedStageIndex]}): ',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SearchableSelectField<String>(
                                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                                value: _assignedMachine,
                                options: _machineOptions.map((m) => SearchableSelectOption(value: m, label: m)).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _assignedMachine = val);
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Save Action
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    AppButton(
                      label: 'Switch to Power Bench',
                      variant: AppButtonVariant.secondary,
                      onPressed: widget.onSwitchToBench,
                    ),
                    AppButton(
                      label: '📋 Clone for New Material',
                      variant: AppButtonVariant.secondary,
                      onPressed: _cloneForNewMaterial,
                    ),
                    AppButton(
                      key: const ValueKey('wizard_save_complete_recipe'),
                      label: 'Save Complete Manufacturing Recipe',
                      icon: Icons.save,
                      isLoading: _saving,
                      onPressed: _handleSave,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Section 0: Set Components Sibling Tray
  Widget _buildSetComponentsTray() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.accent.withValues(alpha: 0.3)),
        boxShadow: SoftErpTheme.insetShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, size: 16, color: SoftErpTheme.accent),
              const SizedBox(width: 8),
              Text(
                'SET COMPONENTS IN "$_selectedTypeSet" (MANY IN ONE):',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.accent),
              ),
              const Spacer(),
              Text(
                '${_siblings.length} Part${_siblings.length == 1 ? '' : 's'} in this Set',
                style: const TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (int i = 0; i < _siblings.length; i++) ...[
                  InkWell(
                    onTap: () => _loadSiblingData(i),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _activeSiblingIndex == i ? SoftErpTheme.accentSoft : SoftErpTheme.cardSurfaceAlt,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _activeSiblingIndex == i ? SoftErpTheme.accent : SoftErpTheme.border,
                          width: _activeSiblingIndex == i ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _siblings[i].isSaved ? Icons.check_circle : Icons.radio_button_checked,
                            size: 14,
                            color: _activeSiblingIndex == i ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${i + 1}. ${_siblings[i].partName} (${_siblings[i].alloy})',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _activeSiblingIndex == i ? FontWeight.w800 : FontWeight.w600,
                              color: _activeSiblingIndex == i ? SoftErpTheme.accent : SoftErpTheme.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                InkWell(
                  onTap: _addSiblingPart,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: SoftErpTheme.cardSurfaceAlt,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SoftErpTheme.accent),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.add, size: 15, color: SoftErpTheme.accent),
                        SizedBox(width: 4),
                        Text('+ Add Part to Set', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoftErpTheme.accent)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card & Field Builders
  Widget _buildCard({
    required String title,
    required String badge,
    required Widget child,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
        boxShadow: SoftErpTheme.insetShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: SoftErpTheme.accentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  badge,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: SoftErpTheme.accent),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing,
              ],
            ],
          ),
          const Divider(height: 24),
          child,
        ],
      ),
    );
  }

  Widget _buildFieldInput({required String label, required TextEditingController controller}) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildReadonlyBadge({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: SoftErpTheme.textSecondary)),
          const SizedBox(height: 2),
          Text(value.isEmpty ? '—' : value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildYieldCounter(String label, int value, ValueChanged<int> onChanged) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: SoftErpTheme.cardSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: SoftErpTheme.textSecondary)),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                InkWell(
                  onTap: () {
                    if (value > 0) onChanged(value - 1);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: SoftErpTheme.sectionSurface, borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.remove, size: 14),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('$value', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
                ),
                InkWell(
                  onTap: () => onChanged(value + 1),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: SoftErpTheme.sectionSurface, borderRadius: BorderRadius.circular(4)),
                    child: const Icon(Icons.add, size: 14),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
