import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/services/entity_photos.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/company_documents_box.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/mini_photo.dart';
import '../../domain/client_definition.dart';
import '../../domain/sub_contractor_definition.dart';
import '../providers/clients_provider.dart';
import '../providers/sub_contractors_provider.dart';
import '../screens/clients_screen.dart';

/// What a company is, rather than how to change it: its logo and details,
/// its people, its contractors, and the documents it keeps.
///
/// Clicking a client used to open its editor. Documents are read far more
/// often than a company is edited, so a click now shows the company, with
/// Edit one button away. Opened down the right-hand edge, the shape the group
/// view uses, so the list it came from stays in sight.
abstract final class CompanyView {
  static Future<void> openClient(BuildContext context, int clientId) =>
      _show(context, 'Company details', _ClientView(clientId: clientId));

  static Future<void> openContractor(BuildContext context, int contractorId) =>
      _show(context, 'Contractor details', _ContractorView(contractorId: contractorId));

  static Future<void> _show(BuildContext context, String label, Widget sheet) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: label,
      barrierColor: const Color(0x66100D1F),
      pageBuilder: (context, animation, secondaryAnimation) => SafeArea(
        child: Align(
          alignment: Alignment.topRight,
          child: Padding(
            padding: const EdgeInsets.only(top: 12, right: 12, bottom: 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600, minWidth: 440),
              child: sheet,
            ),
          ),
        ),
      ),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(curved),
          child: FadeTransition(opacity: curved, child: child),
        );
      },
    );
  }

  static T? _maybe<T>(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<T>(context, listen: listen);
    } on ProviderNotFoundException {
      return null;
    }
  }
}

class _ClientView extends StatefulWidget {
  const _ClientView({required this.clientId});

  final int clientId;

  @override
  State<_ClientView> createState() => _ClientViewState();
}

class _ClientViewState extends State<_ClientView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      CompanyView._maybe<SubContractorsProvider>(context, listen: false)?.ensureLoadedForClient(widget.clientId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final clients = CompanyView._maybe<ClientsProvider>(context);
    ClientDefinition? client;
    for (final c in clients?.clients ?? const <ClientDefinition>[]) {
      if (c.id == widget.clientId) client = c;
    }
    final contractors =
        CompanyView._maybe<SubContractorsProvider>(context)?.forClient(widget.clientId) ??
        const <SubContractorDefinition>[];
    final id = '${widget.clientId}';

    if (client == null) {
      return _scaffold(
        context,
        title: 'Company',
        subtitle: null,
        leading: null,
        body: const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: Text('This company is no longer on file.', style: TextStyle(fontSize: 15)),
        ),
        onEdit: null,
      );
    }
    final found = client;
    final people = found.activeContacts;

    return _scaffold(
      context,
      title: found.name,
      subtitle: [
        'Client',
        if (found.alias.trim().isNotEmpty) found.alias.trim(),
        if (found.isArchived) 'Archived',
      ].join(' · '),
      leading: MiniPhoto(
        owner: PhotoOwner.client,
        id: id,
        size: 52,
        what: 'logo',
        fallbackUrl: found.logoUrl.isNotEmpty ? found.logoUrl : found.photoUrl,
      ),
      onEdit: () => ClientsScreen.openEditor(context, client: found),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Facts(facts: [
            ('GST', found.gstNumber),
            ('Address', found.address),
            if (people.isEmpty) ...[
              ('Contact', found.contactName),
              ('Phone', found.phone),
              ('Email', found.email),
            ],
          ]),
          const SizedBox(height: 16),
          CompanyDocumentsBox(owner: PhotoOwner.client, id: id, note: 'for ${found.name}'),
          if (people.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Section(
              title: 'People · ${people.length}',
              children: [
                for (final person in people)
                  _Line(
                    leading: MiniPhoto(
                      owner: PhotoOwner.person,
                      id: person.id == null ? null : '${person.id}',
                      size: 36,
                      what: 'photo',
                    ),
                    title: person.isPrimary ? '${person.name}  ·  Primary' : person.name,
                    detail: [person.designation, person.phone, person.email]
                        .where((part) => part.trim().isNotEmpty)
                        .join(' · '),
                  ),
              ],
            ),
          ],
          if (contractors.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Section(
              title: 'Contractors · ${contractors.length}',
              children: [
                for (final contractor in contractors)
                  _Line(
                    key: ValueKey<String>('company-view-contractor-${contractor.id}'),
                    leading: const Icon(Icons.handyman_outlined, size: 22, color: SoftErpTheme.textSecondary),
                    title: contractor.name,
                    detail: [contractor.designation, contractor.phone, contractor.gstNumber]
                        .where((part) => part.trim().isNotEmpty)
                        .join(' · '),
                    // One company at a time: this panel closes, that one opens.
                    onTap: () {
                      final navigator = Navigator.of(context);
                      final host = navigator.context;
                      navigator.pop();
                      CompanyView.openContractor(host, contractor.id);
                    },
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ContractorView extends StatefulWidget {
  const _ContractorView({required this.contractorId});

  final int contractorId;

  @override
  State<_ContractorView> createState() => _ContractorViewState();
}

class _ContractorViewState extends State<_ContractorView> {
  @override
  void initState() {
    super.initState();
    // Opened from a part, the contractor's client may never have been listed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final contractors = CompanyView._maybe<SubContractorsProvider>(context, listen: false);
      if (contractors != null &&
          !contractors.allSubContractors.any((c) => c.id == widget.contractorId)) {
        contractors.loadAll();
      }
    });
  }

  int get contractorId => widget.contractorId;

  @override
  Widget build(BuildContext context) {
    SubContractorDefinition? found;
    for (final c in CompanyView._maybe<SubContractorsProvider>(context)?.allSubContractors ??
        const <SubContractorDefinition>[]) {
      if (c.id == contractorId) found = c;
    }
    if (found == null) {
      for (final client in CompanyView._maybe<ClientsProvider>(context)?.clients ?? const <ClientDefinition>[]) {
        for (final c in CompanyView._maybe<SubContractorsProvider>(context)?.forClient(client.id) ??
            const <SubContractorDefinition>[]) {
          if (c.id == contractorId) found = c;
        }
      }
    }
    final contractor = found;
    final id = '$contractorId';
    if (contractor == null) {
      return _scaffold(
        context,
        title: 'Contractor',
        subtitle: null,
        leading: null,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('This contractor\'s details are not loaded here.', style: TextStyle(fontSize: 15)),
            const SizedBox(height: 16),
            CompanyDocumentsBox(owner: PhotoOwner.subContractor, id: id),
          ],
        ),
        onEdit: null,
      );
    }
    final photo = contractor.photoUrl.trim();
    return _scaffold(
      context,
      title: contractor.name,
      subtitle: [
        'Contractor',
        if ((contractor.clientName ?? '').trim().isNotEmpty) 'for ${contractor.clientName!.trim()}',
      ].join(' '),
      leading: Container(
        width: 52,
        height: 52,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: SoftErpTheme.shellSurface,
          borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: photo.startsWith('http')
            ? Image.network(
                photo,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) =>
                    const Icon(Icons.handyman_outlined, color: SoftErpTheme.textSecondary),
              )
            : const Icon(Icons.handyman_outlined, color: SoftErpTheme.textSecondary),
      ),
      onEdit: () => ClientsScreen.openSubContractorEditor(context, subContractor: contractor),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Facts(facts: [
            ('For', contractor.clientName ?? ''),
            ('Designation', contractor.designation),
            ('Phone', contractor.phone),
            ('Email', contractor.email),
            ('GST', contractor.gstNumber),
            ('Address', contractor.address),
            ('Notes', contractor.notes),
          ]),
          const SizedBox(height: 16),
          CompanyDocumentsBox(owner: PhotoOwner.subContractor, id: id, note: 'for ${contractor.name}'),
        ],
      ),
    );
  }
}

Widget _scaffold(
  BuildContext context, {
  required String title,
  required String? subtitle,
  required Widget? leading,
  required Widget body,
  required Future<Object?> Function()? onEdit,
}) {
  return ErpFormScaffold(
    title: title,
    subtitle: subtitle,
    leading: leading,
    onClose: () => Navigator.of(context).pop(),
    body: body,
    footer: Row(
      children: [
        const Spacer(),
        AppButton(
          label: 'Close',
          variant: AppButtonVariant.secondary,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (onEdit != null) ...[
          const SizedBox(width: 12),
          AppButton(
            key: const ValueKey<String>('company-view-edit'),
            label: 'Edit',
            icon: Icons.edit_outlined,
            // Over the view, so the view shows the saved changes after.
            onPressed: () => onEdit(),
          ),
        ],
      ],
    ),
  );
}

/// The company's own facts, label and value; an empty one is left out.
class _Facts extends StatelessWidget {
  const _Facts({required this.facts});

  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final shown = [for (final (label, value) in facts) if (value.trim().isNotEmpty) (label, value.trim())];
    if (shown.isEmpty) {
      return const Text(
        'No details on file yet.',
        style: TextStyle(fontSize: 14, color: SoftErpTheme.textSecondary),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (label, value) in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(
                    label,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: SoftErpTheme.textSecondary),
                  ),
                ),
                Expanded(
                  child: SelectableText(
                    value,
                    style: const TextStyle(fontSize: 15, color: SoftErpTheme.textPrimary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurface,
        borderRadius: BorderRadius.circular(SoftErpTheme.radiusSm),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({super.key, required this.leading, required this.title, required this.detail, this.onTap});

  final Widget leading;
  final String title;
  final String detail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SoftErpTheme.radiusXs),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            SizedBox(width: 40, child: Center(child: leading)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: SoftErpTheme.textPrimary),
                  ),
                  if (detail.isNotEmpty)
                    Text(detail, style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary)),
                ],
              ),
            ),
            if (onTap != null)
              const Icon(Icons.chevron_right_rounded, size: 20, color: SoftErpTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}
