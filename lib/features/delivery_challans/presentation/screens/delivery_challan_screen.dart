import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/page_container.dart';
import '../../../../core/widgets/soft_primitives.dart';
import '../../../clients/presentation/providers/clients_provider.dart';
import '../../../orders/domain/order_entry.dart';
import '../../../orders/presentation/providers/orders_provider.dart';
import '../../data/delivery_challan_repository.dart';
import '../../domain/delivery_challan.dart';
import '../providers/delivery_challan_provider.dart';

class DeliveryChallanScreen extends StatefulWidget {
  const DeliveryChallanScreen({super.key});

  static Future<void> openEditorForOrder(
    BuildContext context,
    OrderEntry order,
  ) {
    return _showChallanEditor(context, initialOrder: order);
  }

  @override
  State<DeliveryChallanScreen> createState() => _DeliveryChallanScreenState();
}

Future<void> _showChallanEditor(
  BuildContext context, {
  DeliveryChallan? challan,
  DeliveryChallan? sourceForDuplicate,
  OrderEntry? initialOrder,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: math.min(MediaQuery.of(context).size.width - 48, 980),
        height: math.min(MediaQuery.of(context).size.height - 48, 760),
        child: _ChallanEditor(
          challan: challan,
          sourceForDuplicate: sourceForDuplicate,
          initialOrder: initialOrder,
          onPrint: (saved) {
            if (context.mounted) {
              _openPrintPreviewFromContext(context, saved);
            }
          },
        ),
      ),
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

class _DeliveryChallanScreenState extends State<DeliveryChallanScreen> {
  final TextEditingController _searchController = TextEditingController();

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
            onCreate: () => _openEditor(context),
            onEditProfile: () => _openCompanyProfile(context),
          ),
          const SizedBox(height: 16),
          _Filters(
            searchController: _searchController,
            status: provider.statusFilter,
            orderFilterId: provider.orderFilterId,
            onSearch: provider.setSearchQuery,
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
                  ? _EmptyState(onCreate: () => _openEditor(context))
                  : _ChallanTable(
                      challans: provider.challans,
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
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor(
    BuildContext context, {
    DeliveryChallan? challan,
    bool duplicate = false,
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
    await provider.cancelChallan(challan.id);
  }

  Future<void> _delete(BuildContext context, DeliveryChallan challan) async {
    await context.read<DeliveryChallanProvider>().deleteChallan(challan.id);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onCreate, required this.onEditProfile});

  final VoidCallback onCreate;
  final VoidCallback onEditProfile;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Delivery Challan',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: SoftErpTheme.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Create, issue, print, and manage order-linked delivery documents.',
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
        const SizedBox(width: 10),
        AppButton(
          label: 'Create Challan',
          icon: Icons.add_rounded,
          onPressed: onCreate,
        ),
      ],
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.searchController,
    required this.status,
    required this.orderFilterId,
    required this.onSearch,
    required this.onStatusChanged,
    required this.onClearOrderFilter,
  });

  final TextEditingController searchController;
  final DeliveryChallanStatus? status;
  final int? orderFilterId;
  final ValueChanged<String> onSearch;
  final ValueChanged<DeliveryChallanStatus?> onStatusChanged;
  final VoidCallback onClearOrderFilter;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: searchController,
              onSubmitted: onSearch,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: 'Search challan number, order number, or customer',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: SoftErpTheme.border),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (orderFilterId != null) ...[
            InputChip(
              label: Text('Order #$orderFilterId'),
              onDeleted: onClearOrderFilter,
            ),
            const SizedBox(width: 12),
          ],
          SegmentedButton<DeliveryChallanStatus?>(
            segments: const [
              ButtonSegment(value: null, label: Text('All')),
              ButtonSegment(
                value: DeliveryChallanStatus.draft,
                label: Text('Draft'),
              ),
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
          ),
        ],
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
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF7F8FC)),
        columns: const [
          DataColumn(label: Text('Challan No.')),
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Order No.')),
          DataColumn(label: Text('Customer')),
          DataColumn(label: Text('Items')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: challans
            .map(
              (challan) => DataRow(
                cells: [
                  DataCell(Text(challan.challanNo)),
                  DataCell(Text(_date(challan.date))),
                  DataCell(
                    Text(challan.orderNo.isEmpty ? '-' : challan.orderNo),
                  ),
                  DataCell(
                    Text(
                      challan.customerName.isEmpty ? '-' : challan.customerName,
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onCreate});

  final VoidCallback onCreate;

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
          const Text('No delivery challans yet'),
          const SizedBox(height: 14),
          AppButton(
            label: 'Create Challan',
            icon: Icons.add_rounded,
            onPressed: onCreate,
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
    required this.onPrint,
  });

  final DeliveryChallan? challan;
  final DeliveryChallan? sourceForDuplicate;
  final OrderEntry? initialOrder;
  final ValueChanged<DeliveryChallan> onPrint;

  @override
  State<_ChallanEditor> createState() => _ChallanEditorState();
}

class _ChallanEditorState extends State<_ChallanEditor> {
  late final TextEditingController _orderSearchController;
  late final TextEditingController _dateController;
  late final TextEditingController _customerController;
  late final TextEditingController _gstinController;
  late final TextEditingController _notesController;
  late List<_ItemDraft> _items;
  OrderEntry? _selectedOrder;
  String? _validationError;

  DeliveryChallan? get _source => widget.challan ?? widget.sourceForDuplicate;
  bool get _editingExisting => widget.challan != null;
  bool get _canEdit => widget.challan?.isDraft ?? true;
  _OrderItemOption? get _selectedOrderOption => _selectedOrder == null
      ? null
      : _OrderItemOption.fromOrder(_selectedOrder!);

  OrderEntry? _findOrder(int? orderId) {
    if (orderId == null) {
      return null;
    }
    for (final order in context.read<OrdersProvider>().orders) {
      if (order.id == orderId) {
        return order;
      }
    }
    return null;
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
    final order = _selectedOrder;
    if (order == null) {
      return;
    }
    _customerController.text = order.clientName;
    _gstinController.text = _gstinForOrder(order);
  }

  @override
  void initState() {
    super.initState();
    final source = _source;
    _selectedOrder = widget.initialOrder ?? _findOrder(source?.orderId);
    _orderSearchController = TextEditingController();
    _dateController = TextEditingController(
      text: _date(source?.date ?? DateTime.now()),
    );
    _customerController = TextEditingController(
      text: source?.customerName ?? '',
    );
    _gstinController = TextEditingController(text: source?.customerGstin ?? '');
    _notesController = TextEditingController(text: source?.notes ?? '');
    _items = (source?.items.isNotEmpty ?? false)
        ? source!.items.map(_ItemDraft.fromItem).toList()
        : [_ItemDraft.fromOrderOption(_selectedOrderOption)];
    _applySelectedOrderSnapshots();
  }

  @override
  void dispose() {
    _orderSearchController.dispose();
    _dateController.dispose();
    _customerController.dispose();
    _gstinController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 18, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _editingExisting
                      ? 'Edit Delivery Challan'
                      : 'Create Delivery Challan',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _challanNumberDisplay()),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field('Date', _dateController, enabled: _canEdit),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _orderSelector(context),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        'Customer name / M/s',
                        _customerController,
                        enabled: false,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        'Customer GSTIN',
                        _gstinController,
                        enabled: false,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _ItemsEditor(
                  enabled: _canEdit,
                  items: _items,
                  orderOption: _selectedOrderOption,
                  onChanged: () => setState(() {
                    _validationError = null;
                  }),
                ),
                const SizedBox(height: 14),
                _field(
                  'Notes',
                  _notesController,
                  enabled: _canEdit,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              if (_validationError != null || provider.errorMessage != null)
                Expanded(
                  child: _ErrorBanner(
                    message: _validationError ?? provider.errorMessage!,
                  ),
                )
              else
                const Spacer(),
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
                        await provider.cancelChallan(widget.challan!.id);
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
                label: 'Issue Challan',
                icon: Icons.verified_outlined,
                isLoading: provider.isSaving,
                onPressed: _canEdit ? _issue : null,
              ),
            ],
          ),
        ),
      ],
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

  Widget _challanNumberDisplay() {
    final value =
        _editingExisting && (widget.challan?.challanNo.isNotEmpty ?? false)
        ? widget.challan!.challanNo
        : 'Will be generated on save';
    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Challan No.',
        filled: true,
        fillColor: const Color(0xFFF7F8FC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: Text(
        value,
        style: TextStyle(
          color: _editingExisting
              ? SoftErpTheme.textPrimary
              : SoftErpTheme.textSecondary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _orderSelector(BuildContext context) {
    final orders = context.watch<OrdersProvider>().orders;
    final query = _orderSearchController.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? orders
        : orders
              .where(
                (order) =>
                    order.orderNo.toLowerCase().contains(query) ||
                    order.clientName.toLowerCase().contains(query) ||
                    order.itemName.toLowerCase().contains(query),
              )
              .toList(growable: false);
    final selectedOrderStillVisible =
        _selectedOrder == null ||
        filtered.any((order) => order.id == _selectedOrder!.id);
    final dropdownOrders = selectedOrderStillVisible
        ? filtered
        : <OrderEntry>[_selectedOrder!, ...filtered];

    return SoftSurface(
      padding: const EdgeInsets.all(12),
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _orderSearchController,
                  enabled: _canEdit,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'Search orders',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<int>(
                  key: ValueKey<int?>(_selectedOrder?.id),
                  initialValue: _selectedOrder?.id,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Select order',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  items: dropdownOrders
                      .map(
                        (order) => DropdownMenuItem<int>(
                          value: order.id,
                          child: Text(
                            _orderOptionLabel(order),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _canEdit
                      ? (value) {
                          OrderEntry? selected;
                          for (final order in orders) {
                            if (order.id == value) {
                              selected = order;
                              break;
                            }
                          }
                          setState(() {
                            _selectedOrder = selected;
                            _validationError = null;
                            _items = [
                              _ItemDraft.fromOrderOption(_selectedOrderOption),
                            ];
                            _applySelectedOrderSnapshots();
                          });
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  DeliveryChallanDraftInput _input() {
    return DeliveryChallanDraftInput(
      orderId: _selectedOrder?.id ?? _source?.orderId ?? 0,
      date: DateTime.tryParse(_dateController.text) ?? DateTime.now(),
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
    if ((_selectedOrder?.id ?? _source?.orderId ?? 0) <= 0) {
      setState(() {
        _validationError = 'Select an order before saving challan.';
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
    if (input.orderId <= 0) {
      setState(() {
        _validationError = 'Select an order before issuing challan.';
      });
      return;
    }
    if (input.items.isEmpty) {
      setState(() {
        _validationError = 'Add at least one line item before issuing challan.';
      });
      return;
    }
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
    setState(() {
      _validationError = null;
    });
    final saved = _editingExisting
        ? await provider.updateChallan(widget.challan!.id, input)
        : await provider.createChallan(input);
    if (saved == null) {
      return;
    }
    await provider.issueChallan(saved.id);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _ItemsEditor extends StatelessWidget {
  const _ItemsEditor({
    required this.items,
    required this.enabled,
    required this.orderOption,
    required this.onChanged,
  });

  final List<_ItemDraft> items;
  final bool enabled;
  final _OrderItemOption? orderOption;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SoftSurface(
      padding: const EdgeInsets.all(12),
      elevated: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Line items',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              TextButton.icon(
                onPressed: enabled && orderOption != null
                    ? () {
                        items.add(_ItemDraft.fromOrderOption(null));
                        onChanged();
                      }
                    : null,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add row'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (orderOption == null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Select an order first.',
                style: TextStyle(color: SoftErpTheme.textSecondary),
              ),
            ),
          ],
          for (final entry in items.asMap().entries) ...[
            Row(
              children: [
                SizedBox(width: 28, child: Text('${entry.key + 1}.')),
                Expanded(
                  flex: 5,
                  child: DropdownButtonFormField<int>(
                    key: ValueKey<String>(
                      '${entry.key}-${entry.value.orderItemId}-${orderOption?.orderItemId}',
                    ),
                    initialValue: entry.value.orderItemId,
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
                    items: [
                      if (orderOption != null)
                        DropdownMenuItem<int>(
                          value: orderOption!.orderItemId,
                          child: Text(
                            orderOption!.label,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: enabled && orderOption != null
                        ? (value) {
                            entry.value.applyOrderOption(orderOption);
                            onChanged();
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _readonlyItemField(entry.value.hsnCode, 'HSN Code'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _itemField(
                    entry.value.quantityPcs,
                    'Qty / Pcs',
                    enabled && orderOption != null,
                    (value) => entry.value.quantityPcs = value,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _itemField(
                    entry.value.weight,
                    'Weight',
                    enabled && orderOption != null,
                    (value) => entry.value.weight = value,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove row',
                  onPressed: enabled && items.length > 1
                      ? () {
                          items.removeAt(entry.key);
                          onChanged();
                        }
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
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
    this.itemId,
    this.particulars = '',
    this.hsnCode = '',
    this.quantityPcs = '',
    this.weight = '',
  });

  int? orderItemId;
  int? itemId;
  String particulars;
  String hsnCode;
  String quantityPcs;
  String weight;

  factory _ItemDraft.fromOrderOption(_OrderItemOption? option) {
    return _ItemDraft(
      orderItemId: option?.orderItemId,
      itemId: option?.itemId,
      particulars: option?.particulars ?? '',
      hsnCode: option?.hsnCode ?? '',
    );
  }

  factory _ItemDraft.fromItem(DeliveryChallanItem item) {
    return _ItemDraft(
      orderItemId: item.orderItemId,
      itemId: item.itemId,
      particulars: item.particulars,
      hsnCode: item.hsnCode,
      quantityPcs: item.quantityPcs,
      weight: item.weight,
    );
  }

  void applyOrderOption(_OrderItemOption? option) {
    orderItemId = option?.orderItemId;
    itemId = option?.itemId;
    particulars = option?.particulars ?? '';
    hsnCode = option?.hsnCode ?? '';
  }

  DeliveryChallanItem toItem(int lineNo) {
    return DeliveryChallanItem(
      id: 0,
      orderItemId: orderItemId,
      itemId: itemId,
      lineNo: lineNo,
      particulars: particulars,
      hsnCode: hsnCode,
      quantityPcs: quantityPcs,
      weight: weight,
    );
  }
}

class _OrderItemOption {
  const _OrderItemOption({
    required this.orderItemId,
    required this.itemId,
    required this.particulars,
    required this.hsnCode,
    required this.quantity,
  });

  final int orderItemId;
  final int itemId;
  final String particulars;
  final String hsnCode;
  final int quantity;

  factory _OrderItemOption.fromOrder(OrderEntry order) {
    final variation = order.variationPathLabel.trim();
    final particulars = variation.isEmpty
        ? order.itemName.trim()
        : '${order.itemName.trim()} - $variation';
    return _OrderItemOption(
      orderItemId: order.id,
      itemId: order.itemId,
      particulars: particulars,
      hsnCode: '',
      quantity: order.quantity,
    );
  }

  String get label {
    final qty = quantity > 0 ? ' • Ordered $quantity' : '';
    return '$particulars$qty';
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

class _PrintPreview extends StatelessWidget {
  const _PrintPreview({required this.challan});

  final DeliveryChallan challan;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DeliveryChallanProvider>();
    final profile =
        challan.companyProfileSnapshot ??
        provider.companyProfile ??
        CompanyProfile.empty();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Print Preview',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              AppButton(
                label: 'Print',
                icon: Icons.print_outlined,
                onPressed: () async {
                  await _launchPrintHtml(challan, profile);
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
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: _ChallanDocument(challan: challan, profile: profile),
            ),
          ),
        ),
      ],
    );
  }
}

class _ChallanDocument extends StatelessWidget {
  const _ChallanDocument({required this.challan, required this.profile});

  final DeliveryChallan challan;
  final CompanyProfile profile;

  @override
  Widget build(BuildContext context) {
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
                      const Expanded(
                        flex: 2,
                        child: Text(
                          'DELIVERY CHALLAN',
                          textAlign: TextAlign.center,
                          style: TextStyle(
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
                          Text('M/s: ${challan.customerName}'),
                          const SizedBox(height: 8),
                          Text('GSTIN: ${challan.customerGstin}'),
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
<div class="pad"><div class="top"><div></div><div class="title">DELIVERY CHALLAN</div><div class="mobile">${profile.mobile.isEmpty ? '' : 'Mobile: ${e(profile.mobile)}'}</div></div>
<div class="company">${e(profile.companyName)}</div><div class="center">${e(profile.businessDescription)}</div><div class="center">${e(profile.address)}</div></div>
<div class="grid"><div><p>M/s: ${e(challan.customerName)}</p><p>GSTIN: ${e(challan.customerGstin)}</p></div><div><p>Challan No.: ${e(challan.challanNo)}</p><p>Date: ${_date(challan.date)}</p></div></div>
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
