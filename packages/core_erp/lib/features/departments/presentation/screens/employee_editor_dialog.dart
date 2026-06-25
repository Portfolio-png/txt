import 'dart:convert';

import 'package:barcode_widget/barcode_widget.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/generic_asset_service.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../domain/employee_definition.dart';
import '../providers/departments_provider.dart';

class EmployeeEditorDialog extends StatelessWidget {
  const EmployeeEditorDialog({
    super.key,
    required this.departmentId,
    this.employee,
  });

  final int departmentId;
  final EmployeeDefinition? employee;

  static Future<void> open(
    BuildContext context, {
    required int departmentId,
    EmployeeDefinition? employee,
  }) {
    return showErpFormDialog(
      context,
      maxWidth: 960,
      maxHeight: 900,
      child: EmployeeEditorDialog(
        departmentId: departmentId,
        employee: employee,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _EmployeeEditorSheet(departmentId: departmentId, employee: employee);
  }
}

class _EmployeeEditorSheet extends StatefulWidget {
  const _EmployeeEditorSheet({required this.departmentId, this.employee});

  final int departmentId;
  final EmployeeDefinition? employee;

  @override
  State<_EmployeeEditorSheet> createState() => _EmployeeEditorSheetState();
}

class _EmployeeEditorSheetState extends State<_EmployeeEditorSheet> {
  final _nameController = TextEditingController();
  final _roleController = TextEditingController();
  final _phoneController = TextEditingController();
  final _aadharNumberController = TextEditingController();
  final _panNumberController = TextEditingController();
  final _addressController = TextEditingController();
  final _aadharPhotoUrlController = TextEditingController();
  final _panPhotoUrlController = TextEditingController();
  final _employeePhotoUrlController = TextEditingController();
  final _barcodeIdController = TextEditingController();
  String _employmentType = 'in-house';

  @override
  void initState() {
    super.initState();
    final emp = widget.employee;
    if (emp != null) {
      _nameController.text = emp.name;
      _roleController.text = emp.role;
      _phoneController.text = emp.phone;
      _aadharNumberController.text = emp.aadharNumber;
      _panNumberController.text = emp.panNumber;
      _addressController.text = emp.address;
      _aadharPhotoUrlController.text = emp.aadharPhotoUrl;
      _panPhotoUrlController.text = emp.panPhotoUrl;
      _employeePhotoUrlController.text = emp.employeePhotoUrl;
      _barcodeIdController.text = emp.barcodeId;
      _employmentType = emp.employmentType;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _roleController.dispose();
    _phoneController.dispose();
    _aadharNumberController.dispose();
    _panNumberController.dispose();
    _addressController.dispose();
    _aadharPhotoUrlController.dispose();
    _panPhotoUrlController.dispose();
    _employeePhotoUrlController.dispose();
    _barcodeIdController.dispose();
    super.dispose();
  }

  String _generateBarcode() =>
      'FR-${DateTime.now().millisecondsSinceEpoch.toString().substring(5)}';

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final provider = context.read<DepartmentsProvider>();
    final success = widget.employee == null
        ? await provider.createEmployee(
            widget.departmentId,
            name,
            _roleController.text.trim(),
            _phoneController.text.trim(),
            _aadharNumberController.text.trim(),
            _aadharPhotoUrlController.text.trim(),
            _panNumberController.text.trim(),
            _panPhotoUrlController.text.trim(),
            _addressController.text.trim(),
            _employeePhotoUrlController.text.trim(),
            _employmentType,
            _barcodeIdController.text.trim(),
          )
        : await provider.updateEmployee(
            widget.employee!.id,
            widget.departmentId,
            name,
            _roleController.text.trim(),
            _phoneController.text.trim(),
            _aadharNumberController.text.trim(),
            _aadharPhotoUrlController.text.trim(),
            _panNumberController.text.trim(),
            _panPhotoUrlController.text.trim(),
            _addressController.text.trim(),
            _employeePhotoUrlController.text.trim(),
            _employmentType,
            _barcodeIdController.text.trim(),
          );

    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    final isFreelancer = _employmentType == 'freelancer';

    return ErpFormScaffold(
      title: widget.employee == null ? 'New Employee' : 'Edit Employee',
      subtitle:
          'Capture the person\'s details, identity documents, and how they\'re engaged.',
      errorBanner: provider.errorMessage == null
          ? null
          : ErpFormMessageBanner(message: provider.errorMessage!),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ErpDialogSectionCard(
                  title: 'Details',
                  child: Column(
                    children: [
                      _Field(
                          controller: _nameController, label: 'Employee Name'),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _Field(
                                controller: _roleController,
                                label: 'Role / Position'),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _Field(
                              controller: _phoneController,
                              label: 'Phone',
                              keyboardType: TextInputType.phone,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _Field(
                        controller: _addressController,
                        label: 'Address',
                        maxLines: 2,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ErpDialogSectionCard(
                  title: 'Identity Numbers',
                  child: Row(
                    children: [
                      Expanded(
                        child: _Field(
                          controller: _aadharNumberController,
                          label: 'Aadhar Number',
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: _Field(
                          controller: _panNumberController,
                          label: 'PAN Number',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ErpDialogSectionCard(
                  title: 'Engagement',
                  child: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _employmentType,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: SoftErpTheme.textSecondary),
                        dropdownColor: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        style: const TextStyle(
                          fontSize: 14,
                          color: SoftErpTheme.textPrimary,
                        ),
                        decoration: _decoration('Employment Type'),
                        items: const [
                          DropdownMenuItem(
                            value: 'in-house',
                            child: Text('In-house'),
                          ),
                          DropdownMenuItem(
                            value: 'freelancer',
                            child: Text('Freelancer'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val == null) return;
                          setState(() {
                            _employmentType = val;
                            if (val == 'freelancer' &&
                                _barcodeIdController.text.isEmpty) {
                              _barcodeIdController.text = _generateBarcode();
                            }
                          });
                        },
                      ),
                      if (isFreelancer) ...[
                        const SizedBox(height: 14),
                        _Field(
                          controller: _barcodeIdController,
                          label: 'Freelancer Barcode ID',
                          suffix: IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Regenerate',
                            onPressed: () => setState(
                              () => _barcodeIdController.text =
                                  _generateBarcode(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.info_outline_rounded,
                                size: 16,
                                color: SoftErpTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 7),
                            const Expanded(
                              child: Text(
                                'This code identifies the freelancer at job hand-off and internal scan points.',
                                style: TextStyle(
                                  color: SoftErpTheme.textSecondary,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            AppButton(
                              label: 'Preview ID card',
                              icon: Icons.badge_outlined,
                              variant: AppButtonVariant.secondary,
                              onPressed:
                                  _barcodeIdController.text.trim().isEmpty
                                      ? null
                                      : _showIdCard,
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ErpDialogSectionCard(
                  title: 'Photos & Documents',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _EmployeeImagePickerField(
                        controller: _employeePhotoUrlController,
                        label: 'Employee Photo',
                        placeholderIcon: Icons.person,
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      _EmployeeImagePickerField(
                        controller: _aadharPhotoUrlController,
                        label: 'Aadhar Card',
                        placeholderIcon: Icons.credit_card,
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 16),
                      _EmployeeImagePickerField(
                        controller: _panPhotoUrlController,
                        label: 'PAN Card',
                        placeholderIcon: Icons.credit_card_outlined,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      footer: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          AppButton(
            label: 'Cancel',
            variant: AppButtonVariant.secondary,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 12),
          AppButton(
            label: 'Save',
            isLoading: provider.isSaving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  void _showIdCard() {
    final barcodeId = _barcodeIdController.text.trim();
    if (barcodeId.isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Freelancer ID card'),
        content: Container(
          width: 390,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFDFCFF), Color(0xFFF2F0FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: SoftErpTheme.borderStrong),
            borderRadius: BorderRadius.circular(22),
            boxShadow: SoftErpTheme.subtleShadow,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: SoftErpTheme.accentGradient,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.handyman_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PAPER ERP',
                          style: TextStyle(
                            color: SoftErpTheme.accentDark,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        Text(
                          'Freelancer identification',
                          style: TextStyle(
                            color: SoftErpTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SoftStatusPill(
                    label: 'ACTIVE',
                    background: SoftErpTheme.successBg,
                    textColor: SoftErpTheme.successText,
                    borderColor: SoftErpTheme.successBg,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                _nameController.text.trim().isNotEmpty
                    ? _nameController.text.trim()
                    : 'Freelancer name',
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (_roleController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  _roleController.text.trim(),
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: SoftErpTheme.border),
                ),
                child: BarcodeWidget(
                  barcode: Barcode.code128(),
                  data: barcodeId,
                  width: double.infinity,
                  height: 76,
                  drawText: true,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Freelancer ID card sent to printer.'),
                ),
              );
            },
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('Print card'),
          ),
        ],
      ),
    );
  }
}

InputDecoration _decoration(String label, {Widget? suffix}) {
  return InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
    suffixIcon: suffix,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD7DBE7)),
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.suffix,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final Widget? suffix;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      decoration: _decoration(label, suffix: suffix),
    );
  }
}

class _EmployeeImagePickerField extends StatefulWidget {
  const _EmployeeImagePickerField({
    required this.controller,
    required this.label,
    required this.placeholderIcon,
  });

  final TextEditingController controller;
  final String label;
  final IconData placeholderIcon;

  @override
  State<_EmployeeImagePickerField> createState() =>
      _EmployeeImagePickerFieldState();
}

class _EmployeeImagePickerFieldState extends State<_EmployeeImagePickerField> {
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  String _contentTypeFromExtension(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      default:
        return 'application/octet-stream';
    }
  }

  Future<void> _deleteOldS3Object(String url) async {
    if (url.isEmpty || !url.contains('amazonaws.com')) return;
    final baseUrl = const String.fromEnvironment(
      'PAPER_API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    );
    try {
      await http.post(
        Uri.parse('\$baseUrl/api/delete-s3-object'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'url': url}),
      );
    } catch (e) {
      // Best effort deletion.
      debugPrint('Failed to delete old S3 object: \$e');
    }
  }

  Future<void> _pickAndUploadImage() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Images',
          mimeTypes: ['image/png', 'image/jpeg', 'image/webp'],
          extensions: ['png', 'jpg', 'jpeg', 'webp'],
        ),
      ],
    );
    if (file == null || !mounted) {
      return;
    }

    setState(() => _isUploading = true);
    final baseUrl = const String.fromEnvironment(
      'PAPER_API_BASE_URL',
      defaultValue: 'http://localhost:8080',
    );
    final service = GenericAssetService(baseUrl: baseUrl);

    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final contentType =
          file.mimeType ??
          lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ??
          _contentTypeFromExtension(file.name);

      final intent = await service.createUploadIntent(
        GenericAssetUploadIntentInput(
          fileName: file.name,
          contentType: contentType,
          sizeBytes: bytes.length,
          sha256: digest,
        ),
      );

      if (intent.uploadUrl.host != 'mock.local') {
        final response = await http.put(
          intent.uploadUrl,
          headers: intent.headers,
          body: bytes,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(
            'Image upload failed with status \${response.statusCode}.',
          );
        }
      }

      if (intent.readUrl == null) {
        throw Exception('Failed to get read URL from intent.');
      }

      // Delete the old one if it existed and is different
      final oldUrl = widget.controller.text.trim();
      if (oldUrl.isNotEmpty && oldUrl != intent.readUrl) {
        await _deleteOldS3Object(oldUrl);
      }

      widget.controller.text = intent.readUrl!;
      if (mounted) {
        showAppSnack(
          const SnackBar(content: Text('Image uploaded successfully.')),
        );
      }
    } catch (error) {
      if (mounted) {
        showAppSnack(
          SnackBar(content: Text('Image upload failed: \$error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuild);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.controller.text.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              widget.label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            if (url.isNotEmpty)
              TextButton.icon(
                onPressed: () async {
                  await _deleteOldS3Object(url);
                  widget.controller.clear();
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Remove'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          height: 120,
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: url.isNotEmpty
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        widget.placeholderIcon,
                        color: const Color(0xFF94A3B8),
                        size: 48,
                      ),
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: AppButton(
                        label: 'Reupload',
                        icon: Icons.upload_file,
                        isLoading: _isUploading,
                        onPressed: _pickAndUploadImage,
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.placeholderIcon,
                        color: const Color(0xFF94A3B8),
                        size: 32,
                      ),
                      const SizedBox(height: 12),
                      AppButton(
                        label: 'Upload',
                        icon: Icons.upload_file,
                        variant: AppButtonVariant.secondary,
                        isLoading: _isUploading,
                        onPressed: _pickAndUploadImage,
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
