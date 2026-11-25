import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/erp_form_dialog.dart';
import '../../vendors/presentation/providers/vendors_provider.dart';
import '../data/rivet_repository.dart';
import '../domain/rivet.dart';
import 'rivet_drawing.dart';
import 'vendor_prices_editor.dart';

/// Add or change a rivet: the drawing on the left with each dimension
/// labelled, the fields on the right, and the name built from them as you type.
///
/// Opened from Raw Materials › Rivets. Answers the saved rivet, or null.
class RivetFormDialog extends StatefulWidget {
  const RivetFormDialog({
    super.key,
    this.rivet,
    this.attachToItemId,
    this.onSaved,
    this.onCancel,
  });

  final RivetDefinition? rivet;

  /// An item already filed under Rivets that has no rivet spec yet (made in
  /// the plain item form). Saving gives THIS item the spec instead of making
  /// a new rivet.
  final int? attachToItemId;

  /// Set when the form is shown inside another window (the item editor's
  /// Rivet view) rather than as its own dialog: the host decides what saving
  /// and closing do. Unset, the form pops itself with the saved rivet.
  final ValueChanged<RivetDefinition>? onSaved;
  final VoidCallback? onCancel;

  static Future<RivetDefinition?> open(
    BuildContext context, {
    RivetDefinition? rivet,
  }) {
    return showErpFormDialog<RivetDefinition>(
      context,
      maxWidth: 1180,
      maxHeight: 900,
      child: RivetFormDialog(rivet: rivet),
    );
  }

  @override
  State<RivetFormDialog> createState() => _RivetFormDialogState();
}

class _RivetFormDialogState extends State<RivetFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _type = TextEditingController();
  final _code = TextEditingController();
  final Map<RivetDimension, TextEditingController> _dims = {
    for (final dim in RivetDimension.values) dim: TextEditingController(),
  };
  final Map<RivetDimension, FocusNode> _focus = {
    for (final dim in RivetDimension.values) dim: FocusNode(),
  };
  final List<VendorPriceLine> _vendors = <VendorPriceLine>[];

  RivetDefinition? _editing;
  RivetHeadType _headType = RivetHeadType.flat;
  RivetDimension? _focused;
  bool _saving = false;
  String? _error;
  RivetDefinition? _existing;

  @override
  void initState() {
    super.initState();
    _fill(widget.rivet);
    for (final entry in _focus.entries) {
      entry.value.addListener(() {
        if (!mounted) return;
        setState(() {
          if (entry.value.hasFocus) {
            _focused = entry.key;
          } else if (_focused == entry.key) {
            _focused = null;
          }
        });
      });
    }
    for (final c in <TextEditingController>[_type, ..._dims.values]) {
      c.addListener(() => setState(() {}));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVendors());
  }

  void _fill(RivetDefinition? rivet) {
    _editing = rivet;
    if (rivet == null) return;
    _type.text = rivet.rivetType;
    _code.text = rivet.code;
    _headType = rivet.headType;
    for (final dim in RivetDimension.values) {
      _dims[dim]!.text = rivet.dimensions[dim]?.mm ?? '';
    }
    for (final line in _vendors) {
      line.price.dispose();
    }
    _vendors
      ..clear()
      ..addAll(
        rivet.vendors.map(
          (v) => VendorPriceLine(
            vendorId: v.vendorId,
            price: v.price,
            basis: v.basis,
          ),
        ),
      );
  }

  Future<void> _loadVendors() async {
    final provider = _vendorsProvider;
    if (provider != null && provider.vendors.isEmpty) {
      await provider.refresh();
    }
  }

  VendorsProvider? get _vendorsProvider {
    try {
      return context.read<VendorsProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  @override
  void dispose() {
    _type.dispose();
    _code.dispose();
    for (final c in _dims.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    for (final line in _vendors) {
      line.price.dispose();
    }
    super.dispose();
  }

  Map<RivetDimension, String> get _values => {
    for (final dim in RivetDimension.values) dim: _dims[dim]!.text,
  };

  String get _name => rivetName(
    rivetType: _type.text,
    headType: _headType,
    dimensions: _values,
  );

  bool get _hasSilver => rivetHasSilverLayer(_type.text);

  /// Picking Copper or Aluminium clears the silver layer: those rivets have none.
  void _pickType(String type) {
    setState(() {
      _type.text = type;
      if (!rivetHasSilverLayer(type)) {
        _dims[RivetDimension.silverLayer]!.clear();
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _error = null;
      _existing = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repository = context.read<RivetRepository>();
    final input = RivetInput(
      rivetType: _type.text,
      headType: _headType,
      dimensions: _values,
      code: _code.text,
      vendors: _vendors
          .map((line) => line.toPrice())
          .whereType<RivetVendorPrice>()
          .toList(growable: false),
    );
    setState(() => _saving = true);
    try {
      final editing = _editing;
      final targetId = editing?.itemId ?? widget.attachToItemId;
      final saved = targetId == null
          ? await repository.create(input)
          : await repository.update(targetId, input);
      if (!mounted) return;
      showAppToast(
        context,
        editing == null ? 'Added ${saved.name}' : 'Saved ${saved.name}',
        kind: AppToastKind.success,
      );
      if (widget.onSaved != null) {
        // The host may keep the form open: it now edits the saved rivet, and
        // its button is no longer spinning.
        setState(() {
          _saving = false;
          _editing = saved;
        });
        widget.onSaved!(saved);
      } else {
        Navigator.of(context).pop(saved);
      }
    } on RivetApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.message;
        _existing = error.existing?.itemId == _editing?.itemId
            ? null
            : error.existing;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save the rivet: $error';
      });
    }
  }

  /// New: neither a rivet being edited nor an item to give a spec to.
  bool get _isNew => _editing == null && widget.attachToItemId == null;

  void _close() {
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _openExisting() {
    final existing = _existing;
    if (existing == null) return;
    setState(() {
      _fill(existing);
      _error = null;
      _existing = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 1000;
    final drawingPane = _DrawingPane(
      rivetType: _type.text,
      headType: _headType,
      values: _values,
      focused: _focused,
      name: _name,
      code: _code.text,
    );
    final fieldsPane = _fields(context);
    return Form(
      key: _formKey,
      child: ErpFormScaffold(
        title: _isNew ? 'Add rivet' : 'Edit rivet',
        subtitle: 'Raw Materials › Rivets',
        onClose: _close,
        errorBanner: _error == null
            ? null
            : _ErrorBanner(
                message: _error!,
                onOpenExisting: _existing == null ? null : _openExisting,
              ),
        body: isWide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(width: 440, child: drawingPane),
                  const SizedBox(width: 28),
                  Expanded(child: fieldsPane),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  drawingPane,
                  const SizedBox(height: 20),
                  fieldsPane,
                ],
              ),
        footer: Row(
          children: <Widget>[
            const Spacer(),
            AppButton(
              label: 'Cancel',
              variant: AppButtonVariant.secondary,
              onPressed: _close,
            ),
            const SizedBox(width: 12),
            AppButton(
              key: const ValueKey<String>('rivet-save'),
              label: _isNew ? 'Add rivet' : 'Save rivet',
              icon: Icons.check_rounded,
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fields(BuildContext context) {
    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionTitle('Rivet Type'),
          FormField<String>(
            key: const ValueKey<String>('rivet-type'),
            validator: (_) =>
                _type.text.trim().isEmpty ? 'Pick the rivet type' : null,
            builder: (field) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SegmentedButton<String>(
                  emptySelectionAllowed: true,
                  segments: <ButtonSegment<String>>[
                    for (final type in rivetTypes)
                      ButtonSegment<String>(
                        value: type,
                        label: Text(
                          type,
                          key: ValueKey<String>('rivet-type-$type'),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                  selected: <String>{
                    for (final type in rivetTypes)
                      if (type.toLowerCase() == _type.text.trim().toLowerCase())
                        type,
                  },
                  onSelectionChanged: (picked) {
                    if (picked.isEmpty) return;
                    _pickType(picked.first);
                    field.didChange(picked.first);
                  },
                ),
                if (field.hasError)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 4),
                    child: Text(
                      field.errorText!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: SoftErpTheme.dangerText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Head Type'),
          SegmentedButton<RivetHeadType>(
            key: const ValueKey<String>('rivet-head-type'),
            segments: <ButtonSegment<RivetHeadType>>[
              for (final type in RivetHeadType.values)
                ButtonSegment<RivetHeadType>(
                  value: type,
                  label: Text(
                    '${type.code} — ${type.label}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
            selected: <RivetHeadType>{_headType},
            onSelectionChanged: (s) => setState(() => _headType = s.first),
          ),
          const SizedBox(height: 18),
          const _SectionTitle('Rivet Code'),
          SizedBox(
            width: 280,
            child: TextFormField(
              key: const ValueKey<String>('rivet-code'),
              controller: _code,
              textInputAction: TextInputAction.next,
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(hintText: 'Your code for it'),
            ),
          ),
          const SizedBox(height: 22),
          const _SectionTitle('Dimensions (mm)'),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 520 ? 2 : 1;
              final width =
                  (constraints.maxWidth - (columns - 1) * 16) / columns;
              return Wrap(
                spacing: 16,
                runSpacing: 14,
                children: <Widget>[
                  for (final dim in RivetDimension.values)
                    SizedBox(width: width, child: _dimensionField(dim)),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
          VendorPricesEditor(
            lines: _vendors,
            onChanged: () => setState(() {}),
            keyPrefix: 'rivet',
            noun: 'rivet',
          ),
        ],
      ),
    );
  }

  Widget _dimensionField(RivetDimension dim) {
    final isSilver = dim == RivetDimension.silverLayer;
    final enabled = !isSilver || _hasSilver;
    final field = TextFormField(
      key: ValueKey<String>('rivet-${dim.key}'),
      controller: _dims[dim],
      focusNode: _focus[dim],
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: dim.label,
        suffixText: 'mm',
        helperText: enabled ? null : 'Only a bimetal rivet has one',
      ),
      validator: (value) {
        if (!enabled) return null;
        final text = (value ?? '').trim();
        if (text.isEmpty) return '${dim.label} is needed';
        if (!isValidMillimetres(text)) return 'A number of mm, like 2.0';
        return null;
      },
    );
    // Drawn disabled with the reason, never hidden.
    return enabled
        ? field
        : Tooltip(
            message: 'Only a bimetal rivet has a silver layer.',
            child: field,
          );
  }
}

/// The drawing, and under it the name the rivet will be saved as.
class _DrawingPane extends StatelessWidget {
  const _DrawingPane({
    required this.rivetType,
    required this.headType,
    required this.values,
    required this.focused,
    required this.name,
    required this.code,
  });

  final String rivetType;
  final RivetHeadType headType;
  final Map<RivetDimension, String> values;
  final RivetDimension? focused;
  final String name;
  final String code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SoftErpTheme.sectionSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          RivetDrawing(
            rivetType: rivetType,
            headType: headType,
            values: values,
            focused: focused,
          ),
          const SizedBox(height: 14),
          const Text(
            'ITEM NAME',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            name,
            key: const ValueKey<String>('rivet-name-preview'),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: SoftErpTheme.textPrimary,
              height: 1.3,
            ),
          ),
          if (code.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: SoftErpTheme.accentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'Code ${code.trim()}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.accentDark,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Built from the fields. It changes as you type.',
            style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: SoftErpTheme.textPrimary,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, this.onOpenExisting});

  final String message;
  final VoidCallback? onOpenExisting;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: SoftErpTheme.dangerBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            color: SoftErpTheme.dangerText,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: SoftErpTheme.dangerText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onOpenExisting != null)
            TextButton(
              key: const ValueKey<String>('rivet-open-existing'),
              onPressed: onOpenExisting,
              child: const Text(
                'Open that rivet',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
