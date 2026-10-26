import 'package:flutter/material.dart';

import 'package:core_erp/core/theme/soft_erp_theme.dart';
import 'package:core_erp/core/widgets/app_button.dart';
import 'package:core_erp/core/widgets/app_card.dart';
import 'package:core_erp/core/widgets/app_section_title.dart';
import 'package:core_erp/core/widgets/app_toast.dart';
import 'package:core_erp/core/widgets/searchable_select.dart';
import '../screens/pm_item_master_detail_screen.dart';

/// Available UX modes to compare for the Group -> Sub Group -> Item -> Variation workflow.
enum PMCascadeViewMode {
  matrixGrid, // Direct Spreadsheet Grid (Screenshot Fidelity)
  millerColumns, // Miller Columns / Cascading Finder
  progressiveLedger, // Progressive Version & Drawing Stream
  quickMatrixBar, // Fast-Entry Operator Ribbon
}

/// A progressive variation / version of an Item.
///
/// Changes with progressive numbers (48, 49, 50...).
/// Each variation holds its own Photo, CAD file, and timestamp of noting.
class PMItemVariation {
  PMItemVariation({
    required this.number,
    required this.partCode,
    required this.date,
    required this.time,
    this.photoName = 'dolly_patti_brass.png',
    this.cadFileName = 'SADBP48_Rev2.step',
    this.cadFileSize = '1.4 MB',
    this.material = 'Brass',
    this.gauge = '22G',
    this.status = PMVariationStatus.okey,
    this.notedBy = 'Puranik (Q.C.)',
  });

  int number;
  String partCode;
  String date;
  String time;
  String photoName;
  String cadFileName;
  String cadFileSize;
  String material;
  String gauge;
  PMVariationStatus status;
  String notedBy;
}

enum PMVariationStatus {
  auto,
  edit,
  okey,
}

/// PM Tab Section exploring alternative UX/UI models for:
/// - Group (Switch Action)
/// - Sub Group (Dolly)
/// - Item (Patti)
/// - Progressive Variations (48, 49, 50...) with Photo, CAD, Date & Time of noting.
class PMGroupItemCascadeSection extends StatefulWidget {
  const PMGroupItemCascadeSection({super.key});

  @override
  State<PMGroupItemCascadeSection> createState() =>
      _PMGroupItemCascadeSectionState();
}

class _PMGroupItemCascadeSectionState extends State<PMGroupItemCascadeSection> {
  PMCascadeViewMode _currentMode = PMCascadeViewMode.matrixGrid;

  // Selected Hierarchy
  String _selectedGroup = 'Switch Action';
  String _selectedSubGroup = 'Dolly';
  String _selectedItem = 'Patti';

  // Group Catalog
  final List<String> _groups = [
    'Cutout',
    'Double Pole',
    'Switch Action',
    'Socket',
    'Others',
  ];

  // Sub Group Catalog mapped by Group
  final Map<String, List<String>> _subGroupsByGroup = {
    'Switch Action': ['Dolly', 'Italya', 'Rocker', 'Ram Ban', 'TC No'],
    'Cutout': ['Porcelain Cutout', 'Deluxe Cutout', 'Heavy Duty'],
    'Double Pole': ['32A DP', '63A DP', 'Modular DP'],
    'Socket': ['2-in-1 Socket', 'Multi Socket', 'Uni Socket'],
    'Others': ['Terminal Block', 'Spacer', 'Spring Washer'],
  };

  // Items mapped by Sub Group
  final Map<String, List<String>> _itemsBySubGroup = {
    'Dolly': ['Patti', 'Dabbi', 'Threading Patti', 'Cam', 'Spring'],
    'Italya': ['Base Plate', 'Contact Patti', 'Bridge'],
    'Rocker': ['Rocker Knob', 'Pivot Patti', 'Terminal Pin'],
    'Ram Ban': ['Main Contact', 'Catch Patti', 'Slide Guide'],
    'TC No': ['TC Patti', 'Screw Clamp', 'Washer'],
  };

  /// Items are keyed by group AND sub-group. Keyed by the sub-group name
  /// alone, every new group's "General" replaced every other group's, and a
  /// "Dolly" added under Cutout wiped Switch Action › Dolly. The seed above is
  /// still read by bare sub-group name, as the fallback.
  static String _itemsKey(String group, String subGroup) => '$group›$subGroup';

  /// The one fallback: a selection that falls back to "Item 1" while its
  /// option list fell back to "Patti" showed nothing selected.
  static const List<String> _defaultItems = ['Item 1'];

  List<String> _itemsFor(String group, String subGroup) =>
      _itemsBySubGroup[_itemsKey(group, subGroup)] ??
      _itemsBySubGroup[subGroup] ??
      _defaultItems;

  /// The list to add to, copied under this group's own key first.
  List<String> _editableItemsFor(String group, String subGroup) =>
      _itemsBySubGroup[_itemsKey(group, subGroup)] ??=
          List<String>.of(_itemsFor(group, subGroup));

  bool _hasName(Iterable<String> names, String name) =>
      names.any((n) => n.trim().toLowerCase() == name.trim().toLowerCase());

  // Progressive variations for the selected item (Patti)
  late final List<PMItemVariation> _variations = [
    PMItemVariation(
      number: 48,
      partCode: 'SADBP48',
      date: '15/05/2026',
      time: '10.05 AM',
      photoName: 'dolly_patti_48_brass.webp',
      cadFileName: 'SADBP48_RevA.step',
      status: PMVariationStatus.okey,
    ),
    PMItemVariation(
      number: 49,
      partCode: 'SADBP49',
      date: '18/05/2026',
      time: '02.40 PM',
      photoName: 'dolly_patti_49_brass.webp',
      cadFileName: 'SADBP49_RevB.step',
      status: PMVariationStatus.okey,
    ),
    PMItemVariation(
      number: 50,
      partCode: 'SADBP50',
      date: '20/05/2026',
      time: '11.15 AM',
      photoName: 'dolly_patti_50_brass.webp',
      cadFileName: 'SADBP50_RevC.step',
      status: PMVariationStatus.auto,
    ),
  ];

  int _selectedVariationIndex = 0;
  final bool _isAutoCodeEnabled = true;

  String _formatDate(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';

  String _formatTime(DateTime dt) {
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final a = dt.hour >= 12 ? 'PM' : 'AM';
    return '${h.toString().padLeft(2, '0')}.$m $a';
  }

  // Controllers for Inline Editing
  late TextEditingController _partNoController;
  late TextEditingController _partCodeController;
  late TextEditingController _dateController;
  late TextEditingController _timeController;

  @override
  void initState() {
    super.initState();
    final current = _variations[_selectedVariationIndex];
    _partNoController = TextEditingController(text: '${current.number}');
    _partCodeController = TextEditingController(text: current.partCode);
    _dateController = TextEditingController(text: current.date);
    _timeController = TextEditingController(text: current.time);
  }

  @override
  void dispose() {
    _partNoController.dispose();
    _partCodeController.dispose();
    _dateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  void _syncControllersWithActiveVariation() {
    if (_selectedVariationIndex >= _variations.length) {
      _selectedVariationIndex = 0;
    }
    final v = _variations[_selectedVariationIndex];
    _partNoController.text = '${v.number}';
    _partCodeController.text = v.partCode;
    _dateController.text = v.date;
    _timeController.text = v.time;
  }

  String _derivePartCode(int partNumber) {
    // Switch Action (SA) + Dolly (D) + Brass (B) + Patti (P) + number
    // A one-letter group ("A") is a group too; substring(0, 2) threw on it.
    final g = _selectedGroup == 'Switch Action'
        ? 'SA'
        : (_selectedGroup.length < 2
                ? _selectedGroup
                : _selectedGroup.substring(0, 2))
            .toUpperCase();
    final sg = _selectedSubGroup.isNotEmpty ? _selectedSubGroup.substring(0, 1).toUpperCase() : 'X';
    final it = _selectedItem.isNotEmpty ? _selectedItem.substring(0, 1).toUpperCase() : 'P';
    return '$g$sg${'B'}$it$partNumber';
  }

  void _addNextProgressiveVariation() {
    final lastNum = _variations.isNotEmpty ? _variations.last.number : 47;
    final nextNum = lastNum + 1;
    final now = DateTime.now();
    final dateStr = _formatDate(now);
    final timeStr = _formatTime(now);
    final nextCode = _derivePartCode(nextNum);

    final newVar = PMItemVariation(
      number: nextNum,
      partCode: nextCode,
      date: dateStr,
      time: timeStr,
      photoName: 'dolly_${_selectedItem.toLowerCase()}_$nextNum.webp',
      cadFileName: '${nextCode}_Rev1.step',
      status: PMVariationStatus.auto,
    );

    setState(() {
      _variations.add(newVar);
      _selectedVariationIndex = _variations.length - 1;
      _syncControllersWithActiveVariation();
    });

    showAppToast(context, 'Stamped progressive version #$nextNum ($nextCode)');
  }

  void _addNewGroupDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Group', style: TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Group Name', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty && _hasName(_groups, val)) {
                // Re-adding "Socket" duplicated it and wiped its sub-groups.
                showAppToast(context, '"$val" is already a group.');
                return;
              }
              if (val.isNotEmpty) {
                setState(() {
                  _groups.add(val);
                  _subGroupsByGroup[val] = ['General'];
                  _itemsBySubGroup[_itemsKey(val, 'General')] = ['Item 1'];
                  _selectedGroup = val;
                  _selectedSubGroup = 'General';
                  _selectedItem = 'Item 1';
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add Group'),
          ),
        ],
      ),
    );
  }

  void _addNewSubGroupDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Sub Group to "$_selectedGroup"', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Sub Group Name', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty &&
                  _hasName(_subGroupsByGroup[_selectedGroup] ?? const [], val)) {
                showAppToast(context, '"$val" is already under $_selectedGroup.');
                return;
              }
              if (val.isNotEmpty) {
                setState(() {
                  (_subGroupsByGroup[_selectedGroup] ??= []).add(val);
                  _itemsBySubGroup[_itemsKey(_selectedGroup, val)] = ['Component 1'];
                  _selectedSubGroup = val;
                  _selectedItem = 'Component 1';
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add Sub Group'),
          ),
        ],
      ),
    );
  }

  void _addNewItemDialog() {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Add Item under "$_selectedSubGroup"', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Item Name', border: OutlineInputBorder()),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                setState(() {
                  _editableItemsFor(_selectedGroup, _selectedSubGroup).add(val);
                  _selectedItem = val;
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Add Item'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Mode Switcher
          // Header Row with Title and Item Master 1 Action
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AppSectionTitle(
                  title: 'Hierarchy & Progressive Variation Matrix (PM Lab)',
                  subtitle:
                      'Group (Switch Action) ➔ Sub Group (Dolly) ➔ Item (Patti) with auto-incrementing progressive versions (#48, #49...), Photo, CAD, and date/time tracking.',
                ),
              ),
              const SizedBox(width: 16),
              AppButton(
                key: const ValueKey('nav_to_item_master_detail_btn'),
                label: 'Item Master 1 (Alloy & Dies) ↗',
                icon: Icons.open_in_new_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PMItemMasterDetailScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 14),

          // View Mode Selector Row
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: SoftErpTheme.sectionSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SoftErpTheme.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModeButton(
                  mode: PMCascadeViewMode.matrixGrid,
                  label: 'Matrix Grid',
                  icon: Icons.grid_on_rounded,
                  tooltip: 'Exact Screenshot spreadsheet cascade',
                ),
                _buildModeButton(
                  mode: PMCascadeViewMode.millerColumns,
                  label: 'Miller Columns',
                  icon: Icons.view_column_rounded,
                  tooltip: 'Finder-style lazy browsing',
                ),
                _buildModeButton(
                  mode: PMCascadeViewMode.progressiveLedger,
                  label: 'Progressive Ledger',
                  icon: Icons.photo_library_outlined,
                  tooltip: 'Visual Photo & CAD drawing history',
                ),
                _buildModeButton(
                  mode: PMCascadeViewMode.quickMatrixBar,
                  label: 'Fast-Entry Bar',
                  icon: Icons.bolt_rounded,
                  tooltip: 'High-speed keyboard entry ribbon',
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Active Mode Body
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: switch (_currentMode) {
              PMCascadeViewMode.matrixGrid => _buildMatrixGridMode(),
              PMCascadeViewMode.millerColumns => _buildMillerColumnsMode(),
              PMCascadeViewMode.progressiveLedger => _buildProgressiveLedgerMode(),
              PMCascadeViewMode.quickMatrixBar => _buildQuickMatrixBarMode(),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required PMCascadeViewMode mode,
    required String label,
    required IconData icon,
    required String tooltip,
  }) {
    final isSelected = _currentMode == mode;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        key: ValueKey('mode_btn_${mode.name}'),
        onTap: () => setState(() => _currentMode = mode),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? SoftErpTheme.accent : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? Colors.white : SoftErpTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? Colors.white : SoftErpTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // MODE A: Direct Matrix Grid (Fidelity to User's Screenshot)
  // ===========================================================================
  Widget _buildMatrixGridMode() {
    final activeVar = _variations[_selectedVariationIndex];
    final currentSubGroups = _subGroupsByGroup[_selectedGroup] ?? ['General'];
    final currentItems = _itemsFor(_selectedGroup, _selectedSubGroup);

    return Column(
      key: const ValueKey('matrix_grid_mode'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Helper Explanation Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: Row(
            children: [
              const Icon(Icons.info_outline, size: 18, color: Color(0xFF15803D)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Screenshot Fidelity Mode: Click any cell to select or trigger Auto / Edit / Okey. Switch Action is Group, Dolly is Sub Group, Patti is Item. Progressive versions increment with Photo & CAD.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF166534)),
                ),
              ),
              AppButton(
                label: '+ Next Version (#${_variations.last.number + 1})',
                icon: Icons.add,
                onPressed: _addNextProgressiveVariation,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // THE MATRIX TABLE (Matches Screenshot Layout)
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Black Block on the Left ("Group Item")
              Container(
                width: 140,
                height: 380,
                color: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                alignment: Alignment.center,
                child: const Text(
                  'Group\nItem',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                    height: 1.3,
                  ),
                ),
              ),

              // Table Columns (Group | Type/SubGroup | Part Name/Item | Part No | Part Code | Date | Time)
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 900,
                    child: Column(
                      children: [
                        // 1. Column Headers (Grey row)
                        _buildGridHeaderRow(),

                        // 2. Active Selected Values Row (Top highlighted values, Blue text)
                        _buildGridActiveSelectedRow(activeVar),

                        // 3. Selectable Options Cascade Rows (Matches rows from screenshot)
                        _buildGridOptionsCascade(currentSubGroups, currentItems),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // Live Variation Details Card (Photo, CAD, Timestamp, Notes)
        _buildActiveVariationInspector(activeVar),
      ],
    );
  }

  Widget _buildGridHeaderRow() {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          _buildGridHeaderCell('Group', flex: 3),
          _buildGridHeaderCell('Type (Sub Group)', flex: 3),
          _buildGridHeaderCell('Part Name (Item)', flex: 3),
          _buildGridHeaderCell('Part No', flex: 2),
          _buildGridHeaderCell('Part Code', flex: 3),
          _buildGridHeaderCell('Date', flex: 2),
          _buildGridHeaderCell('Time', flex: 2),
        ],
      ),
    );
  }

  Widget _buildGridHeaderCell(String title, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildGridActiveSelectedRow(PMItemVariation activeVar) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFFFCCBC), width: 2)),
      ),
      child: Row(
        children: [
          // Group
          Expanded(
            flex: 3,
            child: _buildGridValueCell(
              text: _selectedGroup,
              isHeader: true,
              color: Colors.black,
            ),
          ),
          // Sub Group (Type)
          Expanded(
            flex: 3,
            child: _buildGridValueCell(
              text: _selectedSubGroup,
              isHeader: true,
              color: Colors.black,
            ),
          ),
          // Part Name (Item)
          Expanded(
            flex: 3,
            child: _buildGridValueCell(
              text: _selectedItem,
              isHeader: true,
              color: Colors.black,
            ),
          ),
          // Part No (Blue in Screenshot)
          Expanded(
            flex: 2,
            child: _buildGridValueCell(
              text: '${activeVar.number}',
              color: const Color(0xFF0284C7),
              isBold: true,
            ),
          ),
          // Part Code (Blue in Screenshot)
          Expanded(
            flex: 3,
            child: _buildGridValueCell(
              text: activeVar.partCode,
              color: const Color(0xFF0284C7),
              isBold: true,
            ),
          ),
          // Date (Blue in Screenshot)
          Expanded(
            flex: 2,
            child: _buildGridValueCell(
              text: activeVar.date,
              color: const Color(0xFF0284C7),
              isBold: true,
            ),
          ),
          // Time (Blue in Screenshot)
          Expanded(
            flex: 2,
            child: _buildGridValueCell(
              text: activeVar.time,
              color: const Color(0xFF0284C7),
              isBold: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGridValueCell({
    required String text,
    Color color = Colors.black,
    bool isHeader = false,
    bool isBold = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: isHeader ? 14 : 13,
          fontWeight: isBold || isHeader ? FontWeight.w800 : FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildGridOptionsCascade(List<String> subGroups, List<String> items) {
    // Determine max rows
    final rowCount = [
      _groups.length + 1,
      subGroups.length + 1,
      items.length + 1,
      4, // Auto, Edit, Okey, blank
    ].reduce((a, b) => a > b ? a : b);

    return Column(
      children: List.generate(rowCount, (rowIndex) {
        // Group Option
        final groupText = rowIndex < _groups.length
            ? _groups[rowIndex]
            : (rowIndex == _groups.length ? '+ Add New' : '');
        final isGroupSelected = groupText == _selectedGroup;

        // SubGroup Option
        final subGroupText = rowIndex < subGroups.length
            ? subGroups[rowIndex]
            : (rowIndex == subGroups.length ? '+ Add New' : '');
        final isSubGroupSelected = subGroupText == _selectedSubGroup;

        // Item Option
        final itemText = rowIndex < items.length
            ? items[rowIndex]
            : (rowIndex == items.length ? '+ Add New' : '');
        final isItemSelected = itemText == _selectedItem;

        // Controls for Part No, Part Code, Date, Time (Auto / Edit / Okey)
        final controlType = switch (rowIndex) {
          0 => 'Auto',
          1 => 'Edit',
          2 => 'Okey',
          _ => '',
        };

        return Container(
          decoration: BoxDecoration(
            color: rowIndex.isEven ? const Color(0xFFFAFAFA) : Colors.white,
            border: const Border(bottom: BorderSide(color: Color(0xFFF1F5F9))),
          ),
          child: Row(
            children: [
              // Group Cell
              Expanded(
                flex: 3,
                child: _buildSelectableOptionCell(
                  text: groupText,
                  isSelected: isGroupSelected,
                  isAddNew: groupText == '+ Add New',
                  onTap: () {
                    if (groupText == '+ Add New') {
                      _addNewGroupDialog();
                    } else if (groupText.isNotEmpty) {
                      setState(() {
                        _selectedGroup = groupText;
                        final nextSubs = _subGroupsByGroup[groupText] ?? ['General'];
                        _selectedSubGroup = nextSubs.first;
                        _selectedItem = _itemsFor(_selectedGroup, _selectedSubGroup).first;
                        _syncControllersWithActiveVariation();
                      });
                    }
                  },
                ),
              ),

              // Sub Group Cell
              Expanded(
                flex: 3,
                child: _buildSelectableOptionCell(
                  text: subGroupText,
                  isSelected: isSubGroupSelected,
                  isAddNew: subGroupText == '+ Add New',
                  onTap: () {
                    if (subGroupText == '+ Add New') {
                      _addNewSubGroupDialog();
                    } else if (subGroupText.isNotEmpty) {
                      setState(() {
                        _selectedSubGroup = subGroupText;
                        _selectedItem = _itemsFor(_selectedGroup, subGroupText).first;
                        _syncControllersWithActiveVariation();
                      });
                    }
                  },
                ),
              ),

              // Item Cell
              Expanded(
                flex: 3,
                child: _buildSelectableOptionCell(
                  text: itemText,
                  isSelected: isItemSelected,
                  isAddNew: itemText == '+ Add New',
                  onTap: () {
                    if (itemText == '+ Add New') {
                      _addNewItemDialog();
                    } else if (itemText.isNotEmpty) {
                      setState(() {
                        _selectedItem = itemText;
                        _syncControllersWithActiveVariation();
                      });
                    }
                  },
                ),
              ),

              // Part No Action
              Expanded(
                flex: 2,
                child: _buildActionPillCell(controlType, () => _handleActionClick('Part No', controlType)),
              ),

              // Part Code Action
              Expanded(
                flex: 3,
                child: _buildActionPillCell(controlType, () => _handleActionClick('Part Code', controlType)),
              ),

              // Date Action
              Expanded(
                flex: 2,
                child: _buildActionPillCell(controlType, () => _handleActionClick('Date', controlType)),
              ),

              // Time Action
              Expanded(
                flex: 2,
                child: _buildActionPillCell(controlType, () => _handleActionClick('Time', controlType)),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildSelectableOptionCell({
    required String text,
    required bool isSelected,
    required bool isAddNew,
    required VoidCallback onTap,
  }) {
    if (text.isEmpty) {
      return Container(
        height: 38,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFF1F5F9))),
        ),
      );
    }

    final textColor = isAddNew
        ? const Color(0xFFD946EF) // Pink for Add New (from screenshot)
        : (isSelected
            ? const Color(0xFFEA580C) // Orange bold for selected (from screenshot)
            : const Color(0xFFFDBA74)); // Soft peach for options

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFFFF7ED) : Colors.transparent,
          border: const Border(right: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSelected)
              const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFFEA580C)),
            if (isSelected) const SizedBox(width: 4),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected || isAddNew ? FontWeight.w800 : FontWeight.w600,
                  color: textColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionPillCell(String action, VoidCallback onTap) {
    if (action.isEmpty) {
      return Container(
        height: 38,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFF1F5F9))),
        ),
      );
    }

    // Colors matching screenshot: Auto = Cyan, Edit = Pink, Okey = Green
    final (bg, fg) = switch (action) {
      'Auto' => (const Color(0xFFE0F2FE), const Color(0xFF0284C7)),
      'Edit' => (const Color(0xFFFCE7F3), const Color(0xFFDB2777)),
      'Okey' => (const Color(0xFFDCFCE7), const Color(0xFF16A34A)),
      _ => (Colors.transparent, Colors.grey),
    };

    return InkWell(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            action,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }

  void _handleActionClick(String field, String action) {
    final active = _variations[_selectedVariationIndex];
    if (action == 'Auto') {
      setState(() {
        if (field == 'Part No') {
          active.number = 48 + _selectedVariationIndex;
          _partNoController.text = '${active.number}';
        } else if (field == 'Part Code') {
          active.partCode = _derivePartCode(active.number);
          _partCodeController.text = active.partCode;
        } else if (field == 'Date') {
          active.date = _formatDate(DateTime.now());
          _dateController.text = active.date;
        } else if (field == 'Time') {
          active.time = _formatTime(DateTime.now());
          _timeController.text = active.time;
        }
        active.status = PMVariationStatus.auto;
      });
      showAppToast(context, 'Reset $field to Auto');
    } else if (action == 'Edit') {
      _showEditFieldDialog(field);
    } else if (action == 'Okey') {
      setState(() {
        active.status = PMVariationStatus.okey;
      });
      showAppToast(context, 'Confirmed and locked $field for #${active.number}');
    }
  }

  void _showEditFieldDialog(String field) {
    final active = _variations[_selectedVariationIndex];
    final ctrl = TextEditingController(
      text: switch (field) {
        'Part No' => '${active.number}',
        'Part Code' => active.partCode,
        'Date' => active.date,
        'Time' => active.time,
        _ => '',
      },
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Edit $field (#${active.number})', style: const TextStyle(fontWeight: FontWeight.w800)),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: field,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final val = ctrl.text.trim();
              if (val.isNotEmpty) {
                setState(() {
                  if (field == 'Part No') {
                    final num = int.tryParse(val) ?? active.number;
                    active.number = num;
                    _partNoController.text = '$num';
                    if (_isAutoCodeEnabled) {
                      active.partCode = _derivePartCode(num);
                      _partCodeController.text = active.partCode;
                    }
                  } else if (field == 'Part Code') {
                    active.partCode = val;
                    _partCodeController.text = val;
                  } else if (field == 'Date') {
                    active.date = val;
                    _dateController.text = val;
                  } else if (field == 'Time') {
                    active.time = val;
                    _timeController.text = val;
                  }
                  active.status = PMVariationStatus.edit;
                });
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save & Apply'),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // INSPECTOR: Photo, CAD, and Progressive Version Stream
  // ===========================================================================
  Widget _buildActiveVariationInspector(PMItemVariation activeVar) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Progressive Version Pills & Controls
          Row(
            children: [
              const Icon(Icons.history_toggle_off_rounded, size: 18, color: SoftErpTheme.accent),
              const SizedBox(width: 8),
              const Text(
                'Progressive Variations for Patti:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < _variations.length; i++) ...[
                        InkWell(
                          onTap: () {
                            setState(() {
                              _selectedVariationIndex = i;
                              _syncControllersWithActiveVariation();
                            });
                          },
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _selectedVariationIndex == i ? SoftErpTheme.accentSoft : SoftErpTheme.sectionSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _selectedVariationIndex == i ? SoftErpTheme.accent : SoftErpTheme.border,
                                width: _selectedVariationIndex == i ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _variations[i].status == PMVariationStatus.okey ? Icons.verified_rounded : Icons.fiber_manual_record,
                                  size: 13,
                                  color: _variations[i].status == PMVariationStatus.okey ? SoftErpTheme.successText : SoftErpTheme.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '#${_variations[i].number} (${_variations[i].partCode})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: _selectedVariationIndex == i ? FontWeight.w800 : FontWeight.w600,
                                    color: _selectedVariationIndex == i ? SoftErpTheme.accentDark : SoftErpTheme.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              AppButton(
                label: '+ Progressive Stamp (#${_variations.last.number + 1})',
                variant: AppButtonVariant.secondary,
                icon: Icons.add_circle_outline,
                onPressed: _addNextProgressiveVariation,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 16),

          // Row 2: Photo Card + CAD Card + Timestamp Noting Badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Photo Thumbnail & Upload
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.sectionSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: SoftErpTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                        ),
                        child: const Icon(Icons.camera_alt_outlined, color: Color(0xFFD97706), size: 30),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('Variation Photo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: SoftErpTheme.successBg, borderRadius: BorderRadius.circular(4)),
                                  child: const Text('Attached', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SoftErpTheme.successText)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(activeVar.photoName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: SoftErpTheme.textSecondary)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => showAppToast(context, 'Simulated photo upload for #${activeVar.number}'),
                              child: const Text('Replace Photo / Capture', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SoftErpTheme.accent)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // CAD File (.step/.dwg) Attachment Card
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.sectionSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: SoftErpTheme.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0E7FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFA5B4FC)),
                        ),
                        child: const Icon(Icons.architecture_rounded, color: Color(0xFF4F46E5), size: 30),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Text('CAD Drawing', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: SoftErpTheme.infoBg, borderRadius: BorderRadius.circular(4)),
                                  child: Text(activeVar.cadFileSize, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: SoftErpTheme.infoText)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(activeVar.cadFileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: SoftErpTheme.textSecondary)),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () => showAppToast(context, 'Opening 3D CAD preview for ${activeVar.cadFileName}'),
                              child: const Text('View 3D / Replace CAD', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SoftErpTheme.accent)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Date & Time of Noting Card
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.sectionSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: SoftErpTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.access_time_filled, size: 14, color: SoftErpTheme.accent),
                          const SizedBox(width: 6),
                          const Text('Noting Timestamp', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
                          const Spacer(),
                          Text(activeVar.notedBy, style: const TextStyle(fontSize: 10, color: SoftErpTheme.textSecondary)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: SoftErpTheme.cardSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: SoftErpTheme.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.calendar_today, size: 12, color: SoftErpTheme.textSecondary),
                                const SizedBox(width: 4),
                                Text(activeVar.date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: SoftErpTheme.cardSurface,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: SoftErpTheme.border),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.schedule, size: 12, color: SoftErpTheme.textSecondary),
                                const SizedBox(width: 4),
                                Text(activeVar.time, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MODE B: Miller Columns (Cascading Finder)
  // ===========================================================================
  Widget _buildMillerColumnsMode() {
    final subGroups = _subGroupsByGroup[_selectedGroup] ?? ['General'];
    final items = _itemsFor(_selectedGroup, _selectedSubGroup);
    final active = _variations[_selectedVariationIndex];

    return Column(
      key: const ValueKey('miller_columns_mode'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFBFDBFE)),
          ),
          child: const Row(
            children: [
              Icon(Icons.view_column_outlined, size: 18, color: Color(0xFF1D4ED8)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Miller Columns Finder: Left-to-right hierarchy drilldown. Clean, low mental friction, lazy data entry with progressive versions column.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        SizedBox(
          height: 380,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Column 1: Groups
              Expanded(
                child: _buildFinderColumn(
                  title: '1. Group',
                  count: _groups.length,
                  items: _groups,
                  selectedItem: _selectedGroup,
                  onSelect: (val) {
                    setState(() {
                      _selectedGroup = val;
                      final nextSubs = _subGroupsByGroup[val] ?? ['General'];
                      _selectedSubGroup = nextSubs.first;
                      _selectedItem = _itemsFor(_selectedGroup, _selectedSubGroup).first;
                    });
                  },
                  onAdd: _addNewGroupDialog,
                ),
              ),
              const SizedBox(width: 12),

              // Column 2: Sub Groups
              Expanded(
                child: _buildFinderColumn(
                  title: '2. Sub Group',
                  count: subGroups.length,
                  items: subGroups,
                  selectedItem: _selectedSubGroup,
                  onSelect: (val) {
                    setState(() {
                      _selectedSubGroup = val;
                      _selectedItem = _itemsFor(_selectedGroup, val).first;
                    });
                  },
                  onAdd: _addNewSubGroupDialog,
                ),
              ),
              const SizedBox(width: 12),

              // Column 3: Items
              Expanded(
                child: _buildFinderColumn(
                  title: '3. Item',
                  count: items.length,
                  items: items,
                  selectedItem: _selectedItem,
                  onSelect: (val) {
                    setState(() {
                      _selectedItem = val;
                    });
                  },
                  onAdd: _addNewItemDialog,
                ),
              ),
              const SizedBox(width: 12),

              // Column 4: Progressive Variations
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: SoftErpTheme.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SoftErpTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: const BoxDecoration(
                          color: SoftErpTheme.sectionSurface,
                          border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
                        ),
                        child: Row(
                          children: [
                            const Text('4. Variations', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
                            const Spacer(),
                            InkWell(
                              onTap: _addNextProgressiveVariation,
                              child: const Icon(Icons.add_circle, size: 18, color: SoftErpTheme.accent),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.separated(
                          padding: const EdgeInsets.all(8),
                          itemCount: _variations.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 6),
                          itemBuilder: (ctx, i) {
                            final v = _variations[i];
                            final isSel = _selectedVariationIndex == i;
                            return InkWell(
                              onTap: () => setState(() => _selectedVariationIndex = i),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSel ? SoftErpTheme.accentSoft : SoftErpTheme.cardSurfaceAlt,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isSel ? SoftErpTheme.accent : SoftErpTheme.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text('#${v.number}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: isSel ? SoftErpTheme.accent : SoftErpTheme.textPrimary)),
                                        const Spacer(),
                                        Text(v.partCode, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: isSel ? SoftErpTheme.accentDark : SoftErpTheme.textSecondary)),
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text('${v.date} · ${v.time}', style: const TextStyle(fontSize: 10, color: SoftErpTheme.textSecondary)),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // Column 5: Inspector Pane
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.cardSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: SoftErpTheme.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: SoftErpTheme.accentSoft, borderRadius: BorderRadius.circular(6)),
                            child: Text(active.partCode, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: SoftErpTheme.accent)),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: active.status == PMVariationStatus.okey ? SoftErpTheme.successBg : SoftErpTheme.infoBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(active.status.name.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: active.status == PMVariationStatus.okey ? SoftErpTheme.successText : SoftErpTheme.infoText)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text('$_selectedGroup > $_selectedSubGroup > $_selectedItem', style: const TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary)),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(child: _buildSmallSpec('Part No', '${active.number}')),
                          const SizedBox(width: 8),
                          Expanded(child: _buildSmallSpec('Date', active.date)),
                          const SizedBox(width: 8),
                          Expanded(child: _buildSmallSpec('Time', active.time)),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _buildSmallSpec('Photo Asset', active.photoName, icon: Icons.image),
                      const SizedBox(height: 8),
                      _buildSmallSpec('CAD Drawing', '${active.cadFileName} (${active.cadFileSize})', icon: Icons.architecture),
                      const Spacer(),
                      AppButton(
                        label: 'Stamp Next (#${_variations.last.number + 1})',
                        icon: Icons.add,
                        onPressed: _addNextProgressiveVariation,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFinderColumn({
    required String title,
    required int count,
    required List<String> items,
    required String selectedItem,
    required ValueChanged<String> onSelect,
    required VoidCallback onAdd,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: SoftErpTheme.sectionSurface,
              border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
            ),
            child: Row(
              children: [
                Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
                const Spacer(),
                InkWell(onTap: onAdd, child: const Icon(Icons.add, size: 16, color: SoftErpTheme.accent)),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(6),
              itemCount: items.length,
              separatorBuilder: (context, index) => const SizedBox(height: 4),
              itemBuilder: (ctx, i) {
                final it = items[i];
                final isSel = it == selectedItem;
                return InkWell(
                  onTap: () => onSelect(it),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSel ? SoftErpTheme.accentSoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            it,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                              color: isSel ? SoftErpTheme.accent : SoftErpTheme.textPrimary,
                            ),
                          ),
                        ),
                        if (isSel) const Icon(Icons.chevron_right, size: 16, color: SoftErpTheme.accent),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallSpec(String label, String value, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: SoftErpTheme.accent),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, color: SoftErpTheme.textSecondary)),
                Text(value, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // MODE C: Progressive Ledger & Drawing Stream
  // ===========================================================================
  Widget _buildProgressiveLedgerMode() {
    return Column(
      key: const ValueKey('progressive_ledger_mode'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top breadcrumb banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            color: SoftErpTheme.accentSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SoftErpTheme.accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              const Icon(Icons.account_tree_outlined, size: 18, color: SoftErpTheme.accent),
              const SizedBox(width: 8),
              const Text('Context: ', style: TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary)),
              Text('$_selectedGroup > $_selectedSubGroup > $_selectedItem', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: SoftErpTheme.accentDark)),
              const Spacer(),
              AppButton(
                label: '+ Progressive Revision (#${_variations.last.number + 1})',
                icon: Icons.add_circle,
                onPressed: _addNextProgressiveVariation,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Progressive Revision Cards Stream
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _variations.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (ctx, i) {
            final v = _variations[i];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: SoftErpTheme.cardSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SoftErpTheme.border),
                boxShadow: SoftErpTheme.insetShadow,
              ),
              child: Row(
                children: [
                  // Progressive Number Badge
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: SoftErpTheme.accentSoft,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '#${v.number}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: SoftErpTheme.accent),
                    ),
                  ),
                  const SizedBox(width: 16),

                  // Part Code & Ancestry
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(v.partCode, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: SoftErpTheme.textPrimary)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: v.status == PMVariationStatus.okey ? SoftErpTheme.successBg : SoftErpTheme.infoBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(v.status.name.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: v.status == PMVariationStatus.okey ? SoftErpTheme.successText : SoftErpTheme.infoText)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('$_selectedGroup · Sub: $_selectedSubGroup · Item: $_selectedItem', style: const TextStyle(fontSize: 12, color: SoftErpTheme.textSecondary)),
                      ],
                    ),
                  ),

                  // Photo Thumbnail
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: SoftErpTheme.sectionSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SoftErpTheme.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.image, size: 16, color: Color(0xFFD97706)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(v.photoName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // CAD Drawing
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: SoftErpTheme.sectionSurface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: SoftErpTheme.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.architecture, size: 16, color: Color(0xFF4F46E5)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(v.cadFileName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Date & Time Timestamp
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(v.date, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: SoftErpTheme.textPrimary)),
                        Text(v.time, style: const TextStyle(fontSize: 11, color: SoftErpTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // ===========================================================================
  // MODE D: Quick Matrix Bar (High Speed Ribbon)
  // ===========================================================================
  Widget _buildQuickMatrixBarMode() {
    final active = _variations[_selectedVariationIndex];
    return Column(
      key: const ValueKey('quick_matrix_bar_mode'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: const Row(
            children: [
              Icon(Icons.bolt, size: 18, color: Color(0xFFEA580C)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Operator Quick-Entry Ribbon: High-speed single row entry. Perfect for barcoded production stations where supervisors stamp progressive pieces with minimal clicks.',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF9A3412)),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Quick Entry Ribbon
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SoftErpTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SoftErpTheme.border),
          ),
          child: Row(
            children: [
              // Group searchable select
              Expanded(
                flex: 3,
                child: _buildSearchSelectField(
                  key: ValueKey('group_$_selectedGroup'),
                  label: 'Group',
                  value: _selectedGroup,
                  options: _groups,
                  onSelected: (v) {
                    setState(() {
                      _selectedGroup = v;
                      final subs = _subGroupsByGroup[v] ?? ['General'];
                      _selectedSubGroup = subs.first;
                      _selectedItem = _itemsFor(_selectedGroup, _selectedSubGroup).first;
                      _syncControllersWithActiveVariation();
                    });
                  },
                  onCreate: (val) {
                    if (_hasName(_groups, val)) return;
                    setState(() {
                      _groups.add(val);
                      _subGroupsByGroup[val] = ['General'];
                      _itemsBySubGroup[_itemsKey(val, 'General')] = ['Item 1'];
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),

              // Sub Group searchable select
              Expanded(
                flex: 3,
                child: _buildSearchSelectField(
                  key: ValueKey('subgroup_$_selectedGroup-$_selectedSubGroup'),
                  label: 'Sub Group',
                  value: _selectedSubGroup,
                  options: _subGroupsByGroup[_selectedGroup] ?? ['General'],
                  onSelected: (v) {
                    setState(() {
                      _selectedSubGroup = v;
                      _selectedItem = _itemsFor(_selectedGroup, v).first;
                      _syncControllersWithActiveVariation();
                    });
                  },
                  onCreate: (val) {
                    if (_hasName(_subGroupsByGroup[_selectedGroup] ?? const [], val)) {
                      return;
                    }
                    setState(() {
                      (_subGroupsByGroup[_selectedGroup] ??= []).add(val);
                      _itemsBySubGroup[_itemsKey(_selectedGroup, val)] = ['Item 1'];
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),

              // Item searchable select
              Expanded(
                flex: 3,
                child: _buildSearchSelectField(
                  key: ValueKey('item_$_selectedSubGroup-$_selectedItem'),
                  label: 'Item',
                  value: _selectedItem,
                  options: _itemsFor(_selectedGroup, _selectedSubGroup),
                  onSelected: (v) {
                    setState(() {
                      _selectedItem = v;
                      _syncControllersWithActiveVariation();
                    });
                  },
                  onCreate: (val) {
                    setState(() {
                      _editableItemsFor(_selectedGroup, _selectedSubGroup).add(val);
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),

              // Progressive Part No
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _partNoController,
                  decoration: const InputDecoration(labelText: 'Part No', isDense: true, border: OutlineInputBorder()),
                  keyboardType: TextInputType.number,
                  onChanged: (val) {
                    final num = int.tryParse(val);
                    if (num != null) {
                      setState(() {
                        active.number = num;
                        active.partCode = _derivePartCode(num);
                        _partCodeController.text = active.partCode;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(width: 10),

              // Part Code
              Expanded(
                flex: 3,
                child: TextFormField(
                  controller: _partCodeController,
                  decoration: const InputDecoration(labelText: 'Part Code', isDense: true, border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),

              // Stamp Action
              AppButton(
                label: 'Stamp #$_selectedItem',
                icon: Icons.check,
                onPressed: () {
                  showAppToast(context, 'Stamped ${_partCodeController.text} at ${_formatTime(DateTime.now())}');
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchSelectField({
    required String label,
    required String value,
    required List<String> options,
    required ValueChanged<String> onSelected,
    ValueChanged<String>? onCreate,
    Key? key,
  }) {
    return InkWell(
      key: key,
      onTap: () async {
        final selected = await showSearchableSelectDialog<String>(
          context: context,
          title: 'Select $label',
          searchHintText: 'Search or add $label...',
          selectedValue: value,
          options: options.map((o) => SearchableSelectOption(value: o, label: o)).toList(),
          canCreateOption: (q, _) => onCreate != null && q.trim().isNotEmpty && !options.contains(q.trim()),
          onCreateOption: onCreate != null
              ? (q) async {
                  final trimmed = q.trim();
                  onCreate(trimmed);
                  return SearchableSelectOption(value: trimmed, label: trimmed);
                }
              : null,
        );
        // onSelected calls setState; the section may be gone by the time the
        // dialog answers.
        if (selected != null && mounted) {
          onSelected(selected.value);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.arrow_drop_down, size: 20),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
