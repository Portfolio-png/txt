import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import '../../../../core/services/generic_asset_service.dart';
import '../../../../core/widgets/app_toast.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../domain/department_definition.dart';
import '../providers/departments_provider.dart';

class DepartmentEditorDialog extends StatelessWidget {
  const DepartmentEditorDialog({super.key, this.department});

  final DepartmentDefinition? department;

  static Future<void> open(
    BuildContext context, {
    DepartmentDefinition? department,
  }) {
    return showErpFormDialog(
      context,
      maxWidth: 560,
      maxHeight: 620,
      child: DepartmentEditorDialog(department: department),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _DepartmentEditorSheet(department: department);
  }
}

class _DepartmentEditorSheet extends StatefulWidget {
  const _DepartmentEditorSheet({this.department});

  final DepartmentDefinition? department;

  @override
  State<_DepartmentEditorSheet> createState() => _DepartmentEditorSheetState();
}

class _DepartmentEditorSheetState extends State<_DepartmentEditorSheet> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _photoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final dept = widget.department;
    if (dept != null) {
      _nameController.text = dept.name;
      _descController.text = dept.description;
      _photoController.text = dept.photoUrl;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _photoController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    final provider = context.read<DepartmentsProvider>();
    final success = widget.department == null
        ? await provider.createDepartment(
            name,
            _descController.text,
            _photoController.text,
          )
        : await provider.updateDepartment(
            widget.department!.id,
            name,
            _descController.text,
            _photoController.text,
          );

    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    return ErpFormScaffold(
      title: widget.department == null ? 'New Department' : 'Edit Department',
      subtitle: 'Group employees under a department for easier management.',
      errorBanner: provider.errorMessage == null
          ? null
          : ErpFormMessageBanner(message: provider.errorMessage!),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ErpDialogSectionCard(
            title: 'Details',
            child: Column(
              children: [
                _Field(controller: _nameController, label: 'Department Name'),
                const SizedBox(height: 14),
                _Field(
                  controller: _descController,
                  label: 'Description',
                  maxLines: 2,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ErpDialogSectionCard(
            title: 'Photo',
            child: _DepartmentImagePickerField(controller: _photoController),
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
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: _decoration(label),
    );
  }
}

class _DepartmentImagePickerField extends StatefulWidget {
  const _DepartmentImagePickerField({required this.controller});

  final TextEditingController controller;

  @override
  State<_DepartmentImagePickerField> createState() =>
      _DepartmentImagePickerFieldState();
}

class _DepartmentImagePickerFieldState
    extends State<_DepartmentImagePickerField> {
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
    if (file == null || !mounted) return;

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
          throw Exception('Upload failed with status ${response.statusCode}.');
        }
      }

      if (intent.readUrl == null) throw Exception('No read URL from intent.');

      widget.controller.text = intent.readUrl!;
      showAppSnack(
        const SnackBar(content: Text('Image uploaded successfully.')),
      );
    } catch (e) {
      showAppSnack(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _isUploading = false);
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: url.isNotEmpty
              ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.image, color: Color(0xFF94A3B8)),
                )
              : const Icon(Icons.image, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: widget.controller,
            decoration: _decoration(
              'Photo URL',
              suffix: url.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => widget.controller.clear(),
                    )
                  : null,
            ),
          ),
        ),
        const SizedBox(width: 8),
        AppButton(
          label: 'Upload',
          icon: Icons.upload_file,
          variant: AppButtonVariant.secondary,
          isLoading: _isUploading,
          onPressed: _pickAndUploadImage,
        ),
      ],
    );
  }
}
