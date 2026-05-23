import 'dart:convert';
import 'dart:io' show File, Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/preferences/preferences_provider.dart';
import '../../../../app/reports/domain/reconciliation_report.dart';
import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/erp_form_dialog.dart';
import '../../../../core/widgets/page_container.dart';
import '../../../../core/widgets/searchable_select.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../../widgets/variation_path_selector_dialog.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
import '../../../inventory/presentation/providers/inventory_provider.dart';
import '../../../items/domain/item_definition.dart';
import '../../../units/presentation/providers/units_provider.dart';
import '../../../items/presentation/providers/items_provider.dart';
import '../../../orders/domain/order_entry.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../vendors/presentation/providers/vendors_provider.dart';
import '../../data/delivery_challan_repository.dart';
import '../../domain/challan_template.dart';
import '../../domain/delivery_challan.dart';
import '../providers/challan_editor_command_provider.dart';
import '../providers/delivery_challan_provider.dart';
import 'challan_template_mapping_screen.dart';

const MethodChannel _nativePrintingChannel = MethodChannel(
  'paper/native_printing',
);
const String _defaultChallanStorageLocation = 'MAIN';

class ChallanScreen extends StatefulWidget {
  const ChallanScreen({super.key});

  static Future<void> openEditor(
    BuildContext context, {
    DeliveryChallan? challan,
    DeliveryChallan? sourceForDuplicate,
    OrderEntry? initialOrder,
    ChallanType? initialType,
    String? initialLocation,
  }) {
    return _showChallanEditor(
      context,
      challan: challan,
      sourceForDuplicate: sourceForDuplicate,
      initialOrder: initialOrder,
      initialType: initialType,
      initialLocation: initialLocation,
    );
  }

  static Future<void> openEditorForOrder(
    BuildContext context,
    OrderEntry order,
  ) {
    return _showChallanEditor(
      context,
      initialOrder: order,
      initialType: ChallanType.delivery,
    );
  }

  static Future<void> openReceptionEditor(
    BuildContext context, {
    String? initialLocation,
  }) {
    return _showChallanEditor(
      context,
      initialType: ChallanType.reception,
      initialLocation: initialLocation,
    );
  }

  @override
  State<ChallanScreen> createState() => _ChallanScreenState();
}

Future<void> _showChallanEditor(
  BuildContext context, {
  DeliveryChallan? challan,
  DeliveryChallan? sourceForDuplicate,
  OrderEntry? initialOrder,
  ChallanType? initialType,
  String? initialLocation,
}) {
  context.read<DeliveryChallanProvider>().clearError();
  return showErpFormDialog<void>(
    context,
    maxWidth: 1440,
    maxHeight: 760,
    child: _ChallanEditor(
      challan: challan,
      sourceForDuplicate: sourceForDuplicate,
      initialOrder: initialOrder,
      initialType: initialType,
      initialLocation: initialLocation,
      onPrint: (saved) {
        if (context.mounted) {
          _openPrintPreviewFromContext(context, saved);
        }
      },
    ),
  );
}

Future<void> _openPrintPreviewFromContext(
  BuildContext context,
  DeliveryChallan challan,
) async {
  final provider = context.read<DeliveryChallanProvider>();
  final full = await provider.loadChallan(challan.id) ?? challan;
  if (!context.mounted) {
    return;
  }
  await showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(
        width: 860,
        height: math.min(MediaQuery.of(context).size.height - 40, 820),
        child: _PrintPreview(challan: full),
      ),
    ),
  );
}

class _ChallanScreenState extends State<ChallanScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showTemplates = false;
  String? _activeReportGroupCode;
  int? _focusedChallanId;
  final Set<String> _selectedDeliveryChallanNos = <String>{};
  final Set<String> _selectedReceptionChallanNos = <String>{};
  bool _isGeneratingReport = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();
    final reportGroups = _availableReportGroupCodes(provider.challans);
    final activeReportGroupCode =
        (_activeReportGroupCode != null &&
            reportGroups.contains(_activeReportGroupCode))
        ? _activeReportGroupCode
        : (reportGroups.isEmpty ? null : reportGroups.first);
    final deliveryChallans = provider.challans
        .where(
          (challan) =>
              challan.isDelivery &&
              _challanBelongsToReportGroup(challan, activeReportGroupCode),
        )
        .toList(growable: false);
    final receptionChallans = provider.challans
        .where(
          (challan) =>
              challan.isReception &&
              _receptionVisibleForReportGroup(challan, activeReportGroupCode),
        )
        .toList(growable: false);
    final focusedChallan = _focusedChallanId == null
        ? null
        : provider.challans
              .where((challan) => challan.id == _focusedChallanId)
              .firstOrNull;
    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            isGeneratingReport: _isGeneratingReport,
            canGenerateReport:
                activeReportGroupCode != null &&
                _selectedDeliveryChallanNos.isNotEmpty &&
                _selectedReceptionChallanNos.isNotEmpty,
            onCreateDelivery: () =>
                _openEditor(context, initialType: ChallanType.delivery),
            onCreateReception: () =>
                _openEditor(context, initialType: ChallanType.reception),
            onEditProfile: () => _openCompanyProfile(context),
            onOpenTemplates: () => setState(() => _showTemplates = true),
            onGenerateReport: activeReportGroupCode == null
                ? null
                : () => _generateReport(context, activeReportGroupCode),
          ),
          const SizedBox(height: 16),
          if (_showTemplates)
            Expanded(
              child: TemplateMappingScreen(
                onBack: () => setState(() => _showTemplates = false),
              ),
            )
          else ...[
            _Filters(
              searchController: _searchController,
              status: provider.statusFilter,
              orderFilterId: provider.orderFilterId,
              reportGroups: reportGroups,
              selectedReportGroupCode: activeReportGroupCode,
              selectedDeliveryCount: _selectedDeliveryChallanNos.length,
              selectedReceptionCount: _selectedReceptionChallanNos.length,
              onSearch: provider.setSearchQuery,
              onStatusChanged: provider.setStatusFilter,
              onReportGroupChanged: _setActiveReportGroup,
              onClearOrderFilter: () => provider.setOrderFilter(null),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: provider.isLoading
                  ? const SoftSurface(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _ChallanWorkspace(
                      activeReportGroupCode: activeReportGroupCode,
                      deliveryChallans: deliveryChallans,
                      receptionChallans: receptionChallans,
                      selectedDeliveryChallanNos: _selectedDeliveryChallanNos,
                      selectedReceptionChallanNos: _selectedReceptionChallanNos,
                      focusedChallan: focusedChallan,
                      onFocus: (challan) =>
                          setState(() => _focusedChallanId = challan?.id),
                      onToggleDelivery: _toggleDeliverySelection,
                      onToggleReception: _toggleReceptionSelection,
                      onOpen: (challan) =>
                          _openEditor(context, challan: challan),
                      onPrint: (challan) => _openPrintPreview(context, challan),
                      onDuplicate: (challan) => _openEditor(
                        context,
                        challan: challan,
                        duplicate: true,
                      ),
                      onCancel: (challan) => _cancel(context, challan),
                      onDelete: (challan) => _delete(context, challan),
                      onToggleReportGroup: activeReportGroupCode == null
                          ? null
                          : (challan) => _toggleReceptionReportGroup(
                              context,
                              challan,
                              activeReportGroupCode,
                            ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    DeliveryChallan? challan,
    bool duplicate = false,
    ChallanType? initialType,
  }) async {
    DeliveryChallan? full = challan;
    if (challan != null && !duplicate) {
      full = await context.read<DeliveryChallanProvider>().loadChallan(
        challan.id,
      );
      if (!context.mounted || full == null) {
        return;
      }
    }
    await _showChallanEditor(
      context,
      challan: duplicate ? null : full,
      sourceForDuplicate: duplicate ? full : null,
      initialType: initialType,
    );
  }

  Future<void> _openCompanyProfile(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const Dialog(
        insetPadding: EdgeInsets.all(24),
        child: SizedBox(width: 720, child: _CompanyProfileEditor()),
      ),
    );
  }

  Future<void> _openPrintPreview(
    BuildContext context,
    DeliveryChallan challan,
  ) async {
    await _openPrintPreviewFromContext(context, challan);
  }

  Future<void> _cancel(BuildContext context, DeliveryChallan challan) async {
    final provider = context.read<DeliveryChallanProvider>();
    final cancelled = await provider.cancelChallan(challan.id);
    if (!context.mounted) return;
    if (cancelled != null) {
      await context.read<InventoryProvider>().refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cancelled challan ${challan.challanNo}.')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage ?? 'Could not cancel challan.')),
      );
    }
  }

  Future<void> _delete(BuildContext context, DeliveryChallan challan) async {
    final provider = context.read<DeliveryChallanProvider>();
    await provider.deleteChallan(challan.id);
    if (!context.mounted) return;
    if (provider.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.errorMessage!)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            challan.isReception ? 'Deleted reception challan.' : 'Deleted draft challan.',
          ),
        ),
      );
    }
  }

  void _setActiveReportGroup(String? code) {
    setState(() {
      _activeReportGroupCode = code;
      _focusedChallanId = null;
      _selectedDeliveryChallanNos.clear();
      _selectedReceptionChallanNos.clear();
    });
  }

  void _toggleDeliverySelection(DeliveryChallan challan, bool selected) {
    setState(() {
      if (selected) {
        _selectedDeliveryChallanNos.add(challan.challanNo);
      } else {
        _selectedDeliveryChallanNos.remove(challan.challanNo);
      }
    });
  }

  void _toggleReceptionSelection(DeliveryChallan challan, bool selected) {
    setState(() {
      if (selected) {
        _selectedReceptionChallanNos.add(challan.challanNo);
      } else {
        _selectedReceptionChallanNos.remove(challan.challanNo);
      }
    });
  }

  Future<void> _toggleReceptionReportGroup(
    BuildContext context,
    DeliveryChallan challan,
    String reportGroupCode,
  ) async {
    final codes = _effectiveReportGroupCodes(challan).toSet();
    if (codes.contains(reportGroupCode)) {
      codes.remove(reportGroupCode);
      _selectedReceptionChallanNos.remove(challan.challanNo);
    } else {
      codes.add(reportGroupCode);
    }
    final provider = context.read<DeliveryChallanProvider>();
    final updated = await provider.updateChallanReportGroups(
      challan.id,
      codes.toList(growable: false),
    );
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          updated == null
              ? (provider.errorMessage ?? 'Could not update report group links.')
              : 'Updated report links for ${challan.challanNo}.',
        ),
      ),
    );
  }

  Future<void> _generateReport(
    BuildContext context,
    String reportGroupCode,
  ) async {
    if (_selectedDeliveryChallanNos.isEmpty ||
        _selectedReceptionChallanNos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Select at least one delivery and one linked reception challan.',
          ),
        ),
      );
      return;
    }
    setState(() => _isGeneratingReport = true);
    try {
      final report = await context
          .read<DeliveryChallanProvider>()
          .repository
          .generateClientStatementReport(
            reportGroupCode: reportGroupCode,
            challanNos: _selectedDeliveryChallanNos.toList(growable: false)
              ..sort(),
            receptionChallanNos: _selectedReceptionChallanNos.toList(
              growable: false,
            )..sort(),
          );
      final bytes = await _buildClientStatementPdf(report, reportGroupCode);
      showDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          insetPadding: const EdgeInsets.all(20),
          child: SizedBox(
            width: 860,
            height: math.min(MediaQuery.of(context).size.height - 40, 820),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Client Statement Preview',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: PdfPreview(
                    build: (_) async => bytes,
                    allowPrinting: true,
                    allowSharing: true,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    pdfFileName: 'client-statement-$reportGroupCode.pdf',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (!context.mounted) {
        return;
      }
      await context.read<DeliveryChallanProvider>().refresh();
      setState(() {
        _selectedDeliveryChallanNos.clear();
        _selectedReceptionChallanNos.clear();
      });
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingReport = false);
      }
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.isGeneratingReport,
    required this.canGenerateReport,
    required this.onCreateDelivery,
    required this.onCreateReception,
    required this.onEditProfile,
    required this.onOpenTemplates,
    required this.onGenerateReport,
  });

  final bool isGeneratingReport;
  final bool canGenerateReport;
  final VoidCallback onCreateDelivery;
  final VoidCallback onCreateReception;
  final VoidCallback onEditProfile;
  final VoidCallback onOpenTemplates;
  final VoidCallback? onGenerateReport;

  @override
  Widget build(BuildContext context) {
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppButton(
          label: 'Company Profile',
          icon: Icons.apartment_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: onEditProfile,
        ),
        const SizedBox(width: 10),
        AppButton(
          label: 'Templates',
          icon: Icons.dashboard_customize_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: onOpenTemplates,
        ),
        const SizedBox(width: 10),
        AppButton(
          label: 'Report',
          icon: Icons.analytics_outlined,
          isLoading: isGeneratingReport,
          onPressed: canGenerateReport ? onGenerateReport : null,
        ),
        const SizedBox(width: 14),
        AppButton(
          label: 'Create Reception',
          icon: Icons.south_west_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: onCreateReception,
        ),
        const SizedBox(width: 10),
        AppButton(
          label: 'Create Delivery',
          icon: Icons.north_east_rounded,
          onPressed: onCreateDelivery,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final title = ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 280, maxWidth: 620),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Challans',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Select a report group, verify receptions, then generate the client statement directly.',
                style: TextStyle(color: SoftErpTheme.textSecondary),
              ),
            ],
          ),
        );

        if (!constraints.hasBoundedWidth || constraints.maxWidth < 920) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: actions,
                ),
              ),
            ],
          );
        }

        if (constraints.maxWidth < 1280) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [Expanded(child: title)],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: actions,
                ),
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            title,
            const SizedBox(width: 14),
            Flexible(
              child: Align(
                alignment: Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: actions,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.searchController,
    required this.status,
    required this.orderFilterId,
    required this.reportGroups,
    required this.selectedReportGroupCode,
    required this.selectedDeliveryCount,
    required this.selectedReceptionCount,
    required this.onSearch,
    required this.onStatusChanged,
    required this.onReportGroupChanged,
    required this.onClearOrderFilter,
  });

  final TextEditingController searchController;
  final DeliveryChallanStatus? status;
  final int? orderFilterId;
  final List<String> reportGroups;
  final String? selectedReportGroupCode;
  final int selectedDeliveryCount;
  final int selectedReceptionCount;
  final ValueChanged<String> onSearch;
  final ValueChanged<DeliveryChallanStatus?> onStatusChanged;
  final ValueChanged<String?> onReportGroupChanged;
  final VoidCallback onClearOrderFilter;

  @override
  Widget build(BuildContext context) {
    final searchField = TextField(
      controller: searchController,
      onSubmitted: onSearch,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search_rounded),
        hintText:
            'Search challan number, order, customer, vendor, or reference',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SoftErpTheme.border),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
      ),
    );
    final statusFilter = SegmentedButton<DeliveryChallanStatus?>(
      segments: const [
        ButtonSegment(value: null, label: Text('All')),
        ButtonSegment(value: DeliveryChallanStatus.draft, label: Text('Draft')),
        ButtonSegment(
          value: DeliveryChallanStatus.issued,
          label: Text('Issued'),
        ),
        ButtonSegment(
          value: DeliveryChallanStatus.cancelled,
          label: Text('Cancelled'),
        ),
      ],
      selected: {status},
      onSelectionChanged: (value) => onStatusChanged(value.first),
    );
    final groupSelector = SizedBox(
      width: 260,
      child: DropdownButtonFormField<String>(
        initialValue: selectedReportGroupCode,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: 'Report group',
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: SoftErpTheme.border),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        items: reportGroups
            .map(
              (code) => DropdownMenuItem<String>(
                value: code,
                child: Text(code, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(growable: false),
        onChanged: reportGroups.isEmpty ? null : onReportGroupChanged,
      ),
    );
    final selectionPill = SoftPill(
      label: '$selectedReceptionCount Rec / $selectedDeliveryCount Del',
      background: SoftErpTheme.accent.withValues(alpha: 0.08),
      foreground: SoftErpTheme.textPrimary,
      borderColor: SoftErpTheme.accent.withValues(alpha: 0.2),
    );

    return SoftSurface(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1180;
          final filterWrap = Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (orderFilterId != null)
                InputChip(
                  label: Text('Order #$orderFilterId'),
                  onDeleted: onClearOrderFilter,
                ),
              groupSelector,
              statusFilter,
              selectionPill,
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [searchField, const SizedBox(height: 12), filterWrap],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 12),
              Flexible(child: filterWrap),
            ],
          );
        },
      ),
    );
  }
}

class _ChallanWorkspace extends StatelessWidget {
  const _ChallanWorkspace({
    required this.activeReportGroupCode,
    required this.deliveryChallans,
    required this.receptionChallans,
    required this.selectedDeliveryChallanNos,
    required this.selectedReceptionChallanNos,
    required this.focusedChallan,
    required this.onFocus,
    required this.onToggleDelivery,
    required this.onToggleReception,
    required this.onOpen,
    required this.onPrint,
    required this.onDuplicate,
    required this.onCancel,
    required this.onDelete,
    required this.onToggleReportGroup,
  });

  final String? activeReportGroupCode;
  final List<DeliveryChallan> deliveryChallans;
  final List<DeliveryChallan> receptionChallans;
  final Set<String> selectedDeliveryChallanNos;
  final Set<String> selectedReceptionChallanNos;
  final DeliveryChallan? focusedChallan;
  final void Function(DeliveryChallan?) onFocus;
  final void Function(DeliveryChallan challan, bool selected) onToggleDelivery;
  final void Function(DeliveryChallan challan, bool selected) onToggleReception;
  final ValueChanged<DeliveryChallan> onOpen;
  final ValueChanged<DeliveryChallan> onPrint;
  final ValueChanged<DeliveryChallan> onDuplicate;
  final ValueChanged<DeliveryChallan> onCancel;
  final ValueChanged<DeliveryChallan> onDelete;
  final ValueChanged<DeliveryChallan>? onToggleReportGroup;

  @override
  Widget build(BuildContext context) {
    final sideOpen = focusedChallan != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SoftSurface(
            clipContent: true,
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                Expanded(
                  child: _ChallanColumn(
                    title: 'Reception',
                    subtitle: 'Material received and linked manually',
                    challans: receptionChallans,
                    activeReportGroupCode: activeReportGroupCode,
                    selectedChallanNos: selectedReceptionChallanNos,
                    focusedChallanId: focusedChallan?.id,
                    onFocus: onFocus,
                    onToggle: onToggleReception,
                    onOpen: onOpen,
                    onPrint: onPrint,
                    onDuplicate: onDuplicate,
                    onCancel: onCancel,
                    onDelete: onDelete,
                  ),
                ),
                const VerticalDivider(width: 1, color: SoftErpTheme.border),
                Expanded(
                  child: _ChallanColumn(
                    title: 'Delivery',
                    subtitle: 'Output challans in this report group',
                    challans: deliveryChallans,
                    activeReportGroupCode: activeReportGroupCode,
                    selectedChallanNos: selectedDeliveryChallanNos,
                    focusedChallanId: focusedChallan?.id,
                    onFocus: onFocus,
                    onToggle: onToggleDelivery,
                    onOpen: onOpen,
                    onPrint: onPrint,
                    onDuplicate: onDuplicate,
                    onCancel: onCancel,
                    onDelete: onDelete,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: sideOpen ? 460 : 0,
          margin: EdgeInsets.only(left: sideOpen ? 14 : 0),
          child: ClipRect(
            child: sideOpen
                ? _ChallanDetailPane(
                    challan: focusedChallan!,
                    activeReportGroupCode: activeReportGroupCode,
                    onOpen: onOpen,
                    onPrint: onPrint,
                    onToggleReportGroup: onToggleReportGroup,
                    onClose: () => onFocus(null),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class _ChallanColumn extends StatelessWidget {
  const _ChallanColumn({
    required this.title,
    required this.subtitle,
    required this.challans,
    required this.activeReportGroupCode,
    required this.selectedChallanNos,
    required this.focusedChallanId,
    required this.onFocus,
    required this.onToggle,
    required this.onOpen,
    required this.onPrint,
    required this.onDuplicate,
    required this.onCancel,
    required this.onDelete,
  });

  final String title;
  final String subtitle;
  final List<DeliveryChallan> challans;
  final String? activeReportGroupCode;
  final Set<String> selectedChallanNos;
  final int? focusedChallanId;
  final ValueChanged<DeliveryChallan> onFocus;
  final void Function(DeliveryChallan challan, bool selected) onToggle;
  final ValueChanged<DeliveryChallan> onOpen;
  final ValueChanged<DeliveryChallan> onPrint;
  final ValueChanged<DeliveryChallan> onDuplicate;
  final ValueChanged<DeliveryChallan> onCancel;
  final ValueChanged<DeliveryChallan> onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              SoftPill(
                label: '${challans.length}',
                background: SoftErpTheme.cardSurfaceAlt,
                foreground: SoftErpTheme.textPrimary,
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: SoftErpTheme.border),
        Expanded(
          child: challans.isEmpty
              ? _ColumnEmptyState(title: title)
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: challans.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final challan = challans[index];
                    return _ChallanCard(
                      key: ValueKey<String>('challan-card-${challan.id}'),
                      challan: challan,
                      focused: focusedChallanId == challan.id,
                      selected: selectedChallanNos.contains(challan.challanNo),
                      activeReportGroupCode: activeReportGroupCode,
                      onFocus: () => onFocus(challan),
                      onToggle: (selected) => onToggle(challan, selected),
                      onOpen: () => onOpen(challan),
                      onPrint: () => onPrint(challan),
                      onDuplicate: () => onDuplicate(challan),
                      onCancel: () => onCancel(challan),
                      onDelete: () => onDelete(challan),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _ChallanCard extends StatelessWidget {
  const _ChallanCard({
    super.key,
    required this.challan,
    required this.focused,
    required this.selected,
    required this.activeReportGroupCode,
    required this.onFocus,
    required this.onToggle,
    required this.onOpen,
    required this.onPrint,
    required this.onDuplicate,
    required this.onCancel,
    required this.onDelete,
  });

  final DeliveryChallan challan;
  final bool focused;
  final bool selected;
  final String? activeReportGroupCode;
  final VoidCallback onFocus;
  final ValueChanged<bool> onToggle;
  final VoidCallback onOpen;
  final VoidCallback onPrint;
  final VoidCallback onDuplicate;
  final VoidCallback onCancel;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final linkedToGroup = _challanBelongsToReportGroup(
      challan,
      activeReportGroupCode,
    );
    final canSelect = challan.isIssued && linkedToGroup;
    final codes = _effectiveReportGroupCodes(challan);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onFocus,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 10),
          decoration: BoxDecoration(
            color: focused
                ? SoftErpTheme.accent.withValues(alpha: 0.08)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: focused ? SoftErpTheme.accent : SoftErpTheme.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: selected,
                onChanged: canSelect
                    ? (value) => onToggle(value == true)
                    : null,
                activeColor: SoftErpTheme.accent,
              ),
              const SizedBox(width: 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _partyName(challan),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SoftErpTheme.textPrimary,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _StatusPill(status: challan.status),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _itemSummary(challan),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _CompactPill(
                          label: challan.challanNo,
                          background: SoftErpTheme.cardSurfaceAlt,
                          foreground: SoftErpTheme.textPrimary,
                        ),
                        _CompactPill(
                          label: _qtyLabel(challan),
                          background: SoftErpTheme.cardSurfaceAlt,
                          foreground: SoftErpTheme.textSecondary,
                        ),
                        _CompactPill(
                          label: codes.isEmpty ? 'UNLINKED' : codes.join(', '),
                          background: linkedToGroup
                              ? SoftErpTheme.accent.withValues(alpha: 0.08)
                              : SoftErpTheme.warningBg.withValues(alpha: 0.7),
                          foreground: SoftErpTheme.textPrimary,
                        ),
                        if (challan.usedInReport)
                          const _CompactPill(
                            label: 'USED',
                            background: Color(0xFFF2F3F7),
                            foreground: SoftErpTheme.textSecondary,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'Challan actions',
                icon: const Icon(Icons.more_vert_rounded),
                onSelected: (value) {
                  switch (value) {
                    case 'open':
                      onOpen();
                      break;
                    case 'print':
                      onPrint();
                      break;
                    case 'duplicate':
                      onDuplicate();
                      break;
                    case 'cancel':
                      onCancel();
                      break;
                    case 'delete':
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'open', child: Text('View/Edit')),
                  const PopupMenuItem(value: 'print', child: Text('Print')),
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: Text('Duplicate'),
                  ),
                  if (!challan.isCancelled)
                    const PopupMenuItem(value: 'cancel', child: Text('Cancel')),
                  if (challan.isDraft || challan.isReception)
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(
                        challan.isReception ? 'Delete challan' : 'Delete draft',
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactPill extends StatelessWidget {
  const _CompactPill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 170),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: foreground,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _ChallanDetailPane extends StatelessWidget {
  const _ChallanDetailPane({
    required this.challan,
    required this.activeReportGroupCode,
    required this.onOpen,
    required this.onPrint,
    required this.onToggleReportGroup,
    required this.onClose,
  });

  final DeliveryChallan challan;
  final String? activeReportGroupCode;
  final ValueChanged<DeliveryChallan> onOpen;
  final ValueChanged<DeliveryChallan> onPrint;
  final ValueChanged<DeliveryChallan>? onToggleReportGroup;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final linked = _challanBelongsToReportGroup(challan, activeReportGroupCode);
    return SoftSurface(
      clipContent: true,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        challan.challanNo,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _TypePill(type: challan.type),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Close pane',
                      onPressed: onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _DetailLineCompact('Party', _partyName(challan)),
                _DetailLineCompact('Date', _date(challan.date)),
                _DetailLineCompact(
                  challan.isDelivery ? 'Order' : 'Source',
                  challan.isDelivery
                      ? (challan.orderNo.isEmpty ? '-' : challan.orderNo)
                      : (challan.sourceReference.isEmpty
                            ? '-'
                            : challan.sourceReference),
                ),
                _DetailLineCompact(
                  'Report Group',
                  _effectiveReportGroupCodes(challan).isEmpty
                      ? 'Unlinked'
                      : _effectiveReportGroupCodes(challan).join(', '),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AppButton(
                      label: 'View/Edit',
                      icon: Icons.edit_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => onOpen(challan),
                    ),
                    AppButton(
                      label: 'Print',
                      icon: Icons.print_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: () => onPrint(challan),
                    ),
                    if (challan.isReception && activeReportGroupCode != null)
                      AppButton(
                        label: linked ? 'Unlink Group' : 'Link Group',
                        icon: linked
                            ? Icons.link_off_rounded
                            : Icons.add_link_rounded,
                        variant: AppButtonVariant.secondary,
                        onPressed: onToggleReportGroup == null
                            ? null
                            : () => onToggleReportGroup!(challan),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: SoftErpTheme.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _LineItemsPanel(challan: challan),
                const SizedBox(height: 14),
                _ChallanTemplatePreviewPane(challan: challan),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailLineCompact extends StatelessWidget {
  const _DetailLineCompact(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: SoftErpTheme.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineItemsPanel extends StatelessWidget {
  const _LineItemsPanel({required this.challan});

  final DeliveryChallan challan;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(12),
      elevated: false,
      color: SoftErpTheme.cardSurfaceAlt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Items', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          if (challan.items.isEmpty)
            const Text(
              'No line item details loaded.',
              style: TextStyle(color: SoftErpTheme.textSecondary),
            )
          else
            ...challan.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.particulars.trim().isEmpty
                            ? 'Unnamed item'
                            : item.particulars.trim(),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Qty ${item.quantityPcs.isEmpty ? '0' : item.quantityPcs}\nWt ${item.weight.isEmpty ? '0' : item.weight}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: SoftErpTheme.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColumnEmptyState extends StatelessWidget {
  const _ColumnEmptyState({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No $title challans for this report group.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: SoftErpTheme.textSecondary),
        ),
      ),
    );
  }
}

class _ChallanTemplatePreviewPane extends StatefulWidget {
  const _ChallanTemplatePreviewPane({required this.challan});

  final DeliveryChallan challan;

  @override
  State<_ChallanTemplatePreviewPane> createState() =>
      _ChallanTemplatePreviewPaneState();
}

class _ChallanTemplatePreviewPaneState
    extends State<_ChallanTemplatePreviewPane> {
  List<ChallanTemplate> _templates = const <ChallanTemplate>[];
  ChallanTemplate? _selectedTemplate;
  Uint8List? _pdfBytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_ChallanTemplatePreviewPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.challan.id != widget.challan.id) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _pdfBytes = null;
    });
    try {
      final provider = context.read<DeliveryChallanProvider>();
      final templates = await provider.loadTemplates(
        partyType: ChallanTemplatePartyType.generic,
        activeOnly: true,
      );
      final ordered = <ChallanTemplate>[
        ...templates.where(
          (template) => template.challanType == widget.challan.type,
        ),
        ...templates.where(
          (template) => template.challanType != widget.challan.type,
        ),
      ];
      final selected = ordered.isEmpty ? null : ordered.first;
      Uint8List? bytes;
      if (widget.challan.id > 0) {
        bytes = await provider.repository.fetchTemplatePreviewPdf(
          challanId: widget.challan.id,
          templateId: selected?.id,
          mode: 'digital',
        );
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _templates = ordered;
        _selectedTemplate = selected;
        _pdfBytes = bytes;
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _selectTemplate(int? id) async {
    final selected = _templates
        .where((template) => template.id == id)
        .firstOrNull;
    if (selected == null) {
      return;
    }
    setState(() {
      _selectedTemplate = selected;
      _loading = true;
      _pdfBytes = null;
      _error = null;
    });
    try {
      final bytes = await context
          .read<DeliveryChallanProvider>()
          .repository
          .fetchTemplatePreviewPdf(
            challanId: widget.challan.id,
            templateId: selected.id,
            mode: 'digital',
          );
      if (mounted) {
        setState(() {
          _pdfBytes = bytes;
          _loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(12),
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Template Preview',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          if (_templates.isNotEmpty) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _selectedTemplate?.id,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Template',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: SoftErpTheme.border),
                ),
              ),
              items: _templates
                  .map(
                    (template) => DropdownMenuItem<int>(
                      value: template.id,
                      child: Text(
                        template.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: _selectTemplate,
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            height: 360,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _pdfBytes != null
                ? PdfPreview(
                    build: (_) async => _pdfBytes!,
                    allowPrinting: false,
                    allowSharing: false,
                    canChangeOrientation: false,
                    canChangePageFormat: false,
                    canDebug: false,
                    useActions: false,
                    maxPageWidth: 360,
                  )
                : Center(
                    child: Text(
                      _error ?? 'No template preview available.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: SoftErpTheme.textSecondary),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final DeliveryChallanStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      DeliveryChallanStatus.draft => const Color(0xFF7B8194),
      DeliveryChallanStatus.issued => const Color(0xFF1D8A62),
      DeliveryChallanStatus.cancelled => const Color(0xFFB94A48),
    };
    return SoftPill(
      label: status.name.toUpperCase(),
      foreground: color,
      background: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.24),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    );
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.type});

  final ChallanType type;

  @override
  Widget build(BuildContext context) {
    final isReception = type == ChallanType.reception;
    final color = isReception
        ? const Color(0xFF15803D)
        : const Color(0xFFB42318);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isReception ? Icons.south_west_rounded : Icons.north_east_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            isReception ? 'Reception' : 'Delivery',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChallanEditor extends StatefulWidget {
  const _ChallanEditor({
    this.challan,
    this.sourceForDuplicate,
    this.initialOrder,
    this.initialType,
    this.initialLocation,
    required this.onPrint,
  });

  final DeliveryChallan? challan;
  final DeliveryChallan? sourceForDuplicate;
  final OrderEntry? initialOrder;
  final ChallanType? initialType;
  final String? initialLocation;
  final ValueChanged<DeliveryChallan> onPrint;

  @override
  State<_ChallanEditor> createState() => _ChallanEditorState();
}

class _ChallanEditorState extends State<_ChallanEditor> {
  late final TextEditingController _challanNumberController;
  late final TextEditingController _dateController;
  late final TextEditingController _customerController;
  late final TextEditingController _gstinController;
  late final TextEditingController _locationController;
  late final TextEditingController _sourceReferenceController;
  late final TextEditingController _notesController;
  late List<_ItemDraft> _items;
  late ChallanType _selectedType;
  late List<OrderEntry> _selectedOrders;
  int? _selectedVendorId;
  String? _validationError;
  bool _isOrdersPanelOpen = false;
  bool _orderSelectionTouched = false;
  bool _ordersCommandRegistered = false;
  ChallanEditorCommandProvider? _ordersCommandProvider;

  DeliveryChallan? get _source => widget.challan ?? widget.sourceForDuplicate;
  bool get _editingExisting => widget.challan != null;
  bool get _canEdit => widget.challan?.isDraft ?? true;
  bool get _isReception => _selectedType == ChallanType.reception;
  bool get _maintainStocks =>
      _source?.maintainStocks ??
      context.read<PreferencesProvider>().maintainStocks;
  OrderEntry? get _primarySelectedOrder =>
      _selectedOrders.isEmpty ? null : _selectedOrders.first;
  List<_OrderItemOption> get _selectedOrderOptions =>
      _selectedOrders.map(_OrderItemOption.fromOrder).toList(growable: false);
  List<int> get _sourceOrderIds {
    final source = _source;
    if (source == null) {
      return const <int>[];
    }
    if (source.orderIds.isNotEmpty) {
      return source.orderIds;
    }
    return [if (source.orderId != null) source.orderId!];
  }

  List<OrderEntry> _findOrders(Iterable<int> orderIds) {
    final ids = orderIds.toSet();
    return context
        .read<OrdersProvider>()
        .orders
        .where((order) => ids.contains(order.id))
        .toList(growable: false);
  }

  String _gstinForOrder(OrderEntry? order) {
    if (order == null) {
      return '';
    }
    for (final client in context.read<ClientsProvider>().clients) {
      if (client.id == order.clientId) {
        return client.gstNumber;
      }
    }
    return '';
  }

  void _applySelectedOrderSnapshots() {
    final order = _primarySelectedOrder;
    if (order == null) {
      if (_selectedType == ChallanType.delivery && !_orderSelectionTouched) {
        _customerController.text = _source?.customerName ?? '';
        _gstinController.text = _source?.customerGstin ?? '';
      } else {
        _customerController.clear();
        _gstinController.clear();
      }
      return;
    }
    _customerController.text = order.clientName;
    _gstinController.text = _gstinForOrder(order);
  }

  void _hydrateSelectedOrdersFromSourceIfAvailable() {
    if (!mounted ||
        _selectedType != ChallanType.delivery ||
        _orderSelectionTouched ||
        _selectedOrders.isNotEmpty) {
      return;
    }
    final hydratedOrders = _findOrders(_sourceOrderIds);
    if (hydratedOrders.isEmpty) {
      return;
    }
    setState(() {
      _selectedOrders = hydratedOrders;
      _applySelectedOrderSnapshots();
    });
  }

  bool _isOrderEligible(OrderEntry order) {
    if (order.status == OrderStatus.completed) {
      return false;
    }
    if (_selectedOrders.any((selected) => selected.id == order.id)) {
      return false;
    }
    final clientId = _primarySelectedOrder?.clientId;
    if (clientId != null && order.clientId != clientId) {
      return false;
    }
    return true;
  }

  void _resetDeliveryItemsForSelectedOrders() {
    final selectedOrderIds = _selectedOrders.map((order) => order.id).toSet();
    _items = _items
        .where((item) {
          return item.orderItemId != null &&
              selectedOrderIds.contains(item.orderItemId);
        })
        .toList(growable: true);
    if (_items.isEmpty) {
      _items = [
        if (_selectedOrderOptions.isNotEmpty)
          _ItemDraft.fromOrderOption(_selectedOrderOptions.first)
        else
          _ItemDraft.blank(1),
      ];
    }
  }

  @override
  void initState() {
    super.initState();
    context.read<UnitsProvider>().initialize();
    final source = _source;
    _selectedType = widget.initialType ?? source?.type ?? ChallanType.delivery;
    final initialOrderIds = source?.orderIds.isNotEmpty == true
        ? source!.orderIds
        : [
            if (widget.initialOrder != null)
              widget.initialOrder!.id
            else if (source?.orderId != null)
              source!.orderId!,
          ];
    _selectedOrders = _findOrders(initialOrderIds);
    _selectedVendorId = source?.vendorId;
    _challanNumberController = TextEditingController(
      text: source?.challanNo ?? '',
    );
    _dateController = TextEditingController(
      text: _date(source?.date ?? DateTime.now()),
    );
    _customerController = TextEditingController(
      text: _selectedType == ChallanType.reception
          ? source?.vendorName ?? ''
          : source?.customerName ?? '',
    );
    _gstinController = TextEditingController(
      text: _selectedType == ChallanType.reception
          ? source?.vendorGstin ?? ''
          : source?.customerGstin ?? '',
    );
    _locationController = TextEditingController(
      text:
          source?.location ??
          widget.initialLocation ??
          _defaultChallanStorageLocation,
    );
    _sourceReferenceController = TextEditingController(
      text: source?.sourceReference ?? '',
    );
    _notesController = TextEditingController(text: source?.notes ?? '');
    _items = (source?.items.isNotEmpty ?? false)
        ? source!.items.map(_ItemDraft.fromItem).toList()
        : [
            if (_selectedOrderOptions.isNotEmpty)
              _ItemDraft.fromOrderOption(_selectedOrderOptions.first)
            else
              _ItemDraft.blank(1),
          ];
    _applySelectedOrderSnapshots();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncOrdersCommand());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ordersCommandProvider = context.read<ChallanEditorCommandProvider>();
    _syncOrdersCommand();
  }

  @override
  void dispose() {
    if (_ordersCommandRegistered) {
      _ordersCommandProvider?.unregisterOrdersPanelOpener(
        _openOrdersPanelFromShortcut,
      );
      _ordersCommandRegistered = false;
    }
    _challanNumberController.dispose();
    _dateController.dispose();
    _customerController.dispose();
    _gstinController.dispose();
    _locationController.dispose();
    _sourceReferenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _syncOrdersCommand() {
    if (!mounted) {
      return;
    }
    final commands =
        _ordersCommandProvider ?? context.read<ChallanEditorCommandProvider>();
    final shouldRegister = _canEdit && !_isReception && _maintainStocks;
    if (shouldRegister && !_ordersCommandRegistered) {
      commands.registerOrdersPanelOpener(_openOrdersPanelFromShortcut);
      _ordersCommandRegistered = true;
    } else if (!shouldRegister && _ordersCommandRegistered) {
      commands.unregisterOrdersPanelOpener(_openOrdersPanelFromShortcut);
      _ordersCommandRegistered = false;
    }
  }

  void _openOrdersPanelFromShortcut() {
    if (!_canEdit || _isReception || !_maintainStocks || _isOrdersPanelOpen) {
      return;
    }
    _toggleOrdersPanel();
  }

  Future<void> _toggleOrdersPanel() async {
    setState(() {
      _isOrdersPanelOpen = !_isOrdersPanelOpen;
      _validationError = null;
    });
    if (_isOrdersPanelOpen) {
      await context.read<OrdersProvider>().refresh();
    }
  }

  void _onItemsFetched(List<OrderEntry> items) {
    if (items.isEmpty) {
      return;
    }
    final firstClientId =
        _primarySelectedOrder?.clientId ?? items.first.clientId;
    if (items.any((item) => item.clientId != firstClientId)) {
      setState(() {
        _validationError =
            'Selected order lines must belong to the same client.';
      });
      return;
    }
    final ineligible = items.where((item) => !_isOrderEligible(item)).toList();
    if (ineligible.isNotEmpty) {
      setState(() {
        _validationError =
            'One or more selected order lines are no longer eligible for this challan.';
      });
      return;
    }
    setState(() {
      _orderSelectionTouched = true;
      _selectedOrders = [..._selectedOrders, ...items];
      final fetchedItems = items
          .map(
            (item) =>
                _ItemDraft.fromOrderOption(_OrderItemOption.fromOrder(item)),
          )
          .toList(growable: false);
      _items = [
        for (final draft in _items)
          if (!draft.isBlank) draft,
        ...fetchedItems,
      ];
      _validationError = null;
      _isOrdersPanelOpen = false;
      _applySelectedOrderSnapshots();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();
    context.watch<PreferencesProvider>();
    context.watch<OrdersProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncOrdersCommand();
      _hydrateSelectedOrdersFromSourceIfAvailable();
    });
    final editorTitle = _editingExisting
        ? (_isReception ? 'Edit Reception Challan' : 'Edit Delivery Challan')
        : (_isReception
              ? 'Create Reception Challan'
              : 'Create Delivery Challan');
    final issueLabel = _isReception ? 'Issue Reception' : 'Issue Delivery';
    final errorText = _validationError ?? provider.errorMessage;
    final challanNumberWarningText =
        provider.warningMessage ?? _manualChallanWarningText();
    final showOrdersPanel = _isOrdersPanelOpen && !_isReception;
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.of(context).size.width - 48;
        final maxHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.of(context).size.height - 48;
        final popupHeight = math.min(650.0, maxHeight);
        final roomForPanel = maxWidth - 560.0 - 20.0;
        final panelWidth = showOrdersPanel && roomForPanel > 0
            ? math.min(460.0, roomForPanel)
            : 0.0;
        final gutterWidth = panelWidth > 0 ? 20.0 : 0.0;
        final availableFormWidth = math.max(
          0.0,
          maxWidth - panelWidth - gutterWidth,
        );
        final formWidth = math.min(800.0, availableFormWidth);
        final totalWidth = formWidth + gutterWidth + panelWidth;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              width: totalWidth,
              height: popupHeight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Container(
                      height: popupHeight,
                      clipBehavior: Clip.antiAlias,
                      decoration: _floatingWindowDecoration(context),
                      child: _buildChallanFormWindow(
                        context: context,
                        provider: provider,
                        title: editorTitle,
                        subtitle: _isReception
                            ? 'Record inbound stock against a vendor-backed reception document before it reaches inventory.'
                            : 'Prepare the outbound document linked to an order before dispatch stock leaves the warehouse.',
                        errorText: errorText,
                        challanNumberWarningText: challanNumberWarningText,
                        issueLabel: issueLabel,
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    width: gutterWidth,
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    width: panelWidth,
                    height: popupHeight,
                    child: ClipRect(
                      child: SizedBox(
                        width: 460.0,
                        child: showOrdersPanel && panelWidth > 0
                            ? Container(
                                clipBehavior: Clip.antiAlias,
                                decoration: _floatingWindowDecoration(
                                  context,
                                  shadowOffset: const Offset(4, 8),
                                ),
                                child: OrdersFetchPanel(
                                  selectedOrderIds: _selectedOrders
                                      .map((order) => order.id)
                                      .toSet(),
                                  lockedClientId:
                                      _primarySelectedOrder?.clientId,
                                  onClose: () => setState(
                                    () => _isOrdersPanelOpen = false,
                                  ),
                                  onFetch: _onItemsFetched,
                                ),
                              )
                            : const SizedBox(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  BoxDecoration _floatingWindowDecoration(
    BuildContext context, {
    Offset shadowOffset = const Offset(0, 8),
  }) {
    return BoxDecoration(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.15),
          blurRadius: 24,
          offset: shadowOffset,
        ),
      ],
    );
  }

  Widget _buildChallanFormWindow({
    required BuildContext context,
    required DeliveryChallanProvider provider,
    required String title,
    required String subtitle,
    required String? errorText,
    required String? challanNumberWarningText,
    required String issueLabel,
  }) {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          _buildFloatingHeader(context, title: title, subtitle: subtitle),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
              child: ErpFormMessageBanner(message: errorText, isError: true),
            ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 22),
              child: _buildChallanFormBody(challanNumberWarningText),
            ),
          ),
          _buildFloatingFooter(context, provider, issueLabel),
        ],
      ),
    );
  }

  Widget _buildFloatingHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 20, 18, 16),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(bottom: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: SoftErpTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: SoftErpTheme.textSecondary,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).maybePop(),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF8FAFC),
              foregroundColor: const Color(0xFF334155),
              side: const BorderSide(color: Color(0xFFD9E2F2)),
            ),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildChallanFormBody(String? challanNumberWarningText) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _documentDetailsSection(challanNumberWarningText),
        const SizedBox(height: 16),
        ErpDialogSectionCard(
          title: _isReception ? 'Reception Line Items' : 'Dispatch Line Items',
          subtitle: _isReception
              ? 'Lock each row to an exact item variation and quantity before issuing stock into the warehouse.'
              : 'Review the selected order-linked dispatch rows and quantities before issuing the challan.',
          child: _ItemsEditor(
            isReception: _isReception,
            maintainStocks: _maintainStocks,
            enabled: _canEdit,
            items: _items,
            orderOptions: _selectedOrderOptions,
            onChanged: () => setState(() {
              _validationError = null;
            }),
          ),
        ),
        const SizedBox(height: 16),
        ErpDialogSectionCard(
          title: 'Notes',
          subtitle:
              'Add any transport, handoff, or document context that should travel with this challan.',
          child: _field(
            'Notes',
            _notesController,
            enabled: _canEdit,
            maxLines: 3,
          ),
        ),
      ],
    );
  }

  Widget _documentDetailsSection(String? challanNumberWarningText) {
    return SoftSurface(
      radius: SoftErpTheme.radiusLg,
      color: SoftErpTheme.cardSurface,
      elevated: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Document Details',
                      style: TextStyle(
                        color: SoftErpTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Choose the challan type, source document, and date first.',
                      style: TextStyle(
                        color: SoftErpTheme.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isReception && _maintainStocks) ...[
                const SizedBox(width: 12),
                _ordersHeaderButton(),
              ],
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _challanNumberField()),
              const SizedBox(width: 12),
              Expanded(
                child: _field('Date', _dateController, enabled: _canEdit),
              ),
            ],
          ),
          if (challanNumberWarningText != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                challanNumberWarningText,
                style: const TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
          if (_maintainStocks) ...[
            if (_isReception) ...[
              const SizedBox(height: 12),
              _vendorSelector(context),
            ] else
              _selectedOrdersSummary(),
            const SizedBox(height: 12),
            _field(
              _isReception
                  ? 'Supplier Ref / GRN / Invoice'
                  : 'Dispatch Reference',
              _sourceReferenceController,
              enabled: _canEdit,
            ),
          ] else ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _field(
                    _isReception ? 'Vendor / Source' : 'Customer name / M/s',
                    _customerController,
                    enabled: _canEdit,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    _isReception ? 'Vendor GSTIN' : 'Customer GSTIN',
                    _gstinController,
                    enabled: _canEdit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _field(
              _isReception
                  ? 'Supplier Ref / GRN / Invoice'
                  : 'Dispatch Reference',
              _sourceReferenceController,
              enabled: _canEdit,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFloatingFooter(
    BuildContext context,
    DeliveryChallanProvider provider,
    String issueLabel,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
      decoration: const BoxDecoration(
        color: Color(0xFFFBFBFB),
        border: Border(top: BorderSide(color: SoftErpTheme.border)),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppButton(
                label: 'Print',
                icon: Icons.print_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: _source == null
                    ? null
                    : () => widget.onPrint(_source!),
              ),
              const SizedBox(width: 10),
              AppButton(
                label: 'Cancel',
                icon: Icons.block_outlined,
                variant: AppButtonVariant.secondary,
                onPressed: widget.challan == null || widget.challan!.isCancelled
                    ? null
                    : () async {
                        final cancelled = await provider.cancelChallan(
                          widget.challan!.id,
                        );
                        if (cancelled != null) {
                          if (context.mounted) {
                            await context.read<InventoryProvider>().refresh();
                            Navigator.of(context).pop();
                          }
                        }
                      },
              ),
              const SizedBox(width: 10),
              AppButton(
                label: 'Save Draft',
                icon: Icons.save_outlined,
                isLoading: provider.isSaving,
                onPressed: _canEdit ? _save : null,
              ),
              const SizedBox(width: 10),
              AppButton(
                label: issueLabel,
                icon: Icons.verified_outlined,
                isLoading: provider.isSaving,
                onPressed: _canEdit ? _issue : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool enabled = true,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _challanNumberField() {
    return TextField(
      controller: _challanNumberController,
      enabled: _canEdit,
      decoration: InputDecoration(
        labelText: 'Challan No.',
        hintText: 'Leave empty to auto-generate',
        filled: true,
        fillColor: _canEdit ? Colors.white : const Color(0xFFF7F8FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  String? _manualChallanWarningText() {
    final manualValue = _challanNumberController.text.trim();
    if (manualValue.isEmpty) {
      return null;
    }
    final expectedPrefix = _selectedType == ChallanType.reception
        ? 'RC-'
        : 'DC-';
    if (manualValue.toUpperCase().startsWith(expectedPrefix)) {
      return null;
    }
    return 'Manual challan numbers usually start with $expectedPrefix. This is a warning only; unique values are still allowed.';
  }

  Widget _ordersHeaderButton() {
    return OutlinedButton(
      onPressed: _canEdit ? _toggleOrdersPanel : null,
      style: OutlinedButton.styleFrom(
        foregroundColor: SoftErpTheme.accent,
        side: const BorderSide(color: SoftErpTheme.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        visualDensity: VisualDensity.compact,
      ),
      child: Text(
        _isOrdersPanelOpen ? 'close orders ↙︎' : 'fetch order ↗︎',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _selectedOrdersSummary() {
    if (_selectedOrders.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selectedOrders
                .map((order) {
                  return InputChip(
                    label: Text(_orderOptionLabel(order)),
                    onDeleted: !_canEdit
                        ? null
                        : () {
                            setState(() {
                              _orderSelectionTouched = true;
                              _selectedOrders = _selectedOrders
                                  .where((selected) => selected.id != order.id)
                                  .toList(growable: false);
                              _validationError = null;
                              _resetDeliveryItemsForSelectedOrders();
                              _applySelectedOrderSnapshots();
                            });
                          },
                  );
                })
                .toList(growable: false),
          ),
          const SizedBox(height: 8),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                'Client locked to ${_selectedOrders.first.clientName} for this challan.',
                style: const TextStyle(color: SoftErpTheme.textSecondary),
              ),
              if (_gstinForOrder(_selectedOrders.first).isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: SoftErpTheme.cardSurfaceAlt,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: SoftErpTheme.border),
                  ),
                  child: Text(
                    'GSTIN: ${_gstinForOrder(_selectedOrders.first)}',
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _vendorSelector(BuildContext context) {
    final vendors = context
        .watch<VendorsProvider>()
        .vendors
        .where((vendor) => !vendor.isArchived)
        .toList(growable: false);
    return DropdownButtonFormField<int>(
      initialValue: _selectedVendorId,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Vendor',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      items: vendors
          .map(
            (vendor) => DropdownMenuItem<int>(
              value: vendor.id,
              child: Text(vendor.displayLabel, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(growable: false),
      onChanged: !_canEdit
          ? null
          : (value) {
              final vendor = context.read<VendorsProvider>().findById(value);
              setState(() {
                _selectedVendorId = value;
                _customerController.text = vendor?.name ?? '';
                _gstinController.text = vendor?.gstNumber ?? '';
                _validationError = null;
              });
            },
    );
  }

  String get _storageLocation {
    final entered = _locationController.text.trim();
    return entered.isEmpty ? _defaultChallanStorageLocation : entered;
  }

  DeliveryChallanDraftInput _input() {
    final maintainStocks = _maintainStocks;
    final selectedOrderIds = _selectedOrders
        .map((order) => order.id)
        .toList(growable: false);
    final canFallbackToSourceOrders =
        _source != null && !_orderSelectionTouched && selectedOrderIds.isEmpty;
    final orderIds = _selectedType == ChallanType.delivery && maintainStocks
        ? (selectedOrderIds.isNotEmpty
              ? selectedOrderIds
              : canFallbackToSourceOrders
              ? _sourceOrderIds
              : const <int>[])
        : const <int>[];
    return DeliveryChallanDraftInput(
      type: _selectedType,
      challanNo: _challanNumberController.text.trim(),
      orderId: _selectedType == ChallanType.delivery && maintainStocks
          ? (orderIds.isEmpty ? (_source?.orderId ?? 0) : orderIds.first)
          : 0,
      orderIds: orderIds,
      vendorId: _selectedType == ChallanType.reception && maintainStocks
          ? (_selectedVendorId ?? _source?.vendorId ?? 0)
          : 0,
      date: DateTime.tryParse(_dateController.text) ?? DateTime.now(),
      location: _storageLocation,
      sourceReference: _sourceReferenceController.text,
      notes: _notesController.text,
      maintainStocks: maintainStocks,
      customerName: _selectedType == ChallanType.delivery
          ? _customerController.text
          : '',
      customerGstin: _selectedType == ChallanType.delivery
          ? _gstinController.text
          : '',
      vendorName: _selectedType == ChallanType.reception
          ? _customerController.text
          : '',
      vendorGstin: _selectedType == ChallanType.reception
          ? _gstinController.text
          : '',
      items: _items
          .asMap()
          .entries
          .map((entry) => entry.value.toItem(entry.key + 1))
          .where(
            (item) =>
                item.orderItemId != null ||
                item.itemId != null ||
                item.particulars.trim().isNotEmpty ||
                item.quantityPcs.trim().isNotEmpty ||
                item.weight.trim().isNotEmpty,
          )
          .toList(growable: false),
    );
  }

  bool _sameOrderIds(List<int> left, List<int> right) {
    final leftSorted = left.toList(growable: false)..sort();
    final rightSorted = right.toList(growable: false)..sort();
    if (leftSorted.length != rightSorted.length) {
      return false;
    }
    for (var index = 0; index < leftSorted.length; index += 1) {
      if (leftSorted[index] != rightSorted[index]) {
        return false;
      }
    }
    return true;
  }

  bool _sameNullableInt(int? left, int? right) => (left ?? 0) == (right ?? 0);

  bool _sameText(String left, String right) => left.trim() == right.trim();

  bool _sameItem(DeliveryChallanItem left, DeliveryChallanItem right) {
    return _sameNullableInt(left.orderItemId, right.orderItemId) &&
        _sameNullableInt(left.productionRunId, right.productionRunId) &&
        _sameNullableInt(left.itemId, right.itemId) &&
        left.variationLeafNodeId == right.variationLeafNodeId &&
        _sameText(left.particulars, right.particulars) &&
        _sameText(left.hsnCode, right.hsnCode) &&
        _sameText(left.variationPathLabel, right.variationPathLabel) &&
        _sameText(left.note, right.note) &&
        _sameText(left.quantityPcs, right.quantityPcs) &&
        _sameText(left.weight, right.weight);
  }

  bool _sameItems(
    List<DeliveryChallanItem> left,
    List<DeliveryChallanItem> right,
  ) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_sameItem(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }

  bool _matchesSourceDraft(DeliveryChallanDraftInput input) {
    final source = widget.challan;
    if (source == null) {
      return false;
    }
    return input.type == source.type &&
        _sameText(input.challanNo, source.challanNo) &&
        _date(input.date) == _date(source.date) &&
        _sameText(input.location, source.location) &&
        _sameText(input.sourceReference, source.sourceReference) &&
        _sameText(input.notes, source.notes) &&
        input.maintainStocks == source.maintainStocks &&
        _sameText(input.customerName, source.customerName) &&
        _sameText(input.customerGstin, source.customerGstin) &&
        _sameText(input.vendorName, source.vendorName) &&
        _sameText(input.vendorGstin, source.vendorGstin) &&
        _sameNullableInt(input.vendorId, source.vendorId) &&
        _sameOrderIds(input.orderIds, _sourceOrderIds) &&
        _sameItems(input.items, source.items);
  }

  Future<void> _save() async {
    final provider = context.read<DeliveryChallanProvider>();
    setState(() {
      _validationError = null;
    });
    final input = _input();
    if (_maintainStocks &&
        _isReception &&
        (_selectedVendorId ?? _source?.vendorId ?? 0) <= 0) {
      setState(() {
        _validationError = 'Select a vendor before saving challan.';
      });
      return;
    }
    if (_maintainStocks && !_isReception && input.orderIds.isEmpty) {
      setState(() {
        _validationError = 'Select at least one order before saving challan.';
      });
      return;
    }
    final saved = _editingExisting && _matchesSourceDraft(input)
        ? widget.challan
        : _editingExisting
        ? await provider.updateChallan(widget.challan!.id, input)
        : await provider.createChallan(input);
    if (saved != null && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _issue() async {
    final provider = context.read<DeliveryChallanProvider>();
    final input = _input();
    final maintainStocks = input.maintainStocks;
    if (maintainStocks &&
        _selectedType == ChallanType.delivery &&
        input.orderIds.isEmpty) {
      setState(() {
        _validationError = 'Select at least one order before saving challan.';
      });
      return;
    }
    if (maintainStocks &&
        _selectedType == ChallanType.reception &&
        input.vendorId <= 0) {
      setState(() {
        _validationError = 'Select a vendor before issuing reception challan.';
      });
      return;
    }
    if (input.items.isEmpty) {
      setState(() {
        _validationError = 'Add at least one line item before issuing challan.';
      });
      return;
    }
    if (!maintainStocks) {
      if (input.items.any((item) {
        final quantity = double.tryParse(item.quantityPcs.trim());
        final weight = double.tryParse(item.weight.trim());
        return item.particulars.trim().isEmpty ||
            !((quantity != null && quantity > 0) ||
                (weight != null && weight > 0));
      })) {
        setState(() {
          _validationError =
              'Enter item text and Qty / Pcs or Weight for every row.';
        });
        return;
      }
    } else if (_selectedType == ChallanType.delivery) {
      if (input.items.any(
        (item) =>
            item.orderItemId == null ||
            (item.quantityPcs.trim().isEmpty && item.weight.trim().isEmpty),
      )) {
        setState(() {
          _validationError =
              'Select an order item and enter Qty / Pcs or Weight for every row.';
        });
        return;
      }
    } else if (input.items.any((item) {
      if (item.itemId == null) return true;
      final q = double.tryParse(item.quantityPcs.trim()) ?? 0;
      final w = double.tryParse(item.weight.trim()) ?? 0;
      return q <= 0 && w <= 0;
    })) {
      setState(() {
        _validationError =
            'Select an exact item variation and enter quantity or weight for every reception row.';
      });
      return;
    }
    setState(() {
      _validationError = null;
    });

    if (maintainStocks && _selectedType == ChallanType.delivery) {
      final overDeliveries = <String>[];
      for (final item in input.items) {
        if (item.orderItemId != null && item.orderItemId! > 0) {
          OrderEntry? order;
          for (final o in _selectedOrders) {
            if (o.id == item.orderItemId) {
              order = o;
              break;
            }
          }
          if (order != null) {
            final qty = double.tryParse(item.quantityPcs.trim()) ?? 0;
            if (order.totalDeliveredQty + qty > order.quantity) {
              final orderLabel = order.orderNo.trim().isNotEmpty ? order.orderNo : '#${order.id}';
              overDeliveries.add(orderLabel);
            }
          }
        }
      }
      
      if (overDeliveries.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Over-Delivery Warning'),
              content: Text(
                'The quantity you are about to issue for order(s) ${overDeliveries.toSet().join(', ')} '
                'exceeds the remaining ordered quantity.\n\n'
                'Are you sure you want to proceed with this over-delivery?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Proceed'),
                ),
              ],
            );
          },
        );
        
        if (confirmed != true) {
          return;
        }
      }
    }

    final inventoryProvider = context.read<InventoryProvider>();
    final saved = _editingExisting && _matchesSourceDraft(input)
        ? widget.challan
        : _editingExisting
        ? await provider.updateChallan(widget.challan!.id, input)
        : await provider.createChallan(input);
    if (saved == null) {
      return;
    }
    final issued = await provider.issueChallan(saved.id);
    if (issued == null) {
      return;
    }
    if (mounted) {
      await inventoryProvider.refresh();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class OrdersFetchPanel extends StatefulWidget {
  const OrdersFetchPanel({
    super.key,
    required this.selectedOrderIds,
    required this.lockedClientId,
    required this.onClose,
    required this.onFetch,
  });

  final Set<int> selectedOrderIds;
  final int? lockedClientId;
  final VoidCallback onClose;
  final ValueChanged<List<OrderEntry>> onFetch;

  @override
  State<OrdersFetchPanel> createState() => _OrdersFetchPanelState();
}

class _OrdersFetchPanelState extends State<OrdersFetchPanel> {
  final TextEditingController _searchController = TextEditingController();
  final Set<int> _selectedLineIds = <int>{};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _tokens => _searchController.text
      .split(',')
      .map((token) => token.trim().toLowerCase())
      .where((token) => token.isNotEmpty)
      .toList(growable: false);

  bool _matchesTokens(_OrderFetchGroup group, List<String> tokens) {
    if (tokens.isEmpty) {
      return true;
    }
    final groupText = '${group.partyName} ${group.orderCode}'.toLowerCase();
    return tokens.every((token) {
      if (groupText.contains(token)) {
        return true;
      }
      return group.items.any((item) {
        final itemText =
            '${item.itemName} ${item.clientCode} ${item.variationPathLabel}'
                .toLowerCase();
        return itemText.contains(token);
      });
    });
  }

  bool _matchesLine(
    _OrderFetchGroup group,
    OrderEntry item,
    List<String> tokens,
  ) {
    if (tokens.isEmpty) {
      return true;
    }
    final groupText = '${group.partyName} ${group.orderCode}'.toLowerCase();
    final itemText =
        '${item.itemName} ${item.clientCode} ${item.variationPathLabel}'
            .toLowerCase();
    return tokens.every(
      (token) => groupText.contains(token) || itemText.contains(token),
    );
  }

  void _toggleLine(OrderEntry item, bool selected) {
    setState(() {
      if (selected) {
        _selectedLineIds.add(item.id);
      } else {
        _selectedLineIds.remove(item.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select Order Line',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: SoftErpTheme.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close orders panel',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _selectedLineIds.isEmpty
                    ? null
                    : () {
                        final provider = context.read<OrdersProvider>();
                        final selected = provider.orders
                            .where(
                              (order) => _selectedLineIds.contains(order.id),
                            )
                            .toList(growable: false);
                        widget.onFetch(selected);
                      },
                icon: const Icon(Icons.north_east_rounded, size: 16),
                label: const Text(
                  'Fetch Selected Items ↗',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search client, order, or items. Use commas for AND.',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: SoftErpTheme.border),
              ),
            ),
          ),
        ),
        if (widget.lockedClientId != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: SoftErpTheme.accent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: SoftErpTheme.accent.withValues(alpha: 0.18),
                ),
              ),
              child: const Text(
                'Client locked by the first selected order.',
                style: TextStyle(
                  color: SoftErpTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        Expanded(
          child: Consumer<OrdersProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading) {
                return const Center(child: CircularProgressIndicator());
              }
              if (provider.errorMessage != null) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: SoftErpTheme.dangerText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                );
              }
              final orderLines =
                  provider.orders
                      .where((line) {
                        if (line.status == OrderStatus.completed) {
                          return false;
                        }
                        if (widget.selectedOrderIds.contains(line.id)) {
                          return false;
                        }
                        if (widget.lockedClientId != null &&
                            line.clientId != widget.lockedClientId) {
                          return false;
                        }
                        return true;
                      })
                      .toList(growable: false)
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              final groups = _OrderFetchGroup.fromLines(orderLines)
                  .where((group) => _matchesTokens(group, _tokens))
                  .toList(growable: false);
              if (groups.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No eligible orders available.',
                      style: TextStyle(color: SoftErpTheme.textSecondary),
                    ),
                  ),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                itemCount: groups.length,
                itemBuilder: (context, index) {
                  final group = groups[index];
                  return _OrderFetchAccordion(
                    group: group,
                    visibleItems: group.items
                        .where((item) => _matchesLine(group, item, _tokens))
                        .toList(growable: false),
                    selectedLineIds: _selectedLineIds,
                    onToggle: _toggleLine,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _OrderFetchGroup {
  const _OrderFetchGroup({required this.parent, required this.items});

  final OrderEntry parent;
  final List<OrderEntry> items;

  String get orderCode {
    final value = parent.orderNo.trim();
    return value.isEmpty ? 'Order #${parent.id}' : value;
  }

  String get partyName {
    final value = parent.clientName.trim();
    return value.isEmpty ? 'No party name' : value;
  }

  String get title => '$partyName / $orderCode';

  static List<_OrderFetchGroup> fromLines(List<OrderEntry> lines) {
    final grouped = <String, List<OrderEntry>>{};
    for (final line in lines) {
      final orderCode = line.orderNo.trim();
      final fallbackOrderKey = orderCode.isEmpty
          ? 'line-${line.id}'
          : orderCode;
      final key = '${line.clientId}|$fallbackOrderKey|${line.poNumber.trim()}';
      grouped.putIfAbsent(key, () => <OrderEntry>[]).add(line);
    }
    return grouped.values
        .map(
          (items) => _OrderFetchGroup(
            parent: items.first,
            items: List<OrderEntry>.unmodifiable(items),
          ),
        )
        .toList(growable: false);
  }
}

class _OrderFetchAccordion extends StatelessWidget {
  const _OrderFetchAccordion({
    required this.group,
    required this.visibleItems,
    required this.selectedLineIds,
    required this.onToggle,
  });

  final _OrderFetchGroup group;
  final List<OrderEntry> visibleItems;
  final Set<int> selectedLineIds;
  final void Function(OrderEntry item, bool selected) onToggle;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: SoftErpTheme.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: EdgeInsets.zero,
          trailing: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          title: Text(
            group.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SoftErpTheme.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                _OrderFetchStatusBadge(status: group.parent.status),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${visibleItems.length} line${visibleItems.length == 1 ? '' : 's'} available',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SoftErpTheme.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          children: visibleItems
              .map(
                (item) => _OrderFetchLineRow(
                  item: item,
                  selected: selectedLineIds.contains(item.id),
                  onToggle: (selected) => onToggle(item, selected),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _OrderFetchLineRow extends StatelessWidget {
  const _OrderFetchLineRow({
    required this.item,
    required this.selected,
    required this.onToggle,
  });

  final OrderEntry item;
  final bool selected;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final variation = item.variationPathLabel.trim();
    final unit = variation.isEmpty ? '' : ' • $variation';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: SoftErpTheme.border, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: selected,
            onChanged: (value) => onToggle(value ?? false),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.itemName.trim().isEmpty
                      ? 'Unnamed item'
                      : item.itemName.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Qty: ${item.quantity}$unit',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderFetchStatusBadge extends StatelessWidget {
  const _OrderFetchStatusBadge({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      OrderStatus.draft => 'Draft',
      OrderStatus.notStarted => 'Open',
      OrderStatus.inProgress => 'In Progress',
      OrderStatus.completed => 'Completed',
      OrderStatus.delayed => 'Delayed',
    };
    final color = switch (status) {
      OrderStatus.draft => SoftErpTheme.textSecondary,
      OrderStatus.notStarted => const Color(0xFF2563EB),
      OrderStatus.inProgress => const Color(0xFF7C3AED),
      OrderStatus.completed => const Color(0xFF15803D),
      OrderStatus.delayed => const Color(0xFFB45309),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _ItemsEditor extends StatelessWidget {
  const _ItemsEditor({
    required this.isReception,
    required this.maintainStocks,
    required this.items,
    required this.enabled,
    required this.orderOptions,
    required this.onChanged,
  });

  final bool isReception;
  final bool maintainStocks;
  final List<_ItemDraft> items;
  final bool enabled;
  final List<_OrderItemOption> orderOptions;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final availableItems = context
        .watch<ItemsProvider>()
        .items
        .where((item) => !item.isArchived)
        .toList(growable: false);
    return SoftSurface(
      padding: const EdgeInsets.all(12),
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isReception ? 'Reception items' : 'Line items',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              TextButton.icon(
                onPressed:
                    enabled &&
                        (!maintainStocks ||
                            isReception ||
                            orderOptions.isNotEmpty)
                    ? () {
                        items.add(
                          maintainStocks &&
                                  !isReception &&
                                  orderOptions.isNotEmpty
                              ? _ItemDraft.fromOrderOption(orderOptions.first)
                              : _ItemDraft.blank(items.length + 1),
                        );
                        onChanged();
                      }
                    : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add row'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (maintainStocks && !isReception && orderOptions.isEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Select at least one order first.',
                style: TextStyle(color: SoftErpTheme.textSecondary),
              ),
            ),
          ],
          for (final entry in items.asMap().entries) ...[
            !maintainStocks
                ? _buildTypewriterRow(entry.key, entry.value)
                : isReception
                ? _buildReceptionRow(
                    context,
                    entry.key,
                    entry.value,
                    availableItems,
                  )
                : _buildDeliveryRow(context, entry.key, entry.value),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildTypewriterRow(int index, _ItemDraft draft) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: 28, child: Text('${index + 1}.')),
              Expanded(
                flex: 5,
                child: _itemField(
                  draft.particulars,
                  'Item / Particulars',
                  enabled,
                  (value) => draft.particulars = value,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _itemField(
                  draft.hsnCode,
                  'HSN Code',
                  enabled,
                  (value) => draft.hsnCode = value,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _itemField(
                  draft.quantityPcs,
                  'Qty / Pcs',
                  enabled,
                  (value) => draft.quantityPcs = value,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _itemField(
                  draft.weight,
                  'Weight',
                  enabled,
                  (value) => draft.weight = value,
                ),
              ),
              IconButton(
                tooltip: 'Remove row',
                onPressed: enabled && items.length > 1
                    ? () {
                        items.removeAt(index);
                        onChanged();
                      }
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _itemField(
            draft.note,
            'Line note',
            enabled,
            (value) => draft.note = value,
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryRow(BuildContext context, int index, _ItemDraft draft) {
    return Column(
      children: [
        Row(
          children: [
            SizedBox(width: 28, child: Text('${index + 1}.')),
            Expanded(
              flex: 5,
              child: DropdownButtonFormField<int>(
                key: ValueKey<String>(
                  '$index-${draft.orderItemId}-${orderOptions.length}',
                ),
                initialValue: draft.orderItemId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: 'Particulars',
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: orderOptions
                    .map(
                      (orderOption) => DropdownMenuItem<int>(
                        value: orderOption.orderItemId,
                        child: Text(
                          orderOption.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: enabled && orderOptions.isNotEmpty
                    ? (value) {
                        _OrderItemOption? selectedOption;
                        for (final option in orderOptions) {
                          if (option.orderItemId == value) {
                            selectedOption = option;
                            break;
                          }
                        }
                        draft.applyOrderOption(selectedOption);
                        onChanged();
                      }
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _readonlyItemField(draft.hsnCode, 'HSN Code'),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _itemField(
                draft.quantityPcs,
                'Qty / Pcs',
                enabled && orderOptions.isNotEmpty,
                (value) => draft.quantityPcs = value,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: _itemField(
                draft.weight,
                'Weight',
                enabled && orderOptions.isNotEmpty,
                (value) => draft.weight = value,
              ),
            ),
            IconButton(
              tooltip: 'Remove row',
              onPressed: enabled && items.length > 1
                  ? () {
                      items.removeAt(index);
                      onChanged();
                    }
                  : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ],
        ),
        if (draft.itemId != null &&
            draft.variationPathLabel.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildDeliveryVariationPathField(context, index, draft),
        ],
        const SizedBox(height: 8),
        _itemField(
          draft.note,
          'Line note',
          enabled,
          (value) => draft.note = value,
        ),
      ],
    );
  }

  Widget _buildReceptionRow(
    BuildContext context,
    int index,
    _ItemDraft draft,
    List<ItemDefinition> availableItems,
  ) {
    final unitsProvider = context.watch<UnitsProvider>();
    final selectedItem = availableItems
        .where((item) => item.id == draft.itemId)
        .firstOrNull;
    if (selectedItem != null) {
      draft.initializeConversionFields(selectedItem, unitsProvider);
    }
    final itemOptions = availableItems
        .map(
          (item) => SearchableSelectOption<int>(
            value: item.id,
            label: item.displayName,
            searchText: '${item.displayName} ${item.alias} ${item.name}',
          ),
        )
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: 28, child: Text('${index + 1}.')),
              Expanded(
                flex: 6,
                child: SearchableSelectField<int>(
                  key: ValueKey<String>('challan-reception-item-$index'),
                  tapTargetKey: ValueKey<String>(
                    'challan-reception-item-$index',
                  ),
                  value: draft.itemId,
                  fieldEnabled: enabled,
                  decoration: InputDecoration(
                    labelText: 'Item',
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  dialogTitle: 'Select Item',
                  searchHintText: 'Search item',
                  options: itemOptions,
                  onChanged: (itemId) async {
                    final item = availableItems
                        .where((candidate) => candidate.id == itemId)
                        .firstOrNull;
                    draft.applyReceptionItem(item);
                    onChanged();
                    
                    if (item != null && item.topLevelProperties.isNotEmpty) {
                      final result = await _openVariationSelector(
                        context,
                        item: item,
                        draft: draft,
                        readOnly: false,
                      );
                      if (result != null) {
                        draft.applyReceptionVariationSelection(
                          result.item,
                          result.valueNodeIds,
                          result.leaf,
                          _variationSelectionLabel(result.item, result.valueNodeIds),
                        );
                        onChanged();
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (selectedItem == null) ...[
                Expanded(
                  flex: 2,
                  child: _itemField(
                    draft.quantityPcs,
                    'Qty',
                    enabled,
                    (value) => draft.quantityPcs = value,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _itemField(
                    draft.weight,
                    'Weight (Kg)',
                    enabled,
                    (value) => draft.weight = value,
                  ),
                ),
              ] else ...[
                Expanded(
                  flex: 2,
                  child: _buildUnitDropdown(context, draft, selectedItem, unitsProvider),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _itemField(
                    draft.enteredValue,
                    'Value',
                    enabled,
                    (value) {
                      draft.enteredValue = value;
                      draft.updateConversions(selectedItem, unitsProvider);
                      onChanged();
                    },
                  ),
                ),
              ],
              IconButton(
                tooltip: 'Remove row',
                onPressed: enabled && items.length > 1
                    ? () {
                        items.removeAt(index);
                        onChanged();
                      }
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          if (selectedItem != null) ...[
            const SizedBox(height: 10),
            _buildConversionSummary(context, draft, selectedItem, unitsProvider),
            const SizedBox(height: 10),
            _buildReceptionVariationPathField(
              context,
              index,
              draft,
              selectedItem,
            ),
          ],
          const SizedBox(height: 8),
          _itemField(
            draft.note,
            'Line note',
            enabled,
            (value) => draft.note = value,
          ),
        ],
      ),
    );
  }

  Widget _buildUnitDropdown(
    BuildContext context,
    _ItemDraft draft,
    ItemDefinition item,
    UnitsProvider unitsProvider,
  ) {
    final units = draft.getAvailableUnits(item, unitsProvider);
    if (units.isEmpty) {
      return const SizedBox.shrink();
    }
    return DropdownButtonFormField<int>(
      value: draft.selectedUnitId,
      decoration: InputDecoration(
        labelText: 'Unit',
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      items: units.map((u) {
        return DropdownMenuItem<int>(
          value: u.id,
          child: Text(u.symbol, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: enabled
          ? (unitId) {
              draft.selectedUnitId = unitId;
              draft.updateConversions(item, unitsProvider);
              onChanged();
            }
          : null,
    );
  }

  Widget _buildConversionSummary(
    BuildContext context,
    _ItemDraft draft,
    ItemDefinition item,
    UnitsProvider unitsProvider,
  ) {
    final units = draft.getAvailableUnits(item, unitsProvider);
    if (units.isEmpty) return const SizedBox.shrink();

    // Trigger update conversions if empty to make sure values are in sync
    if (draft.quantityPcs.isEmpty && draft.weight.isEmpty && draft.enteredValue.isNotEmpty) {
      draft.updateConversions(item, unitsProvider);
    }

    final parts = <String>[];
    final val = double.tryParse(draft.enteredValue.trim());
    if (val != null && val > 0) {
      final selectedUnit = units.firstWhere((u) => u.id == draft.selectedUnitId, orElse: () => units.first);
      final primaryVal = val * selectedUnit.factorToPrimary;
      
      for (final u in units) {
        final converted = primaryVal / u.factorToPrimary;
        parts.add('${draft.formatDouble(converted)} ${u.symbol}');
      }
    }

    if (parts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Icon(
              Icons.swap_horiz,
              size: 14,
              color: Color(0xFF64748B),
            ),
            Text(
              'Converted: ${parts.join("  •  ")}',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceptionVariationPathField(
    BuildContext context,
    int index,
    _ItemDraft draft,
    ItemDefinition item,
  ) {
    if (item.topLevelProperties.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SoftPill(
          label: 'No variation required',
          foreground: SoftErpTheme.textSecondary,
          background: SoftErpTheme.cardSurfaceAlt,
          borderColor: SoftErpTheme.border,
        ),
      );
    }
    final hasSelectedPath =
        draft.variationLeafNodeId > 0 ||
        draft.variationPathLabel.trim().isNotEmpty;
    final label = hasSelectedPath
        ? draft.variationPathLabel
        : 'Select variation path';
    return InkWell(
      key: ValueKey<String>('challan-reception-variation-$index'),
      onTap: enabled
          ? () async {
              final result = await _openVariationSelector(
                context,
                item: item,
                draft: draft,
                readOnly: false,
              );
              if (result == null) {
                return;
              }
              draft.applyReceptionVariationSelection(
                result.item,
                result.valueNodeIds,
                result.leaf,
                _variationSelectionLabel(result.item, result.valueNodeIds),
              );
              onChanged();
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hasSelectedPath ? SoftErpTheme.accentSoft : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasSelectedPath
                ? const Color(0xFFDAD4FF)
                : SoftErpTheme.border,
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.route_rounded,
              size: 17,
              color: SoftErpTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: hasSelectedPath
                      ? SoftErpTheme.accentDark
                      : SoftErpTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                  decoration: TextDecoration.underline,
                  decorationColor: hasSelectedPath
                      ? SoftErpTheme.accentDark
                      : SoftErpTheme.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeliveryVariationPathField(
    BuildContext context,
    int index,
    _ItemDraft draft,
  ) {
    final item = context
        .read<ItemsProvider>()
        .items
        .where((candidate) => candidate.id == draft.itemId)
        .firstOrNull;
    if (item == null || draft.variationPathLabel.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return InkWell(
      key: ValueKey<String>('challan-delivery-variation-$index'),
      onTap: () {
        _openVariationSelector(
          context,
          item: item,
          draft: draft,
          readOnly: true,
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: SoftErpTheme.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: SoftErpTheme.border),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.route_rounded,
              size: 17,
              color: SoftErpTheme.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                draft.variationPathLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<VariationPathSelectionResult?> _openVariationSelector(
    BuildContext context, {
    required ItemDefinition item,
    required _ItemDraft draft,
    required bool readOnly,
  }) {
    return showDialog<VariationPathSelectionResult>(
      context: context,
      builder: (dialogContext) => Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680, maxHeight: 760),
          child: VariationPathSelectorDialog(
            item: item,
            initialRootPropertyId: null,
            initialValueNodeIds: draft.variationPathNodeIds.isNotEmpty
                ? draft.variationPathNodeIds
                : draft.variationLeafNodeId <= 0
                    ? const <int>[]
                    : _valueNodeIdsForLeaf(item, draft.variationLeafNodeId),
            onCreateValue: null,
            readOnly: readOnly,
          ),
        ),
      ),
    );
  }

  List<int> _valueNodeIdsForLeaf(ItemDefinition item, int leafId) {
    final path = <ItemVariationNodeDefinition>[];

    bool visit(ItemVariationNodeDefinition node) {
      path.add(node);
      if (node.id == leafId) {
        return true;
      }
      for (final child in node.activeChildren) {
        if (visit(child)) {
          return true;
        }
      }
      path.removeLast();
      return false;
    }

    for (final root in item.topLevelProperties) {
      if (visit(root)) {
        break;
      }
      path.clear();
    }

    return path
        .where((node) => node.kind == ItemVariationNodeKind.value)
        .map((node) => node.id)
        .toList(growable: false);
  }

  String _variationSelectionLabel(ItemDefinition item, List<int> valueNodeIds) {
    if (valueNodeIds.isEmpty) {
      return '';
    }
    final selectedValueIds = valueNodeIds.toSet();
    final segments = <String>[];
    for (final root in item.topLevelProperties) {
      ItemVariationNodeDefinition currentProperty = root;
      while (true) {
        final selectedValue = currentProperty.activeChildren
            .where((node) => node.kind == ItemVariationNodeKind.value)
            .where((node) => selectedValueIds.contains(node.id))
            .firstOrNull;
        if (selectedValue == null) {
          break;
        }
        final propertyName = currentProperty.name.trim();
        final valueName = selectedValue.name.trim().isEmpty
            ? selectedValue.displayName.trim()
            : selectedValue.name.trim();
        if (propertyName.isNotEmpty || valueName.isNotEmpty) {
          segments.add(
            valueName.isEmpty ? propertyName : '$propertyName: $valueName',
          );
        }
        final nextProperty = selectedValue.activeChildren
            .where((node) => node.kind == ItemVariationNodeKind.property)
            .firstOrNull;
        if (nextProperty == null) {
          break;
        }
        currentProperty = nextProperty;
      }
    }
    return segments.join(' / ');
  }

  Widget _itemField(
    String initialValue,
    String label,
    bool enabled,
    ValueChanged<String> onChanged,
  ) {
    return TextFormField(
      initialValue: initialValue,
      enabled: enabled,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _readonlyItemField(String value, String label) {
    return TextFormField(
      initialValue: value,
      enabled: false,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: const Color(0xFFF7F8FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0B8B5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: Color(0xFFB94A48),
            size: 18,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _friendlyError(message),
              style: const TextStyle(
                color: Color(0xFF9F3430),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ItemUnitOption {
  final int id;
  final String name;
  final String symbol;
  final double factorToPrimary;
  final bool isPrimary;

  ItemUnitOption({
    required this.id,
    required this.name,
    required this.symbol,
    required this.factorToPrimary,
    required this.isPrimary,
  });
}

class _ItemDraft {
  _ItemDraft({
    this.orderItemId,
    this.productionRunId,
    this.itemId,
    this.variationLeafNodeId = 0,
    this.variationPathNodeIds = const <int>[],
    this.particulars = '',
    this.hsnCode = '',
    this.variationPathLabel = '',
    this.productionRunLabel = '',
    this.note = '',
    this.quantityPcs = '',
    this.weight = '',
  });

  int? orderItemId;
  int? productionRunId;
  int? itemId;
  int variationLeafNodeId;
  List<int> variationPathNodeIds;
  String particulars;
  String hsnCode;
  String variationPathLabel;
  String productionRunLabel;
  String note;
  String quantityPcs;
  String weight;
  int? selectedUnitId;
  String enteredValue = '';

  bool get isBlank =>
      orderItemId == null &&
      productionRunId == null &&
      itemId == null &&
      particulars.trim().isEmpty &&
      hsnCode.trim().isEmpty &&
      variationPathLabel.trim().isEmpty &&
      productionRunLabel.trim().isEmpty &&
      note.trim().isEmpty &&
      quantityPcs.trim().isEmpty &&
      weight.trim().isEmpty &&
      enteredValue.trim().isEmpty;

  factory _ItemDraft.blank(int lineNo) => _ItemDraft();

  factory _ItemDraft.fromOrderOption(_OrderItemOption? option) {
    return _ItemDraft(
      orderItemId: option?.orderItemId,
      productionRunId: null,
      itemId: option?.itemId,
      variationLeafNodeId: option?.variationLeafNodeId ?? 0,
      variationPathNodeIds: option?.variationPathNodeIds ?? const <int>[],
      particulars: option?.particulars ?? '',
      hsnCode: option?.hsnCode ?? '',
      variationPathLabel: option?.variationPathLabel ?? '',
    );
  }

  factory _ItemDraft.fromItem(DeliveryChallanItem item) {
    return _ItemDraft(
      orderItemId: item.orderItemId,
      productionRunId: item.productionRunId,
      itemId: item.itemId,
      variationLeafNodeId: item.variationLeafNodeId,
      particulars: item.particulars,
      hsnCode: item.hsnCode,
      variationPathLabel: item.variationPathLabel,
      productionRunLabel: item.productionRunId == null
          ? ''
          : 'Run #${item.productionRunId}',
      note: item.note,
      quantityPcs: item.quantityPcs,
      weight: item.weight,
    );
  }

  List<ItemUnitOption> getAvailableUnits(ItemDefinition item, UnitsProvider unitsProvider) {
    final list = <ItemUnitOption>[];
    final primary = unitsProvider.findById(item.unitId);
    if (primary != null) {
      list.add(ItemUnitOption(
        id: primary.id,
        name: primary.name,
        symbol: primary.symbol,
        factorToPrimary: 1.0,
        isPrimary: true,
      ));
    }
    for (final conv in item.unitConversions) {
      if (conv.unitId == item.unitId) continue;
      list.add(ItemUnitOption(
        id: conv.unitId,
        name: conv.unitName,
        symbol: conv.unitSymbol,
        factorToPrimary: conv.factorToPrimary,
        isPrimary: false,
      ));
    }
    return list;
  }

  bool isWeightUnit(ItemUnitOption option) {
    final s = option.symbol.toLowerCase();
    final n = option.name.toLowerCase();
    return s == 'kg' || s == 'kgs' || s == 'g' || s == 'gms' || s == 'gram' || s == 'grams' || s == 'kilogram' || s == 'kilograms' || n.contains('weight');
  }

  bool isQtyUnit(ItemUnitOption option) {
    final s = option.symbol.toLowerCase();
    final n = option.name.toLowerCase();
    return s == 'pcs' || s == 'pc' || s == 'piece' || s == 'pieces' || s == 'unit' || s == 'units' || n.contains('quantity') || n.contains('count');
  }

  void initializeConversionFields(ItemDefinition? item, UnitsProvider unitsProvider) {
    if (item == null) return;
    final units = getAvailableUnits(item, unitsProvider);
    if (units.isEmpty) return;

    if (selectedUnitId != null) return;

    if (weight.isNotEmpty && double.tryParse(weight) != null) {
      ItemUnitOption? wtOpt;
      for (final u in units) {
        if (isWeightUnit(u)) {
          wtOpt = u;
          break;
        }
      }
      final targetUnit = wtOpt ?? units.first;
      selectedUnitId = targetUnit.id;
      enteredValue = weight;
    } else if (quantityPcs.isNotEmpty && double.tryParse(quantityPcs) != null) {
      ItemUnitOption? qtyOpt;
      for (final u in units) {
        if (isQtyUnit(u)) {
          qtyOpt = u;
          break;
        }
      }
      final targetUnit = qtyOpt ?? units.first;
      selectedUnitId = targetUnit.id;
      enteredValue = quantityPcs;
    } else {
      selectedUnitId = units.first.id;
      enteredValue = '';
    }
  }

  void updateConversions(ItemDefinition? item, UnitsProvider unitsProvider) {
    if (item == null) return;
    final units = getAvailableUnits(item, unitsProvider);
    if (units.isEmpty) return;

    if (selectedUnitId == null) {
      selectedUnitId = units.first.id;
    }

    final val = double.tryParse(enteredValue.trim());
    if (val == null || val <= 0) {
      quantityPcs = '';
      weight = '';
      return;
    }

    final selectedUnit = units.firstWhere((u) => u.id == selectedUnitId, orElse: () => units.first);
    final primaryVal = val * selectedUnit.factorToPrimary;

    ItemUnitOption? wtOpt;
    for (final u in units) {
      if (isWeightUnit(u)) {
        wtOpt = u;
        break;
      }
    }
    ItemUnitOption? qtyOpt;
    for (final u in units) {
      if (isQtyUnit(u)) {
        qtyOpt = u;
        break;
      }
    }

    if (wtOpt != null) {
      final wtVal = primaryVal / wtOpt.factorToPrimary;
      weight = formatDouble(wtVal);
    } else {
      final primaryUnit = unitsProvider.findById(item.unitId);
      if (primaryUnit != null && isWeightUnit(ItemUnitOption(id: primaryUnit.id, name: primaryUnit.name, symbol: primaryUnit.symbol, factorToPrimary: 1.0, isPrimary: true))) {
        weight = formatDouble(primaryVal);
      } else {
        weight = '';
      }
    }

    if (qtyOpt != null) {
      final qtyVal = primaryVal / qtyOpt.factorToPrimary;
      quantityPcs = formatDouble(qtyVal);
    } else {
      final primaryUnit = unitsProvider.findById(item.unitId);
      if (primaryUnit != null && isQtyUnit(ItemUnitOption(id: primaryUnit.id, name: primaryUnit.name, symbol: primaryUnit.symbol, factorToPrimary: 1.0, isPrimary: true))) {
        quantityPcs = formatDouble(primaryVal);
      } else {
        quantityPcs = '';
      }
    }
  }

  String formatDouble(double val) {
    if (val == val.toInt()) {
      return val.toInt().toString();
    }
    final str = val.toStringAsFixed(4);
    if (str.contains('.')) {
      var end = str.length - 1;
      while (end > 0 && str[end] == '0') {
        end--;
      }
      if (str[end] == '.') {
        end--;
      }
      return str.substring(0, end + 1);
    }
    return str;
  }

  void applyOrderOption(_OrderItemOption? option) {
    orderItemId = option?.orderItemId;
    if (productionRunId == null) {
      itemId = option?.itemId;
      variationLeafNodeId = option?.variationLeafNodeId ?? 0;
      variationPathNodeIds = option?.variationPathNodeIds ?? const <int>[];
      particulars = option?.particulars ?? '';
      hsnCode = option?.hsnCode ?? '';
      variationPathLabel = option?.variationPathLabel ?? '';
    }
  }

  void applyReceptionItem(ItemDefinition? item) {
    itemId = item?.id;
    orderItemId = null;
    productionRunId = null;
    hsnCode = '';
    variationLeafNodeId = 0;
    variationPathLabel = '';
    productionRunLabel = '';
    particulars = item?.displayName ?? '';
    selectedUnitId = null;
    enteredValue = '';
  }

  void applyReceptionVariationSelection(
    ItemDefinition item,
    List<int> valueNodeIds,
    ItemVariationNodeDefinition? leaf,
    String label,
  ) {
    itemId = item.id;
    orderItemId = null;
    productionRunId = null;
    variationLeafNodeId = leaf?.id ?? 0;
    variationPathLabel = label;
    productionRunLabel = '';
    particulars = label.trim().isEmpty
        ? item.displayName
        : '${item.displayName} - $label';
    hsnCode = '';
    selectedUnitId = null;
    enteredValue = '';
  }

  void applyProductionRun(CompletedProductionRun run) {
    orderItemId = null;
    productionRunId = run.id;
    itemId = run.itemId;
    variationLeafNodeId = run.variationLeafNodeId;
    variationPathLabel = run.variationPathLabel;
    productionRunLabel = run.displayLabel;
    particulars = run.variationPathLabel.trim().isEmpty
        ? run.itemName
        : '${run.itemName} - ${run.variationPathLabel}';
    hsnCode = '';
    if (run.outputQuantity > 0) {
      quantityPcs = run.outputQuantity.truncateToDouble() == run.outputQuantity
          ? run.outputQuantity.toStringAsFixed(0)
          : run.outputQuantity.toStringAsFixed(2);
    }
  }

  void clearProductionRun() {
    productionRunId = null;
    productionRunLabel = '';
  }

  DeliveryChallanItem toItem(int lineNo) {
    return DeliveryChallanItem(
      id: 0,
      orderItemId: orderItemId,
      productionRunId: productionRunId,
      itemId: itemId,
      variationLeafNodeId: variationLeafNodeId,
      lineNo: lineNo,
      particulars: particulars,
      hsnCode: hsnCode,
      variationPathLabel: variationPathLabel,
      note: note,
      quantityPcs: quantityPcs,
      weight: weight,
    );
  }
}

class _OrderItemOption {
  const _OrderItemOption({
    required this.orderItemId,
    required this.orderNo,
    required this.itemId,
    required this.variationLeafNodeId,
    required this.variationPathNodeIds,
    required this.particulars,
    required this.hsnCode,
    required this.variationPathLabel,
    required this.quantity,
  });

  final int orderItemId;
  final String orderNo;
  final int itemId;
  final int variationLeafNodeId;
  final List<int> variationPathNodeIds;
  final String particulars;
  final String hsnCode;
  final String variationPathLabel;
  final int quantity;

  factory _OrderItemOption.fromOrder(OrderEntry order) {
    final variation = order.variationPathLabel.trim();
    final particulars = variation.isEmpty
        ? order.itemName.trim()
        : '${order.itemName.trim()} - $variation';
    return _OrderItemOption(
      orderItemId: order.id,
      orderNo: order.orderNo,
      itemId: order.itemId,
      variationLeafNodeId: order.variationLeafNodeId,
      variationPathNodeIds: order.variationPathNodeIds,
      particulars: particulars,
      hsnCode: '',
      variationPathLabel: variation,
      quantity: order.quantity,
    );
  }

  String get label {
    final qty = quantity > 0 ? ' • Ordered $quantity' : '';
    final orderLabel = orderNo.trim().isEmpty
        ? ''
        : ' — Order ${orderNo.trim()}';
    return '$particulars$orderLabel$qty';
  }
}

class _CompanyProfileEditor extends StatefulWidget {
  const _CompanyProfileEditor();

  @override
  State<_CompanyProfileEditor> createState() => _CompanyProfileEditorState();
}

class _CompanyProfileEditorState extends State<_CompanyProfileEditor> {
  late final Map<String, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    final profile =
        context.read<DeliveryChallanProvider>().companyProfile ??
        CompanyProfile.empty();
    _controllers = {
      'companyName': TextEditingController(text: profile.companyName),
      'mobile': TextEditingController(text: profile.mobile),
      'businessDescription': TextEditingController(
        text: profile.businessDescription,
      ),
      'address': TextEditingController(text: profile.address),
      'stateCode': TextEditingController(text: profile.stateCode),
      'gstin': TextEditingController(text: profile.gstin),
      'logoUrl': TextEditingController(text: profile.logoUrl),
      'signatureLabel': TextEditingController(text: profile.signatureLabel),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Company Profile',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _profileField('Company name', 'companyName'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _profileField('Mobile', 'mobile')),
              const SizedBox(width: 10),
              Expanded(child: _profileField('State Code', 'stateCode')),
            ],
          ),
          const SizedBox(height: 10),
          _profileField('Business description', 'businessDescription'),
          const SizedBox(height: 10),
          _profileField('Address', 'address', maxLines: 3),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _profileField('GSTIN', 'gstin')),
              const SizedBox(width: 10),
              Expanded(child: _profileField('Logo URL / path', 'logoUrl')),
            ],
          ),
          const SizedBox(height: 10),
          _profileField(
            'Signature label / authorized signatory',
            'signatureLabel',
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              if (provider.errorMessage != null)
                Expanded(child: _ErrorBanner(message: provider.errorMessage!))
              else
                const Spacer(),
              AppButton(
                label: 'Save Profile',
                icon: Icons.save_outlined,
                isLoading: provider.isSaving,
                onPressed: _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileField(String label, String key, {int maxLines = 1}) {
    return TextField(
      controller: _controllers[key],
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Future<void> _save() async {
    final current =
        context.read<DeliveryChallanProvider>().companyProfile ??
        CompanyProfile.empty();
    final saved = await context
        .read<DeliveryChallanProvider>()
        .saveCompanyProfile(
          CompanyProfile(
            id: current.id,
            companyName: _controllers['companyName']!.text,
            mobile: _controllers['mobile']!.text,
            businessDescription: _controllers['businessDescription']!.text,
            address: _controllers['address']!.text,
            stateCode: _controllers['stateCode']!.text,
            gstin: _controllers['gstin']!.text,
            logoUrl: _controllers['logoUrl']!.text,
            signatureLabel: _controllers['signatureLabel']!.text,
          ),
        );
    if (saved != null && mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _PrintPreview extends StatefulWidget {
  const _PrintPreview({required this.challan});

  final DeliveryChallan challan;

  @override
  State<_PrintPreview> createState() => _PrintPreviewState();
}

class _PrintPreviewState extends State<_PrintPreview> {
  late final Future<List<ChallanTemplate>> _templatesFuture;
  ChallanTemplate? _activeTemplateOverride;
  bool _isNudgingTemplate = false;
  bool _isPrintingTemplate = false;

  @override
  void initState() {
    super.initState();
    _templatesFuture = _loadMatchingTemplates();
  }

  Future<List<ChallanTemplate>> _loadMatchingTemplates() async {
    final templates = await context
        .read<DeliveryChallanProvider>()
        .loadTemplates(
          partyType: ChallanTemplatePartyType.generic,
          activeOnly: true,
        );
    return [
      ...templates.where(
        (template) => template.challanType == widget.challan.type,
      ),
      ...templates.where(
        (template) => template.challanType != widget.challan.type,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();
    final profile =
        widget.challan.companyProfileSnapshot ??
        provider.companyProfile ??
        CompanyProfile.empty();
    return FutureBuilder<List<ChallanTemplate>>(
      future: _templatesFuture,
      builder: (context, snapshot) {
        final templates = snapshot.data ?? const <ChallanTemplate>[];
        final loadedTemplate = templates.isEmpty ? null : templates.first;
        final template = _activeTemplateOverride ?? loadedTemplate;
        final defaultedPrintPositions = template == null
            ? const <String>[]
            : _missingTemplatePrintPositions(template);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Print Preview',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (template != null) ...[
                    AppButton(
                      label: 'Digital Preview',
                      icon: Icons.picture_as_pdf_outlined,
                      variant: AppButtonVariant.secondary,
                      onPressed: _isPrintingTemplate
                          ? null
                          : () =>
                                _printTemplatePdf(context, template, 'digital'),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Overprint',
                      icon: Icons.print_outlined,
                      onPressed: _isPrintingTemplate
                          ? null
                          : () => _printTemplatePdf(
                              context,
                              template,
                              'overprint',
                            ),
                    ),
                  ] else
                    AppButton(
                      label: 'Print',
                      icon: Icons.print_outlined,
                      onPressed: () async {
                        await _launchPrintDialog(widget.challan, profile);
                      },
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            if (template != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: _SelectedTemplateStrip(
                  templates: templates,
                  selectedTemplate: template,
                  defaultedPrintPositions: defaultedPrintPositions,
                  onChanged: (templateId) {
                    final selected = templates
                        .where((entry) => entry.id == templateId)
                        .firstOrNull;
                    if (selected == null) {
                      return;
                    }
                    setState(() => _activeTemplateOverride = selected);
                  },
                ),
              ),
            if (template != null)
              _TemplateNudgeBar(
                template: template,
                isSaving: _isNudgingTemplate,
                onNudge: _nudgeTemplate,
              ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: _ChallanDocument(
                    challan: widget.challan,
                    profile: profile,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  List<String> _missingTemplatePrintPositions(ChallanTemplate template) {
    final fieldKeys = template.mappings
        .map((mapping) => mapping.fieldKey.trim())
        .where((fieldKey) => fieldKey.isNotEmpty)
        .toSet();
    final missing = <String>[];
    bool hasAny(Set<String> aliases) => aliases.any(fieldKeys.contains);
    if (!hasAny({'date', 'challan_date', 'challanDate'})) {
      missing.add('Date');
    }
    if (!hasAny({
      'party_name',
      'partyName',
      'client_name',
      'clientName',
      'customer_name',
      'customerName',
      'vendor_name',
      'vendorName',
    })) {
      missing.add('Party Name');
    }
    if (!hasAny({
      'gstin',
      'gst_number',
      'gstNumber',
      'customer_gstin',
      'customerGstin',
      'vendor_gstin',
      'vendorGstin',
    })) {
      missing.add('GSTIN');
    }
    return missing;
  }

  Future<void> _printTemplatePdf(
    BuildContext context,
    ChallanTemplate? template,
    String mode,
  ) async {
    if (_isPrintingTemplate) {
      return;
    }
    final provider = context.read<DeliveryChallanProvider>();
    setState(() => _isPrintingTemplate = true);
    try {
      final bytes = await provider.repository.fetchTemplatePreviewPdf(
        challanId: widget.challan.id,
        templateId: template?.id,
        mode: mode,
      );
      final fileName = _templatePrintFileName(widget.challan, mode);
      final printed = await _showPdfPrintDialog(bytes, fileName);
      if (printed) {
        await provider.recordPrint(widget.challan.id);
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        this.context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    } finally {
      if (mounted) {
        setState(() => _isPrintingTemplate = false);
      }
    }
  }

  Future<void> _nudgeTemplate(
    ChallanTemplate template,
    double deltaXmm,
    double deltaYmm,
  ) async {
    if (_isNudgingTemplate) {
      return;
    }
    setState(() => _isNudgingTemplate = true);
    final provider = context.read<DeliveryChallanProvider>();
    final saved = await provider.saveTemplate(
      id: template.id,
      input: ChallanTemplateInput(
        name: template.name,
        partyType: template.partyType,
        partyId: template.partyType == ChallanTemplatePartyType.generic
            ? 0
            : template.partyId,
        challanType: template.challanType,
        backgroundObjectKey: template.backgroundObjectKey,
        canvasWidth: template.canvasWidth,
        canvasHeight: template.canvasHeight,
        rotationDegrees: template.rotationDegrees,
        globalOffsetXmm: template.globalOffsetXmm + deltaXmm,
        globalOffsetYmm: template.globalOffsetYmm + deltaYmm,
        stockSize: template.stockSize,
        paperSize: template.paperSize,
        nUpLayout: template.nUpLayout,
        isActive: template.isActive,
        mappings: template.mappings,
      ),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _isNudgingTemplate = false;
      if (saved != null) {
        _activeTemplateOverride = saved;
      }
    });
  }
}

class _TemplateNudgeBar extends StatelessWidget {
  const _TemplateNudgeBar({
    required this.template,
    required this.isSaving,
    required this.onNudge,
  });

  final ChallanTemplate template;
  final bool isSaving;
  final Future<void> Function(
    ChallanTemplate template,
    double deltaXmm,
    double deltaYmm,
  )
  onNudge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
      color: SoftErpTheme.cardSurfaceAlt,
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Template: ${template.name}',
            style: const TextStyle(
              color: SoftErpTheme.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'Offset X ${template.globalOffsetXmm.toStringAsFixed(1)}mm, '
            'Y ${template.globalOffsetYmm.toStringAsFixed(1)}mm',
            style: const TextStyle(color: SoftErpTheme.textSecondary),
          ),
          const SizedBox(width: 6),
          _NudgeButton(
            label: 'Left',
            icon: Icons.keyboard_arrow_left_rounded,
            isSaving: isSaving,
            onPressed: () => onNudge(template, -0.5, 0),
          ),
          _NudgeButton(
            label: 'Right',
            icon: Icons.keyboard_arrow_right_rounded,
            isSaving: isSaving,
            onPressed: () => onNudge(template, 0.5, 0),
          ),
          _NudgeButton(
            label: 'Up',
            icon: Icons.keyboard_arrow_up_rounded,
            isSaving: isSaving,
            onPressed: () => onNudge(template, 0, -0.5),
          ),
          _NudgeButton(
            label: 'Down',
            icon: Icons.keyboard_arrow_down_rounded,
            isSaving: isSaving,
            onPressed: () => onNudge(template, 0, 0.5),
          ),
        ],
      ),
    );
  }
}

class _SelectedTemplateStrip extends StatelessWidget {
  const _SelectedTemplateStrip({
    required this.templates,
    required this.selectedTemplate,
    required this.defaultedPrintPositions,
    required this.onChanged,
  });

  final List<ChallanTemplate> templates;
  final ChallanTemplate selectedTemplate;
  final List<String> defaultedPrintPositions;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: SoftErpTheme.cardSurfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SoftErpTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.description_outlined,
                size: 18,
                color: SoftErpTheme.accent,
              ),
              const SizedBox(width: 8),
              const Text(
                'Selected Template',
                style: TextStyle(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              SoftPill(
                label:
                    '${selectedTemplate.stockSize} on ${selectedTemplate.paperSize} • ${selectedTemplate.nUpLayout}-up',
                background: Colors.white,
                foreground: SoftErpTheme.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Party, GSTIN, and date values come from the saved challan. The template only controls where those values print on paper.',
            style: TextStyle(color: SoftErpTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            initialValue: selectedTemplate.id,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Template',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: SoftErpTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: SoftErpTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: SoftErpTheme.accent),
              ),
            ),
            items: templates
                .map(
                  (template) => DropdownMenuItem<int>(
                    value: template.id,
                    child: Text(
                      '${template.name} (${template.challanType.name})',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              if (value != null) {
                onChanged(value);
              }
            },
          ),
          if (defaultedPrintPositions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Using default print position for: ${defaultedPrintPositions.join(', ')}. The challan data exists; add/move these blocks in the template editor for exact alignment.',
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({
    required this.label,
    required this.icon,
    required this.isSaving,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final bool isSaving;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: isSaving ? null : onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: SoftErpTheme.textPrimary,
        side: const BorderSide(color: SoftErpTheme.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _ChallanDocument extends StatelessWidget {
  const _ChallanDocument({required this.challan, required this.profile});

  final DeliveryChallan challan;
  final CompanyProfile profile;

  @override
  Widget build(BuildContext context) {
    final isReception = challan.isReception;
    final docTitle = isReception ? 'RECEPTION CHALLAN' : 'DELIVERY CHALLAN';
    final partyLabel = isReception ? 'Vendor' : 'M/s';
    final partyName = isReception ? challan.vendorName : challan.customerName;
    final partyGstin = isReception
        ? challan.vendorGstin
        : challan.customerGstin;
    final referenceLabel = isReception ? 'Source Ref.' : 'Challan No.';
    final referenceValue = isReception
        ? (challan.sourceReference.trim().isEmpty
              ? challan.challanNo
              : challan.sourceReference)
        : challan.challanNo;
    return Container(
      width: 760,
      color: Colors.white,
      padding: const EdgeInsets.all(18),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.black, width: 1.4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(child: SizedBox()),
                      Expanded(
                        flex: 2,
                        child: Text(
                          docTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          profile.mobile.isEmpty
                              ? ''
                              : 'Mobile: ${profile.mobile}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    profile.companyName,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (profile.businessDescription.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      profile.businessDescription,
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (profile.address.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(profile.address, textAlign: TextAlign.center),
                  ],
                ],
              ),
            ),
            const Divider(color: Colors.black, height: 1),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$partyLabel: $partyName'),
                          const SizedBox(height: 8),
                          Text('GSTIN: $partyGstin'),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, color: Colors.black),
                  SizedBox(
                    width: 230,
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('$referenceLabel: $referenceValue'),
                          const SizedBox(height: 8),
                          Text('Challan No.: ${challan.challanNo}'),
                          const SizedBox(height: 8),
                          Text('Date: ${_date(challan.date)}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: Colors.black, height: 1),
            Table(
              border: TableBorder.all(color: Colors.black),
              columnWidths: const {
                0: FlexColumnWidth(4),
                1: FlexColumnWidth(1.4),
                2: FlexColumnWidth(1.4),
                3: FlexColumnWidth(1.3),
              },
              children: [
                _tableRow([
                  'Particulars',
                  'HSN Code',
                  'QTY. Pcs.',
                  'Weight',
                ], header: true),
                ...challan.items.map(
                  (item) => _tableRow([
                    item.note.trim().isEmpty
                        ? item.particulars
                        : '${item.particulars}\n${item.note}',
                    item.hsnCode,
                    item.quantityPcs,
                    item.weight,
                  ]),
                ),
                for (var i = challan.items.length; i < 9; i++)
                  _tableRow(['', '', '', '']),
              ],
            ),
            IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('State Code: ${profile.stateCode}'),
                          const SizedBox(height: 8),
                          Text('GSTIN: ${profile.gstin}'),
                          const SizedBox(height: 52),
                          const Text('Receiver’s Signature'),
                        ],
                      ),
                    ),
                  ),
                  Container(width: 1, color: Colors.black),
                  SizedBox(
                    width: 270,
                    child: _docCell(
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            'For ${profile.companyName}',
                            textAlign: TextAlign.right,
                          ),
                          const SizedBox(height: 64),
                          Text(
                            profile.signatureLabel.isEmpty
                                ? 'Checked by / Authorized Signatory'
                                : profile.signatureLabel,
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docCell(Widget child) {
    return Padding(padding: const EdgeInsets.all(10), child: child);
  }

  TableRow _tableRow(List<String> values, {bool header = false}) {
    return TableRow(
      children: values
          .map(
            (value) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
              child: Text(
                value,
                style: TextStyle(
                  fontWeight: header ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

Future<void> _launchPrintDialog(
  DeliveryChallan challan,
  CompanyProfile profile,
) async {
  final windowsDialogResult = await _showWindowsPrintDialog(challan, profile);
  if (windowsDialogResult != null) {
    return;
  }

  await _launchPrintHtml(challan, profile);
}

String _templatePrintFileName(DeliveryChallan challan, String mode) {
  final rawName = challan.challanNo.trim().isEmpty
      ? 'challan-${challan.id}'
      : challan.challanNo.trim();
  final safeName = rawName.replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_');
  return '$safeName-$mode.pdf';
}

Future<bool> _showPdfPrintDialog(Uint8List bytes, String fileName) async {
  if (!kIsWeb && Platform.isMacOS) {
    try {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return await _nativePrintingChannel.invokeMethod<bool>('printPdfFile', {
            'filePath': file.path,
          }) ??
          false;
    } on MissingPluginException {
      // Fall through to the cross-platform print plugin.
    } on PlatformException {
      // Fall through to the cross-platform print plugin.
    }
  }

  return Printing.layoutPdf(name: fileName, onLayout: (_) async => bytes);
}

Future<bool?> _showWindowsPrintDialog(
  DeliveryChallan challan,
  CompanyProfile profile,
) async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) {
    return null;
  }

  try {
    return await _nativePrintingChannel.invokeMethod<bool>(
          'showPrintDialog',
          _nativePrintPayload(challan, profile),
        ) ??
        false;
  } on MissingPluginException {
    return null;
  } on PlatformException {
    return null;
  }
}

Map<String, Object> _nativePrintPayload(
  DeliveryChallan challan,
  CompanyProfile profile,
) {
  final isReception = challan.isReception;
  final signatureLabel = profile.signatureLabel.isEmpty
      ? 'Checked by / Authorized Signatory'
      : profile.signatureLabel;
  return {
    'docTitle': isReception ? 'RECEPTION CHALLAN' : 'DELIVERY CHALLAN',
    'companyName': profile.companyName,
    'mobile': profile.mobile,
    'businessDescription': profile.businessDescription,
    'address': profile.address,
    'partyLabel': isReception ? 'Vendor' : 'M/s',
    'partyName': isReception ? challan.vendorName : challan.customerName,
    'partyGstin': isReception ? challan.vendorGstin : challan.customerGstin,
    'location': '',
    'referenceLabel': isReception ? 'Source Ref.' : 'Challan No.',
    'referenceValue': isReception
        ? (challan.sourceReference.trim().isEmpty
              ? challan.challanNo
              : challan.sourceReference)
        : challan.challanNo,
    'challanNo': challan.challanNo,
    'date': _date(challan.date),
    'stateCode': profile.stateCode,
    'gstin': profile.gstin,
    'signatureLabel': signatureLabel,
    'items': challan.items
        .map(
          (item) => {
            'particulars': item.particulars,
            'hsnCode': item.hsnCode,
            'note': item.note,
            'quantityPcs': item.quantityPcs,
            'weight': item.weight,
          },
        )
        .toList(growable: false),
  };
}

Future<void> _launchPrintHtml(
  DeliveryChallan challan,
  CompanyProfile profile,
) async {
  final html = _printHtml(challan, profile);
  final uri = Uri.parse(
    'data:text/html;charset=utf-8,${Uri.encodeComponent(html)}',
  );
  await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _printHtml(DeliveryChallan challan, CompanyProfile profile) {
  String e(String value) => const HtmlEscape().convert(value);
  final isReception = challan.isReception;
  final docTitle = isReception ? 'RECEPTION CHALLAN' : 'DELIVERY CHALLAN';
  final partyLabel = isReception ? 'Vendor' : 'M/s';
  final partyName = isReception ? challan.vendorName : challan.customerName;
  final partyGstin = isReception ? challan.vendorGstin : challan.customerGstin;
  final referenceLabel = isReception ? 'Source Ref.' : 'Challan No.';
  final referenceValue = isReception
      ? (challan.sourceReference.trim().isEmpty
            ? challan.challanNo
            : challan.sourceReference)
      : challan.challanNo;
  final rows = [
    ...challan.items.map(
      (item) =>
          '<tr><td>${e(item.particulars)}${item.note.trim().isEmpty ? '' : '<br><small><em>${e(item.note)}</em></small>'}</td><td>${e(item.hsnCode)}</td><td>${e(item.quantityPcs)}</td><td>${e(item.weight)}</td></tr>',
    ),
    for (var i = challan.items.length; i < 9; i++)
      '<tr><td></td><td></td><td></td><td></td></tr>',
  ].join();
  return '''
<!doctype html><html><head><meta charset="utf-8"><title>${e(challan.challanNo)}</title>
<style>
body{font-family:Arial,sans-serif;margin:24px;color:#000}.doc{max-width:820px;margin:auto;border:2px solid #000}.pad{padding:12px}.title{text-align:center;font-weight:800;font-size:20px}.company{text-align:center;font-weight:900;font-size:30px;margin-top:8px}.center{text-align:center}.top{display:grid;grid-template-columns:1fr 2fr 1fr;align-items:start}.mobile{text-align:right;font-weight:700}.grid{display:grid;grid-template-columns:1fr 240px;border-top:1px solid #000}.grid>div{padding:12px}.grid>div+div{border-left:1px solid #000}table{width:100%;border-collapse:collapse}td,th{border:1px solid #000;padding:10px;height:24px;text-align:left}th{font-weight:800}.bottom{display:grid;grid-template-columns:1fr 280px;border-top:1px solid #000}.bottom>div{padding:12px;min-height:120px}.bottom>div+div{border-left:1px solid #000;text-align:right}.sign{margin-top:58px}@media print{body{margin:0}.actions{display:none}.doc{border-width:1.5px}}</style>
</head><body><div class="actions"><button onclick="window.print()">Print</button></div><div class="doc">
<div class="pad"><div class="top"><div></div><div class="title">$docTitle</div><div class="mobile">${profile.mobile.isEmpty ? '' : 'Mobile: ${e(profile.mobile)}'}</div></div>
<div class="company">${e(profile.companyName)}</div><div class="center">${e(profile.businessDescription)}</div><div class="center">${e(profile.address)}</div></div>
<div class="grid"><div><p>$partyLabel: ${e(partyName)}</p><p>GSTIN: ${e(partyGstin)}</p></div><div><p>$referenceLabel: ${e(referenceValue)}</p><p>Challan No.: ${e(challan.challanNo)}</p><p>Date: ${_date(challan.date)}</p></div></div>
<table><thead><tr><th>Particulars</th><th>HSN Code</th><th>QTY. Pcs.</th><th>Weight</th></tr></thead><tbody>$rows</tbody></table>
<div class="bottom"><div><p>State Code: ${e(profile.stateCode)}</p><p>GSTIN: ${e(profile.gstin)}</p><p class="sign">Receiver's Signature</p></div><div><p>For ${e(profile.companyName)}</p><p class="sign">${e(profile.signatureLabel.isEmpty ? 'Checked by / Authorized Signatory' : profile.signatureLabel)}</p></div></div>
</div><script>setTimeout(()=>window.print(),300)</script></body></html>
''';
}

List<String> _availableReportGroupCodes(List<DeliveryChallan> challans) {
  final codes = <String>{};
  for (final challan in challans) {
    codes.addAll(_effectiveReportGroupCodes(challan));
  }
  return codes.toList(growable: false)..sort();
}

List<String> _effectiveReportGroupCodes(DeliveryChallan challan) {
  final explicitCodes =
      challan.reportGroupCodes
          .map((code) => code.trim().toUpperCase())
          .where((code) => code.isNotEmpty)
          .toSet()
          .toList(growable: false)
        ..sort();
  if (explicitCodes.isNotEmpty || !challan.isDelivery) {
    return explicitCodes;
  }
  final orderIds = challan.orderIds.isNotEmpty
      ? challan.orderIds
      : [if (challan.orderId != null) challan.orderId!];
  final normalized = orderIds.where((id) => id > 0).toSet().toList()..sort();
  if (normalized.isEmpty) {
    return const <String>[];
  }
  if (normalized.length == 1) {
    return <String>['ORD-${normalized.first}'];
  }
  return <String>['ORDSET-${normalized.join('-')}'];
}

bool _challanBelongsToReportGroup(DeliveryChallan challan, String? code) {
  if (code == null || code.isEmpty) {
    return true;
  }
  return _effectiveReportGroupCodes(challan).contains(code);
}

bool _receptionVisibleForReportGroup(DeliveryChallan challan, String? code) {
  if (code == null || code.isEmpty) {
    return true;
  }
  final codes = _effectiveReportGroupCodes(challan);
  return codes.isEmpty || codes.contains(code);
}

String _partyName(DeliveryChallan challan) {
  final value = challan.isReception ? challan.vendorName : challan.customerName;
  return value.trim().isEmpty ? 'Unassigned party' : value.trim();
}

String _itemSummary(DeliveryChallan challan) {
  if (challan.items.isEmpty) {
    return '${challan.itemsCount} item${challan.itemsCount == 1 ? '' : 's'}';
  }
  return challan.items
      .take(2)
      .map((item) => item.particulars.trim())
      .where((value) => value.isNotEmpty)
      .join(' / ');
}

String _qtyLabel(DeliveryChallan challan) {
  final quantity = challan.items.fold<double>(
    0,
    (sum, item) => sum + (double.tryParse(item.quantityPcs) ?? 0),
  );
  final weight = challan.items.fold<double>(
    0,
    (sum, item) => sum + (double.tryParse(item.weight) ?? 0),
  );
  final qtyPrefix = challan.isReception ? 'Received' : 'Delivered';
  if (quantity == 0 && weight == 0) {
    return '$qtyPrefix ${challan.itemsCount} item${challan.itemsCount == 1 ? '' : 's'}';
  }
  final parts = <String>[];
  if (quantity > 0) {
    parts.add('${_formatMetric(quantity)} Pcs');
  }
  if (weight > 0) {
    parts.add('${_formatMetric(weight)} Kg');
  }
  return '$qtyPrefix ${parts.join(' / ')}';
}

String _formatMetric(double value) {
  if (value == value.roundToDouble()) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}

Future<Uint8List> _buildClientStatementPdf(
  ClientStatementReport report,
  String reportGroupCode,
) async {
  final document = pw.Document();
  final rows = report.rows;
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Text(
          'CLIENT STATEMENT',
          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 16),
        ),
        pw.SizedBox(height: 4),
        pw.Text('Report Group: $reportGroupCode'),
        pw.SizedBox(height: 12),
        pw.TableHelper.fromTextArray(
          headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          cellStyle: const pw.TextStyle(fontSize: 8),
          headers: const <String>[
            'Date',
            'Challan',
            'Client',
            'Order',
            'Item',
            'Qty',
            'Weight',
          ],
          data: rows
              .map(
                (row) => <String>[
                  row.date == null ? '-' : _date(row.date!),
                  row.challanNo,
                  row.clientName,
                  row.orderNo,
                  row.itemName,
                  _formatMetric(row.quantityPcs),
                  _formatMetric(row.weight),
                ],
              )
              .toList(growable: false),
        ),
        pw.SizedBox(height: 12),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Total: ${_formatMetric(report.totalQuantityPcs)} Pcs / ${_formatMetric(report.totalWeight)} Kg',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  return document.save();
}

String _date(DateTime value) {
  return value.toIso8601String().substring(0, 10);
}

String _orderOptionLabel(OrderEntry order) {
  final date = _date(order.createdAt);
  final client = order.clientName.trim().isEmpty
      ? 'Unknown customer'
      : order.clientName.trim();
  return '${order.orderNo} - $client - $date';
}

String _friendlyError(String message) {
  if (message.contains('Server returned an invalid response') ||
      message.contains('HTML instead of JSON') ||
      message.contains('FormatException')) {
    return 'Could not save challan. Server returned an invalid response.';
  }
  return message;
}
