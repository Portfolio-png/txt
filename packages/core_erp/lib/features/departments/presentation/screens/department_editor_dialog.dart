import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';

import '../../../../core/services/generic_asset_service.dart';
import '../../../../core/widgets/app_toast.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../domain/department_definition.dart';
import '../providers/departments_provider.dart';

class DepartmentEditorDialog extends StatefulWidget {
  const DepartmentEditorDialog({super.key, this.department});

  final DepartmentDefinition? department;

  static Future<void> open(BuildContext context, {DepartmentDefinition? department}) {
    return showDialog(
      context: context,
      builder: (_) => DepartmentEditorDialog(department: department),
    );
  }

  @override
  State<DepartmentEditorDialog> createState() => _DepartmentEditorDialogState();
}

class _DepartmentEditorDialogState extends State<DepartmentEditorDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _photoController = TextEditingController(); // Keeping simple string input for URL for now

  @override
  void initState() {
    super.initState();
    if (widget.department != null) {
      _nameController.text = widget.department!.name;
      _descController.text = widget.department!.description;
      _photoController.text = widget.department!.photoUrl;
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
        ? await provider.createDepartment(name, _descController.text, _photoController.text)
        : await provider.updateDepartment(widget.department!.id, name, _descController.text, _photoController.text);

    if (success && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DepartmentsProvider>();
    return AlertDialog(
      title: Text(widget.department == null ? 'New Department' : 'Edit Department'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Department Name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _photoController,
              decoration: const InputDecoration(labelText: 'Photo URL / ID'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        AppButton(
          label: 'Save',
          isLoading: provider.isSaving,
          onPressed: _save,
        ),
      ],
    );
  }
}

class _DepartmentImagePickerField extends StatefulWidget {
  const _DepartmentImagePickerField({
    required this.controller,
  });

  final TextEditingController controller;

  @override
  State<_DepartmentImagePickerField> createState() => _DepartmentImagePickerFieldState();
}

class _DepartmentImagePickerFieldState extends State<_DepartmentImagePickerField> {
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
      case 'png': return 'image/png';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'webp': return 'image/webp';
      default: return 'application/octet-stream';
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
    final baseUrl = const String.fromEnvironment('PAPER_API_BASE_URL', defaultValue: 'http://localhost:8080');
    final service = GenericAssetService(baseUrl: baseUrl);

    try {
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes).toString();
      final contentType = file.mimeType ?? lookupMimeType(file.name, headerBytes: bytes.take(24).toList()) ?? _contentTypeFromExtension(file.name);

      final intent = await service.createUploadIntent(
        GenericAssetUploadIntentInput(
          fileName: file.name,
          contentType: contentType,
          sizeBytes: bytes.length,
          sha256: digest,
        ),
      );

      if (intent.uploadUrl.host != 'mock.local') {
        final response = await http.put(intent.uploadUrl, headers: intent.headers, body: bytes);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Upload failed with status ${response.statusCode}.');
        }
      }

      if (intent.readUrl == null) throw Exception('No read URL from intent.');

      widget.controller.text = intent.readUrl!;
      showAppSnack(const SnackBar(content: Text('Image uploaded successfully.')));
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
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: url.isNotEmpty
              ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_,__,___) => const Icon(Icons.image, color: Color(0xFF94A3B8)))
              : const Icon(Icons.image, color: Color(0xFF94A3B8)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextFormField(
            controller: widget.controller,
            decoration: InputDecoration(
              labelText: 'Photo URL',
              suffixIcon: url.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => widget.controller.clear())
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

