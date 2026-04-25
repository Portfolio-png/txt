import 'package:flutter/material.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_info_panel.dart';
import '../../../../core/widgets/app_section_title.dart';
import '../barcode/material_barcode_toolkit.dart';

class PMScreen extends StatefulWidget {
  const PMScreen({super.key});

  @override
  State<PMScreen> createState() => _PMScreenState();
}

class _PMScreenState extends State<PMScreen> {
  final _sandboxNameController = TextEditingController(text: 'Paper Cone');
  final _sandboxPropertyController = TextEditingController();
  String _selectedSegment = 'group';
  String _selectedSegmentSoft = 'group';
  String _uxFamily = 'context';
  String _uxMethod = 'workspace';
  String _sandboxType = 'Primary';
  bool _sandboxAddSubGroup = true;
  bool _sandboxAddItem = false;
  bool _sandboxAddProperties = true;
  String? _sandboxSubGroup = 'Cone';
  String? _sandboxItem;
  final List<String> _sandboxProperties = <String>['GSM', 'Width'];
  String _sandboxLayout = 'workspace';

  @override
  void initState() {
    super.initState();
    _sandboxNameController.addListener(_refreshSandbox);
    _sandboxPropertyController.addListener(_refreshSandbox);
  }

  @override
  void dispose() {
    _sandboxNameController.removeListener(_refreshSandbox);
    _sandboxPropertyController.removeListener(_refreshSandbox);
    _sandboxNameController.dispose();
    _sandboxPropertyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _PMHero(),
            const SizedBox(height: 24),
            _FigmaSegmentSection(
              selectedValue: _selectedSegment,
              onChanged: (value) {
                setState(() {
                  _selectedSegment = value;
                });
              },
            ),
            const SizedBox(height: 24),
            _FigmaSoftSegmentSection(
              selectedValue: _selectedSegmentSoft,
              onChanged: (value) {
                setState(() {
                  _selectedSegmentSoft = value;
                });
              },
            ),
            const SizedBox(height: 24),
            _PMInventorySandboxSection(
              nameController: _sandboxNameController,
              propertyController: _sandboxPropertyController,
              groupType: _sandboxType,
              addSubGroup: _sandboxAddSubGroup,
              addItem: _sandboxAddItem,
              addProperties: _sandboxAddProperties,
              selectedSubGroup: _sandboxSubGroup,
              selectedItem: _sandboxItem,
              properties: _sandboxProperties,
              layout: _sandboxLayout,
              onLayoutChanged: (value) {
                setState(() {
                  _sandboxLayout = value;
                });
              },
              onGroupTypeChanged: (value) {
                setState(() {
                  _sandboxType = value;
                });
              },
              onAddSubGroupChanged: (value) {
                setState(() {
                  _sandboxAddSubGroup = value;
                  if (!value) {
                    _sandboxSubGroup = null;
                  } else {
                    _sandboxSubGroup ??= 'Cone';
                  }
                });
              },
              onAddItemChanged: (value) {
                setState(() {
                  _sandboxAddItem = value;
                  if (!value) {
                    _sandboxItem = null;
                  } else {
                    _sandboxItem ??= 'Funnel Small';
                  }
                });
              },
              onAddPropertiesChanged: (value) {
                setState(() {
                  _sandboxAddProperties = value;
                  if (!value) {
                    _sandboxPropertyController.clear();
                  }
                });
              },
              onSubGroupChanged: (value) {
                setState(() {
                  _sandboxSubGroup = value;
                });
              },
              onItemChanged: (value) {
                setState(() {
                  _sandboxItem = value;
                });
              },
              onQuickAddItem: _quickAddSandboxItem,
              onAddProperty: _addSandboxProperty,
              onRemoveProperty: (property) {
                setState(() {
                  _sandboxProperties.remove(property);
                });
              },
              onReset: _resetSandbox,
            ),
            const SizedBox(height: 24),
            _PMInventoryUxExplorationSection(
              selectedFamily: _uxFamily,
              selectedMethod: _uxMethod,
              onFamilyChanged: (value) {
                setState(() {
                  _uxFamily = value;
                  _uxMethod = switch (value) {
                    'context' => 'workspace',
                    'guided' => 'stepper',
                    'fast' => 'sheet',
                    _ => 'workspace',
                  };
                });
              },
              onMethodChanged: (value) {
                setState(() {
                  _uxMethod = value;
                });
              },
            ),
            const SizedBox(height: 24),
            const _PMDatabaseIdeasSection(),
            const SizedBox(height: 24),
            const _ButtonLibrarySection(),
            const SizedBox(height: 24),
            const _BarcodeToolkitSection(),
          ],
        ),
      ),
    );
  }

  void _refreshSandbox() {
    if (mounted) {
      setState(() {});
    }
  }

  void _addSandboxProperty() {
    final value = _sandboxPropertyController.text.trim();
    if (value.isEmpty || _sandboxProperties.contains(value)) {
      return;
    }

    setState(() {
      _sandboxProperties.add(value);
      _sandboxPropertyController.clear();
      _sandboxAddProperties = true;
    });
  }

  void _resetSandbox() {
    setState(() {
      _sandboxNameController.text = 'Paper Cone';
      _sandboxPropertyController.clear();
      _sandboxType = 'Primary';
      _sandboxAddSubGroup = true;
      _sandboxAddItem = false;
      _sandboxAddProperties = true;
      _sandboxSubGroup = 'Cone';
      _sandboxItem = null;
      _sandboxProperties
        ..clear()
        ..addAll(['GSM', 'Width']);
      _sandboxLayout = 'workspace';
    });
  }

  void _quickAddSandboxItem() {
    setState(() {
      _sandboxAddItem = true;
      _sandboxItem = 'New Inline Item';
    });
  }
}

class _PMHero extends StatelessWidget {
  const _PMHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(
          colors: [Color(0xFF111827), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A1E3A8A),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTight = constraints.maxWidth < 760;

          return Flex(
            direction: isTight ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                flex: isTight ? 0 : 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      child: const Text(
                        'PM',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Custom button and shared UI playground',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1.15,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Use this space to collect the custom buttons, actions, and reusable UI patterns we want available across the app.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFFE5E7EB),
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: isTight ? 0 : 24, height: isTight ? 24 : 0),
              const Expanded(flex: 2, child: _HeroPreviewCard()),
            ],
          );
        },
      ),
    );
  }
}

class _HeroPreviewCard extends StatelessWidget {
  const _HeroPreviewCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Pinned actions',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              AppButton(label: 'Primary CTA', onPressed: null),
              AppButton(
                label: 'Secondary',
                onPressed: null,
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ButtonLibrarySection extends StatelessWidget {
  const _ButtonLibrarySection();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Button library',
            subtitle:
                'A starter home for shared custom buttons and reusable UI states across Paper ERP.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 780;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Expanded(
                    child: _ButtonGroupCard(
                      title: 'Primary actions',
                      description:
                          'High-emphasis actions for save, create, and proceed flows.',
                      children: [
                        AppButton(
                          label: 'Create Item',
                          icon: Icons.add_rounded,
                          onPressed: null,
                        ),
                        AppButton(
                          label: 'Sync Pipeline',
                          icon: Icons.sync_rounded,
                          onPressed: null,
                        ),
                        AppButton(
                          label: 'Saving',
                          onPressed: null,
                          isLoading: true,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 16, height: 16),
                  Expanded(
                    child: _ButtonGroupCard(
                      title: 'Secondary actions',
                      description:
                          'Lower-emphasis actions for support flows, filters, and previews.',
                      children: [
                        AppButton(
                          label: 'Preview',
                          icon: Icons.visibility_outlined,
                          onPressed: null,
                          variant: AppButtonVariant.secondary,
                        ),
                        AppButton(
                          label: 'Export',
                          icon: Icons.file_download_outlined,
                          onPressed: null,
                          variant: AppButtonVariant.secondary,
                        ),
                        AppButton(
                          label: 'Open Config',
                          icon: Icons.tune_outlined,
                          onPressed: null,
                          variant: AppButtonVariant.secondary,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BarcodeToolkitSection extends StatelessWidget {
  const _BarcodeToolkitSection();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Barcode toolkit',
            subtitle:
                'Reusable barcode UI lives in PM so Inventory can keep its own UX while future modules reuse the same building blocks.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 860;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: _BarcodeToolkitDocCard(
                      title: 'What is reusable',
                      bullets: [
                        'Scan trace badge',
                        'Inline barcode preview',
                        'Desktop barcode sheet dialog',
                        'Shared material barcode detail rows',
                      ],
                    ),
                  ),
                  const SizedBox(width: 16, height: 16),
                  Expanded(
                    child: AppCard(
                      padding: const EdgeInsets.all(18),
                      backgroundColor: const Color(0xFFF8F7FF),
                      borderColor: const Color(0xFFE0DEFF),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            'Reference components',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF111827),
                            ),
                          ),
                          SizedBox(height: 14),
                          BarcodeTraceBadge(scanCount: 4),
                          SizedBox(height: 14),
                          InlineBarcodePreview(value: 'CHD-8266-01'),
                          SizedBox(height: 14),
                          Text(
                            'Docs path: lib/features/pm/BARCODE_TOOLKIT.md',
                            style: TextStyle(
                              color: Color(0xFF6B7280),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BarcodeToolkitDocCard extends StatelessWidget {
  const _BarcodeToolkitDocCard({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          ...bullets.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: Color(0xFF6C63FF),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FigmaSegmentSection extends StatelessWidget {
  const _FigmaSegmentSection({
    required this.selectedValue,
    required this.onChanged,
  });

  final String selectedValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Figma custom button',
            subtitle:
                'Translated from node 15289:6503 in Funnel Reborn and added to PM as a reusable segmented control.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 720;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _FigmaPreviewPanel(
                      selectedValue: selectedValue,
                      onChanged: onChanged,
                    ),
                  ),
                  SizedBox(width: isNarrow ? 0 : 20, height: isNarrow ? 20 : 0),
                  const Expanded(child: _FigmaSpecPanel()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FigmaPreviewPanel extends StatelessWidget {
  const _FigmaPreviewPanel({
    required this.selectedValue,
    required this.onChanged,
  });

  final String selectedValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Live preview',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'This keeps the compact pill shape, active gradient fill, and tight label tracking from the design.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: PMFigmaSegmentedControl(
              value: selectedValue,
              onChanged: onChanged,
              variant: PMFigmaSegmentedControlVariant.gradient,
            ),
          ),
        ],
      ),
    );
  }
}

class _FigmaSoftSegmentSection extends StatelessWidget {
  const _FigmaSoftSegmentSection({
    required this.selectedValue,
    required this.onChanged,
  });

  final String selectedValue;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Figma custom button alt',
            subtitle:
                'Translated from node 15289:6480 in Funnel Reborn as the softer selected state with a white chip and blue active text.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 720;

              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Alternate state preview',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'This version keeps the same shell but swaps the selected chip to a white surface with a shadow and bright blue label.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF6B7280)),
                          ),
                          const SizedBox(height: 24),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: PMFigmaSegmentedControl(
                              value: selectedValue,
                              onChanged: onChanged,
                              variant: PMFigmaSegmentedControlVariant.soft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: isNarrow ? 0 : 20, height: isNarrow ? 20 : 0),
                  const Expanded(child: _FigmaSoftSpecPanel()),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FigmaSpecPanel extends StatelessWidget {
  const _FigmaSpecPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mapped details',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          const _SpecRow(
            label: 'Container',
            value: '20px radius, 2px outer padding',
          ),
          const _SpecRow(
            label: 'Active state',
            value: 'Vertical violet gradient + subtle drop shadow',
          ),
          const _SpecRow(
            label: 'Typography',
            value: '12px label size with compact line-height and tracking',
          ),
          const _SpecRow(
            label: 'Options',
            value: 'Group and Item, with reusable toggle behavior',
          ),
        ],
      ),
    );
  }
}

class _FigmaSoftSpecPanel extends StatelessWidget {
  const _FigmaSoftSpecPanel();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mapped details',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          const _SpecRow(
            label: 'Container',
            value: 'Same light shell, same 2px padding, same chip spacing',
          ),
          const _SpecRow(
            label: 'Active state',
            value: 'White selected chip, subtle shadow, blue active label',
          ),
          const _SpecRow(
            label: 'Typography',
            value: '12px text, semibold when active and medium when idle',
          ),
          const _SpecRow(
            label: 'Reuse',
            value:
                'Implemented as a second visual variant of the same reusable segmented control',
          ),
        ],
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: const Color(0xFF93C5FD),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFFE5E7EB),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _PMInventoryUxExplorationSection extends StatelessWidget {
  const _PMInventoryUxExplorationSection({
    required this.selectedFamily,
    required this.selectedMethod,
    required this.onFamilyChanged,
    required this.onMethodChanged,
  });

  final String selectedFamily;
  final String selectedMethod;
  final ValueChanged<String> onFamilyChanged;
  final ValueChanged<String> onMethodChanged;

  @override
  Widget build(BuildContext context) {
    final families = <_PMUxFamily>[
      const _PMUxFamily(
        id: 'context',
        title: 'Keep inventory context visible',
        description:
            'Good when users need to compare the new group against existing rows while they build it.',
        methods: [
          _PMUxMethod(
            id: 'workspace',
            eyebrow: 'Method 01',
            title: 'Split workspace',
            description:
                'Builder on one side, summary on the other. Strong for comparison and confidence.',
            accent: Color(0xFFEEF2FF),
            mock: _PMSplitWorkspaceMock(),
          ),
          _PMUxMethod(
            id: 'drawer',
            eyebrow: 'Method 02',
            title: 'Right-side drawer',
            description:
                'A side panel that keeps the table visible underneath.',
            accent: Color(0xFFEFF6FF),
            mock: _PMDrawerMock(),
          ),
        ],
      ),
      const _PMUxFamily(
        id: 'guided',
        title: 'Guide the user step by step',
        description:
            'Good when the form feels intimidating or when users need help sequencing decisions.',
        methods: [
          _PMUxMethod(
            id: 'stepper',
            eyebrow: 'Method 03',
            title: 'Stepper flow',
            description:
                'Breaks the form into a sequence so users focus on one layer at a time.',
            accent: Color(0xFFECFDF3),
            mock: _PMStepperMock(),
          ),
        ],
      ),
      const _PMUxFamily(
        id: 'fast',
        title: 'Create quickly and move on',
        description:
            'Good when operators create similar groups often and want speed over explanation.',
        methods: [
          _PMUxMethod(
            id: 'sheet',
            eyebrow: 'Method 04',
            title: 'Command sheet',
            description: 'A compact quick-create panel for repetitive entry.',
            accent: Color(0xFFFFF7ED),
            mock: _PMCommandSheetMock(),
          ),
        ],
      ),
    ];
    final family =
        families.where((item) => item.id == selectedFamily).firstOrNull ??
        families.first;
    final method =
        family.methods.where((item) => item.id == selectedMethod).firstOrNull ??
        family.methods.first;

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Inventory group UX explorations',
            subtitle:
                'Grouped by UX intent, so you can cluster related methods first and compare variants inside each cluster later.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: families
                .map(
                  (item) => _PMChoiceChip(
                    label: item.title,
                    selected: item.id == family.id,
                    onTap: () => onFamilyChanged(item.id),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  family.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  family.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: family.methods
                      .map(
                        (item) => _PMChoiceChip(
                          label: item.title,
                          selected: item.id == method.id,
                          onTap: () => onMethodChanged(item.id),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _PMUxConceptCard(
            eyebrow: method.eyebrow,
            title: method.title,
            description: method.description,
            accent: method.accent,
            child: method.mock,
          ),
          const SizedBox(height: 18),
          AppInfoPanel(
            title: 'How to club these later',
            subtitle:
                'Think in families first, then decide which visual method should represent each family in the product.',
            rows: [
              const AppInfoRow(
                label: 'Context family',
                value:
                    'Workspace and drawer both belong together because they preserve the surrounding inventory view.',
              ),
              const AppInfoRow(
                label: 'Guided family',
                value:
                    'Stepper belongs here because its main job is sequencing and reducing decision overload.',
              ),
              const AppInfoRow(
                label: 'Fast-entry family',
                value:
                    'Command sheet belongs here because its main job is quick repetitive creation.',
              ),
              AppInfoRow(
                label: 'Current selection',
                value:
                    '${family.title} -> ${method.title}. This makes it easier to test one family at a time.',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PMUxFamily {
  const _PMUxFamily({
    required this.id,
    required this.title,
    required this.description,
    required this.methods,
  });

  final String id;
  final String title;
  final String description;
  final List<_PMUxMethod> methods;
}

class _PMUxMethod {
  const _PMUxMethod({
    required this.id,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.accent,
    required this.mock,
  });

  final String id;
  final String eyebrow;
  final String title;
  final String description;
  final Color accent;
  final Widget mock;
}

class _PMInventorySandboxSection extends StatelessWidget {
  const _PMInventorySandboxSection({
    required this.nameController,
    required this.propertyController,
    required this.groupType,
    required this.addSubGroup,
    required this.addItem,
    required this.addProperties,
    required this.selectedSubGroup,
    required this.selectedItem,
    required this.properties,
    required this.layout,
    required this.onLayoutChanged,
    required this.onGroupTypeChanged,
    required this.onAddSubGroupChanged,
    required this.onAddItemChanged,
    required this.onAddPropertiesChanged,
    required this.onSubGroupChanged,
    required this.onItemChanged,
    required this.onQuickAddItem,
    required this.onAddProperty,
    required this.onRemoveProperty,
    required this.onReset,
  });

  final TextEditingController nameController;
  final TextEditingController propertyController;
  final String groupType;
  final bool addSubGroup;
  final bool addItem;
  final bool addProperties;
  final String? selectedSubGroup;
  final String? selectedItem;
  final List<String> properties;
  final String layout;
  final ValueChanged<String> onLayoutChanged;
  final ValueChanged<String> onGroupTypeChanged;
  final ValueChanged<bool> onAddSubGroupChanged;
  final ValueChanged<bool> onAddItemChanged;
  final ValueChanged<bool> onAddPropertiesChanged;
  final ValueChanged<String?> onSubGroupChanged;
  final ValueChanged<String?> onItemChanged;
  final VoidCallback onQuickAddItem;
  final VoidCallback onAddProperty;
  final ValueChanged<String> onRemoveProperty;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final notes = <String>[
      'Group Type: $groupType',
      if (addSubGroup && selectedSubGroup != null)
        'Sub-Group: $selectedSubGroup',
      if (addItem && selectedItem != null) 'Item: $selectedItem',
      if (addProperties && properties.isNotEmpty)
        'Properties: ${properties.join(', ')}',
    ];

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Inventory group sandbox',
            subtitle:
                'Interactive, but fake. Tinker with the same form ideas here without touching the real database.',
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _PMChoiceChip(
                label: 'Split workspace',
                selected: layout == 'workspace',
                onTap: () => onLayoutChanged('workspace'),
              ),
              _PMChoiceChip(
                label: 'Stepper',
                selected: layout == 'stepper',
                onTap: () => onLayoutChanged('stepper'),
              ),
              _PMChoiceChip(
                label: 'Drawer',
                selected: layout == 'drawer',
                onTap: () => onLayoutChanged('drawer'),
              ),
              AppButton(
                label: 'Reset Sandbox',
                onPressed: onReset,
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 980;
              final form = _PMSandboxEditor(
                nameController: nameController,
                propertyController: propertyController,
                groupType: groupType,
                addSubGroup: addSubGroup,
                addItem: addItem,
                addProperties: addProperties,
                selectedSubGroup: selectedSubGroup,
                selectedItem: selectedItem,
                properties: properties,
                onGroupTypeChanged: onGroupTypeChanged,
                onAddSubGroupChanged: onAddSubGroupChanged,
                onAddItemChanged: onAddItemChanged,
                onAddPropertiesChanged: onAddPropertiesChanged,
                onSubGroupChanged: onSubGroupChanged,
                onItemChanged: onItemChanged,
                onQuickAddItem: onQuickAddItem,
                onAddProperty: onAddProperty,
                onRemoveProperty: onRemoveProperty,
              );
              final preview = _PMSandboxPreview(
                name: nameController.text.trim(),
                groupType: groupType,
                addSubGroup: addSubGroup,
                addItem: addItem,
                selectedSubGroup: selectedSubGroup,
                selectedItem: selectedItem,
                properties: properties,
                notes: notes,
                layout: layout,
              );

              if (isNarrow) {
                return Column(
                  children: [form, const SizedBox(height: 16), preview],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: form),
                  const SizedBox(width: 16),
                  Expanded(flex: 2, child: preview),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PMSandboxEditor extends StatelessWidget {
  const _PMSandboxEditor({
    required this.nameController,
    required this.propertyController,
    required this.groupType,
    required this.addSubGroup,
    required this.addItem,
    required this.addProperties,
    required this.selectedSubGroup,
    required this.selectedItem,
    required this.properties,
    required this.onGroupTypeChanged,
    required this.onAddSubGroupChanged,
    required this.onAddItemChanged,
    required this.onAddPropertiesChanged,
    required this.onSubGroupChanged,
    required this.onItemChanged,
    required this.onQuickAddItem,
    required this.onAddProperty,
    required this.onRemoveProperty,
  });

  final TextEditingController nameController;
  final TextEditingController propertyController;
  final String groupType;
  final bool addSubGroup;
  final bool addItem;
  final bool addProperties;
  final String? selectedSubGroup;
  final String? selectedItem;
  final List<String> properties;
  final ValueChanged<String> onGroupTypeChanged;
  final ValueChanged<bool> onAddSubGroupChanged;
  final ValueChanged<bool> onAddItemChanged;
  final ValueChanged<bool> onAddPropertiesChanged;
  final ValueChanged<String?> onSubGroupChanged;
  final ValueChanged<String?> onItemChanged;
  final VoidCallback onQuickAddItem;
  final VoidCallback onAddProperty;
  final ValueChanged<String> onRemoveProperty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sandbox editor',
            style: TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _PMFieldLabel(label: 'Group name'),
          const SizedBox(height: 6),
          TextField(
            controller: nameController,
            decoration: _pmInputDecoration('Enter group name'),
          ),
          const SizedBox(height: 14),
          _PMFieldLabel(label: 'Group type'),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            key: ValueKey<String>('type-$groupType'),
            initialValue: groupType,
            decoration: _pmInputDecoration('Select type'),
            items: const ['Primary', 'Secondary', 'Material', 'Assembly']
                .map(
                  (option) =>
                      DropdownMenuItem(value: option, child: Text(option)),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) {
                onGroupTypeChanged(value);
              }
            },
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _PMSandboxToggleCard(
                  label: 'Sub-group',
                  value: addSubGroup,
                  onChanged: onAddSubGroupChanged,
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String>('sub-$selectedSubGroup-$addSubGroup'),
                    initialValue: selectedSubGroup,
                    decoration: _pmInputDecoration('Choose sub-group'),
                    items: const ['Cone', 'Tube', 'Core']
                        .map(
                          (option) => DropdownMenuItem(
                            value: option,
                            child: Text(option),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: addSubGroup ? onSubGroupChanged : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PMSandboxToggleCard(
                  label: 'Item',
                  value: addItem,
                  onChanged: onAddItemChanged,
                  headerAction: _PMInlineAddAction(
                    label: '+ Add Item',
                    onTap: onQuickAddItem,
                  ),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey<String>('item-$selectedItem-$addItem'),
                    initialValue: selectedItem,
                    decoration: _pmInputDecoration('Choose item'),
                    items: const ['Funnel Small', 'Funnel Large', 'Insert']
                        .map(
                          (option) => DropdownMenuItem(
                            value: option,
                            child: Text(option),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: addItem ? onItemChanged : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PMSandboxToggleCard(
            label: 'Properties',
            value: addProperties,
            onChanged: onAddPropertiesChanged,
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: propertyController,
                        enabled: addProperties,
                        decoration: _pmInputDecoration('Enter property'),
                        onSubmitted: (_) => onAddProperty(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppButton(
                      label: 'Add',
                      onPressed: addProperties ? onAddProperty : null,
                      variant: AppButtonVariant.secondary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: properties
                      .map(
                        (property) => _PMPropertyPill(
                          label: property,
                          onRemove: () => onRemoveProperty(property),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PMSandboxPreview extends StatelessWidget {
  const _PMSandboxPreview({
    required this.name,
    required this.groupType,
    required this.addSubGroup,
    required this.addItem,
    required this.selectedSubGroup,
    required this.selectedItem,
    required this.properties,
    required this.notes,
    required this.layout,
  });

  final String name;
  final String groupType;
  final bool addSubGroup;
  final bool addItem;
  final String? selectedSubGroup;
  final String? selectedItem;
  final List<String> properties;
  final List<String> notes;
  final String layout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppInfoPanel(
          title: 'Local preview only',
          subtitle:
              'This section responds to your changes, but it does not touch the database.',
          rows: [
            AppInfoRow(label: 'Layout mode', value: layout),
            AppInfoRow(label: 'Name', value: name.isEmpty ? 'Untitled' : name),
            AppInfoRow(label: 'Type', value: groupType),
            AppInfoRow(
              label: 'Sub-group',
              value: addSubGroup ? (selectedSubGroup ?? 'Not selected') : 'Off',
            ),
            AppInfoRow(
              label: 'Item',
              value: addItem ? (selectedItem ?? 'Not selected') : 'Off',
            ),
            AppInfoRow(
              label: 'Properties',
              value: properties.isEmpty ? 'None' : properties.join(', '),
            ),
            AppInfoRow(label: 'Generated notes', value: notes.join('\n')),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'How to use this sandbox',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              ...const [
                'Change the layout chip to compare presentation styles.',
                'Edit fields and toggles to feel how the same information behaves in each mode.',
                'Use this to decide UX direction before we wire anything real.',
              ].map(
                (line) => Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    line,
                    style: TextStyle(color: Color(0xFFCBD5E1), height: 1.4),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PMDatabaseIdeasSection extends StatelessWidget {
  const _PMDatabaseIdeasSection();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Database ideas -> UX ideas',
            subtitle:
                'These are proposals only. Nothing here changes the real database, but each model suggests a different product experience.',
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 980;
              return Flex(
                direction: isNarrow ? Axis.vertical : Axis.horizontal,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Expanded(
                    child: _PMDatabaseIdeaCard(
                      title: 'Draft + publish model',
                      databaseIdea:
                          'Store groups as drafts first, then publish a versioned snapshot when approved.',
                      uxIdea:
                          'Lets us build a studio-like editor with autosave, review, and publish instead of a single save button.',
                    ),
                  ),
                  SizedBox(width: 16, height: 16),
                  Expanded(
                    child: _PMDatabaseIdeaCard(
                      title: 'Template + instance model',
                      databaseIdea:
                          'Separate reusable group templates from actual inventory groups created from them.',
                      uxIdea:
                          'Unlocks a gallery-first UX where users start from patterns rather than blank forms.',
                    ),
                  ),
                  SizedBox(width: 16, height: 16),
                  Expanded(
                    child: _PMDatabaseIdeaCard(
                      title: 'Relationship graph model',
                      databaseIdea:
                          'Represent sub-groups, items, and properties as linked nodes instead of packing meaning into notes.',
                      uxIdea:
                          'Supports a visual canvas or map-based builder where users attach pieces spatially and inspect dependencies.',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PMDatabaseIdeaCard extends StatelessWidget {
  const _PMDatabaseIdeaCard({
    required this.title,
    required this.databaseIdea,
    required this.uxIdea,
  });

  final String title;
  final String databaseIdea;
  final String uxIdea;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          const Text(
            'Database proposal',
            style: TextStyle(
              color: Color(0xFF4338CA),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            databaseIdea,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF374151)),
          ),
          const SizedBox(height: 12),
          const Text(
            'UX implication',
            style: TextStyle(
              color: Color(0xFF0F766E),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            uxIdea,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF374151)),
          ),
        ],
      ),
    );
  }
}

class _PMUxConceptCard extends StatelessWidget {
  const _PMUxConceptCard({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.accent,
    required this.child,
  });

  final String eyebrow;
  final String title;
  final String description;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              eyebrow,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: const Color(0xFF111827),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _PMSplitWorkspaceMock extends StatelessWidget {
  const _PMSplitWorkspaceMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: const [
          _PMMockField(label: 'Group name', value: 'Paper Cone'),
          SizedBox(height: 10),
          _PMMockField(label: 'Group type', value: 'Primary'),
          SizedBox(height: 12),
          _PMMockToggle(label: 'Attach sub-group', enabled: true),
          SizedBox(height: 8),
          _PMMockToggle(label: 'Attach item', enabled: false),
          SizedBox(height: 12),
          _PMMockPreviewCard(
            title: 'Live summary',
            lines: ['1 child relation', '2 properties', 'Notes generated'],
          ),
        ],
      ),
    );
  }
}

class _PMStepperMock extends StatelessWidget {
  const _PMStepperMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: const [
          _PMStepRow(index: 1, title: 'Name and type', active: true),
          SizedBox(height: 10),
          _PMStepRow(index: 2, title: 'Attach sub-groups or items'),
          SizedBox(height: 10),
          _PMStepRow(index: 3, title: 'Add properties'),
          SizedBox(height: 10),
          _PMStepRow(index: 4, title: 'Review and create'),
        ],
      ),
    );
  }
}

class _PMCommandSheetMock extends StatelessWidget {
  const _PMCommandSheetMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _PMSheetPill(label: 'Quick Create Group'),
          SizedBox(height: 12),
          _PMDarkField(label: 'Name', value: 'Paper Cone'),
          SizedBox(height: 10),
          _PMDarkField(label: 'Type', value: 'Primary'),
          SizedBox(height: 10),
          _PMDarkField(label: 'Properties', value: 'GSM, Width'),
          SizedBox(height: 12),
          Row(
            children: [
              _PMMiniAction(label: 'Cancel'),
              SizedBox(width: 8),
              _PMMiniAction(label: 'Create', primary: true),
            ],
          ),
        ],
      ),
    );
  }
}

class _PMDrawerMock extends StatelessWidget {
  const _PMDrawerMock();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: const [
                  _PMGhostRow(widthFactor: 1),
                  SizedBox(height: 8),
                  _PMGhostRow(widthFactor: 0.82),
                  SizedBox(height: 8),
                  _PMGhostRow(widthFactor: 0.9),
                ],
              ),
            ),
          ),
          Container(
            width: 150,
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.horizontal(right: Radius.circular(16)),
              border: Border(left: BorderSide(color: Color(0xFFE5E7EB))),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'New Group',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 10),
                _PMGhostRow(widthFactor: 1),
                SizedBox(height: 8),
                _PMGhostRow(widthFactor: 1),
                SizedBox(height: 8),
                _PMGhostRow(widthFactor: 0.74),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PMMockField extends StatelessWidget {
  const _PMMockField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFF6B7280),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD7DEEA)),
          ),
          child: Text(value),
        ),
      ],
    );
  }
}

class _PMChoiceChip extends StatelessWidget {
  const _PMChoiceChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF6C63FF) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: selected ? const Color(0xFF4338CA) : const Color(0xFF374151),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PMFieldLabel extends StatelessWidget {
  const _PMFieldLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: const Color(0xFF374151),
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _PMSandboxToggleCard extends StatelessWidget {
  const _PMSandboxToggleCard({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.child,
    this.headerAction,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget child;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? const Color(0xFFC4B5FD) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              if (headerAction != null) ...[
                const SizedBox(width: 8),
                headerAction!,
              ],
              Switch.adaptive(
                value: value,
                onChanged: onChanged,
                activeThumbColor: const Color(0xFF6C63FF),
                activeTrackColor: const Color(0xFFC4B5FD),
              ),
            ],
          ),
          Opacity(
            opacity: value ? 1 : 0.5,
            child: IgnorePointer(ignoring: !value, child: child),
          ),
        ],
      ),
    );
  }
}

class _PMInlineAddAction extends StatelessWidget {
  const _PMInlineAddAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFC7D2FE)),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: const Color(0xFF4338CA),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PMPropertyPill extends StatelessWidget {
  const _PMPropertyPill({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 6, top: 6, bottom: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9FE),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF5B21B6),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: onRemove,
            child: const Icon(
              Icons.close_rounded,
              size: 16,
              color: Color(0xFF5B21B6),
            ),
          ),
        ],
      ),
    );
  }
}

class _PMGhostRow extends StatelessWidget {
  const _PMGhostRow({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: 18,
        decoration: BoxDecoration(
          color: const Color(0xFFE5E7EB),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _PMMockToggle extends StatelessWidget {
  const _PMMockToggle({required this.label, required this.enabled});

  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled ? const Color(0xFFF3F0FF) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: enabled ? const Color(0xFFC4B5FD) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            width: 36,
            height: 22,
            decoration: BoxDecoration(
              color: enabled
                  ? const Color(0xFF6C63FF)
                  : const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: enabled ? Alignment.centerRight : Alignment.centerLeft,
            padding: const EdgeInsets.all(2),
            child: Container(
              width: 18,
              height: 18,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PMMockPreviewCard extends StatelessWidget {
  const _PMMockPreviewCard({required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                line,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF6B7280)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PMStepRow extends StatelessWidget {
  const _PMStepRow({
    required this.index,
    required this.title,
    this.active = false,
  });

  final int index;
  final String title;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: active ? const Color(0xFF6C63FF) : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: active ? const Color(0xFF6C63FF) : const Color(0xFFD1D5DB),
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            '$index',
            style: TextStyle(
              color: active ? Colors.white : const Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: active ? FontWeight.w700 : FontWeight.w600,
              color: active ? const Color(0xFF111827) : const Color(0xFF6B7280),
            ),
          ),
        ),
      ],
    );
  }
}

class _PMSheetPill extends StatelessWidget {
  const _PMSheetPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PMDarkField extends StatelessWidget {
  const _PMDarkField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: const Color(0xFFCBD5E1),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _PMMiniAction extends StatelessWidget {
  const _PMMiniAction({required this.label, this.primary = false});

  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: primary
            ? const Color(0xFF6C63FF)
            : Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: primary
              ? const Color(0xFF6C63FF)
              : Colors.white.withValues(alpha: 0.1),
        ),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ButtonGroupCard extends StatelessWidget {
  const _ButtonGroupCard({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF6B7280)),
          ),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: children),
        ],
      ),
    );
  }
}

class PMFigmaSegmentedControl extends StatelessWidget {
  const PMFigmaSegmentedControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.variant = PMFigmaSegmentedControlVariant.gradient,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final PMFigmaSegmentedControlVariant variant;

  @override
  Widget build(BuildContext context) {
    const segmentWidth = 108.0;
    const segmentHeight = 42.0;
    const shellPadding = 4.0;
    const gradient = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF5E5BF9), Color(0xFF413F9C)],
      stops: [0, 1],
    );
    final usesGradient = variant == PMFigmaSegmentedControlVariant.gradient;

    return Semantics(
      container: true,
      label: 'PM group and item segmented control',
      child: Container(
        width: (segmentWidth * 2) + (shellPadding * 2),
        height: segmentHeight + (shellPadding * 2),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: const Color(0xFFF5F7F9),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubicEmphasized,
              alignment: value == 'group'
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Container(
                width: segmentWidth,
                height: segmentHeight,
                decoration: BoxDecoration(
                  color: usesGradient ? null : Colors.white,
                  gradient: usesGradient ? gradient : null,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x24000000),
                      blurRadius: 8,
                      offset: Offset(0, 3),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PMFigmaSegmentChip(
                  width: segmentWidth,
                  height: segmentHeight,
                  label: 'Groups',
                  isSelected: value == 'group',
                  onTap: () => onChanged('group'),
                  variant: variant,
                ),
                _PMFigmaSegmentChip(
                  width: segmentWidth,
                  height: segmentHeight,
                  label: 'Items',
                  isSelected: value == 'item',
                  onTap: () => onChanged('item'),
                  variant: variant,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PMFigmaSegmentChip extends StatelessWidget {
  const _PMFigmaSegmentChip({
    required this.width,
    required this.height,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.variant,
  });

  final double width;
  final double height;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final PMFigmaSegmentedControlVariant variant;

  @override
  Widget build(BuildContext context) {
    final usesGradient = variant == PMFigmaSegmentedControlVariant.gradient;
    final activeTextColor = usesGradient
        ? Colors.white
        : const Color(0xFF1100FF);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: height,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                color: isSelected ? activeTextColor : const Color(0xFF1C2632),
                fontSize: 16,
                height: 1,
                letterSpacing: 0,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}

enum PMFigmaSegmentedControlVariant { gradient, soft }

InputDecoration _pmInputDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD7DEEA)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFD7DEEA)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 1.4),
    ),
  );
}
