import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

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
import '../../../items/presentation/providers/items_provider.dart';
import '../../../orders/domain/order_entry.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../../vendors/presentation/providers/vendors_provider.dart';
import '../../data/delivery_challan_repository.dart';
import '../../domain/challan_template.dart';
import '../../domain/delivery_challan.dart';
import '../providers/delivery_challan_provider.dart';
import 'challan_template_mapping_screen.dart';

const MethodChannel _nativePrintingChannel = MethodChannel(
  'paper/native_printing',
);

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
  return showErpFormDialog<void>(
    context,
    maxWidth: 980,
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();
    return PageContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            onCreateDelivery: () => _openEditor(context),
            onCreateReception: () =>
                _openEditor(context, initialType: ChallanType.reception),
            onEditProfile: () => _openCompanyProfile(context),
            onOpenTemplates: () => setState(() => _showTemplates = true),
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
              type: provider.typeFilter,
              status: provider.statusFilter,
              orderFilterId: provider.orderFilterId,
              onSearch: provider.setSearchQuery,
              onTypeChanged: provider.setTypeFilter,
              onStatusChanged: provider.setStatusFilter,
              onClearOrderFilter: () => provider.setOrderFilter(null),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SoftSurface(
                clipContent: true,
                padding: EdgeInsets.zero,
                child: provider.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : provider.challans.isEmpty
                    ? _EmptyState(
                        onCreateDelivery: () => _openEditor(context),
                        onCreateReception: () => _openEditor(
                          context,
                          initialType: ChallanType.reception,
                        ),
                      )
                    : _ChallanTable(
                        challans: provider.challans,
                        onOpen: (challan) =>
                            _openEditor(context, challan: challan),
                        onPrint: (challan) =>
                            _openPrintPreview(context, challan),
                        onDuplicate: (challan) => _openEditor(
                          context,
                          challan: challan,
                          duplicate: true,
                        ),
                        onCancel: (challan) => _cancel(context, challan),
                        onDelete: (challan) => _delete(context, challan),
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
    if (cancelled != null && context.mounted) {
      await context.read<InventoryProvider>().refresh();
    }
  }

  Future<void> _delete(BuildContext context, DeliveryChallan challan) async {
    await context.read<DeliveryChallanProvider>().deleteChallan(challan.id);
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onCreateDelivery,
    required this.onCreateReception,
    required this.onEditProfile,
    required this.onOpenTemplates,
  });

  final VoidCallback onCreateDelivery;
  final VoidCallback onCreateReception;
  final VoidCallback onEditProfile;
  final VoidCallback onOpenTemplates;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 320, maxWidth: 680),
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
                'Manage outbound delivery and inbound reception documents from one hub.',
                style: TextStyle(color: SoftErpTheme.textSecondary),
              ),
            ],
          ),
        ),
        AppButton(
          label: 'Company Profile',
          icon: Icons.apartment_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: onEditProfile,
        ),
        AppButton(
          label: 'Templates',
          icon: Icons.dashboard_customize_outlined,
          variant: AppButtonVariant.secondary,
          onPressed: onOpenTemplates,
        ),
        AppButton(
          label: 'Create Reception',
          icon: Icons.south_west_rounded,
          variant: AppButtonVariant.secondary,
          onPressed: onCreateReception,
        ),
        AppButton(
          label: 'Create Delivery',
          icon: Icons.north_east_rounded,
          onPressed: onCreateDelivery,
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.searchController,
    required this.type,
    required this.status,
    required this.orderFilterId,
    required this.onSearch,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onClearOrderFilter,
  });

  final TextEditingController searchController;
  final ChallanType? type;
  final DeliveryChallanStatus? status;
  final int? orderFilterId;
  final ValueChanged<String> onSearch;
  final ValueChanged<ChallanType?> onTypeChanged;
  final ValueChanged<DeliveryChallanStatus?> onStatusChanged;
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
    final typeFilter = SegmentedButton<ChallanType?>(
      segments: const [
        ButtonSegment(value: null, label: Text('All')),
        ButtonSegment(value: ChallanType.reception, label: Text('Reception')),
        ButtonSegment(value: ChallanType.delivery, label: Text('Delivery')),
      ],
      selected: {type},
      onSelectionChanged: (value) => onTypeChanged(value.first),
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
              typeFilter,
              if (orderFilterId != null)
                InputChip(
                  label: Text('Order #$orderFilterId'),
                  onDeleted: onClearOrderFilter,
                ),
              statusFilter,
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

class _ChallanTable extends StatelessWidget {
  const _ChallanTable({
    required this.challans,
    required this.onOpen,
    required this.onPrint,
    required this.onDuplicate,
    required this.onCancel,
    required this.onDelete,
  });

  final List<DeliveryChallan> challans;
  final ValueChanged<DeliveryChallan> onOpen;
  final ValueChanged<DeliveryChallan> onPrint;
  final ValueChanged<DeliveryChallan> onDuplicate;
  final ValueChanged<DeliveryChallan> onCancel;
  final ValueChanged<DeliveryChallan> onDelete;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 1120),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF7F8FC)),
          columns: const [
            DataColumn(label: Text('Type')),
            DataColumn(label: Text('Challan No.')),
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Source')),
            DataColumn(label: Text('Party')),
            DataColumn(label: Text('Items')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: challans
              .map(
                (challan) => DataRow(
                  cells: [
                    DataCell(_TypePill(type: challan.type)),
                    DataCell(Text(challan.challanNo)),
                    DataCell(Text(_date(challan.date))),
                    DataCell(
                      Text(
                        challan.isDelivery
                            ? (challan.orderNo.isEmpty ? '-' : challan.orderNo)
                            : (challan.sourceReference.isEmpty
                                  ? '-'
                                  : challan.sourceReference),
                      ),
                    ),
                    DataCell(
                      Text(
                        challan.isDelivery
                            ? (challan.customerName.isEmpty
                                  ? '-'
                                  : challan.customerName)
                            : (challan.vendorName.isEmpty
                                  ? '-'
                                  : challan.vendorName),
                      ),
                    ),
                    DataCell(Text('${challan.itemsCount}')),
                    DataCell(_StatusPill(status: challan.status)),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SoftIconButton(
                            icon: Icons.edit_outlined,
                            tooltip: 'View/Edit',
                            onTap: () => onOpen(challan),
                          ),
                          const SizedBox(width: 6),
                          SoftIconButton(
                            icon: Icons.print_outlined,
                            tooltip: 'Print',
                            onTap: () => onPrint(challan),
                          ),
                          const SizedBox(width: 6),
                          SoftIconButton(
                            icon: Icons.copy_outlined,
                            tooltip: 'Duplicate',
                            onTap: () => onDuplicate(challan),
                          ),
                          const SizedBox(width: 6),
                          SoftIconButton(
                            icon: Icons.block_outlined,
                            tooltip: 'Cancel',
                            onTap: challan.isCancelled
                                ? null
                                : () => onCancel(challan),
                          ),
                          const SizedBox(width: 6),
                          SoftIconButton(
                            icon: Icons.delete_outline,
                            tooltip: 'Delete draft',
                            onTap: challan.isDraft
                                ? () => onDelete(challan)
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
        ),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.onCreateDelivery,
    required this.onCreateReception,
  });

  final VoidCallback onCreateDelivery;
  final VoidCallback onCreateReception;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.description_outlined,
            size: 48,
            color: SoftErpTheme.textSecondary,
          ),
          const SizedBox(height: 12),
          const Text('No challans yet'),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            alignment: WrapAlignment.center,
            children: [
              AppButton(
                label: 'Create Reception',
                icon: Icons.south_west_rounded,
                variant: AppButtonVariant.secondary,
                onPressed: onCreateReception,
              ),
              AppButton(
                label: 'Create Delivery',
                icon: Icons.north_east_rounded,
                onPressed: onCreateDelivery,
              ),
            ],
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
  late final TextEditingController _orderSearchController;
  late final FocusNode _orderSearchFocusNode;
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
  String _debouncedOrderQuery = '';
  Timer? _orderSearchDebounce;
  List<CompletedProductionRun> _completedProductionRuns =
      const <CompletedProductionRun>[];

  DeliveryChallan? get _source => widget.challan ?? widget.sourceForDuplicate;
  bool get _editingExisting => widget.challan != null;
  bool get _canEdit => widget.challan?.isDraft ?? true;
  bool get _isReception => _selectedType == ChallanType.reception;
  OrderEntry? get _primarySelectedOrder =>
      _selectedOrders.isEmpty ? null : _selectedOrders.first;
  List<_OrderItemOption> get _selectedOrderOptions =>
      _selectedOrders.map(_OrderItemOption.fromOrder).toList(growable: false);

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
      _customerController.clear();
      _gstinController.clear();
      return;
    }
    _customerController.text = order.clientName;
    _gstinController.text = _gstinForOrder(order);
  }

  List<OrderEntry> _eligibleOrders() {
    final clientId = _primarySelectedOrder?.clientId;
    return context
        .read<OrdersProvider>()
        .orders
        .where((order) {
          if (order.status == OrderStatus.completed) {
            return false;
          }
          if (_selectedOrders.any((selected) => selected.id == order.id)) {
            return false;
          }
          if (clientId != null && order.clientId != clientId) {
            return false;
          }
          return true;
        })
        .toList(growable: false);
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

  void _handleOrderSearchChanged() {
    _orderSearchDebounce?.cancel();
    _orderSearchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _debouncedOrderQuery = _orderSearchController.text.trim().toLowerCase();
      });
    });
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
    _orderSearchController = TextEditingController();
    _orderSearchFocusNode = FocusNode();
    _orderSearchController.addListener(_handleOrderSearchChanged);
    _dateController = TextEditingController(
      text: _date(source?.date ?? DateTime.now()),
    );
    _customerController = TextEditingController(
      text: source?.customerName ?? '',
    );
    _gstinController = TextEditingController(text: source?.customerGstin ?? '');
    _locationController = TextEditingController(
      text: source?.location ?? widget.initialLocation ?? '',
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCompletedProductionRuns();
    });
  }

  @override
  void dispose() {
    _challanNumberController.dispose();
    _orderSearchController.removeListener(_handleOrderSearchChanged);
    _orderSearchController.dispose();
    _orderSearchDebounce?.cancel();
    _orderSearchFocusNode.dispose();
    _dateController.dispose();
    _customerController.dispose();
    _gstinController.dispose();
    _locationController.dispose();
    _sourceReferenceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadCompletedProductionRuns() async {
    final runs = await context
        .read<DeliveryChallanProvider>()
        .loadCompletedProductionRuns(limit: 100);
    if (!mounted) {
      return;
    }
    setState(() {
      _completedProductionRuns = runs;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();
    final editorTitle = _editingExisting
        ? (_isReception ? 'Edit Reception Challan' : 'Edit Delivery Challan')
        : (_isReception
              ? 'Create Reception Challan'
              : 'Create Delivery Challan');
    final issueLabel = _isReception ? 'Issue Reception' : 'Issue Delivery';
    final errorText = _validationError ?? provider.errorMessage;
    final challanNumberWarningText =
        provider.warningMessage ?? _manualChallanWarningText();
    return ErpFormScaffold(
      title: editorTitle,
      subtitle: _isReception
          ? 'Record inbound stock against a vendor-backed reception document before it reaches inventory.'
          : 'Prepare the outbound document linked to an order before dispatch stock leaves the warehouse.',
      errorBanner: errorText == null
          ? null
          : ErpFormMessageBanner(message: errorText, isError: true),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ErpDialogSectionCard(
            title: 'Document Details',
            subtitle:
                'Choose the challan type, source document, date, and warehouse location first.',
            child: Column(
              children: [
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
                const SizedBox(height: 12),
                _typeSelector(),
                const SizedBox(height: 12),
                if (_isReception)
                  _vendorSelector(context)
                else
                  _orderSelector(context),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        _isReception
                            ? 'Vendor / Source'
                            : 'Customer name / M/s',
                        _customerController,
                        enabled: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        _isReception ? 'Vendor GSTIN' : 'Customer GSTIN',
                        _gstinController,
                        enabled: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        'Location',
                        _locationController,
                        enabled: _canEdit,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        _isReception
                            ? 'Supplier Ref / GRN / Invoice'
                            : 'Dispatch Reference',
                        _sourceReferenceController,
                        enabled: _canEdit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ErpDialogSectionCard(
            title: _isReception
                ? 'Reception Line Items'
                : 'Dispatch Line Items',
            subtitle: _isReception
                ? 'Lock each row to an exact item variation and quantity before issuing stock into the warehouse.'
                : 'Review the selected order-linked dispatch rows and quantities before issuing the challan.',
            child: _ItemsEditor(
              isReception: _isReception,
              enabled: _canEdit,
              items: _items,
              orderOptions: _selectedOrderOptions,
              productionRuns: _completedProductionRuns,
              onProductionRunPicked: (run) {
                if (_locationController.text.trim().isEmpty &&
                    run.location.trim().isNotEmpty) {
                  _locationController.text = run.location.trim();
                }
              },
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
      ),
      footer: Row(
        children: [
          const Spacer(),
          AppButton(
            label: 'Print',
            icon: Icons.print_outlined,
            variant: AppButtonVariant.secondary,
            onPressed: _source == null ? null : () => widget.onPrint(_source!),
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
                    if (cancelled != null && context.mounted) {
                      await context.read<InventoryProvider>().refresh();
                    }
                    if (context.mounted) Navigator.of(context).pop();
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

  Widget _typeSelector() {
    return SegmentedButton<ChallanType>(
      segments: const [
        ButtonSegment(
          value: ChallanType.delivery,
          label: Text('Delivery'),
          icon: Icon(Icons.arrow_upward_rounded),
        ),
        ButtonSegment(
          value: ChallanType.reception,
          label: Text('Reception'),
          icon: Icon(Icons.arrow_downward_rounded),
        ),
      ],
      selected: {_selectedType},
      onSelectionChanged: !_canEdit
          ? null
          : (selection) {
              final next = selection.first;
              setState(() {
                _selectedType = next;
                _validationError = null;
                _items = [_ItemDraft.blank(1)];
                if (next == ChallanType.delivery) {
                  _selectedVendorId = null;
                  _sourceReferenceController.text = '';
                  _applySelectedOrderSnapshots();
                } else {
                  _selectedOrders = <OrderEntry>[];
                  _orderSearchController.clear();
                  _customerController.clear();
                  _gstinController.clear();
                }
              });
            },
    );
  }

  Widget _orderSelector(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(12),
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Orders',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          RawAutocomplete<OrderEntry>(
            textEditingController: _orderSearchController,
            focusNode: _orderSearchFocusNode,
            displayStringForOption: _orderOptionLabel,
            optionsBuilder: (textEditingValue) {
              final eligible = _eligibleOrders();
              if (_debouncedOrderQuery.isEmpty) {
                return eligible.take(12);
              }
              return eligible
                  .where((order) {
                    return _orderOptionLabel(
                      order,
                    ).toLowerCase().contains(_debouncedOrderQuery);
                  })
                  .take(12);
            },
            onSelected: (order) {
              if (!_isOrderEligible(order)) {
                setState(() {
                  _validationError =
                      'The selected order is no longer eligible for this challan.';
                });
                return;
              }
              setState(() {
                _selectedOrders = [..._selectedOrders, order];
                _validationError = null;
                _debouncedOrderQuery = '';
                _orderSearchController.clear();
                _resetDeliveryItemsForSelectedOrders();
                _applySelectedOrderSnapshots();
              });
              _orderSearchFocusNode.requestFocus();
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: _canEdit,
                    decoration: InputDecoration(
                      labelText: 'Find Order...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onSubmitted: (_) => onFieldSubmitted(),
                  );
                },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 720,
                      maxHeight: 280,
                    ),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shrinkWrap: true,
                      children: options
                          .map(
                            (order) => ListTile(
                              dense: true,
                              title: Text(_orderOptionLabel(order)),
                              subtitle: Text(order.clientName),
                              onTap: () => onSelected(order),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ),
              );
            },
          ),
          if (_selectedOrders.isNotEmpty) ...[
            const SizedBox(height: 12),
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
                                _selectedOrders = _selectedOrders
                                    .where(
                                      (selected) => selected.id != order.id,
                                    )
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
            Text(
              'Client locked to ${_selectedOrders.first.clientName} for this challan.',
              style: const TextStyle(color: SoftErpTheme.textSecondary),
            ),
          ],
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

  DeliveryChallanDraftInput _input() {
    final orderIds = _selectedType == ChallanType.delivery
        ? _selectedOrders.map((order) => order.id).toList(growable: false)
        : const <int>[];
    return DeliveryChallanDraftInput(
      type: _selectedType,
      challanNo: _challanNumberController.text.trim(),
      orderId: _selectedType == ChallanType.delivery
          ? (orderIds.isEmpty ? (_source?.orderId ?? 0) : orderIds.first)
          : 0,
      orderIds: orderIds,
      vendorId: _selectedType == ChallanType.reception
          ? (_selectedVendorId ?? _source?.vendorId ?? 0)
          : 0,
      date: DateTime.tryParse(_dateController.text) ?? DateTime.now(),
      location: _locationController.text,
      sourceReference: _sourceReferenceController.text,
      notes: _notesController.text,
      items: _items
          .asMap()
          .entries
          .map((entry) => entry.value.toItem(entry.key + 1))
          .where(
            (item) =>
                item.orderItemId != null ||
                item.itemId != null ||
                item.quantityPcs.trim().isNotEmpty ||
                item.weight.trim().isNotEmpty,
          )
          .toList(growable: false),
    );
  }

  Future<void> _save() async {
    final provider = context.read<DeliveryChallanProvider>();
    setState(() {
      _validationError = null;
    });
    if (_isReception && (_selectedVendorId ?? _source?.vendorId ?? 0) <= 0) {
      setState(() {
        _validationError = 'Select a vendor before saving challan.';
      });
      return;
    }
    if (!_isReception &&
        _selectedOrders.isEmpty &&
        !_items.any((item) => item.productionRunId != null)) {
      setState(() {
        _validationError =
            'Select at least one order or pull a completed production run before saving challan.';
      });
      return;
    }
    final saved = _editingExisting
        ? await provider.updateChallan(widget.challan!.id, _input())
        : await provider.createChallan(_input());
    if (saved != null && mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _issue() async {
    final provider = context.read<DeliveryChallanProvider>();
    final input = _input();
    if (_selectedType == ChallanType.delivery &&
        input.orderIds.isEmpty &&
        !input.items.any((item) => item.productionRunId != null)) {
      setState(() {
        _validationError =
            'Select at least one order or pull a completed production run before saving challan.';
      });
      return;
    }
    if (_selectedType == ChallanType.reception && input.vendorId <= 0) {
      setState(() {
        _validationError = 'Select a vendor before issuing reception challan.';
      });
      return;
    }
    if (input.location.trim().isEmpty) {
      setState(() {
        _validationError = 'Enter a location before issuing challan.';
      });
      return;
    }
    if (input.items.isEmpty) {
      setState(() {
        _validationError = 'Add at least one line item before issuing challan.';
      });
      return;
    }
    if (_selectedType == ChallanType.delivery) {
      if (input.items.any(
        (item) =>
            (item.orderItemId == null && item.productionRunId == null) ||
            (item.quantityPcs.trim().isEmpty && item.weight.trim().isEmpty),
      )) {
        setState(() {
          _validationError =
              'Select an order item and enter Qty / Pcs or Weight for every row.';
        });
        return;
      }
    } else if (input.items.any(
      (item) =>
          item.itemId == null ||
          item.quantityPcs.trim().isEmpty ||
          double.tryParse(item.quantityPcs.trim()) == null ||
          double.parse(item.quantityPcs.trim()) <= 0,
    )) {
      setState(() {
        _validationError =
            'Select an exact item variation and enter quantity for every reception row.';
      });
      return;
    }
    setState(() {
      _validationError = null;
    });
    final inventoryProvider = context.read<InventoryProvider>();
    final saved = _editingExisting
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

class _ItemsEditor extends StatelessWidget {
  const _ItemsEditor({
    required this.isReception,
    required this.items,
    required this.enabled,
    required this.orderOptions,
    required this.productionRuns,
    required this.onProductionRunPicked,
    required this.onChanged,
  });

  final bool isReception;
  final List<_ItemDraft> items;
  final bool enabled;
  final List<_OrderItemOption> orderOptions;
  final List<CompletedProductionRun> productionRuns;
  final ValueChanged<CompletedProductionRun> onProductionRunPicked;
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
                onPressed: enabled && (isReception || orderOptions.isNotEmpty)
                    ? () {
                        items.add(
                          !isReception && orderOptions.isNotEmpty
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
          if (!isReception && orderOptions.isEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Select at least one order first.',
                style: TextStyle(color: SoftErpTheme.textSecondary),
              ),
            ),
          ],
          for (final entry in items.asMap().entries) ...[
            isReception
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

  Widget _buildDeliveryRow(BuildContext context, int index, _ItemDraft draft) {
    return Column(
      children: [
        Row(
          children: [
            const SizedBox(width: 28),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: !enabled
                          ? null
                          : () async {
                              final selected =
                                  await showSearchableSelectDialog<int>(
                                    context: context,
                                    title: 'Pull from Production',
                                    searchHintText:
                                        'Search by run, item, or variation',
                                    options: productionRuns
                                        .map(
                                          (run) => SearchableSelectOption<int>(
                                            value: run.id,
                                            label: run.displayLabel,
                                            searchText:
                                                '${run.runCode} ${run.itemName} ${run.variationPathLabel} ${run.location}',
                                          ),
                                        )
                                        .toList(growable: false),
                                  );
                              if (selected == null) {
                                return;
                              }
                              final run = productionRuns
                                  .where((entry) => entry.id == selected.value)
                                  .firstOrNull;
                              if (run == null) {
                                return;
                              }
                              draft.applyProductionRun(run);
                              onProductionRunPicked(run);
                              onChanged();
                            },
                      icon: const Icon(Icons.factory_outlined, size: 18),
                      label: const Text('Pull from Production'),
                    ),
                    if (draft.productionRunId != null)
                      InputChip(
                        label: Text(
                          draft.productionRunLabel.trim().isEmpty
                              ? 'Run #${draft.productionRunId}'
                              : draft.productionRunLabel,
                        ),
                        onDeleted: !enabled
                            ? null
                            : () {
                                draft.clearProductionRun();
                                onChanged();
                              },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
      ],
    );
  }

  Widget _buildReceptionRow(
    BuildContext context,
    int index,
    _ItemDraft draft,
    List<ItemDefinition> availableItems,
  ) {
    final selectedItem = availableItems
        .where((item) => item.id == draft.itemId)
        .firstOrNull;
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
                  onChanged: (itemId) {
                    final item = availableItems
                        .where((candidate) => candidate.id == itemId)
                        .firstOrNull;
                    draft.applyReceptionItem(item);
                    onChanged();
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _itemField(
                  draft.quantityPcs,
                  'Qty',
                  enabled,
                  (value) => draft.quantityPcs = value,
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
          if (selectedItem != null) ...[
            const SizedBox(height: 10),
            _buildReceptionVariationPathField(
              context,
              index,
              draft,
              selectedItem,
            ),
          ],
        ],
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
                initialLeafId: draft.variationLeafNodeId,
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
          initialLeafId: draft.variationLeafNodeId,
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
    required int initialLeafId,
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
            initialValueNodeIds: initialLeafId <= 0
                ? const <int>[]
                : _valueNodeIdsForLeaf(item, initialLeafId),
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

class _ItemDraft {
  _ItemDraft({
    this.orderItemId,
    this.productionRunId,
    this.itemId,
    this.variationLeafNodeId = 0,
    this.particulars = '',
    this.hsnCode = '',
    this.variationPathLabel = '',
    this.productionRunLabel = '',
    this.quantityPcs = '',
    this.weight = '',
  });

  int? orderItemId;
  int? productionRunId;
  int? itemId;
  int variationLeafNodeId;
  String particulars;
  String hsnCode;
  String variationPathLabel;
  String productionRunLabel;
  String quantityPcs;
  String weight;

  factory _ItemDraft.blank(int lineNo) => _ItemDraft();

  factory _ItemDraft.fromOrderOption(_OrderItemOption? option) {
    return _ItemDraft(
      orderItemId: option?.orderItemId,
      productionRunId: null,
      itemId: option?.itemId,
      variationLeafNodeId: option?.variationLeafNodeId ?? 0,
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
      quantityPcs: item.quantityPcs,
      weight: item.weight,
    );
  }

  void applyOrderOption(_OrderItemOption? option) {
    orderItemId = option?.orderItemId;
    if (productionRunId == null) {
      itemId = option?.itemId;
      variationLeafNodeId = option?.variationLeafNodeId ?? 0;
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
    required this.particulars,
    required this.hsnCode,
    required this.variationPathLabel,
    required this.quantity,
  });

  final int orderItemId;
  final String orderNo;
  final int itemId;
  final int variationLeafNodeId;
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

  @override
  void initState() {
    super.initState();
    _templatesFuture = _loadMatchingTemplates();
  }

  Future<List<ChallanTemplate>> _loadMatchingTemplates() {
    final partyId = widget.challan.isReception
        ? widget.challan.vendorId
        : widget.challan.clientId;
    if (partyId == null || partyId <= 0) {
      return Future.value(const <ChallanTemplate>[]);
    }
    return context.read<DeliveryChallanProvider>().loadTemplates(
      partyType: widget.challan.isReception
          ? ChallanTemplatePartyType.vendor
          : ChallanTemplatePartyType.client,
      partyId: partyId,
      challanType: widget.challan.type,
      activeOnly: true,
    );
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
        final loadedTemplate =
            (snapshot.data ?? const <ChallanTemplate>[]).isEmpty
            ? null
            : (snapshot.data ?? const <ChallanTemplate>[]).first;
        final template = _activeTemplateOverride ?? loadedTemplate;
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
                      onPressed: () =>
                          _openTemplatePdf(context, template, 'digital'),
                    ),
                    const SizedBox(width: 8),
                    AppButton(
                      label: 'Overprint',
                      icon: Icons.print_outlined,
                      onPressed: () =>
                          _openTemplatePdf(context, template, 'overprint'),
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

  Future<void> _openTemplatePdf(
    BuildContext context,
    ChallanTemplate template,
    String mode,
  ) async {
    final provider = context.read<DeliveryChallanProvider>();
    final uri = provider.repository.templatePreviewUri(
      challanId: widget.challan.id,
      templateId: template.id,
      mode: mode,
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    await provider.recordPrint(widget.challan.id);
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
        partyId: template.partyId,
        challanType: template.challanType,
        backgroundObjectKey: template.backgroundObjectKey,
        canvasWidth: template.canvasWidth,
        canvasHeight: template.canvasHeight,
        rotationDegrees: template.rotationDegrees,
        globalOffsetXmm: template.globalOffsetXmm + deltaXmm,
        globalOffsetYmm: template.globalOffsetYmm + deltaYmm,
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
                          const SizedBox(height: 8),
                          Text('Location: ${challan.location}'),
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
                    item.particulars,
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
    'location': challan.location,
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
          '<tr><td>${e(item.particulars)}</td><td>${e(item.hsnCode)}</td><td>${e(item.quantityPcs)}</td><td>${e(item.weight)}</td></tr>',
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
<div class="grid"><div><p>$partyLabel: ${e(partyName)}</p><p>GSTIN: ${e(partyGstin)}</p><p>Location: ${e(challan.location)}</p></div><div><p>$referenceLabel: ${e(referenceValue)}</p><p>Challan No.: ${e(challan.challanNo)}</p><p>Date: ${_date(challan.date)}</p></div></div>
<table><thead><tr><th>Particulars</th><th>HSN Code</th><th>QTY. Pcs.</th><th>Weight</th></tr></thead><tbody>$rows</tbody></table>
<div class="bottom"><div><p>State Code: ${e(profile.stateCode)}</p><p>GSTIN: ${e(profile.gstin)}</p><p class="sign">Receiver's Signature</p></div><div><p>For ${e(profile.companyName)}</p><p class="sign">${e(profile.signatureLabel.isEmpty ? 'Checked by / Authorized Signatory' : profile.signatureLabel)}</p></div></div>
</div><script>setTimeout(()=>window.print(),300)</script></body></html>
''';
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
