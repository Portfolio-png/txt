import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/party_import_service.dart';
import '../theme/soft_erp_theme.dart';
import 'app_button.dart';
import 'app_toast.dart';

/// Creates one record from a parsed row. Returns an error message, or null on
/// success — the dialog stays agnostic about clients vs vendors.
typedef PartyRowImporter = Future<String?> Function(Map<String, String> values);

/// Download-a-template / fill-in / import-back flow for the client and vendor
/// masters, for users who keep this data in Excel already.
class PartyImportDialog extends StatefulWidget {
  const PartyImportDialog({
    super.key,
    required this.kind,
    required this.existingNames,
    required this.onImportRow,
  });

  final PartyKind kind;
  final List<String> existingNames;
  final PartyRowImporter onImportRow;

  static Future<bool> open(
    BuildContext context, {
    required PartyKind kind,
    required List<String> existingNames,
    required PartyRowImporter onImportRow,
  }) async {
    final imported = await showDialog<bool>(
      context: context,
      builder: (_) => PartyImportDialog(
        kind: kind,
        existingNames: existingNames,
        onImportRow: onImportRow,
      ),
    );
    return imported ?? false;
  }

  @override
  State<PartyImportDialog> createState() => _PartyImportDialogState();
}

class _PartyImportDialogState extends State<PartyImportDialog> {
  PartyImportResult? _parsed;
  String? _fileName;
  bool _isWorking = false;
  int _importedCount = 0;
  final List<String> _failures = <String>[];
  bool _finished = false;

  /// Saves the template straight to Downloads rather than through a Save panel.
  ///
  /// The template is a fixed artefact with a fixed name — there is nothing to
  /// choose — and on a sandboxed macOS build the first NSSavePanel costs
  /// seconds spinning up the powerbox service. Generating the file itself takes
  /// ~25 ms, so skipping the panel is the whole difference.
  ///
  /// Platforms with no Downloads directory (mobile, web) still get the picker.
  Future<void> _downloadTemplate() async {
    setState(() => _isWorking = true);
    final fileName = '${widget.kind.templateFileName}.xlsx';
    const mimeType =
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    try {
      final bytes = PartyImportService.buildTemplate(widget.kind);

      // Inferred, so this file needs no dart:io import of its own.
      var downloads = await _downloadsDirectoryOrNull();

      if (downloads == null) {
        final location = await getSaveLocation(suggestedName: fileName);
        if (location == null) return;
        await XFile.fromData(bytes, mimeType: mimeType).saveTo(location.path);
        showAppSnack(const SnackBar(content: Text('Template saved.')));
        return;
      }

      // Forward slash is accepted by Dart's file APIs on Windows too.
      final path = '${downloads.path}/$fileName';
      await XFile.fromData(bytes, mimeType: mimeType).saveTo(path);
      showAppSnack(
        SnackBar(
          content: Text('Saved to Downloads — $fileName'),
          action: SnackBarAction(
            label: 'Open',
            onPressed: () => launchUrl(Uri.file(path)),
          ),
        ),
      );
    } catch (error) {
      showAppSnack(SnackBar(content: Text('Could not save template: $error')));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _pickFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Excel', extensions: ['xlsx']),
      ],
    );
    if (file == null || !mounted) return;

    setState(() => _isWorking = true);
    try {
      final bytes = Uint8List.fromList(await file.readAsBytes());
      final parsed = PartyImportService.parse(
        bytes,
        widget.kind,
        existingNames: widget.existingNames,
      );
      if (!mounted) return;
      setState(() {
        _parsed = parsed;
        _fileName = file.name;
        _importedCount = 0;
        _failures.clear();
        _finished = false;
      });
    } catch (error) {
      showAppSnack(SnackBar(content: Text('Could not read the file: $error')));
    } finally {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  Future<void> _runImport() async {
    final rows = _parsed?.importable ?? const <PartyImportRow>[];
    if (rows.isEmpty) return;
    setState(() {
      _isWorking = true;
      _importedCount = 0;
      _failures.clear();
    });
    for (final row in rows) {
      final error = await widget.onImportRow(row.values);
      if (!mounted) return;
      setState(() {
        if (error == null) {
          _importedCount++;
        } else {
          _failures.add('Row ${row.rowNumber} (${row.name}): $error');
        }
      });
    }
    if (!mounted) return;
    setState(() {
      _isWorking = false;
      _finished = true;
    });
  }

  /// Null on platforms with no Downloads directory (mobile, web), where the
  /// caller falls back to a save picker.
  Future<dynamic> _downloadsDirectoryOrNull() async {
    try {
      return await getDownloadsDirectory();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final parsed = _parsed;
    return Dialog(
      backgroundColor: SoftErpTheme.cardSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Import ${widget.kind.pluralLabel} from Excel',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: SoftErpTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _isWorking
                        ? null
                        : () => Navigator.of(context).pop(_importedCount > 0),
                    icon: const Icon(Icons.close_rounded, size: 20),
                    color: SoftErpTheme.textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Download the template, fill one ${widget.kind.label.toLowerCase()} '
                'per row, then bring it back here.',
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: SoftErpTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  AppButton(
                    label: 'Download template',
                    icon: Icons.download_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: _isWorking ? null : _downloadTemplate,
                  ),
                  AppButton(
                    label: parsed == null ? 'Choose filled file' : 'Choose another file',
                    icon: Icons.upload_file_outlined,
                    variant: AppButtonVariant.secondary,
                    onPressed: _isWorking ? null : _pickFile,
                  ),
                ],
              ),
              if (parsed != null) ...[
                const SizedBox(height: 18),
                Flexible(child: _buildSummary(parsed)),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isWorking
                        ? null
                        : () => Navigator.of(context).pop(_importedCount > 0),
                    child: Text(_finished ? 'Done' : 'Cancel'),
                  ),
                  const SizedBox(width: 8),
                  if (!_finished)
                    AppButton(
                      label: parsed == null
                          ? 'Import'
                          : 'Import ${parsed.importable.length}',
                      isLoading: _isWorking,
                      onPressed:
                          (parsed == null || parsed.importable.isEmpty || _isWorking)
                          ? null
                          : _runImport,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummary(PartyImportResult parsed) {
    if (parsed.headerProblems.isNotEmpty) {
      return _panel(
        tone: SoftErpTheme.dangerBg,
        border: const Color(0xFFF4D4CB),
        children: [
          _line('This file cannot be imported:', bold: true),
          for (final problem in parsed.headerProblems) _line('• $problem'),
          _line(
            'Use the downloaded template and keep its header row unchanged.',
          ),
        ],
      );
    }

    final rejected = parsed.rejected;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _line('$_fileName', bold: true),
          const SizedBox(height: 8),
          _panel(
            tone: SoftErpTheme.successBg,
            border: const Color(0xFFBFE7CD),
            children: [
              _line(
                _finished
                    ? '$_importedCount of ${parsed.importable.length} imported.'
                    : '${parsed.importable.length} ready to import.',
                bold: true,
              ),
            ],
          ),
          if (rejected.isNotEmpty) ...[
            const SizedBox(height: 10),
            _panel(
              tone: SoftErpTheme.warningBg,
              border: const Color(0xFFF2DFC0),
              children: [
                _line('${rejected.length} row(s) will be skipped:', bold: true),
                for (final row in rejected.take(12))
                  _line(
                    '• Row ${row.rowNumber}'
                    '${row.name.isEmpty ? '' : ' (${row.name})'}: '
                    '${row.isDuplicate ? 'already exists' : row.errors.join(' ')}',
                  ),
                if (rejected.length > 12)
                  _line('• …and ${rejected.length - 12} more'),
              ],
            ),
          ],
          if (_failures.isNotEmpty) ...[
            const SizedBox(height: 10),
            _panel(
              tone: SoftErpTheme.dangerBg,
              border: const Color(0xFFF4D4CB),
              children: [
                _line('${_failures.length} row(s) failed to save:', bold: true),
                for (final failure in _failures.take(12)) _line('• $failure'),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _panel({
    required Color tone,
    required Color border,
    required List<Widget> children,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _line(String text, {bool bold = false}) => Padding(
    padding: const EdgeInsets.only(bottom: 2),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.4,
        fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        color: SoftErpTheme.textPrimary,
      ),
    ),
  );
}
