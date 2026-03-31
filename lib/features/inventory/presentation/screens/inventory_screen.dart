import 'dart:io' show Platform;

import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/shell/navigation_provider.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_empty_state.dart';
import '../../../../core/widgets/app_info_panel.dart';
import '../../../../core/widgets/app_section_title.dart';
import '../../domain/create_parent_material_input.dart';
import '../../domain/material_record.dart';
import '../providers/inventory_provider.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  bool get _isDesktopPlatform =>
      kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    return Consumer<InventoryProvider>(
      builder: (context, inventory, _) {
        if (inventory.isLoading && inventory.materials.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 800 || !_isDesktopPlatform;

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppSectionTitle(
                    title: 'Inventory Materials',
                    subtitle:
                        'Create parent sheets, auto-generate child barcodes, and track scan count across the flow.',
                    trailing: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        AppButton(
                          label: 'Open Scan',
                          icon: Icons.qr_code_scanner_outlined,
                          variant: AppButtonVariant.secondary,
                          onPressed: () {
                            context.read<NavigationProvider>().select(
                              'inventory_scan',
                            );
                          },
                        ),
                        if (_isDesktopPlatform)
                          AppButton(
                            label: 'Add New Big Sheet',
                            icon: Icons.add,
                            isLoading: inventory.isSaving,
                            onPressed: () => _openAddMaterialForm(
                              context,
                              isNarrow: isNarrow,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (!_isDesktopPlatform) ...[
                    const SizedBox(height: 12),
                    const _DesktopOnlyNotice(),
                  ],
                  if (inventory.errorMessage != null) ...[
                    const SizedBox(height: 12),
                    _ErrorBanner(message: inventory.errorMessage!),
                  ],
                  const SizedBox(height: 20),
                  Expanded(
                    child: isNarrow
                        ? _InventoryStackedLayout(
                            materials: inventory.materials,
                          )
                        : _InventoryWideLayout(materials: inventory.materials),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openAddMaterialForm(
    BuildContext context, {
    required bool isNarrow,
  }) async {
    final body = const _AddMaterialForm();
    if (isNarrow) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: body,
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: body,
        ),
      ),
    );
  }
}

class _DesktopOnlyNotice extends StatelessWidget {
  const _DesktopOnlyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: const Text(
        'Barcode generation and new material entry is available only on desktop.',
        style: TextStyle(color: Color(0xFF92400E), fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _InventoryWideLayout extends StatelessWidget {
  const _InventoryWideLayout({required this.materials});

  final List<MaterialRecord> materials;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 3, child: _MaterialsList(materials: materials)),
        const SizedBox(width: 20),
        const Expanded(flex: 2, child: _MaterialDetailsPane()),
      ],
    );
  }
}

class _InventoryStackedLayout extends StatelessWidget {
  const _InventoryStackedLayout({required this.materials});

  final List<MaterialRecord> materials;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MaterialsList(
            materials: materials,
            shrinkWrap: true,
            scrollable: false,
          ),
          const SizedBox(height: 16),
          const _MaterialDetailsPane(),
        ],
      ),
    );
  }
}

class _MaterialsList extends StatelessWidget {
  const _MaterialsList({
    required this.materials,
    this.shrinkWrap = false,
    this.scrollable = true,
  });

  final List<MaterialRecord> materials;
  final bool shrinkWrap;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    if (materials.isEmpty) {
      return const AppEmptyState(
        title: 'No materials yet',
        message:
            'Add a big sheet to generate its child barcodes and start the inventory trace flow.',
      );
    }

    final parents = materials.where((item) => item.isParent).toList();
    final children = materials.where((item) => item.isChild).toList();

    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: scrollable
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      itemCount: parents.length,
      separatorBuilder: (_, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final parent = parents[index];
        final linkedChildren = children
            .where((child) => child.parentBarcode == parent.barcode)
            .toList(growable: false);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _MaterialListItem(record: parent),
            if (linkedChildren.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 18, top: 10),
                child: Column(
                  children: linkedChildren
                      .map(
                        (child) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MaterialListItem(
                            record: child,
                            isChild: true,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _MaterialListItem extends StatelessWidget {
  const _MaterialListItem({required this.record, this.isChild = false});

  final MaterialRecord record;
  final bool isChild;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();
    final isSelected = provider.selectedMaterial?.barcode == record.barcode;

    return AppCard(
      onTap: () =>
          context.read<InventoryProvider>().selectMaterial(record.barcode),
      backgroundColor: isSelected ? const Color(0xFFF4F1FF) : Colors.white,
      borderColor: isSelected
          ? const Color(0xFF6C63FF)
          : const Color(0xFFE5E7F0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: isChild ? 54 : 64,
            decoration: BoxDecoration(
              color: isChild
                  ? const Color(0xFFC7D2FE)
                  : const Color(0xFF6C63FF),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                    _Badge(label: record.isParent ? 'Parent' : 'Child'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  record.barcode,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF4B5563),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text('${record.type} • ${record.grade}'),
                    Text('Thickness ${record.thickness}'),
                    Text(
                      record.isParent
                          ? 'Parent of ${record.numberOfChildren} children'
                          : 'Child of ${record.parentBarcode}',
                    ),
                    Text('Scanned ${record.scanCount} times'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MaterialDetailsPane extends StatelessWidget {
  const _MaterialDetailsPane();

  bool get _isDesktopPlatform =>
      kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Widget build(BuildContext context) {
    final selected = context.watch<InventoryProvider>().selectedMaterial;

    if (selected == null) {
      return const AppEmptyState(
        title: 'Select a material',
        message:
            'Choose a parent or child material to inspect its barcode, relationship details, and scan count.',
        icon: Icons.search_outlined,
      );
    }

    return AppInfoPanel(
      title: selected.name,
      subtitle: selected.isParent
          ? 'Parent material record'
          : 'Child material record',
      headerTrailing: _ScanTraceBadge(scanCount: selected.scanCount),
      rows: [
        AppInfoRow(label: 'Barcode', value: selected.barcode),
        if (_isDesktopPlatform)
          AppInfoRow(
            label: 'Barcode image',
            child: _InlineBarcodePreview(value: selected.barcode),
          ),
        AppInfoRow(label: 'Type', value: selected.type),
        AppInfoRow(label: 'Grade', value: selected.grade),
        AppInfoRow(label: 'Thickness', value: selected.thickness),
        AppInfoRow(label: 'Supplier', value: selected.supplier),
        AppInfoRow(
          label: 'Relationship',
          value: selected.isParent
              ? 'Parent of ${selected.numberOfChildren} children'
              : 'Child of ${selected.parentBarcode}',
        ),
        AppInfoRow(
          label: 'Scan trace',
          value: 'Scanned ${selected.scanCount} times',
        ),
        if (selected.isParent)
          AppInfoRow(
            label: 'Child barcodes',
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: selected.linkedChildBarcodes
                  .map((barcode) => _Badge(label: barcode))
                  .toList(),
            ),
          ),
      ],
      footer: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          if (_isDesktopPlatform) _ShowBarcodeButton(material: selected),
          _DebugResetTraceButton(barcode: selected.barcode),
        ],
      ),
    );
  }
}

class _AddMaterialForm extends StatefulWidget {
  const _AddMaterialForm();

  @override
  State<_AddMaterialForm> createState() => _AddMaterialFormState();
}

class _AddMaterialFormState extends State<_AddMaterialForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _typeController = TextEditingController();
  final _gradeController = TextEditingController();
  final _thicknessController = TextEditingController();
  final _supplierController = TextEditingController();
  final _childrenController = TextEditingController(text: '2');
  final _nameFocus = FocusNode();
  final _typeFocus = FocusNode();
  final _gradeFocus = FocusNode();
  final _thicknessFocus = FocusNode();
  final _supplierFocus = FocusNode();
  final _childrenFocus = FocusNode();

  @override
  void dispose() {
    _nameController.dispose();
    _typeController.dispose();
    _gradeController.dispose();
    _thicknessController.dispose();
    _supplierController.dispose();
    _childrenController.dispose();
    _nameFocus.dispose();
    _typeFocus.dispose();
    _gradeFocus.dispose();
    _thicknessFocus.dispose();
    _supplierFocus.dispose();
    _childrenFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<InventoryProvider>();

    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionTitle(
                title: 'Add New Big Sheet',
                subtitle:
                    'Save one parent material and auto-generate child barcodes in one step.',
              ),
              const SizedBox(height: 18),
              _FormField(
                controller: _nameController,
                label: 'Name',
                focusNode: _nameFocus,
                nextFocus: _typeFocus,
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _typeController,
                label: 'Type',
                focusNode: _typeFocus,
                nextFocus: _gradeFocus,
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _gradeController,
                label: 'Grade',
                focusNode: _gradeFocus,
                nextFocus: _thicknessFocus,
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _thicknessController,
                label: 'Thickness',
                focusNode: _thicknessFocus,
                nextFocus: _supplierFocus,
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _supplierController,
                label: 'Supplier',
                focusNode: _supplierFocus,
                nextFocus: _childrenFocus,
              ),
              const SizedBox(height: 12),
              _FormField(
                controller: _childrenController,
                label: 'Cut into X children',
                keyboardType: TextInputType.number,
                focusNode: _childrenFocus,
                textInputAction: TextInputAction.done,
                onSubmitted: () => _submit(context),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Save Parent + Children',
                      isLoading: provider.isSaving,
                      onPressed: () => _submit(context),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final childrenCount = int.tryParse(_childrenController.text.trim()) ?? 0;
    final provider = context.read<InventoryProvider>();
    await provider.addParentMaterial(
      CreateParentMaterialInput(
        name: _nameController.text.trim(),
        type: _typeController.text.trim(),
        grade: _gradeController.text.trim(),
        thickness: _thicknessController.text.trim(),
        supplier: _supplierController.text.trim(),
        numberOfChildren: childrenCount,
      ),
    );

    if (!context.mounted || provider.errorMessage != null) {
      return;
    }

    Navigator.of(context).maybePop();
  }
}

class _FormField extends StatelessWidget {
  const _FormField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.focusNode,
    this.nextFocus,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final FocusNode? focusNode;
  final FocusNode? nextFocus;
  final TextInputAction? textInputAction;
  final VoidCallback? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      focusNode: focusNode,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
        ),
      ),
      validator: (value) {
        final trimmed = value?.trim() ?? '';
        if (trimmed.isEmpty) {
          return 'Required';
        }
        if (label == 'Cut into X children') {
          final number = int.tryParse(trimmed) ?? 0;
          if (number < 1) {
            return 'Enter at least 1 child';
          }
        }
        return null;
      },
      textInputAction: textInputAction ?? TextInputAction.next,
      onFieldSubmitted: (_) {
        if (nextFocus != null) {
          FocusScope.of(context).requestFocus(nextFocus);
          return;
        }
        onSubmitted?.call();
      },
    );
  }
}

class _ScanTraceBadge extends StatelessWidget {
  const _ScanTraceBadge({required this.scanCount});

  final int scanCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEAFE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Scanned $scanCount times',
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF5B4FE6),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _InlineBarcodePreview extends StatelessWidget {
  const _InlineBarcodePreview({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7F0)),
      ),
      child: BarcodeWidget(
        barcode: Barcode.code128(),
        data: value,
        drawText: false,
        width: 220,
        height: 48,
        color: const Color(0xFF111827),
        backgroundColor: Colors.white,
      ),
    );
  }
}

class _ShowBarcodeButton extends StatelessWidget {
  const _ShowBarcodeButton({required this.material});

  final MaterialRecord material;

  @override
  Widget build(BuildContext context) {
    return AppButton(
      label: 'Show Barcode',
      icon: Icons.qr_code_2_outlined,
      variant: AppButtonVariant.secondary,
      onPressed: () {
        showDialog<void>(
          context: context,
          builder: (context) => Dialog(
            insetPadding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _BarcodeSheetDialog(material: material),
            ),
          ),
        );
      },
    );
  }
}

class _BarcodeSheetDialog extends StatelessWidget {
  const _BarcodeSheetDialog({required this.material});

  final MaterialRecord material;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: '${material.name} Barcode',
            subtitle: material.isParent
                ? 'Desktop-generated barcode sheet for the parent and its linked children.'
                : 'Desktop-generated barcode sheet for this selected child material.',
          ),
          const SizedBox(height: 20),
          Flexible(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _BarcodeSheetCard(
                    title: material.name,
                    subtitle: material.isParent
                        ? 'Parent Sheet'
                        : 'Child Sheet',
                    barcode: material.barcode,
                  ),
                  ...material.linkedChildBarcodes.map(
                    (barcode) => _BarcodeSheetCard(
                      title: 'Linked Child',
                      subtitle: barcode,
                      barcode: barcode,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Align(
            alignment: Alignment.centerRight,
            child: AppButton(
              label: 'Close',
              variant: AppButtonVariant.secondary,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarcodeSheetCard extends StatelessWidget {
  const _BarcodeSheetCard({
    required this.title,
    required this.subtitle,
    required this.barcode,
  });

  final String title;
  final String subtitle;
  final String barcode;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: SizedBox(
        width: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            BarcodeWidget(
              barcode: Barcode.code128(),
              data: barcode,
              width: 252,
              height: 80,
              color: const Color(0xFF111827),
              backgroundColor: Colors.white,
            ),
          ],
        ),
      ),
    );
  }
}

class _DebugResetTraceButton extends StatelessWidget {
  const _DebugResetTraceButton({required this.barcode});

  final String barcode;

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: AppButton(
        label: 'Reset Trace',
        icon: Icons.restore,
        variant: AppButtonVariant.secondary,
        onPressed: () {
          context.read<InventoryProvider>().resetScanTrace(barcode);
        },
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEEEAFE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          color: Color(0xFF5B4FE6),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF991B1B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
