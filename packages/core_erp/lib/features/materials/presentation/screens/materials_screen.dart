import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/soft_master_data.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/material_definition.dart';
import '../providers/materials_provider.dart';

/// The material master: a name and a density, and nothing else.
///
/// It looks slight because it is. Sheet planning already works out a sheet's
/// volume down to the blade width; what it cannot know is what the sheet is
/// made of. This screen supplies that one missing number, and volume × density
/// turns every plan into a weight — which is what material is bought by, scrap
/// is sold by, and a challan is weighed in.
class MaterialsScreen extends StatefulWidget {
  const MaterialsScreen({super.key});

  /// On the widget, not the state: the shell opens the editor from a keyboard
  /// shortcut with no MaterialsScreen mounted.
  static Future<void> openMaterialEditor(
    BuildContext context, {
    MaterialDefinition? material,
  }) {
    return showErpFormDialog<void>(
      context,
      maxWidth: 720,
      maxHeight: 620,
      child: _MaterialEditorSheet(material: material),
    );
  }

  @override
  State<MaterialsScreen> createState() => _MaterialsScreenState();
}

class _MaterialsScreenState extends State<MaterialsScreen> {
  bool _isGridView = true;
  String _category = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MaterialsProvider>().ensureLoaded();
    });
  }

  List<MaterialDefinition> _visible(MaterialsProvider provider) {
    final byCategory = _category == 'all'
        ? provider.filteredMaterials
        : provider.filteredMaterials
              .where((material) => material.category == _category)
              .toList();
    return byCategory;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MaterialsProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.materials.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        final materials = _visible(provider);
        final counts = <String, int>{
          'all': provider.materials.length,
          for (final key in const ['metal', 'plastic', 'other'])
            key: provider.materials.where((m) => m.category == key).length,
        };

        return SoftMasterDataPage(
          title: 'Materials',
          subtitle:
              'Density is what turns a planned sheet into a weight. '
              'Edit any figure — your supplier’s brass is not a handbook’s.',
          action: AppButton(
            label: 'Add Material',
            icon: Icons.add,
            isLoading: provider.isSaving,
            onPressed: () => MaterialsScreen.openMaterialEditor(context),
          ),
          toolbar: SoftMasterToolbar(
            children: [
              SoftMasterSearchField(
                hintText: 'Search materials',
                onChanged: provider.setSearchQuery,
              ),
              SoftSegmentedFilter<String>(
                selected: _category,
                onChanged: (value) => setState(() => _category = value),
                options: [
                  SoftSegmentOption(
                    value: 'all',
                    label: 'All',
                    count: counts['all'],
                  ),
                  SoftSegmentOption(
                    value: 'metal',
                    label: 'Metals',
                    count: counts['metal'],
                  ),
                  SoftSegmentOption(
                    value: 'plastic',
                    label: 'Plastics',
                    count: counts['plastic'],
                  ),
                  SoftSegmentOption(
                    value: 'other',
                    label: 'Other',
                    count: counts['other'],
                  ),
                ],
              ),
              SoftViewToggleButton(
                isGridView: _isGridView,
                onTap: () => setState(() => _isGridView = !_isGridView),
              ),
            ],
          ),
          messages: [
            if (provider.errorMessage != null)
              _MaterialsBanner(message: provider.errorMessage!),
          ],
          body: materials.isEmpty
              ? AppEmptyState(
                  title: 'No materials found',
                  message: provider.searchQuery.isEmpty
                      ? 'Add the materials you cut, with the density your '
                            'supplier quotes.'
                      : 'Nothing matches “${provider.searchQuery}”.',
                  icon: Icons.layers_outlined,
                )
              : _isGridView
              ? _MaterialCardGrid(materials: materials, provider: provider)
              : _MaterialTable(materials: materials),
        );
      },
    );
  }
}

/// A 4′ × 8′ sheet at 1.6 mm — the size a shop buys by default.
///
/// The card shows what one of these weighs in each material, because a bare
/// "7.85 g/cm³" means nothing to the person holding the sheet, and "37.3 kg"
/// means everything. It is also the fastest way to spot a density entered in
/// the wrong unit: a sheet that weighs 37 tonnes reads wrong instantly.
class ReferenceSheet {
  const ReferenceSheet._();

  static const double widthMm = 1219.2; // 48″
  static const double heightMm = 2438.4; // 96″
  static const double thicknessMm = 1.6;

  static const String label = '4′×8′ × 1.6 mm';

  /// In cm³, since density is quoted per cm³.
  static double get volumeCm3 =>
      (widthMm / 10) * (heightMm / 10) * (thicknessMm / 10);

  static String weightLabel(MaterialDefinition material) {
    final kg = material.weightKg(volumeCm3);
    if (kg <= 0) return '';
    return '$label → ${kg.toStringAsFixed(1)} kg';
  }
}

class _MaterialCardGrid extends StatelessWidget {
  const _MaterialCardGrid({required this.materials, required this.provider});

  final List<MaterialDefinition> materials;
  final MaterialsProvider provider;

  @override
  Widget build(BuildContext context) {
    return SoftEntityCardGrid(
      itemCount: materials.length,
      maxCardWidth: 268,
      cardHeight: 262,
      itemBuilder: (context, index) {
        final material = materials[index];
        return SoftEntityCard(
          key: ValueKey('material-card-${material.id}'),
          title: material.name,
          subtitle: material.densityLabel,
          photoUrl: provider.imageUrl(material),
          fallbackIcon: Icons.layers_outlined,
          badge: SoftPill(
            label: _categoryLabel(material.category),
            background: Colors.white.withValues(alpha: 0.92),
          ),
          details: [
            SoftEntityDetail(
              icon: Icons.scale_outlined,
              value: ReferenceSheet.weightLabel(material),
            ),
            if (material.notes.trim().isNotEmpty)
              SoftEntityDetail(icon: Icons.info_outline, value: material.notes),
          ],
          onTap: () =>
              MaterialsScreen.openMaterialEditor(context, material: material),
        );
      },
    );
  }
}

class _MaterialTable extends StatelessWidget {
  const _MaterialTable({required this.materials});

  final List<MaterialDefinition> materials;

  @override
  Widget build(BuildContext context) {
    return SoftMasterTable(
      columns: const [
        SoftTableColumn('Material', flex: 3),
        SoftTableColumn('Density', flex: 2),
        SoftTableColumn('Category', flex: 2),
        SoftTableColumn(ReferenceSheet.label, flex: 2),
        SoftTableColumn('Notes', flex: 4),
      ],
      itemCount: materials.length,
      rowBuilder: (context, index) {
        final material = materials[index];
        return SoftMasterRow(
          key: ValueKey('material-row-${material.id}'),
          onTap: () =>
              MaterialsScreen.openMaterialEditor(context, material: material),
          children: [
            Expanded(
              flex: 3,
              child: Text(
                material.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                material.densityLabel,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: SoftErpTheme.textPrimary,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: SoftInlineText(_categoryLabel(material.category)),
            ),
            Expanded(
              flex: 2,
              child: Text(
                ReferenceSheet.weightLabel(material).split('→ ').last,
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                  color: SoftErpTheme.textSecondary,
                ),
              ),
            ),
            Expanded(flex: 4, child: SoftInlineText(material.notes)),
          ],
        );
      },
    );
  }
}

String _categoryLabel(String category) => switch (category) {
  'metal' => 'Metal',
  'plastic' => 'Plastic',
  _ => 'Other',
};

class _MaterialsBanner extends StatelessWidget {
  const _MaterialsBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// Name, density, category, notes — and a live readout of what the density
/// means, so a figure entered in the wrong unit is caught while it is being
/// typed rather than after it has priced a job.
class _MaterialEditorSheet extends StatefulWidget {
  const _MaterialEditorSheet({this.material});

  final MaterialDefinition? material;

  @override
  State<_MaterialEditorSheet> createState() => _MaterialEditorSheetState();
}

class _MaterialEditorSheetState extends State<_MaterialEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _density;
  late final TextEditingController _notes;
  late String _category;
  String? _error;

  bool get _isEditing => widget.material != null;

  @override
  void initState() {
    super.initState();
    final material = widget.material;
    _name = TextEditingController(text: material?.name ?? '');
    _density = TextEditingController(
      text: material == null || material.densityGCm3 <= 0
          ? ''
          : _trimZeros(material.densityGCm3),
    );
    _notes = TextEditingController(text: material?.notes ?? '');
    _category = material?.category ?? 'metal';
  }

  @override
  void dispose() {
    _name.dispose();
    _density.dispose();
    _notes.dispose();
    super.dispose();
  }

  static String _trimZeros(double value) {
    final text = value.toStringAsFixed(4);
    return text.contains('.')
        ? text.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')
        : text;
  }

  double get _densityValue => double.tryParse(_density.text.trim()) ?? 0;

  /// The one mistake this form exists to catch.
  ///
  /// Handbooks quote steel both as 7.85 g/cm³ and as 7850 kg/m³, and the two
  /// look equally like "the density of steel". Stored in the wrong one, every
  /// sheet weighs a thousand times too much and nothing on screen looks odd.
  String? get _unitWarning {
    final value = _densityValue;
    if (value <= 30) return null;
    return value >= 100
        ? 'That looks like kg/m³. Divide by 1000 — steel is 7.85, not 7850.'
        : 'Nothing solid is denser than osmium at 22.6. Check the figure.';
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the material a name.');
      return;
    }
    if (_densityValue <= 0) {
      setState(() => _error = 'A density is what this master is for.');
      return;
    }
    if (_unitWarning != null) {
      setState(() => _error = _unitWarning);
      return;
    }

    final provider = context.read<MaterialsProvider>();
    final base =
        widget.material ??
        const MaterialDefinition(id: 0, name: '', densityGCm3: 0);
    final saved = await provider.save(
      base.copyWith(
        name: name,
        densityGCm3: _densityValue,
        category: _category,
        notes: _notes.text.trim(),
      ),
    );
    if (!mounted) return;
    if (saved) {
      Navigator.of(context).pop();
      showAppToast(
        context,
        _isEditing ? 'Material saved' : 'Material added',
        kind: AppToastKind.success,
      );
    } else {
      setState(() => _error = provider.errorMessage ?? 'Could not save.');
    }
  }

  Future<void> _archive() async {
    final material = widget.material;
    if (material == null) return;
    final provider = context.read<MaterialsProvider>();
    final done = await provider.archive(material);
    if (!mounted) return;
    if (done) {
      Navigator.of(context).pop();
      showAppToast(context, '${material.name} archived');
    } else {
      setState(() => _error = provider.errorMessage ?? 'Could not archive.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MaterialsProvider>();
    final warning = _unitWarning;
    return ErpFormScaffold(
      title: _isEditing ? widget.material!.name : 'Add Material',
      subtitle: 'Density in grams per cubic centimetre',
      onClose: () => Navigator.of(context).pop(),
      errorBanner: _error == null ? null : _MaterialsBanner(message: _error!),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ErpDialogSectionCard(
            title: 'Material',
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  key: const ValueKey('material-name-field'),
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    hintText: 'Steel / MS',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _density,
                        key: const ValueKey('material-density-field'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Density',
                          suffixText: 'g/cm³',
                          hintText: '7.85',
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _category,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'metal',
                            child: Text('Metal'),
                          ),
                          DropdownMenuItem(
                            value: 'plastic',
                            child: Text('Plastic'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _category = value ?? 'metal'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notes,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    hintText: 'Grade, supplier, anything worth remembering',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _DensityReadout(densityGCm3: _densityValue, warning: warning),
        ],
      ),
      footer: Row(
        children: [
          if (_isEditing)
            AppButton(
              label: 'Archive',
              variant: AppButtonVariant.secondary,
              onPressed: provider.isSaving ? null : _archive,
            ),
          const Spacer(),
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: _isEditing ? 'Save' : 'Add Material',
            isLoading: provider.isSaving,
            onPressed: provider.isSaving ? null : _save,
          ),
        ],
      ),
    );
  }
}

/// What the typed density means for a sheet you can picture.
class _DensityReadout extends StatelessWidget {
  const _DensityReadout({required this.densityGCm3, this.warning});

  final double densityGCm3;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final isWarning = warning != null;
    final kg = densityGCm3 * ReferenceSheet.volumeCm3 / 1000;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isWarning ? const Color(0xFFFFF7ED) : const Color(0xFFF5F7FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isWarning ? const Color(0xFFFDBA74) : SoftErpTheme.border,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isWarning ? Icons.warning_amber_rounded : Icons.scale_outlined,
            size: 18,
            color: isWarning
                ? const Color(0xFFC2410C)
                : SoftErpTheme.textSecondary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isWarning
                  ? warning!
                  : densityGCm3 <= 0
                  ? 'Enter a density to see what a sheet of it weighs.'
                  : 'A ${ReferenceSheet.label} sheet weighs '
                        '${kg.toStringAsFixed(1)} kg.',
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: isWarning
                    ? const Color(0xFFC2410C)
                    : SoftErpTheme.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
