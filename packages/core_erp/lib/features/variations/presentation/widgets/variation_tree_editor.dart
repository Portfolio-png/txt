import 'package:flutter/material.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../data/variation_tree_service.dart';
import '../../domain/variation_node.dart';

/// Holds a master's variation tree while it is being edited, and knows how to
/// load and save it.
///
/// Separate from the widget because the die form saves the tree as part of
/// saving the die: a brand new die has no id to attach a tree to until its own
/// save returns one, so the host drives persistence and the editor only edits.
class VariationTreeController extends ChangeNotifier {
  VariationTreeController({required this.service, this.type = 'die'});

  final VariationTreeService service;
  final String type;

  List<VariationNode> _nodes = [];
  int _version = 1;
  String _label = '';
  bool _loading = false;
  String? _error;

  List<VariationNode> get nodes => _nodes;
  int get version => _version;
  String get label => _label;
  bool get loading => _loading;
  String? get error => _error;

  /// What is already stored is fixed while the current version describes it.
  /// Nodes added since are always editable — they are additions, and nothing
  /// downstream can have been derived from them yet.
  bool get locked =>
      VariationTree(nodes: _nodes, version: _version).isLocked;

  bool canEdit(VariationNode node) => node.isNew || !locked;

  bool get isEmpty => _nodes.isEmpty;

  Future<void> load(String id) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final tree = await service.fetch(type, id);
      _nodes = tree.nodes;
      _version = tree.version;
      _label = tree.label;
    } catch (error) {
      _error = '$error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Writes the tree against [id]. Returns null on success, or a message.
  /// Rethrows nothing: the host is usually mid-save of its own record.
  Future<String?> save(String id) async {
    if (_nodes.isEmpty) return null;
    try {
      final tree = await service.save(type, id, _nodes);
      _nodes = tree.nodes;
      _version = tree.version;
      _label = tree.label;
      notifyListeners();
      return null;
    } on VariationLockedException catch (error) {
      return '${error.message}\n${error.changes.join('\n')}';
    } catch (error) {
      return '$error';
    }
  }

  Future<String?> declareVersion(
    String id, {
    required String label,
    String note = '',
  }) async {
    try {
      _version = await service.declareVersion(
        type,
        id,
        label: label,
        note: note,
      );
      _label = label;
      notifyListeners();
      return null;
    } catch (error) {
      return '$error';
    }
  }

  void addProperty() {
    _nodes.add(VariationNode(kind: 'property'));
    notifyListeners();
  }

  void addValue(VariationNode property) {
    property.children.add(VariationNode(kind: 'value'));
    notifyListeners();
  }

  void remove(VariationNode node, {VariationNode? parent}) {
    if (parent == null) {
      _nodes.remove(node);
    } else {
      parent.children.remove(node);
    }
    notifyListeners();
  }

  void touch() => notifyListeners();
}

/// A property/value tree, as a section inside someone else's form.
///
/// Built for the die editor, and deliberately not bound to it: the store
/// behind it is keyed by (entity type, id), so the same editor serves any
/// master that grows a tree later.
class VariationTreeEditor extends StatelessWidget {
  const VariationTreeEditor({
    super.key,
    required this.controller,
    this.onDeclareVersion,
  });

  final VariationTreeController controller;

  /// Offered when the tree is locked. Null hides the action — a die that has
  /// not been saved yet has no version to declare against.
  final VoidCallback? onDeclareVersion;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.loading) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _VersionBar(
              version: controller.version,
              label: controller.label,
              locked: controller.locked,
              onDeclareVersion: onDeclareVersion,
            ),
            if (controller.error != null) ...[
              const SizedBox(height: 10),
              Text(
                controller.error!,
                style: const TextStyle(
                  fontSize: 14,
                  color: SoftErpTheme.dangerText,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (controller.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'No variations yet. A property is a thing that varies — '
                  'Cavity, Profile — and its values are what it can be.',
                  style: TextStyle(
                    fontSize: 14.5,
                    color: SoftErpTheme.textSecondary,
                  ),
                ),
              )
            else
              for (final property in controller.nodes) ...[
                _PropertyCard(
                  key: ValueKey(
                    'variation_property_${property.id ?? identityHashCode(property)}',
                  ),
                  controller: controller,
                  property: property,
                ),
                const SizedBox(height: 12),
              ],
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                key: const ValueKey('variation_add_property'),
                onPressed: controller.addProperty,
                icon: const Icon(Icons.add, size: 20),
                label: const Text(
                  'Add property',
                  style: TextStyle(fontSize: 15),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _VersionBar extends StatelessWidget {
  const _VersionBar({
    required this.version,
    required this.label,
    required this.locked,
    required this.onDeclareVersion,
  });

  final int version;
  final String label;
  final bool locked;
  final VoidCallback? onDeclareVersion;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: SoftErpTheme.accentSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label.isEmpty ? 'Version $version' : 'Version $version · $label',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.accentDeeper,
            ),
          ),
        ),
        const SizedBox(width: 10),
        if (locked)
          const Expanded(
            child: Text(
              'Fixed in this version. You can still add — changing or removing '
              'needs a new one.',
              style: TextStyle(
                fontSize: 13.5,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          )
        else
          const Expanded(
            child: Text(
              'Open for changes.',
              style: TextStyle(
                fontSize: 13.5,
                color: SoftErpTheme.textSecondary,
              ),
            ),
          ),
        if (locked && onDeclareVersion != null)
          TextButton.icon(
            key: const ValueKey('variation_new_version'),
            onPressed: onDeclareVersion,
            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
            label: const Text(
              'New version',
              style: TextStyle(fontSize: 14.5),
            ),
          ),
      ],
    );
  }
}

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({
    super.key,
    required this.controller,
    required this.property,
  });

  final VariationTreeController controller;
  final VariationNode property;

  @override
  Widget build(BuildContext context) {
    final editable = controller.canEdit(property);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 14),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusMd),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: _NodeField(
                  node: property,
                  controller: controller,
                  hint: 'Property, e.g. Cavity',
                  editable: editable,
                  bold: true,
                ),
              ),
              const SizedBox(width: 8),
              _InputTypePill(
                property: property,
                controller: controller,
                editable: editable,
              ),
              IconButton(
                key: ValueKey(
                  'variation_remove_${property.id ?? identityHashCode(property)}',
                ),
                tooltip: editable
                    ? 'Remove this property'
                    : 'Fixed in this version',
                iconSize: 20,
                color: SoftErpTheme.textSecondary,
                onPressed: editable
                    ? () => controller.remove(property)
                    : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (property.inputType == 'Numeric') ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.linear_scale,
                    size: 16,
                    color: SoftErpTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Range: ',
                    style: TextStyle(
                      fontSize: 13,
                      color: SoftErpTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(
                    width: 75,
                    child: _BoundField(
                      initialValue: property.numericMin,
                      hint: 'Min',
                      editable: editable,
                      key: ValueKey(
                        'variation_min_${property.id ?? identityHashCode(property)}',
                      ),
                      onChanged: (val) {
                        property.numericMin = val;
                        controller.touch();
                      },
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '–',
                      style: TextStyle(color: SoftErpTheme.textSecondary),
                    ),
                  ),
                  SizedBox(
                    width: 75,
                    child: _BoundField(
                      initialValue: property.numericMax,
                      hint: 'Max',
                      editable: editable,
                      key: ValueKey(
                        'variation_max_${property.id ?? identityHashCode(property)}',
                      ),
                      onChanged: (val) {
                        property.numericMax = val;
                        controller.touch();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ] else if (property.inputType == 'Gauge') ...[
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.straighten, size: 16, color: SoftErpTheme.accent),
                  SizedBox(width: 6),
                  Text(
                    'SWG Gauge input (values entered on orders/parts)',
                    style: TextStyle(
                      fontSize: 13,
                      color: SoftErpTheme.accentDeeper,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ] else if (property.inputType == 'Material') ...[
            const SizedBox(height: 6),
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 4),
              child: Row(
                children: [
                  Icon(Icons.category_outlined, size: 16, color: SoftErpTheme.accent),
                  SizedBox(width: 6),
                  Text(
                    'Material values linked to materials master',
                    style: TextStyle(
                      fontSize: 13,
                      color: SoftErpTheme.accentDeeper,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          for (final value in property.children) ...[
            Padding(
              padding: const EdgeInsets.only(left: 18, bottom: 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.subdirectory_arrow_right,
                    size: 18,
                    color: SoftErpTheme.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _NodeField(
                      node: value,
                      controller: controller,
                      hint: 'Value',
                      editable: controller.canEdit(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 110,
                    child: _NodeField(
                      node: value,
                      controller: controller,
                      hint: 'Code',
                      editable: controller.canEdit(value),
                      isCode: true,
                    ),
                  ),
                  IconButton(
                    tooltip: controller.canEdit(value)
                        ? 'Remove this value'
                        : 'Fixed in this version',
                    iconSize: 18,
                    color: SoftErpTheme.textSecondary,
                    onPressed: controller.canEdit(value)
                        ? () => controller.remove(value, parent: property)
                        : null,
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 18),
              child: TextButton.icon(
                key: ValueKey(
                  'variation_add_value_${property.id ?? identityHashCode(property)}',
                ),
                // Always available, whatever the version says: adding takes
                // nothing away from what was derived under it.
                onPressed: () => controller.addValue(property),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add value', style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeField extends StatefulWidget {
  const _NodeField({
    required this.node,
    required this.controller,
    required this.hint,
    required this.editable,
    this.bold = false,
    this.isCode = false,
  });

  final VariationNode node;
  final VariationTreeController controller;
  final String hint;
  final bool editable;
  final bool bold;
  final bool isCode;

  @override
  State<_NodeField> createState() => _NodeFieldState();
}

class _NodeFieldState extends State<_NodeField> {
  late final TextEditingController _text = TextEditingController(
    text: widget.isCode ? widget.node.code : widget.node.name,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _text,
      enabled: widget.editable,
      style: TextStyle(
        fontSize: widget.bold ? 15.5 : 14.5,
        fontWeight: widget.bold ? FontWeight.w700 : FontWeight.w500,
        color: widget.editable
            ? SoftErpTheme.textPrimary
            : SoftErpTheme.textSecondary,
      ),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: const TextStyle(
          fontSize: 14.5,
          color: SoftErpTheme.textSecondary,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        filled: true,
        fillColor: widget.editable
            ? SoftErpTheme.cardSurface
            : SoftErpTheme.sectionSurface,
        suffixIcon: widget.editable
            ? null
            : const Icon(Icons.lock_outline, size: 16),
        suffixIconConstraints: const BoxConstraints(minWidth: 30, minHeight: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
      ),
      onChanged: (value) {
        if (widget.isCode) {
          widget.node.code = value;
        } else {
          widget.node.name = value;
        }
      },
    );
  }
}

class _InputTypePill extends StatelessWidget {
  const _InputTypePill({
    required this.property,
    required this.controller,
    required this.editable,
  });

  final VariationNode property;
  final VariationTreeController controller;
  final bool editable;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      key: ValueKey(
        'variation_type_${property.id ?? identityHashCode(property)}',
      ),
      enabled: editable,
      tooltip: editable ? 'What this property holds' : 'Fixed in this version',
      onSelected: (value) {
        property.inputType = value;
        if (value != 'Numeric') {
          property.numericMin = null;
          property.numericMax = null;
        }
        controller.touch();
      },
      itemBuilder: (context) => [
        for (final type in const ['Text', 'Numeric', 'Gauge', 'Material'])
          PopupMenuItem<String>(
            key: ValueKey('variation_type_opt_$type'),
            value: type,
            child: Text(type, style: const TextStyle(fontSize: 15)),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: SoftErpTheme.sectionSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Text(
          property.inputType,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: editable
                ? SoftErpTheme.textPrimary
                : SoftErpTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _BoundField extends StatefulWidget {
  const _BoundField({
    super.key,
    required this.initialValue,
    required this.hint,
    required this.editable,
    required this.onChanged,
  });

  final double? initialValue;
  final String hint;
  final bool editable;
  final ValueChanged<double?> onChanged;

  @override
  State<_BoundField> createState() => _BoundFieldState();
}

class _BoundFieldState extends State<_BoundField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final v = widget.initialValue;
    _controller = TextEditingController(
      text: v != null
          ? (v % 1 == 0 ? v.toInt().toString() : v.toString())
          : '',
    );
  }

  @override
  void didUpdateWidget(_BoundField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue != widget.initialValue) {
      final v = widget.initialValue;
      final newText = v != null
          ? (v % 1 == 0 ? v.toInt().toString() : v.toString())
          : '';
      if (_controller.text != newText && double.tryParse(_controller.text) != v) {
        _controller.text = newText;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      enabled: widget.editable,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: TextStyle(
        fontSize: 13,
        color: widget.editable
            ? SoftErpTheme.textPrimary
            : SoftErpTheme.textSecondary,
      ),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: const TextStyle(
          fontSize: 13,
          color: SoftErpTheme.textSecondary,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        filled: true,
        fillColor: widget.editable
            ? SoftErpTheme.cardSurface
            : SoftErpTheme.sectionSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
      ),
      onChanged: (text) {
        final parsed = double.tryParse(text.trim());
        widget.onChanged(parsed);
      },
    );
  }
}

/// Asks what the new version should be called, then declares it.
Future<bool> showDeclareVersionDialog(
  BuildContext context, {
  required VariationTreeController controller,
  required String entityId,
  required int nextVersion,
}) async {
  final label = TextEditingController(text: 'v$nextVersion');
  final note = TextEditingController();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Declare a new version'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Everything derived so far was derived under the current version. '
            'A new one says out loud that this has changed.',
            style: TextStyle(fontSize: 14.5),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: label,
            autofocus: true,
            style: const TextStyle(fontSize: 15),
            decoration: const InputDecoration(
              labelText: 'Version name',
              hintText: 'Rev B',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            style: const TextStyle(fontSize: 15),
            decoration: const InputDecoration(
              labelText: 'What changed',
              hintText: 'Cavity 2 reground to 3',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel', style: TextStyle(fontSize: 15)),
        ),
        FilledButton(
          key: const ValueKey('variation_version_confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Declare', style: TextStyle(fontSize: 15)),
        ),
      ],
    ),
  );
  if (confirmed != true) {
    label.dispose();
    note.dispose();
    return false;
  }
  final failure = await controller.declareVersion(
    entityId,
    label: label.text.trim(),
    note: note.text.trim(),
  );
  label.dispose();
  note.dispose();
  if (failure != null && context.mounted) {
    showAppToast(context, failure, kind: AppToastKind.error);
    return false;
  }
  return true;
}
