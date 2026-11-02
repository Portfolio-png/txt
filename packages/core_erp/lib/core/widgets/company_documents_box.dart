import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/company_documents.dart';
import '../services/photo_requests.dart';
import '../theme/soft_erp_theme.dart';
import '../utils/stamp_format.dart';
import 'mini_photo.dart';

/// A company's documents — a GST certificate, a drawing, a visiting card —
/// each under a name the user gave it. Add one from a file on this PC (any
/// kind: PDF, picture, spreadsheet), or have the phone photograph it with the
/// company and the name shown over the camera. Each opens, renames and goes.
///
/// [owner] is `client` or `sub_contractor`. With no company yet ([id] null)
/// the box is drawn, disabled, saying why — never hidden. Drawn only where a
/// [CompanyDocumentsProvider] is provided; elsewhere it takes no space.
class CompanyDocumentsBox extends StatelessWidget {
  const CompanyDocumentsBox({
    super.key,
    required this.owner,
    required this.id,
    this.compact = false,
    this.disabledReason,
    this.note,
  });

  /// `client` or `sub_contractor` ([PhotoOwner]).
  final String owner;
  final String? id;

  /// One line per document, for the sheet and the wizard; the company view
  /// draws the roomier rows.
  final bool compact;

  /// Why there is no company yet ("Pick the company first").
  final String? disabledReason;

  /// Where the box sits, shown on the phone above the camera ("for part HH1").
  final String? note;

  /// Overrides the file picker, for tests.
  @visibleForTesting
  static Future<XFile?> Function()? debugPickFile;

  /// Overrides opening a link outside the app, for tests.
  @visibleForTesting
  static Future<bool> Function(Uri url)? debugLaunch;

  static T? _maybe<T>(BuildContext context) {
    try {
      return Provider.of<T>(context);
    } on ProviderNotFoundException {
      return null;
    }
  }

  /// The newest word wins: in bulk entry a refusal must not wait behind the
  /// last "saved".
  static void _say(BuildContext context, String message, {bool error = false}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 14)),
        backgroundColor: error ? SoftErpTheme.dangerText : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = _maybe<CompanyDocumentsProvider>(context);
    if (documents == null) return const SizedBox.shrink();
    final requests = _maybe<PhotoRequestsProvider>(context);
    final id = this.id;

    if (id == null) {
      return Tooltip(
        message: disabledReason ?? 'Pick the company first',
        child: Opacity(
          opacity: 0.55,
          child: _frame(
            header: _header(count: null, onAdd: null),
            children: [_emptyLine('Documents are kept once the company is picked.')],
          ),
        ),
      );
    }

    documents.request(owner, id);
    final list = documents.documentsOf(owner, id);
    final waiting = requests?.pendingDocumentsFor(owner, id) ?? const <PhotoRequest>[];
    final busy = documents.isBusy(owner, id);
    final error = documents.errorOf(owner, id);

    final rows = <Widget>[
      for (final request in waiting)
        _WaitingRow(
          key: ValueKey<String>('document-waiting-${request.id}'),
          title: request.documentTitle ?? '',
          compact: compact,
          onTakeBack: () async {
            final failed = await requests!.withdraw(request);
            if (!context.mounted) return;
            _say(context, failed ?? 'Taken back from your phone.', error: failed != null);
          },
        ),
      for (final document in list ?? const <CompanyDocument>[])
        _DocumentRow(
          key: ValueKey<String>('document-${document.id}'),
          document: document,
          compact: compact,
          onOpen: () => _openDocument(context, documents, document),
          onRename: () => _rename(context, documents, id, document),
          onRemove: () => _remove(context, documents, id, document),
        ),
    ];

    return _frame(
      header: _header(
        count: list == null ? null : list.length + waiting.length,
        busy: busy || list == null,
        onAdd: busy ? null : () => _add(context, documents, requests, id),
      ),
      children: [
        if (error != null && (list == null || list.isEmpty))
          _emptyLine('Documents could not be read: $error', colour: SoftErpTheme.dangerText)
        else if (list != null && rows.isEmpty)
          _emptyLine('None yet — a GST certificate, a drawing, an agreement, a visiting card.'),
        ...rows,
      ],
    );
  }

  Widget _header({required int? count, bool busy = false, required VoidCallback? onAdd}) {
    return Row(
      children: [
        const Icon(Icons.folder_copy_outlined, size: 18, color: SoftErpTheme.textSecondary),
        const SizedBox(width: 8),
        Text(
          count == null || count == 0 ? 'Documents' : 'Documents · $count',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        if (busy) ...[
          const SizedBox(width: 10),
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ],
        const Spacer(),
        TextButton.icon(
          key: ValueKey<String>('document-add-$owner-${id ?? 'none'}'),
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text(
            'Add document',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }

  Widget _frame({required Widget header, required List<Widget> children}) {
    return Container(
      key: ValueKey<String>('documents-$owner-${id ?? 'none'}'),
      padding: EdgeInsets.fromLTRB(14, compact ? 4 : 8, 6, compact ? 6 : 10),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [header, ...children],
      ),
    );
  }

  Widget _emptyLine(String text, {Color colour = SoftErpTheme.textSecondary}) => Padding(
    padding: const EdgeInsets.only(top: 2, bottom: 4, right: 8),
    child: Text(text, style: TextStyle(fontSize: 14, color: colour)),
  );

  /// Name it, then where it comes from: the phone's camera, or a file here.
  Future<void> _add(
    BuildContext context,
    CompanyDocumentsProvider documents,
    PhotoRequestsProvider? requests,
    String id,
  ) async {
    final choice = await showDialog<({String how, String name})>(
      context: context,
      builder: (_) => _AddDocumentDialog(phoneAvailable: requests != null),
    );
    if (choice == null || !context.mounted) return;

    if (choice.how == 'phone') {
      final failed = await requests!.ask(
        owner,
        id,
        context: note ?? '',
        documentTitle: choice.name,
      );
      if (!context.mounted) return;
      _say(
        context,
        failed ?? 'Sent to your phone — it opens the camera for "${choice.name}".',
        error: failed != null,
      );
      return;
    }

    final file = await (debugPickFile?.call() ?? openFile());
    if (file == null || !context.mounted) return;
    final size = await file.length();
    if (!context.mounted) return;
    if (size > maxCompanyDocumentBytes) {
      _say(
        context,
        '${file.name} is ${formatDocumentSize(size)} — a document can be 25 MB at most.',
        error: true,
      );
      return;
    }
    final name = choice.name.isNotEmpty ? choice.name : _stem(file.name);
    final failed = await documents.upload(owner, id, file, name);
    if (!context.mounted) return;
    _say(context, failed ?? '"$name" saved.', error: failed != null);
  }

  static String _stem(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final stem = (dot > 0 ? fileName.substring(0, dot) : fileName).trim();
    return stem.isEmpty ? 'Document' : stem;
  }

  Future<void> _openDocument(
    BuildContext context,
    CompanyDocumentsProvider documents,
    CompanyDocument document,
  ) async {
    String url;
    try {
      url = await documents.repository.readUrl(document.id);
    } catch (error) {
      if (context.mounted) _say(context, '$error', error: true);
      return;
    }
    if (!context.mounted) return;
    if (document.isImage) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(document.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          content: SizedBox(
            width: 640,
            height: 520,
            child: InteractiveViewer(
              maxScale: 6,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => const Center(
                  child: Icon(Icons.broken_image_outlined, size: 40, color: SoftErpTheme.textMuted),
                ),
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _launch(dialogContext, url),
              icon: const Icon(Icons.open_in_new_rounded),
              label: const Text('Open outside', style: TextStyle(fontSize: 14)),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close', style: TextStyle(fontSize: 14)),
            ),
          ],
        ),
      );
      return;
    }
    await _launch(context, url);
  }

  /// In the PC's own viewer; when there is none, the link is copied instead.
  static Future<void> _launch(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    var opened = false;
    try {
      final launch = debugLaunch;
      opened = launch != null
          ? await launch(uri)
          : await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }
    if (opened || !context.mounted) return;
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) {
      _say(context, 'Could not open it here — the link is copied (good for 5 minutes).');
    }
  }

  Future<void> _rename(
    BuildContext context,
    CompanyDocumentsProvider documents,
    String id,
    CompanyDocument document,
  ) async {
    final next = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(current: document.title),
    );
    if (next == null || next == document.title || !context.mounted) return;
    final failed = await documents.rename(owner, id, document, next);
    if (!context.mounted) return;
    _say(context, failed ?? 'Renamed to "$next".', error: failed != null);
  }

  Future<void> _remove(
    BuildContext context,
    CompanyDocumentsProvider documents,
    String id,
    CompanyDocument document,
  ) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this document?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        content: Text(
          '"${document.title}" (${document.fileName}) is taken off this company.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep', style: TextStyle(fontSize: 14)),
          ),
          TextButton(
            key: const ValueKey<String>('document-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: SoftErpTheme.dangerText),
            child: const Text('Remove', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    final failed = await documents.remove(owner, id, document);
    if (!context.mounted) return;
    _say(context, failed ?? '"${document.title}" removed.', error: failed != null);
  }
}

/// A saved document: what kind it is, its name, and when it came.
class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    super.key,
    required this.document,
    required this.compact,
    required this.onOpen,
    required this.onRename,
    required this.onRemove,
  });

  final CompanyDocument document;
  final bool compact;
  final VoidCallback onOpen;
  final VoidCallback onRename;
  final VoidCallback onRemove;

  IconData get _icon {
    if (document.isPdf) return Icons.picture_as_pdf_outlined;
    if (document.isImage) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final meta =
        '${document.kindLabel} · ${formatDocumentSize(document.sizeBytes)} · ${partStamp(document.uploadedAt)}';
    final thumb = Container(
      width: compact ? 30 : 44,
      height: compact ? 30 : 44,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: SoftErpTheme.shellSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: !compact && document.isImage && (document.readUrl ?? '').isNotEmpty
          ? Image.network(
              document.readUrl!,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stack) =>
                  Icon(_icon, size: 20, color: SoftErpTheme.textSecondary),
            )
          : Icon(_icon, size: compact ? 18 : 22, color: SoftErpTheme.accent),
    );
    final name = Text(
      document.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary),
    );
    final detail = Text(
      meta,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
    );
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 3 : 6),
        child: Row(
          children: [
            Tooltip(message: 'Open ${document.fileName}', child: thumb),
            const SizedBox(width: 10),
            Expanded(
              child: compact
                  ? Row(
                      children: [
                        Flexible(child: name),
                        const SizedBox(width: 10),
                        Flexible(child: detail),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [name, const SizedBox(height: 2), detail],
                    ),
            ),
            IconButton(
              tooltip: 'Rename',
              onPressed: onRename,
              icon: const Icon(Icons.edit_outlined, size: 18),
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}

/// A document the phone has yet to photograph; a tap takes it back.
class _WaitingRow extends StatelessWidget {
  const _WaitingRow({
    super.key,
    required this.title,
    required this.compact,
    required this.onTakeBack,
  });

  final String title;
  final bool compact;
  final VoidCallback onTakeBack;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Waiting for your phone — click to take it back',
      child: InkWell(
        onTap: onTakeBack,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: compact ? 3 : 6),
          child: Row(
            children: [
              Container(
                width: compact ? 30 : 44,
                height: compact ? 30 : 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: SoftErpTheme.shellSurface,
                  borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
                  border: Border.all(color: SoftErpTheme.warningBorder),
                ),
                child: const Icon(Icons.phone_iphone_rounded, size: 18, color: SoftErpTheme.warningText),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: title,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary),
                      ),
                      const TextSpan(
                        text: '   On phone · waiting',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: SoftErpTheme.warningText),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Icon(Icons.close_rounded, size: 18, color: SoftErpTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The name first, then where the document comes from. The phone files it
/// under the name, so it needs one; a file from the PC can take its own.
class _AddDocumentDialog extends StatefulWidget {
  const _AddDocumentDialog({required this.phoneAvailable});

  final bool phoneAvailable;

  @override
  State<_AddDocumentDialog> createState() => _AddDocumentDialogState();
}

class _AddDocumentDialogState extends State<_AddDocumentDialog> {
  final _name = TextEditingController();

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    final named = _trimmed.isNotEmpty;
    return SimpleDialog(
      title: const Text('Add a document', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: SizedBox(
            width: 420,
            child: TextField(
              key: const ValueKey<String>('document-name'),
              controller: _name,
              autofocus: true,
              maxLength: 120,
              style: const TextStyle(fontSize: 15),
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'GST certificate, Drawing rev B, Visiting card…',
                counterText: '',
              ),
            ),
          ),
        ),
        PhotoChoiceTile(
          key: const ValueKey<String>('document-take-on-phone'),
          icon: Icons.phone_iphone_rounded,
          title: 'Take on phone',
          detail: !widget.phoneAvailable
              ? 'Phone photos are not set up in this app.'
              : named
              ? 'Your phone opens the camera, with the company and "$_trimmed" on it.'
              : 'Name it first — the phone files the photo under that name.',
          onTap: widget.phoneAvailable && named
              ? () => Navigator.of(context).pop((how: 'phone', name: _trimmed))
              : null,
        ),
        PhotoChoiceTile(
          key: const ValueKey<String>('document-choose-file'),
          icon: Icons.folder_open_rounded,
          title: 'Choose a file from this PC',
          detail: named
              ? 'Any file — PDF, picture, spreadsheet. Up to 25 MB.'
              : 'Any file, up to 25 MB. Unnamed, it is called by its file name.',
          onTap: () => Navigator.of(context).pop((how: 'file', name: _trimmed)),
        ),
      ],
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.current});

  final String current;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _name = TextEditingController(text: widget.current);

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String get _trimmed => _name.text.replaceAll(RegExp(r'\s+'), ' ').trim();

  @override
  Widget build(BuildContext context) {
    void save() => Navigator.of(context).pop(_trimmed);
    return AlertDialog(
      title: const Text('Rename document', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const ValueKey<String>('document-rename'),
          controller: _name,
          autofocus: true,
          maxLength: 120,
          style: const TextStyle(fontSize: 15),
          decoration: const InputDecoration(labelText: 'Name', counterText: ''),
          onSubmitted: (_) {
            if (_trimmed.isNotEmpty) save();
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(fontSize: 14)),
        ),
        TextButton(
          key: const ValueKey<String>('document-rename-save'),
          onPressed: _trimmed.isEmpty ? null : save,
          child: const Text('Save', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
