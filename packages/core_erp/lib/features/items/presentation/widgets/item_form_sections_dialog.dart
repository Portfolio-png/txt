import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/item_form_sections.dart';
import '../providers/item_form_sections_provider.dart';

/// Editor for which sections the item form shows.
///
/// Rendered as a dialog from the item editor's "Sections" button and inline
/// (via [ItemFormSectionsEditor]) in Settings → Item Creation, so both places
/// stay in step automatically.
class ItemFormSectionsDialog extends StatelessWidget {
  const ItemFormSectionsDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SoftErpTheme.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Item Form Sections',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: SoftErpTheme.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 19),
                      color: SoftErpTheme.textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Applies to every new item you create, on every screen. Only '
                  'your account is affected.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                const ItemFormSectionsEditor(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The toggle list itself, without any dialog chrome.
///
/// Two modes:
/// - **default mode** (no [value]): reads and writes the signed-in user's own
///   default via [ItemFormSectionsProvider].
/// - **controlled mode** ([value] + [onChanged]): edits a caller-owned layout,
///   used by the group editor to author a per-group override. Nothing is
///   persisted here — the caller saves it with the group.
class ItemFormSectionsEditor extends StatefulWidget {
  const ItemFormSectionsEditor({super.key, this.value, this.onChanged})
    : assert(
        value == null || onChanged != null,
        'A controlled editor needs an onChanged callback.',
      );

  final ItemFormSections? value;
  final ValueChanged<ItemFormSections>? onChanged;

  @override
  State<ItemFormSectionsEditor> createState() => _ItemFormSectionsEditorState();

  static const List<ItemFormSectionKey> _mediaKeys = <ItemFormSectionKey>[
    ItemFormSectionKey.itemImage,
    ItemFormSectionKey.cadFile,
    ItemFormSectionKey.additionalFiles,
  ];

  static const List<ItemFormSectionKey> _otherKeys = <ItemFormSectionKey>[
    ItemFormSectionKey.developedFor,
    ItemFormSectionKey.defaultPipeline,
    ItemFormSectionKey.variationTree,
    ItemFormSectionKey.machines,
    ItemFormSectionKey.dies,
  ];
}

class _ItemFormSectionsEditorState extends State<ItemFormSectionsEditor> {
  bool get _isControlled => widget.value != null;

  @override
  void initState() {
    super.initState();
    if (_isControlled) {
      return;
    }
    // Safe from either entry point (item editor or settings) — the provider
    // only fetches once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ItemFormSectionsProvider>().ensureLoaded();
    });
  }

  Future<void> _toggle(
    BuildContext context,
    ItemFormSectionKey key,
    bool value,
  ) async {
    if (_isControlled) {
      widget.onChanged!(key.applyTo(widget.value!, value));
      return;
    }
    final provider = context.read<ItemFormSectionsProvider>();
    final saved = await provider.setSection(key, value);
    if (!saved) {
      showAppSnack(
        SnackBar(
          content: Text(
            provider.errorMessage ?? 'Could not save your section layout.',
          ),
        ),
      );
    }
  }

  Future<void> _reset(BuildContext context) async {
    if (_isControlled) {
      widget.onChanged!(const ItemFormSections());
      return;
    }
    final provider = context.read<ItemFormSectionsProvider>();
    final saved = await provider.resetToDefaults();
    if (!saved) {
      showAppSnack(
        const SnackBar(content: Text('Could not reset your section layout.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final sections =
        widget.value ?? context.watch<ItemFormSectionsProvider>().sections;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MediaGroup(
          sections: sections,
          onToggle: (key, value) => _toggle(context, key, value),
        ),
        const SizedBox(height: 14),
        for (final key in ItemFormSectionsEditor._otherKeys) ...[
          _SectionToggleTile(
            label: key.label,
            description: key.description,
            value: key.valueOf(sections),
            onChanged: (value) => _toggle(context, key, value),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 2),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: () => _reset(context),
            child: const Text('Reset to defaults'),
          ),
        ),
      ],
    );
  }
}

/// The Media block: one collapsible header with a +/- affordance over the
/// three file-related sections.
class _MediaGroup extends StatefulWidget {
  const _MediaGroup({required this.sections, required this.onToggle});

  final ItemFormSections sections;
  final void Function(ItemFormSectionKey key, bool value) onToggle;

  @override
  State<_MediaGroup> createState() => _MediaGroupState();
}

class _MediaGroupState extends State<_MediaGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final enabledCount = ItemFormSectionsEditor._mediaKeys
        .where((key) => key.valueOf(widget.sections))
        .length;

    return Container(
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.perm_media_outlined,
                    size: 18,
                    color: SoftErpTheme.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Media',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '$enabledCount of ${ItemFormSectionsEditor._mediaKeys.length} on',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: SoftErpTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.remove_circle_outline
                        : Icons.add_circle_outline,
                    size: 19,
                    color: SoftErpTheme.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  for (final key in ItemFormSectionsEditor._mediaKeys) ...[
                    _SectionToggleTile(
                      label: key.label,
                      description: key.description,
                      value: key.valueOf(widget.sections),
                      onChanged: (value) => widget.onToggle(key, value),
                      dense: true,
                    ),
                    if (key != ItemFormSectionsEditor._mediaKeys.last)
                      const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionToggleTile extends StatelessWidget {
  const _SectionToggleTile({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
    this.dense = false,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: dense ? SoftErpTheme.cardSurface : SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
