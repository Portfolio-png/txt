import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/soft_erp_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/erp_form_dialog.dart';
import '../../vendors/presentation/providers/vendors_provider.dart';
import '../data/spring_repository.dart';
import '../domain/rivet.dart' show RivetVendorPrice, isValidMillimetres;
import '../domain/spring.dart';
import 'naming_format_editor.dart';
import 'spring_drawing.dart';
import 'vendor_prices_editor.dart';

/// Add or change a spring: the drawing of its kind on the left with each size
/// labelled, the fields on the right, the name built from the blocks the user
/// arranged as they type. The same shape as the rivet form.
///
/// Opened from Raw Materials › Springs, or as the item editor's Spring view.
/// Answers the saved spring, or null.
class SpringFormDialog extends StatefulWidget {
  const SpringFormDialog({
    super.key,
    this.spring,
    this.attachToItemId,
    this.onSaved,
    this.onCancel,
  });

  final SpringDefinition? spring;

  /// An item already filed under Springs that has no spring spec yet: saving
  /// gives THIS item the spec instead of making a new spring.
  final int? attachToItemId;

  /// Set when the form is shown inside another window (the item editor's
  /// Spring view): the host decides what saving and closing do. Unset, the
  /// form pops itself with the saved spring.
  final ValueChanged<SpringDefinition>? onSaved;
  final VoidCallback? onCancel;

  static Future<SpringDefinition?> open(
    BuildContext context, {
    SpringDefinition? spring,
  }) {
    return showErpFormDialog<SpringDefinition>(
      context,
      maxWidth: 1180,
      maxHeight: 900,
      child: SpringFormDialog(spring: spring),
    );
  }

  @override
  State<SpringFormDialog> createState() => _SpringFormDialogState();
}

/// The drawing mark a size lights up: the same names.
SpringMark _markOf(SpringSize size) =>
    SpringMark.values.firstWhere((m) => m.name == size.name);

class _SpringFormDialogState extends State<SpringFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _type = TextEditingController();
  final _gauge = TextEditingController();
  final _grade = TextEditingController();
  final _code = TextEditingController();

  /// Every kind's sizes keep their text: switching kind and back loses nothing.
  final Map<SpringSize, TextEditingController> _sizes = {
    for (final size in SpringSize.values) size: TextEditingController(),
  };
  final List<VendorPriceLine> _vendors = <VendorPriceLine>[];
  late final Map<SpringMark, FocusNode> _focus = {
    for (final mark in SpringMark.values) mark: FocusNode(),
  };

  SpringDefinition? _editing;
  SpringKind _kind = SpringKind.doubleHook;
  List<NameToken> _format = defaultSpringNameFormat(SpringKind.doubleHook);
  SpringMark? _focused;
  bool _saving = false;
  String? _error;
  SpringDefinition? _existing;

  @override
  void initState() {
    super.initState();
    _fill(widget.spring);
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
    for (final c in <TextEditingController>[
      _type,
      _gauge,
      _grade,
      _code,
      ..._sizes.values,
    ]) {
      c.addListener(() => setState(() {}));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVendors());
  }

  void _fill(SpringDefinition? spring) {
    _editing = spring;
    if (spring == null) return;
    _kind = spring.kind;
    _format = List.of(spring.nameFormat);
    _type.text = spring.springType;
    _gauge.text = spring.wireGauge;
    _grade.text = spring.wireGrade;
    _code.text = spring.code;
    for (final size in SpringSize.values) {
      _sizes[size]!.text = spring.sizes[size] ?? '';
    }
    for (final line in _vendors) {
      line.price.dispose();
    }
    _vendors
      ..clear()
      ..addAll(
        spring.vendors.map(
          (v) => VendorPriceLine(
            vendorId: v.vendorId,
            price: v.price,
            basis: v.basis,
          ),
        ),
      );
  }

  Future<void> _loadVendors() async {
    try {
      final provider = context.read<VendorsProvider>();
      if (provider.vendors.isEmpty) await provider.refresh();
    } on ProviderNotFoundException {
      // A window without the vendor list offers none.
    }
  }

  @override
  void dispose() {
    for (final c in <TextEditingController>[
      _type,
      _gauge,
      _grade,
      _code,
      ..._sizes.values,
    ]) {
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

  bool get _isNew => _editing == null && widget.attachToItemId == null;

  Map<SpringSize, String> get _sizeTexts => {
    for (final size in SpringSize.values) size: _sizes[size]!.text,
  };

  String get _name => springName(
    kind: _kind,
    springType: _type.text,
    sizes: _sizeTexts,
    wireGauge: springHasGauge(_kind) ? _gauge.text : '',
    wireGrade: _grade.text,
    format: _format,
  );

  Map<SpringMark, String> get _marks => <SpringMark, String>{
    SpringMark.coilHook: _kind.label,
    for (final size in SpringSize.values) _markOf(size): _sizes[size]!.text,
    SpringMark.wireGauge: _gauge.text,
  };

  /// A new kind: blocks it cannot name drop out of the format, and a format
  /// nobody arranged follows the new kind's default.
  void _pickKind(SpringKind kind) {
    setState(() {
      final untouched = _sameFormat(_format, defaultSpringNameFormat(_kind));
      _kind = kind;
      if (untouched) {
        _format = defaultSpringNameFormat(kind);
      } else {
        final allowed = springNameBlocks(kind).toSet();
        _format = [
          for (final t in _format)
            if (allowed.contains(t.block)) t,
        ];
        if (_format.isEmpty) _format = defaultSpringNameFormat(kind);
      }
    });
  }

  static bool _sameFormat(List<NameToken> a, List<NameToken> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  void _close() {
    if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _error = null;
      _existing = null;
    });
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final repository = context.read<SpringRepository>();
    final input = SpringInput(
      kind: _kind,
      springType: _type.text,
      sizes: _sizeTexts,
      wireGauge: _gauge.text,
      wireGrade: _grade.text,
      code: _code.text,
      nameFormat: _format,
      vendors: _vendors
          .map((line) => line.toPrice())
          .whereType<RivetVendorPrice>()
          .toList(growable: false),
    );
    setState(() => _saving = true);
    try {
      final targetId = _editing?.itemId ?? widget.attachToItemId;
      final saved = targetId == null
          ? await repository.create(input)
          : await repository.update(targetId, input);
      if (!mounted) return;
      showAppToast(
        context,
        _isNew ? 'Added ${saved.name}' : 'Saved ${saved.name}',
        kind: AppToastKind.success,
      );
      if (widget.onSaved != null) {
        // The host may keep the form open: it now edits the saved spring.
        setState(() {
          _saving = false;
          _editing = saved;
        });
        widget.onSaved!(saved);
      } else {
        Navigator.of(context).pop(saved);
      }
    } on SpringApiException catch (error) {
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
        _error = 'Could not save the spring: $error';
      });
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
      kind: _kind,
      marks: _marks,
      focused: _focused,
      name: _name,
      code: _code.text,
    );
    final fieldsPane = _fields();
    return Form(
      key: _formKey,
      child: ErpFormScaffold(
        title: _isNew ? 'Add spring' : 'Edit spring',
        subtitle: 'Raw Materials › Springs',
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
              key: const ValueKey<String>('spring-save'),
              label: _isNew ? 'Add spring' : 'Save spring',
              icon: Icons.check_rounded,
              isLoading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      ),
    );
  }

  Widget _text(
    String key,
    TextEditingController controller,
    String label, {
    SpringMark? mark,
    String? suffix,
    String? hint,
    bool number = false,
    String? Function(String text)? check,
  }) {
    return TextFormField(
      key: ValueKey<String>('spring-$key'),
      controller: controller,
      focusNode: mark == null ? null : _focus[mark],
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      textInputAction: TextInputAction.next,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        hintText: hint,
      ),
      validator: check == null ? null : (value) => check((value ?? '').trim()),
    );
  }

  Widget _sizeField(SpringSize size) {
    // The inner size of the pair, checked against the outer.
    final (SpringSize? outer, String? outerLabel) = switch (size) {
      SpringSize.coilId => (SpringSize.coilOd, 'Coil OD'),
      SpringSize.smallOd => (SpringSize.largeOd, 'Large OD'),
      _ => (null, null),
    };
    return _text(
      size.key,
      _sizes[size]!,
      size.label,
      mark: _markOf(size),
      suffix: size.count ? null : 'mm',
      hint: size.count ? 'How many coils' : null,
      number: true,
      check: (t) {
        if (t.isEmpty) return size.required ? '${size.label} is needed' : null;
        if (size.count) {
          return isValidCoilNumber(t) ? null : 'A whole number, like 6';
        }
        if (!isValidMillimetres(t)) return 'A number of mm, like 114';
        if (outer != null && !coilIdUnderOd(_sizes[outer]!.text, t)) {
          return 'Smaller than $outerLabel';
        }
        return null;
      },
    );
  }

  Widget _fields() {
    Widget pair(Widget a, Widget b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(child: a),
        const SizedBox(width: 16),
        Expanded(child: b),
      ],
    );
    final sizes = springSizesFor(_kind);

    return FocusTraversalGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _SectionTitle('Spring Kind'),
          SegmentedButton<SpringKind>(
            key: const ValueKey<String>('spring-kind'),
            segments: <ButtonSegment<SpringKind>>[
              for (final kind in SpringKind.values)
                ButtonSegment<SpringKind>(
                  value: kind,
                  label: Text(
                    kind.label,
                    key: ValueKey<String>('spring-kind-${kind.name}'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
            selected: <SpringKind>{_kind},
            onSelectionChanged: (s) => _pickKind(s.first),
          ),
          const SizedBox(height: 18),
          pair(
            _text('type', _type, 'Spring Type', hint: '5 A Steel'),
            _text('code', _code, 'Spring Code', hint: 'Your code for it'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final type in springTypeChoices)
                ChoiceChip(
                  key: ValueKey<String>('spring-type-$type'),
                  label: Text(type, style: const TextStyle(fontSize: 14)),
                  selected:
                      _type.text.trim().toLowerCase() == type.toLowerCase(),
                  onSelected: (_) => setState(() => _type.text = type),
                ),
            ],
          ),
          const SizedBox(height: 22),
          _SectionTitle(_kind == SpringKind.conical ? 'Cone' : 'Coil'),
          for (var i = 0; i < sizes.length; i += 2) ...<Widget>[
            if (i > 0) const SizedBox(height: 14),
            pair(
              _sizeField(sizes[i]),
              i + 1 < sizes.length
                  ? _sizeField(sizes[i + 1])
                  : const SizedBox.shrink(),
            ),
          ],
          const SizedBox(height: 22),
          const _SectionTitle('Wire'),
          pair(
            springHasGauge(_kind)
                ? _text(
                    'wireGauge',
                    _gauge,
                    'Wire Gauge',
                    mark: SpringMark.wireGauge,
                    hint: 'As the vendor writes it, e.g. 22 SWG',
                  )
                : const SizedBox.shrink(),
            _text('wireGrade', _grade, 'Wire Grade', hint: 'e.g. SS 302'),
          ),
          const SizedBox(height: 24),
          NamingFormatEditor(
            key: const ValueKey<String>('spring-naming-format'),
            tokens: _format,
            blocks: springNameBlocks(_kind),
            labelOf: springBlockLabel,
            onChanged: (next) => setState(() => _format = next),
            onReset: _sameFormat(_format, defaultSpringNameFormat(_kind))
                ? null
                : () =>
                      setState(() => _format = defaultSpringNameFormat(_kind)),
          ),
          const SizedBox(height: 24),
          VendorPricesEditor(
            lines: _vendors,
            onChanged: () => setState(() {}),
            keyPrefix: 'spring',
            noun: 'spring',
          ),
        ],
      ),
    );
  }
}

/// The drawing, and under it the name the spring will be saved as.
class _DrawingPane extends StatelessWidget {
  const _DrawingPane({
    required this.kind,
    required this.marks,
    required this.focused,
    required this.name,
    required this.code,
  });

  final SpringKind kind;
  final Map<SpringMark, String> marks;
  final SpringMark? focused;
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
          SpringDrawing(kind: kind, values: marks, focused: focused),
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
            key: const ValueKey<String>('spring-name-preview'),
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
            'Built from the blocks in Naming Format. It changes as you type.',
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
              key: const ValueKey<String>('spring-open-existing'),
              onPressed: onOpenExisting,
              child: const Text(
                'Open that spring',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
