import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/export_preview_dialog.dart';
import '../../domain/global_materials.dart';
import '../providers/materials_provider.dart';

/// The global materials catalogue, next to what this shop already has.
///
/// The counterpart of the Global Units Library: every material the system
/// knows, with its handbook density, grouped by category. A material already
/// in the master shows ticked; one that is not can be added with a tick, which
/// is how an archived material comes back. The whole list can be downloaded —
/// as a sheet, a CSV, or a PDF — for the person who wants the densities on
/// paper next to the shear.
class GlobalMaterialsLibraryDialog extends StatefulWidget {
  const GlobalMaterialsLibraryDialog({super.key});

  static const String exportTitle = 'Materials';

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => const GlobalMaterialsLibraryDialog(),
    );
  }

  @override
  State<GlobalMaterialsLibraryDialog> createState() =>
      _GlobalMaterialsLibraryDialogState();
}

class _GlobalMaterialsLibraryDialogState
    extends State<GlobalMaterialsLibraryDialog> {
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // The dialog can be opened before the Materials screen has ever loaded the
    // master, and "in your master" is meaningless against an empty list.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<MaterialsProvider>().ensureLoaded();
    });
  }

  static Set<String> _namesOf(MaterialsProvider provider) => provider.materials
      .map((material) => material.name.trim().toLowerCase())
      .toSet();

  static bool _isInMaster(GlobalMaterial material, Set<String> names) =>
      names.contains(material.name.toLowerCase());

  Future<void> _add(GlobalMaterial material, MaterialsProvider provider) async {
    setState(() => _isSaving = true);
    try {
      final added = await provider.save(material.toDefinition());
      if (added == null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              provider.errorMessage ?? 'Could not add ${material.name}.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addAll(
    List<GlobalMaterial> materials,
    MaterialsProvider provider,
  ) async {
    for (final material in materials) {
      if (_isInMaster(material, _namesOf(provider))) continue;
      await _add(material, provider);
      if (!mounted) return;
    }
  }

  Future<void> _download(MaterialsProvider provider) {
    return ExportPreviewDialog.show(
      context,
      title: GlobalMaterialsLibraryDialog.exportTitle,
      data: globalMaterialExportRows(
        masterNames: provider.materials.map((material) => material.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<MaterialsProvider>();
    final names = _namesOf(provider);
    final byCategory = globalMaterialsByCategory;
    final inMasterCount = globalMaterials
        .where((material) => _isInMaster(material, names))
        .length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 720),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.public, color: SoftErpTheme.accent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Global Materials Library',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('global-materials-download'),
                  onPressed: () => _download(provider),
                  icon: const Icon(Icons.download_outlined, size: 18),
                  label: const Text('Download'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: SoftErpTheme.accent,
                    side: const BorderSide(color: SoftErpTheme.accent),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Every material the system knows, with its handbook density in '
              'g/cm³. Tick one to add it to your materials, or download the '
              'whole list. $inMasterCount of ${globalMaterials.length} are in '
              'your master.',
              style: const TextStyle(color: SoftErpTheme.textSecondary),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.builder(
                itemCount: globalMaterialCategories.length,
                itemBuilder: (context, index) {
                  final category = globalMaterialCategories[index];
                  final materials = byCategory[category]!;
                  final allInMaster = materials.every(
                    (material) => _isInMaster(material, names),
                  );
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: allInMaster,
                              onChanged: (allInMaster || _isSaving)
                                  ? null
                                  : (value) {
                                      if (value == true) {
                                        _addAll(materials, provider);
                                      }
                                    },
                              activeColor: SoftErpTheme.accent,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              globalMaterialCategoryLabel(category),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: SoftErpTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${materials.length}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: SoftErpTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              for (final material in materials)
                                _MaterialTile(
                                  material: material,
                                  inMaster: _isInMaster(material, names),
                                  enabled: !_isSaving,
                                  onAdd: () => _add(material, provider),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MaterialTile extends StatelessWidget {
  const _MaterialTile({
    required this.material,
    required this.inMaster,
    required this.enabled,
    required this.onAdd,
  });

  final GlobalMaterial material;
  final bool inMaster;
  final bool enabled;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      key: ValueKey('global-material-${material.name}'),
      title: Row(
        children: [
          Flexible(
            child: Text(
              material.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: inMaster
                    ? SoftErpTheme.textSecondary
                    : SoftErpTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              material.densityLabel,
              style: const TextStyle(
                fontSize: 12,
                color: SoftErpTheme.textSecondary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
      subtitle: material.notes.isEmpty
          ? null
          : Text(material.notes, style: const TextStyle(fontSize: 12)),
      value: inMaster,
      onChanged: (inMaster || !enabled)
          ? null
          : (value) {
              if (value == true) onAdd();
            },
      activeColor: SoftErpTheme.accent,
      controlAffinity: ListTileControlAffinity.leading,
    );
  }
}
