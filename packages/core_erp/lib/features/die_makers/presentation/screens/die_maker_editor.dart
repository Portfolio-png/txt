import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../domain/die_maker.dart';
import '../providers/die_makers_provider.dart';

/// Names a die maker, with the fields the client form asks for.
///
/// Identity / Contact / Address, in that order and with those words, because
/// the shop asked for "the same fields as what we take for client form" and
/// recognising the form matters more than saving a section. What is NOT copied
/// is the requiredness: on a client, Name is the only required field and that
/// holds here too — but here it does more work, because most die makers will
/// be a name and nothing else. A fitter on the floor has no GST number.
///
/// Opened two ways, like `ClientsScreen`:
///   * [open] — a dialog, returning the saved maker or null
///   * [DieMakerEditor] directly — embedded, driven by onSaved/onCancel
class DieMakerEditor extends StatefulWidget {
  const DieMakerEditor({
    super.key,
    this.dieMaker,
    this.initialName = '',
    required this.onSaved,
    required this.onCancel,
  });

  final DieMaker? dieMaker;

  /// Seeds the Name field. This is what makes inline create work: the picker
  /// hands over what was typed so nobody types it twice.
  final String initialName;

  final ValueChanged<DieMaker> onSaved;
  final VoidCallback onCancel;

  /// The dialog form. Returns the saved maker, or null if it was dismissed.
  static Future<DieMaker?> open(
    BuildContext context, {
    DieMaker? dieMaker,
    String initialName = '',
  }) {
    return showErpFormDialog<DieMaker?>(
      context,
      maxWidth: 760,
      maxHeight: 760,
      child: Builder(
        builder: (dialogContext) => DieMakerEditor(
          dieMaker: dieMaker,
          initialName: initialName,
          onSaved: (saved) => Navigator.of(dialogContext).pop(saved),
          onCancel: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
  }

  @override
  State<DieMakerEditor> createState() => _DieMakerEditorState();
}

class _DieMakerEditorState extends State<DieMakerEditor> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _alias;
  late final TextEditingController _gst;
  late final TextEditingController _contactName;
  late final TextEditingController _designation;
  late final TextEditingController _phone;
  late final TextEditingController _email;
  late final TextEditingController _address;

  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.dieMaker;
    _name = TextEditingController(
      text: existing?.name ?? widget.initialName.trim(),
    );
    _alias = TextEditingController(text: existing?.alias ?? '');
    _gst = TextEditingController(text: existing?.gstNumber ?? '');
    _contactName = TextEditingController(text: existing?.contactName ?? '');
    _designation = TextEditingController(text: existing?.designation ?? '');
    _phone = TextEditingController(text: existing?.phone ?? '');
    _email = TextEditingController(text: existing?.email ?? '');
    _address = TextEditingController(text: existing?.address ?? '');
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _alias,
      _gst,
      _contactName,
      _designation,
      _phone,
      _email,
      _address,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final provider = context.read<DieMakersProvider>();
    final input = DieMakerInput(
      id: widget.dieMaker?.id,
      name: _name.text.trim(),
      alias: _alias.text.trim(),
      gstNumber: _gst.text.trim(),
      contactName: _contactName.text.trim(),
      designation: _designation.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim(),
      address: _address.text.trim(),
    );

    final saved = widget.dieMaker == null
        ? await provider.create(input)
        : await provider.update(input);

    if (!mounted) return;
    if (saved == null) {
      setState(() {
        _saving = false;
        _error = provider.errorMessage ?? 'That did not save.';
      });
      return;
    }
    widget.onSaved(saved);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.dieMaker != null;

    return ErpFormScaffold(
      title: isEdit ? 'Edit die maker' : 'New die maker',
      subtitle: 'Whoever cut the die — a fitter here, or an outside toolroom',
      onClose: widget.onCancel,
      errorBanner: _error == null
          ? null
          : ErpFormMessageBanner(message: _error!, isError: true),
      footer: Wrap(
        alignment: WrapAlignment.end,
        spacing: 12,
        runSpacing: 12,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: widget.onCancel,
          ),
          AppButton(
            label: isEdit ? 'Save changes' : 'Add die maker',
            isLoading: _saving,
            onPressed: _submit,
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ErpDialogSectionCard(
              title: 'Identity',
              child: Column(
                children: [
                  _field(
                    controller: _name,
                    label: 'Name',
                    helper: 'The toolroom, or the person who cut it',
                    required: true,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _alias,
                    label: 'Alias',
                    helper: 'What the shop actually calls them',
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _gst,
                    label: 'GST No.',
                    helper: 'Leave blank for an in-house fitter',
                    capitalization: TextCapitalization.characters,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ErpDialogSectionCard(
              title: 'Contact',
              subtitle: 'The one person you deal with there',
              child: Column(
                children: [
                  _field(
                    controller: _contactName,
                    label: 'Contact Name',
                    helper: 'Who to ring about a die',
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _designation,
                    label: 'Designation',
                    helper: 'Proprietor, Foreman, Fitter…',
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _phone,
                    label: 'Contact No.',
                    helper: '',
                    capitalization: TextCapitalization.none,
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    controller: _email,
                    label: 'Email ID',
                    helper: '',
                    capitalization: TextCapitalization.none,
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ErpDialogSectionCard(
              title: 'Address',
              child: _field(
                controller: _address,
                label: 'Address',
                helper: 'Where the toolroom is',
                maxLines: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String helper,
    bool required = false,
    int maxLines = 1,
    TextCapitalization capitalization = TextCapitalization.words,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: capitalization,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 15),
      decoration: InputDecoration(
        labelText: required ? '$label *' : label,
        helperText: helper.isEmpty ? null : helper,
        helperStyle: const TextStyle(fontSize: 13),
        labelStyle: const TextStyle(fontSize: 14),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      validator: (value) {
        final text = (value ?? '').trim();
        if (required && text.isEmpty) return '$label is needed.';
        // The same fifteen the client form asks for, and the same fifteen the
        // server checks — stated in both places because a portal or an import
        // never passes through this widget.
        if (label == 'GST No.' && text.isNotEmpty && text.length != 15) {
          return 'A GST number is 15 characters.';
        }
        return null;
      },
    );
  }
}
