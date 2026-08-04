import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../domain/delivery_challan.dart';
import '../providers/delivery_challan_provider.dart';

/// Fills in the letterhead printed at the top of delivery and reception
/// challans.
///
/// The preview mirrors the printed header, so what is typed here is visibly the
/// same thing that comes out on the document.
class CompanyProfileDialog extends StatefulWidget {
  const CompanyProfileDialog({super.key});

  static Future<bool> open(BuildContext context) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => const CompanyProfileDialog(),
    );
    return saved ?? false;
  }

  @override
  State<CompanyProfileDialog> createState() => _CompanyProfileDialogState();
}

class _CompanyProfileDialogState extends State<CompanyProfileDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _companyName;
  late final TextEditingController _businessDescription;
  late final TextEditingController _address;
  late final TextEditingController _mobile;
  late final TextEditingController _gstin;
  late final TextEditingController _stateCode;
  late final TextEditingController _signatureLabel;
  bool _isSaving = false;

  CompanyProfile get _existing =>
      context.read<DeliveryChallanProvider>().companyProfile ??
      CompanyProfile.empty();

  @override
  void initState() {
    super.initState();
    final profile = _existing;
    _companyName = TextEditingController(text: profile.companyName)
      ..addListener(_refresh);
    _businessDescription =
        TextEditingController(text: profile.businessDescription)
          ..addListener(_refresh);
    _address = TextEditingController(text: profile.address)
      ..addListener(_refresh);
    _mobile = TextEditingController(text: profile.mobile)..addListener(_refresh);
    _gstin = TextEditingController(text: profile.gstin);
    _stateCode = TextEditingController(text: profile.stateCode);
    _signatureLabel = TextEditingController(text: profile.signatureLabel);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [
      _companyName,
      _businessDescription,
      _address,
      _mobile,
      _gstin,
      _stateCode,
      _signatureLabel,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);
    final provider = context.read<DeliveryChallanProvider>();
    final previous = _existing;
    final saved = await provider.saveCompanyProfile(
      CompanyProfile(
        id: previous.id,
        companyName: _companyName.text.trim(),
        mobile: _mobile.text.trim(),
        businessDescription: _businessDescription.text.trim(),
        address: _address.text.trim(),
        stateCode: _stateCode.text.trim(),
        gstin: _gstin.text.trim(),
        // Not editable here; carried through so saving the text fields cannot
        // wipe a logo set elsewhere.
        logoUrl: previous.logoUrl,
        signatureLabel: _signatureLabel.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() => _isSaving = false);
    if (saved == null) {
      showAppSnack(
        SnackBar(
          content: Text(provider.errorMessage ?? 'Could not save the profile.'),
        ),
      );
      return;
    }
    showAppToast(context, 'Company profile saved', kind: AppToastKind.success);
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: SoftErpTheme.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Company Profile',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: SoftErpTheme.textSecondary,
                  ),
                ],
              ),
              const Text(
                'Printed at the top of every delivery and reception challan.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Flexible(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _LetterheadPreview(
                          companyName: _companyName.text,
                          businessDescription: _businessDescription.text,
                          address: _address.text,
                          mobile: _mobile.text,
                        ),
                        const SizedBox(height: 18),
                        _field(
                          controller: _companyName,
                          label: 'Company Name',
                          hint: 'Shree Ganesh Metal Works',
                          required: true,
                        ),
                        _field(
                          controller: _businessDescription,
                          label: 'Business Description',
                          hint: 'Manufacturers of: FOUNTAIN PEN, BALL PEN…',
                          maxLines: 2,
                        ),
                        _field(
                          controller: _address,
                          label: 'Address',
                          hint: 'Gala No. 1, Ground Floor…',
                          maxLines: 3,
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _field(
                                controller: _mobile,
                                label: 'Mobile',
                                hint: '9324041030',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _field(
                                controller: _gstin,
                                label: 'GSTIN',
                                hint: '27ABHPC1349L1ZN',
                              ),
                            ),
                          ],
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: _field(
                                controller: _stateCode,
                                label: 'State Code',
                                hint: '27',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _field(
                                controller: _signatureLabel,
                                label: 'Signature Label',
                                hint: 'For Shree Ganesh Metal Works',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSaving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    label: 'Save',
                    isLoading: _isSaving,
                    onPressed: _isSaving ? null : _submit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String hint = '',
    int maxLines = 1,
    bool required = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: required ? '$label *' : label,
          hintText: hint,
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
        validator: required
            ? (value) =>
                  (value == null || value.trim().isEmpty) ? 'Required' : null
            : null,
      ),
    );
  }
}

/// Mirrors the printed challan header so the fields below have visible effect.
class _LetterheadPreview extends StatelessWidget {
  const _LetterheadPreview({
    required this.companyName,
    required this.businessDescription,
    required this.address,
    required this.mobile,
  });

  final String companyName;
  final String businessDescription;
  final String address;
  final String mobile;

  @override
  Widget build(BuildContext context) {
    const muted = TextStyle(fontSize: 11.5, color: Color(0xFF64748B));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Expanded(
                child: Text(
                  'DELIVERY CHALLAN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                    color: Color(0xFF2B3245),
                  ),
                ),
              ),
              if (mobile.trim().isNotEmpty)
                Text(
                  'Mobile: ${mobile.trim()}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2B3245),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            companyName.trim().isEmpty ? 'Your Company Name' : companyName.trim(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: companyName.trim().isEmpty
                  ? const Color(0xFFB6BDCC)
                  : const Color(0xFF2B3245),
            ),
          ),
          if (businessDescription.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              businessDescription.trim(),
              textAlign: TextAlign.center,
              style: muted,
            ),
          ],
          if (address.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(address.trim(), textAlign: TextAlign.center, style: muted),
          ],
        ],
      ),
    );
  }
}
