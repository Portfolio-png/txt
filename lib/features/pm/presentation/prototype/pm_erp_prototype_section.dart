import 'package:flutter/material.dart';

import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_info_panel.dart';
import '../../../../core/widgets/app_section_title.dart';

class PMErpPrototypeSection extends StatefulWidget {
  const PMErpPrototypeSection({super.key});

  @override
  State<PMErpPrototypeSection> createState() => _PMErpPrototypeSectionState();
}

class _PMErpPrototypeSectionState extends State<PMErpPrototypeSection> {
  final List<_PMPrototypeRoute> _history = <_PMPrototypeRoute>[
    const _PMPrototypeRoute(_PMPrototypeView.dashboard),
  ];
  String _queueFilter = 'all';
  _PMControlTowerPerspective _towerPerspective =
      _PMControlTowerPerspective.promise;
  _PMControlTowerDeliveryMode _towerDeliveryMode =
      _PMControlTowerDeliveryMode.cockpit;
  late String _selectedTowerFlowId;
  String? _selectedTowerNodeId;

  final Map<String, String> _orderStatusOverrides = <String, String>{};
  final Map<String, String> _procurementStatusOverrides = <String, String>{};
  final Map<String, String> _productionStatusOverrides = <String, String>{};
  final Map<String, String> _msmeStatusOverrides = <String, String>{};
  final Set<String> _mitigatedTowerNodeIds = <String>{};
  final Set<String> _watchedTowerFlowIds = <String>{};
  final Set<String> _decidingTowerNodeIds = <String>{};
  final Set<String> _deliveringTowerNodeIds = <String>{};
  _PMMsmeDeskPresentation _msmeDeskPresentation =
      _PMMsmeDeskPresentation.familiar;
  String _msmeDeskBookFilter = 'All Books';
  String _msmeDeskActionFilter = 'All';
  final Set<String> _pinnedMsmeEntryIds = <String>{};

  _PMPrototypeRoute get _current => _history.last;
  _PMPromiseFlow? get _selectedTowerFlow => _firstWhereOrNull(
    _promiseFlows,
    (flow) => flow.id == _selectedTowerFlowId,
  );

  @override
  void initState() {
    super.initState();
    final firstFlow = _promiseFlows.first;
    _selectedTowerFlowId = firstFlow.id;
    _selectedTowerNodeId = _defaultTowerNodeId(firstFlow);
  }

  @override
  Widget build(BuildContext context) {
    final navEntries = <_PMPrototypeNavEntry>[
      const _PMPrototypeNavEntry(
        label: 'Dashboard',
        route: _PMPrototypeRoute(_PMPrototypeView.dashboard),
      ),
      const _PMPrototypeNavEntry(
        label: 'Work Queue',
        route: _PMPrototypeRoute(_PMPrototypeView.workQueue),
      ),
      const _PMPrototypeNavEntry(
        label: 'Control Tower',
        route: _PMPrototypeRoute(_PMPrototypeView.controlTower),
      ),
      const _PMPrototypeNavEntry(
        label: 'MSME Desk',
        route: _PMPrototypeRoute(_PMPrototypeView.msmeDesk),
      ),
      const _PMPrototypeNavEntry(
        label: 'Orders',
        route: _PMPrototypeRoute(_PMPrototypeView.orders),
      ),
      const _PMPrototypeNavEntry(
        label: 'Inventory',
        route: _PMPrototypeRoute(_PMPrototypeView.inventory),
      ),
      const _PMPrototypeNavEntry(
        label: 'Procurement',
        route: _PMPrototypeRoute(_PMPrototypeView.procurement),
      ),
      const _PMPrototypeNavEntry(
        label: 'Production',
        route: _PMPrototypeRoute(_PMPrototypeView.production),
      ),
      const _PMPrototypeNavEntry(
        label: 'Configurator',
        route: _PMPrototypeRoute(_PMPrototypeView.configurator),
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionTitle(
            title: 'PM ERP clickable prototype',
            subtitle:
                'Self-contained mock of core app views with internal navigation and static data only.',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF3),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFA7F3D0)),
              ),
              child: const Text(
                'Local data only',
                style: TextStyle(
                  color: Color(0xFF047857),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: navEntries
                .map(
                  (entry) => _PrototypeNavChip(
                    label: entry.label,
                    selected: _isSectionSelected(entry.route.view),
                    onTap: () => _setRoot(entry.route),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _history.length > 1 ? _goBack : null,
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('Back'),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _history
                          .map(
                            (route) => Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Text(
                                _routeLabel(route),
                                style: const TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Container(
              key: ValueKey<String>(
                '${_current.view.name}-${_current.entityId ?? 'root'}',
              ),
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 500),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: _buildCurrentView(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentView(BuildContext context) {
    switch (_current.view) {
      case _PMPrototypeView.dashboard:
        return _buildDashboardView();
      case _PMPrototypeView.workQueue:
        return _buildWorkQueueView();
      case _PMPrototypeView.controlTower:
        return _buildControlTowerView();
      case _PMPrototypeView.msmeDesk:
        return _buildMsmeDeskView();
      case _PMPrototypeView.orders:
        return _buildOrdersListView();
      case _PMPrototypeView.orderDetail:
        return _buildOrderDetailView(_current.entityId);
      case _PMPrototypeView.inventory:
        return _buildInventoryListView();
      case _PMPrototypeView.inventoryDetail:
        return _buildInventoryDetailView(_current.entityId);
      case _PMPrototypeView.procurement:
        return _buildProcurementListView();
      case _PMPrototypeView.procurementDetail:
        return _buildProcurementDetailView(_current.entityId);
      case _PMPrototypeView.production:
        return _buildProductionListView();
      case _PMPrototypeView.productionDetail:
        return _buildProductionDetailView(_current.entityId);
      case _PMPrototypeView.configurator:
        return _buildConfiguratorPreviewView();
    }
  }

  Widget _buildDashboardView() {
    final urgentTasks = _tasks.where((task) => task.priority == 'High').length;
    final blockedTasks = _tasks.where((task) => task.blocked).length;
    final openOrders = _orders
        .where((order) => _orderStatusFor(order) != 'Dispatched')
        .length;
    final pendingReceipts = _procurementRequests
        .where((request) => _procurementStatusFor(request) != 'Closed')
        .length;
    final atRiskPromises = _promiseFlows
        .where((flow) => flow.riskLevel != 'Low')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Prototype dashboard',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Click any card or row to navigate to detailed prototype views.',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _MetricCard(
              label: 'Open orders',
              value: openOrders.toString(),
              accent: const Color(0xFFDBEAFE),
              onTap: () =>
                  _pushRoute(const _PMPrototypeRoute(_PMPrototypeView.orders)),
            ),
            _MetricCard(
              label: 'Urgent tasks',
              value: urgentTasks.toString(),
              accent: const Color(0xFFFFEDD5),
              onTap: () => _pushRoute(
                const _PMPrototypeRoute(_PMPrototypeView.workQueue),
              ),
            ),
            _MetricCard(
              label: 'Blocked tasks',
              value: blockedTasks.toString(),
              accent: const Color(0xFFFEE2E2),
              onTap: () => _pushRoute(
                const _PMPrototypeRoute(_PMPrototypeView.workQueue),
              ),
            ),
            _MetricCard(
              label: 'Pending receipts',
              value: pendingReceipts.toString(),
              accent: const Color(0xFFECFEFF),
              onTap: () => _pushRoute(
                const _PMPrototypeRoute(_PMPrototypeView.procurement),
              ),
            ),
            _MetricCard(
              label: 'At-risk promises',
              value: atRiskPromises.toString(),
              accent: const Color(0xFFFFF7ED),
              onTap: () => _pushRoute(
                const _PMPrototypeRoute(_PMPrototypeView.controlTower),
              ),
            ),
            _MetricCard(
              label: 'Ledger rows',
              value: _msmeLedgerEntries.length.toString(),
              accent: const Color(0xFFEFF6FF),
              onTap: () => _pushRoute(
                const _PMPrototypeRoute(_PMPrototypeView.msmeDesk),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 980;
            final left = _buildTaskListCard(
              title: 'Work queue snapshot',
              tasks: _tasks.take(4).toList(growable: false),
            );
            final right = _buildModuleLaunchCard();

            if (isNarrow) {
              return Column(
                children: [left, const SizedBox(height: 12), right],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: right),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildWorkQueueView() {
    final filteredTasks = _tasks
        .where((task) {
          if (_queueFilter == 'today') {
            return task.due.startsWith('Today');
          }
          if (_queueFilter == 'blocked') {
            return task.blocked;
          }
          return true;
        })
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Work queue',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PrototypeNavChip(
              label: 'All',
              selected: _queueFilter == 'all',
              onTap: () => setState(() {
                _queueFilter = 'all';
              }),
            ),
            _PrototypeNavChip(
              label: 'Today',
              selected: _queueFilter == 'today',
              onTap: () => setState(() {
                _queueFilter = 'today';
              }),
            ),
            _PrototypeNavChip(
              label: 'Blocked',
              selected: _queueFilter == 'blocked',
              onTap: () => setState(() {
                _queueFilter = 'blocked';
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...filteredTasks.map(
          (task) => _PrototypeRowCard(
            title: task.title,
            subtitle:
                '${task.module} · ${task.assignee} · ${task.due} · ${task.priority}',
            status: task.blocked ? 'Blocked' : 'Ready',
            statusColor: task.blocked
                ? const Color(0xFFB91C1C)
                : const Color(0xFF047857),
            onTap: () => _openTask(task),
          ),
        ),
      ],
    );
  }

  Widget _buildControlTowerView() {
    final selectedFlow = _selectedTowerFlow;
    if (selectedFlow == null) {
      return const _PrototypeMissingState(
        title: 'Control tower unavailable',
        message: 'Prototype flow data is missing. Please reopen this section.',
      );
    }

    final selectedNode = _selectedTowerNode(selectedFlow);
    final blockedCount = _promiseFlows.fold<int>(
      0,
      (count, flow) =>
          count +
          flow.nodes
              .where((node) => _towerNodeStatus(node) == 'Blocked')
              .length,
    );
    final watchCount = _watchedTowerFlowIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: 'Promise-to-Ship Control Tower',
          subtitle:
              'Reframe the app around delivery commitments and blockers, not isolated modules.',
          actionLabel: _watchedTowerFlowIds.contains(selectedFlow.id)
              ? 'Unwatch Promise'
              : 'Watch Promise',
          onAction: () => _toggleWatch(selectedFlow.id),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                'Problem framing',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Represent: customer promises at risk. Deliver in two styles: Decision Cockpit and Intervention Board.',
                style: TextStyle(color: Color(0xFF4B5563)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PrototypeNavChip(
              label: 'By Promise',
              selected: _towerPerspective == _PMControlTowerPerspective.promise,
              onTap: () => setState(() {
                _towerPerspective = _PMControlTowerPerspective.promise;
              }),
            ),
            _PrototypeNavChip(
              label: 'By Constraint',
              selected:
                  _towerPerspective == _PMControlTowerPerspective.constraint,
              onTap: () => setState(() {
                _towerPerspective = _PMControlTowerPerspective.constraint;
              }),
            ),
            _PrototypeNavChip(
              label: 'By Time',
              selected: _towerPerspective == _PMControlTowerPerspective.time,
              onTap: () => setState(() {
                _towerPerspective = _PMControlTowerPerspective.time;
              }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PrototypeNavChip(
              label: 'Decision Cockpit',
              selected:
                  _towerDeliveryMode == _PMControlTowerDeliveryMode.cockpit,
              onTap: () => setState(() {
                _towerDeliveryMode = _PMControlTowerDeliveryMode.cockpit;
              }),
            ),
            _PrototypeNavChip(
              label: 'Intervention Board',
              selected:
                  _towerDeliveryMode ==
                  _PMControlTowerDeliveryMode.interventionBoard,
              onTap: () => setState(() {
                _towerDeliveryMode =
                    _PMControlTowerDeliveryMode.interventionBoard;
              }),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _TowerMetricPill(
              label: 'Promises at risk',
              value: _promiseFlows
                  .where((flow) => flow.riskLevel == 'High')
                  .length
                  .toString(),
            ),
            _TowerMetricPill(
              label: 'Active blockers',
              value: blockedCount.toString(),
            ),
            _TowerMetricPill(
              label: 'Watched promises',
              value: watchCount.toString(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _towerDeliveryMode == _PMControlTowerDeliveryMode.cockpit
            ? _buildTowerCockpitLayout(
                selectedFlow: selectedFlow,
                selectedNode: selectedNode,
              )
            : _buildTowerInterventionBoard(),
      ],
    );
  }

  Widget _buildTowerCockpitLayout({
    required _PMPromiseFlow selectedFlow,
    required _PMFlowNode? selectedNode,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final leftPanel = _buildTowerSelectorPanel();
        final centerPanel = _buildTowerPathPanel(selectedFlow);
        final rightPanel = _buildTowerActionPanel(
          selectedFlow: selectedFlow,
          selectedNode: selectedNode,
        );

        if (constraints.maxWidth < 1100) {
          return Column(
            children: [
              leftPanel,
              const SizedBox(height: 12),
              centerPanel,
              const SizedBox(height: 12),
              rightPanel,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: leftPanel),
            const SizedBox(width: 12),
            Expanded(flex: 4, child: centerPanel),
            const SizedBox(width: 12),
            Expanded(flex: 3, child: rightPanel),
          ],
        );
      },
    );
  }

  Widget _buildTowerSelectorPanel() {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _towerPerspective == _PMControlTowerPerspective.promise
                ? 'Promise lens'
                : _towerPerspective == _PMControlTowerPerspective.constraint
                ? 'Constraint lens'
                : 'Time lens',
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ..._buildTowerLensCards(),
        ],
      ),
    );
  }

  List<Widget> _buildTowerLensCards() {
    switch (_towerPerspective) {
      case _PMControlTowerPerspective.promise:
        return _promiseFlows
            .map(
              (flow) => _SelectablePrototypeCard(
                title: '${flow.code} · ${flow.client}',
                subtitle:
                    'Due ${flow.dueDate} · ${flow.owner} · ₹${flow.value.toStringAsFixed(0)}',
                status: flow.riskLevel,
                statusColor: _riskColor(flow.riskLevel),
                selected: flow.id == _selectedTowerFlowId,
                onTap: () => _selectTowerFlow(flow.id),
              ),
            )
            .toList(growable: false);
      case _PMControlTowerPerspective.constraint:
        return _constraintLenses
            .map(
              (lens) => _SelectablePrototypeCard(
                title: lens.title,
                subtitle: lens.summary,
                status: lens.severity,
                statusColor: _riskColor(lens.severity),
                selected:
                    lens.flowId == _selectedTowerFlowId &&
                    lens.nodeId == _selectedTowerNodeId,
                onTap: () =>
                    _selectTowerFlow(lens.flowId, preferredNodeId: lens.nodeId),
              ),
            )
            .toList(growable: false);
      case _PMControlTowerPerspective.time:
        return _timeLenses
            .map(
              (lens) => _SelectablePrototypeCard(
                title: lens.windowLabel,
                subtitle: lens.summary,
                status: lens.priority,
                statusColor: _riskColor(lens.priority),
                selected:
                    lens.flowId == _selectedTowerFlowId &&
                    lens.nodeId == _selectedTowerNodeId,
                onTap: () =>
                    _selectTowerFlow(lens.flowId, preferredNodeId: lens.nodeId),
              ),
            )
            .toList(growable: false);
    }
  }

  Widget _buildTowerPathPanel(_PMPromiseFlow flow) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dependency path',
            style: TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Track what blocks ${flow.code} from dispatch.',
            style: const TextStyle(color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List<Widget>.generate(flow.nodes.length, (index) {
                final node = flow.nodes[index];
                final isLast = index == flow.nodes.length - 1;
                return Row(
                  children: [
                    _TowerNodeCard(
                      stage: node.stage,
                      headline: node.headline,
                      status: _towerNodeStatus(node),
                      statusColor: _towerStatusColor(_towerNodeStatus(node)),
                      selected: node.id == _selectedTowerNodeId,
                      onTap: () =>
                          _selectTowerFlow(flow.id, preferredNodeId: node.id),
                    ),
                    if (!isLast)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 18,
                          color: Color(0xFF9CA3AF),
                        ),
                      ),
                  ],
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTowerActionPanel({
    required _PMPromiseFlow selectedFlow,
    required _PMFlowNode? selectedNode,
  }) {
    if (selectedNode == null) {
      return const _PrototypeMissingState(
        title: 'Select a blocker',
        message: 'Pick a node from the dependency path to inspect details.',
      );
    }

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selectedNode.headline,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            selectedNode.summary,
            style: const TextStyle(color: Color(0xFF4B5563)),
          ),
          const SizedBox(height: 12),
          AppInfoPanel(
            title: 'Selected blocker',
            rows: [
              AppInfoRow(label: 'Promise', value: selectedFlow.code),
              AppInfoRow(label: 'Stage', value: selectedNode.stage),
              AppInfoRow(
                label: 'Status',
                value: _towerNodeStatus(selectedNode),
              ),
              AppInfoRow(label: 'Owner', value: selectedNode.owner),
              AppInfoRow(label: 'ETA impact', value: selectedNode.etaImpact),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AppButton(
                label: _mitigatedTowerNodeIds.contains(selectedNode.id)
                    ? 'Undo Simulate Expedite'
                    : 'Simulate Expedite',
                icon: Icons.flash_on_outlined,
                onPressed: () => _toggleMitigation(selectedNode),
                variant: AppButtonVariant.secondary,
              ),
              AppButton(
                label: 'Mock Replan Dispatch',
                icon: Icons.route_outlined,
                onPressed: () => _showMockFeedback(
                  'Prototype only: dispatch plan updated locally.',
                ),
                variant: AppButtonVariant.secondary,
              ),
              AppButton(
                label: 'Mock Assign War Room',
                icon: Icons.groups_2_outlined,
                onPressed: () => _showMockFeedback(
                  'Prototype only: war-room ownership simulated.',
                ),
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTowerInterventionBoard() {
    final detectEntries = _towerEntriesForStage(_PMInterventionStage.detect);
    final decideEntries = _towerEntriesForStage(_PMInterventionStage.decide);
    final deliverEntries = _towerEntriesForStage(_PMInterventionStage.deliver);

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: const Text(
            'Intervention Board delivers the same problem differently: triage blockers, decide interventions, then simulate execution.',
            style: TextStyle(color: Color(0xFF4B5563)),
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final detectColumn = _buildInterventionColumn(
              title: 'Detect',
              subtitle: 'What is actively threatening commitments',
              entries: detectEntries,
              accent: const Color(0xFFFEE2E2),
              stage: _PMInterventionStage.detect,
            );
            final decideColumn = _buildInterventionColumn(
              title: 'Decide',
              subtitle: 'Candidate interventions to test',
              entries: decideEntries,
              accent: const Color(0xFFFEF3C7),
              stage: _PMInterventionStage.decide,
            );
            final deliverColumn = _buildInterventionColumn(
              title: 'Deliver',
              subtitle: 'Simulated interventions in motion',
              entries: deliverEntries,
              accent: const Color(0xFFDCFCE7),
              stage: _PMInterventionStage.deliver,
            );

            if (constraints.maxWidth < 1200) {
              return Column(
                children: [
                  detectColumn,
                  const SizedBox(height: 12),
                  decideColumn,
                  const SizedBox(height: 12),
                  deliverColumn,
                ],
              );
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: detectColumn),
                const SizedBox(width: 12),
                Expanded(child: decideColumn),
                const SizedBox(width: 12),
                Expanded(child: deliverColumn),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildInterventionColumn({
    required String title,
    required String subtitle,
    required List<_PMFlowNodeRef> entries,
    required Color accent,
    required _PMInterventionStage stage,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title (${entries.length})',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF4B5563)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const Text(
              'No cards in this stage.',
              style: TextStyle(color: Color(0xFF6B7280)),
            )
          else
            ...entries.map(
              (entry) => _TowerInterventionCard(
                flowCode: entry.flow.code,
                flowClient: entry.flow.client,
                nodeHeadline: entry.node.headline,
                nodeStage: entry.node.stage,
                status: _towerNodeStatus(entry.node),
                statusColor: _towerStatusColor(_towerNodeStatus(entry.node)),
                onFocus: () => _selectTowerFlow(
                  entry.flow.id,
                  preferredNodeId: entry.node.id,
                ),
                stage: stage,
                onPrimaryAction: () =>
                    _progressIntervention(entry.node.id, stage),
                onSecondaryAction: () =>
                    _reverseIntervention(entry.node.id, stage),
              ),
            ),
        ],
      ),
    );
  }

  List<_PMFlowNodeRef> _towerEntriesForStage(_PMInterventionStage stage) {
    final entries = <_PMFlowNodeRef>[];
    for (final flow in _promiseFlows) {
      for (final node in flow.nodes) {
        final nodeStage = _interventionStageForNode(node.id);
        if (nodeStage == stage && _shouldShowInInterventionStage(node, stage)) {
          entries.add(_PMFlowNodeRef(flow: flow, node: node));
        }
      }
    }
    return entries;
  }

  bool _shouldShowInInterventionStage(
    _PMFlowNode node,
    _PMInterventionStage stage,
  ) {
    if (stage != _PMInterventionStage.detect) {
      return true;
    }
    final status = _towerNodeStatus(node);
    return status == 'Blocked' ||
        status == 'At Risk' ||
        status == 'Queued' ||
        status == 'Pending';
  }

  _PMInterventionStage _interventionStageForNode(String nodeId) {
    if (_deliveringTowerNodeIds.contains(nodeId)) {
      return _PMInterventionStage.deliver;
    }
    if (_decidingTowerNodeIds.contains(nodeId)) {
      return _PMInterventionStage.decide;
    }
    return _PMInterventionStage.detect;
  }

  void _progressIntervention(String nodeId, _PMInterventionStage currentStage) {
    if (currentStage == _PMInterventionStage.detect) {
      _setInterventionStage(nodeId, _PMInterventionStage.decide);
      return;
    }
    if (currentStage == _PMInterventionStage.decide) {
      _setInterventionStage(nodeId, _PMInterventionStage.deliver);
      return;
    }
    _showMockFeedback(
      'Prototype only: intervention already in delivery stage.',
    );
  }

  void _reverseIntervention(String nodeId, _PMInterventionStage currentStage) {
    if (currentStage == _PMInterventionStage.deliver) {
      _setInterventionStage(nodeId, _PMInterventionStage.decide);
      return;
    }
    if (currentStage == _PMInterventionStage.decide) {
      _setInterventionStage(nodeId, _PMInterventionStage.detect);
      return;
    }
    _showMockFeedback('Prototype only: this card is already in detect stage.');
  }

  void _setInterventionStage(String nodeId, _PMInterventionStage stage) {
    setState(() {
      _decidingTowerNodeIds.remove(nodeId);
      _deliveringTowerNodeIds.remove(nodeId);
      if (stage == _PMInterventionStage.decide) {
        _decidingTowerNodeIds.add(nodeId);
      }
      if (stage == _PMInterventionStage.deliver) {
        _deliveringTowerNodeIds.add(nodeId);
        _mitigatedTowerNodeIds.add(nodeId);
      }
      if (stage == _PMInterventionStage.detect) {
        _mitigatedTowerNodeIds.remove(nodeId);
      }
    });
    _showMockFeedback(
      'Prototype only: intervention moved to ${_interventionStageLabel(stage)}.',
    );
  }

  String _interventionStageLabel(_PMInterventionStage stage) {
    switch (stage) {
      case _PMInterventionStage.detect:
        return 'detect';
      case _PMInterventionStage.decide:
        return 'decide';
      case _PMInterventionStage.deliver:
        return 'deliver';
    }
  }

  Widget _buildMsmeDeskView() {
    final entries = _filteredMsmeEntries();
    final blockedCount = entries
        .where((entry) => _msmeStatusFor(entry) == 'Blocked')
        .length;
    final todayCount = entries
        .where((entry) => entry.dueBucket == 'Today')
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: 'MSME Book-to-Software Desk',
          subtitle:
              'High-volume workspace that respects paper-book habits while offering premium clarity.',
          actionLabel: 'Mock New Entry',
          onAction: () => _showMockFeedback(
            'Prototype only: quick-entry drawer simulated.',
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: const Text(
            'This is designed for teams who ran profitable operations on 3-4 paper books. Keep the familiar ledger mental model, then graduate to premium triage views.',
            style: TextStyle(color: Color(0xFF4B5563)),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PrototypeNavChip(
              label: 'Familiar Ledger',
              selected:
                  _msmeDeskPresentation == _PMMsmeDeskPresentation.familiar,
              onTap: () => setState(() {
                _msmeDeskPresentation = _PMMsmeDeskPresentation.familiar;
              }),
            ),
            _PrototypeNavChip(
              label: 'Premium Ops Grid',
              selected:
                  _msmeDeskPresentation == _PMMsmeDeskPresentation.premium,
              onTap: () => setState(() {
                _msmeDeskPresentation = _PMMsmeDeskPresentation.premium;
              }),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _msmeBookFilters
              .map(
                (book) => _PrototypeNavChip(
                  label: book,
                  selected: _msmeDeskBookFilter == book,
                  onTap: () => setState(() {
                    _msmeDeskBookFilter = book;
                  }),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _msmeActionFilters
              .map(
                (filter) => _PrototypeNavChip(
                  label: filter,
                  selected: _msmeDeskActionFilter == filter,
                  onTap: () => setState(() {
                    _msmeDeskActionFilter = filter;
                  }),
                ),
              )
              .toList(growable: false),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _TowerMetricPill(
              label: 'Rows in view',
              value: entries.length.toString(),
            ),
            _TowerMetricPill(
              label: 'Blocked rows',
              value: blockedCount.toString(),
            ),
            _TowerMetricPill(label: 'Due today', value: todayCount.toString()),
            _TowerMetricPill(
              label: 'Pinned',
              value: _pinnedMsmeEntryIds.length.toString(),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _msmeDeskPresentation == _PMMsmeDeskPresentation.familiar
            ? _buildMsmeFamiliarLayout(entries)
            : _buildMsmePremiumLayout(entries),
      ],
    );
  }

  Widget _buildMsmeFamiliarLayout(List<_PMMsmeLedgerEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shelf = _buildMsmeBookShelf(entries);
        final table = _buildMsmeLedgerTable(entries);

        if (constraints.maxWidth < 1120) {
          return Column(children: [shelf, const SizedBox(height: 12), table]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 2, child: shelf),
            const SizedBox(width: 12),
            Expanded(flex: 5, child: table),
          ],
        );
      },
    );
  }

  Widget _buildMsmeBookShelf(List<_PMMsmeLedgerEntry> entries) {
    final bookCounts = <String, int>{};
    for (final entry in entries) {
      bookCounts[entry.book] = (bookCounts[entry.book] ?? 0) + 1;
    }

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Book shelf',
            style: TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Looks familiar to paper-book operators, but keeps instant digital filters and pinned priorities.',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 10),
          ..._msmeBookFilters
              .where((book) => book != 'All Books')
              .map(
                (book) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            book,
                            style: const TextStyle(
                              color: Color(0xFF1F2937),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          '${bookCounts[book] ?? 0}',
                          style: const TextStyle(
                            color: Color(0xFF6B7280),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          const SizedBox(height: 2),
          AppButton(
            label: '+ Add Item',
            icon: Icons.add_rounded,
            onPressed: () => _showMockFeedback(
              'Prototype only: quick add item flow opened.',
            ),
            variant: AppButtonVariant.secondary,
          ),
        ],
      ),
    );
  }

  Widget _buildMsmeLedgerTable(List<_PMMsmeLedgerEntry> entries) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'High-volume ledger',
            style: TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Dense, scan-friendly rows with just enough actions to avoid overwhelming first-time software adopters.',
            style: TextStyle(color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'No entries match the current filters.',
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            )
          else
            SizedBox(
              height: 460,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1052,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: const Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: Text(
                                '#',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 115,
                              child: Text(
                                'Book / Ref',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 180,
                              child: Text(
                                'Party',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 170,
                              child: Text(
                                'Item',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 80,
                              child: Text(
                                'Qty',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 95,
                              child: Text(
                                'Amount',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              child: Text(
                                'Due',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 130,
                              child: Text(
                                'Status',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 130,
                              child: Text(
                                'Quick',
                                style: TextStyle(
                                  color: Color(0xFF4B5563),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 4),
                          itemBuilder: (context, index) => _buildMsmeLedgerRow(
                            entry: entries[index],
                            rowNumber: index + 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMsmeLedgerRow({
    required _PMMsmeLedgerEntry entry,
    required int rowNumber,
  }) {
    final status = _msmeStatusFor(entry);
    final isPinned = _pinnedMsmeEntryIds.contains(entry.id);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isPinned ? const Color(0xFFEEF2FF) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPinned ? const Color(0xFFC7D2FE) : const Color(0xFFE5E7EB),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              '$rowNumber',
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ),
          SizedBox(
            width: 115,
            child: Text(
              '${entry.bookCode}\n${entry.reference}',
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              entry.party,
              style: const TextStyle(color: Color(0xFF1F2937)),
            ),
          ),
          SizedBox(
            width: 170,
            child: Text(
              entry.item,
              style: const TextStyle(color: Color(0xFF1F2937)),
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              '${entry.quantity}',
              style: const TextStyle(color: Color(0xFF1F2937)),
            ),
          ),
          SizedBox(
            width: 95,
            child: Text(
              '₹${entry.amount.toStringAsFixed(0)}',
              style: const TextStyle(color: Color(0xFF1F2937)),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              entry.dueBucket,
              style: const TextStyle(color: Color(0xFF1F2937)),
            ),
          ),
          SizedBox(
            width: 130,
            child: _StatusPill(label: status, color: _msmeStatusColor(status)),
          ),
          SizedBox(
            width: 130,
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                    size: 18,
                    color: isPinned
                        ? const Color(0xFF4F46E5)
                        : const Color(0xFF6B7280),
                  ),
                  tooltip: isPinned ? 'Unpin' : 'Pin',
                  onPressed: () => _toggleMsmePinned(entry.id),
                ),
                TextButton(
                  onPressed: () => _cycleMsmeStatus(entry),
                  child: const Text('Advance'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMsmePremiumLayout(List<_PMMsmeLedgerEntry> entries) {
    final todayEntries = entries
        .where((entry) => entry.dueBucket == 'Today')
        .toList(growable: false);
    final tomorrowEntries = entries
        .where((entry) => entry.dueBucket == 'Tomorrow')
        .toList(growable: false);
    final weekEntries = entries
        .where((entry) => entry.dueBucket == 'This Week')
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final todayPanel = _buildMsmePremiumBucket(
          title: 'Today Priorities',
          subtitle: 'Fast decisions for immediate commitments.',
          entries: todayEntries,
          accent: const Color(0xFFDBEAFE),
        );
        final tomorrowPanel = _buildMsmePremiumBucket(
          title: 'Tomorrow Risks',
          subtitle: 'Prepare interventions before pressure spikes.',
          entries: tomorrowEntries,
          accent: const Color(0xFFFEF3C7),
        );
        final weekPanel = _buildMsmePremiumBucket(
          title: 'This Week Pipeline',
          subtitle: 'Keep future load visible and balanced.',
          entries: weekEntries,
          accent: const Color(0xFFDCFCE7),
        );

        if (constraints.maxWidth < 1200) {
          return Column(
            children: [
              todayPanel,
              const SizedBox(height: 12),
              tomorrowPanel,
              const SizedBox(height: 12),
              weekPanel,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: todayPanel),
            const SizedBox(width: 12),
            Expanded(child: tomorrowPanel),
            const SizedBox(width: 12),
            Expanded(child: weekPanel),
          ],
        );
      },
    );
  }

  Widget _buildMsmePremiumBucket({
    required String title,
    required String subtitle,
    required List<_PMMsmeLedgerEntry> entries,
    required Color accent,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$title (${entries.length})',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF4B5563)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            const Text(
              'No entries in this bucket.',
              style: TextStyle(color: Color(0xFF6B7280)),
            )
          else
            SizedBox(
              height: 430,
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final status = _msmeStatusFor(entry);
                  return Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${entry.reference} · ${entry.party}',
                          style: const TextStyle(
                            color: Color(0xFF111827),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${entry.book} · ${entry.item} · ${entry.quantity} qty',
                          style: const TextStyle(color: Color(0xFF4B5563)),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _StatusPill(
                              label: status,
                              color: _msmeStatusColor(status),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '₹${entry.amount.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Color(0xFF1F2937),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            TextButton(
                              onPressed: () => _cycleMsmeStatus(entry),
                              child: const Text('Advance'),
                            ),
                            TextButton(
                              onPressed: () => _toggleMsmePinned(entry.id),
                              child: Text(
                                _pinnedMsmeEntryIds.contains(entry.id)
                                    ? 'Unpin'
                                    : 'Pin',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  List<_PMMsmeLedgerEntry> _filteredMsmeEntries() {
    final filtered = _msmeLedgerEntries
        .where((entry) {
          if (_msmeDeskBookFilter != 'All Books' &&
              entry.book != _msmeDeskBookFilter) {
            return false;
          }
          final status = _msmeStatusFor(entry);
          switch (_msmeDeskActionFilter) {
            case 'Today':
              return entry.dueBucket == 'Today';
            case 'Needs Action':
              return status == 'Blocked' || status == 'At Risk';
            case 'Blocked':
              return status == 'Blocked';
            default:
              return true;
          }
        })
        .toList(growable: false);

    filtered.sort((a, b) {
      final pinA = _pinnedMsmeEntryIds.contains(a.id) ? 0 : 1;
      final pinB = _pinnedMsmeEntryIds.contains(b.id) ? 0 : 1;
      if (pinA != pinB) {
        return pinA.compareTo(pinB);
      }
      final dueA = _msmeDueRank(a.dueBucket);
      final dueB = _msmeDueRank(b.dueBucket);
      if (dueA != dueB) {
        return dueA.compareTo(dueB);
      }
      return a.reference.compareTo(b.reference);
    });
    return filtered;
  }

  int _msmeDueRank(String bucket) {
    switch (bucket) {
      case 'Today':
        return 0;
      case 'Tomorrow':
        return 1;
      default:
        return 2;
    }
  }

  String _msmeStatusFor(_PMMsmeLedgerEntry entry) {
    return _msmeStatusOverrides[entry.id] ?? entry.status;
  }

  void _toggleMsmePinned(String entryId) {
    setState(() {
      if (_pinnedMsmeEntryIds.contains(entryId)) {
        _pinnedMsmeEntryIds.remove(entryId);
      } else {
        _pinnedMsmeEntryIds.add(entryId);
      }
    });
  }

  void _cycleMsmeStatus(_PMMsmeLedgerEntry entry) {
    const statuses = <String>[
      'Blocked',
      'At Risk',
      'Follow-up',
      'Ready',
      'Closed',
    ];
    setState(() {
      _msmeStatusOverrides[entry.id] = _nextStatus(
        current: _msmeStatusFor(entry),
        statuses: statuses,
      );
    });
    _showMockFeedback(
      'Prototype only: ${entry.reference} moved to ${_msmeStatusFor(entry)}.',
    );
  }

  Color _msmeStatusColor(String status) {
    switch (status) {
      case 'Blocked':
        return const Color(0xFFB91C1C);
      case 'At Risk':
        return const Color(0xFFB45309);
      case 'Ready':
      case 'Closed':
        return const Color(0xFF047857);
      default:
        return const Color(0xFF0E7490);
    }
  }

  Widget _buildOrdersListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: 'Orders',
          subtitle: 'Static ERP orders list for prototype navigation.',
          actionLabel: 'Open Work Queue',
          onAction: () =>
              _pushRoute(const _PMPrototypeRoute(_PMPrototypeView.workQueue)),
        ),
        const SizedBox(height: 12),
        ..._orders.map(
          (order) => _PrototypeRowCard(
            title: '${order.code} · ${order.client}',
            subtitle:
                'Due ${order.dueDate} · ₹${order.amount.toStringAsFixed(0)}',
            status: _orderStatusFor(order),
            statusColor: const Color(0xFF4338CA),
            onTap: () => _pushRoute(
              _PMPrototypeRoute(_PMPrototypeView.orderDetail, order.id),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderDetailView(String? orderId) {
    final order = _firstWhereOrNull(_orders, (item) => item.id == orderId);
    if (order == null) {
      return const _PrototypeMissingState(
        title: 'Order not found',
        message: 'This is static prototype data. Try opening another row.',
      );
    }

    final status = _orderStatusFor(order);
    final linkedInventory = _firstWhereOrNull(
      _inventoryGroups,
      (item) => item.id == order.inventoryGroupId,
    );
    final linkedProcurement = _firstWhereOrNull(
      _procurementRequests,
      (item) => item.id == order.procurementRequestId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: '${order.code} · ${order.client}',
          subtitle:
              'Due ${order.dueDate} · ₹${order.amount.toStringAsFixed(0)} · Current: $status',
          actionLabel: 'Advance Status',
          onAction: () => _cycleOrderStatus(order),
        ),
        const SizedBox(height: 12),
        AppInfoPanel(
          title: 'Order detail snapshot',
          subtitle: 'Prototype-only detail view with local status changes.',
          rows: [
            AppInfoRow(label: 'Client', value: order.client),
            AppInfoRow(label: 'Item', value: order.itemName),
            AppInfoRow(label: 'Quantity', value: order.quantity.toString()),
            AppInfoRow(label: 'Status', value: status),
            AppInfoRow(label: 'Owner', value: order.owner),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AppButton(
              label: 'Open Inventory Group',
              icon: Icons.inventory_2_outlined,
              onPressed: linkedInventory == null
                  ? null
                  : () => _pushRoute(
                      _PMPrototypeRoute(
                        _PMPrototypeView.inventoryDetail,
                        linkedInventory.id,
                      ),
                    ),
              variant: AppButtonVariant.secondary,
            ),
            AppButton(
              label: 'Open Procurement Request',
              icon: Icons.local_shipping_outlined,
              onPressed: linkedProcurement == null
                  ? null
                  : () => _pushRoute(
                      _PMPrototypeRoute(
                        _PMPrototypeView.procurementDetail,
                        linkedProcurement.id,
                      ),
                    ),
              variant: AppButtonVariant.secondary,
            ),
            AppButton(
              label: 'Mock Notify Team',
              icon: Icons.notifications_active_outlined,
              onPressed: () => _showMockFeedback(
                'Prototype action only: team notification simulated.',
              ),
              variant: AppButtonVariant.secondary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildInventoryListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: 'Inventory groups',
          subtitle:
              'Prototype list with static stock indicators and drill-down links.',
          actionLabel: 'Jump to Procurement',
          onAction: () =>
              _setRoot(const _PMPrototypeRoute(_PMPrototypeView.procurement)),
        ),
        const SizedBox(height: 12),
        ..._inventoryGroups.map(
          (group) => _PrototypeRowCard(
            title: group.name,
            subtitle:
                'On-hand ${group.onHand} · Available ${group.available} · Reorder ${group.reorderLevel}',
            status: group.health,
            statusColor: group.health == 'Healthy'
                ? const Color(0xFF047857)
                : const Color(0xFFB45309),
            onTap: () => _pushRoute(
              _PMPrototypeRoute(_PMPrototypeView.inventoryDetail, group.id),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInventoryDetailView(String? groupId) {
    final group = _firstWhereOrNull(
      _inventoryGroups,
      (item) => item.id == groupId,
    );
    if (group == null) {
      return const _PrototypeMissingState(
        title: 'Inventory group not found',
        message: 'This is static prototype data. Try opening another row.',
      );
    }

    final relatedOrders = _orders
        .where((order) => order.inventoryGroupId == group.id)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: group.name,
          subtitle:
              'On-hand ${group.onHand} · Allocated ${group.allocated} · Available ${group.available}',
          actionLabel: 'Mock Recount',
          onAction: () => _showMockFeedback(
            'Prototype action only: recount request simulated.',
          ),
        ),
        const SizedBox(height: 12),
        AppInfoPanel(
          title: 'Inventory detail snapshot',
          rows: [
            AppInfoRow(label: 'Barcode Family', value: group.barcodePrefix),
            AppInfoRow(
              label: 'Reorder Level',
              value: group.reorderLevel.toString(),
            ),
            AppInfoRow(
              label: 'Quality Holds',
              value: group.qualityHolds.toString(),
            ),
            AppInfoRow(label: 'Health', value: group.health),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Related orders',
          style: TextStyle(
            color: Color(0xFF111827),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        ...relatedOrders.map(
          (order) => _PrototypeRowCard(
            title: order.code,
            subtitle: '${order.client} · ${order.itemName}',
            status: _orderStatusFor(order),
            statusColor: const Color(0xFF4338CA),
            onTap: () => _pushRoute(
              _PMPrototypeRoute(_PMPrototypeView.orderDetail, order.id),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProcurementListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: 'Procurement requests',
          subtitle:
              'Static queue of supplier requests with clickable detail pages.',
          actionLabel: 'Mock Create Draft',
          onAction: () => _showMockFeedback(
            'Prototype action only: draft request simulated.',
          ),
        ),
        const SizedBox(height: 12),
        ..._procurementRequests.map(
          (request) => _PrototypeRowCard(
            title: '${request.code} · ${request.supplier}',
            subtitle:
                'ETA ${request.etaDate} · ₹${request.amount.toStringAsFixed(0)}',
            status: _procurementStatusFor(request),
            statusColor: const Color(0xFF0F766E),
            onTap: () => _pushRoute(
              _PMPrototypeRoute(_PMPrototypeView.procurementDetail, request.id),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProcurementDetailView(String? requestId) {
    final request = _firstWhereOrNull(
      _procurementRequests,
      (item) => item.id == requestId,
    );
    if (request == null) {
      return const _PrototypeMissingState(
        title: 'Request not found',
        message: 'This is static prototype data. Try opening another row.',
      );
    }

    final linkedOrder = _firstWhereOrNull(
      _orders,
      (order) => order.id == request.linkedOrderId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: '${request.code} · ${request.supplier}',
          subtitle:
              'ETA ${request.etaDate} · Current: ${_procurementStatusFor(request)}',
          actionLabel: 'Advance Status',
          onAction: () => _cycleProcurementStatus(request),
        ),
        const SizedBox(height: 12),
        AppInfoPanel(
          title: 'Procurement detail snapshot',
          rows: [
            AppInfoRow(label: 'Supplier', value: request.supplier),
            AppInfoRow(
              label: 'Line Items',
              value: request.lineItems.toString(),
            ),
            AppInfoRow(
              label: 'Amount',
              value: '₹${request.amount.toStringAsFixed(0)}',
            ),
            AppInfoRow(label: 'Owner', value: request.owner),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AppButton(
              label: 'Open Linked Order',
              icon: Icons.receipt_long_outlined,
              onPressed: linkedOrder == null
                  ? null
                  : () => _pushRoute(
                      _PMPrototypeRoute(
                        _PMPrototypeView.orderDetail,
                        linkedOrder.id,
                      ),
                    ),
              variant: AppButtonVariant.secondary,
            ),
            AppButton(
              label: 'Mock Receive Material',
              icon: Icons.inventory_rounded,
              onPressed: () => _showMockFeedback(
                'Prototype action only: receive-material flow simulated.',
              ),
              variant: AppButtonVariant.secondary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildProductionListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: 'Production runs',
          subtitle: 'Static run board with stage-level prototype drill-down.',
          actionLabel: 'Mock Plan Run',
          onAction: () => _showMockFeedback(
            'Prototype action only: run planning simulated.',
          ),
        ),
        const SizedBox(height: 12),
        ..._productionRuns.map(
          (run) => _PrototypeRowCard(
            title: '${run.code} · ${run.pipeline}',
            subtitle:
                '${run.stage} · Planned ${run.plannedQty} · Actual ${run.actualQty}',
            status: _productionStatusFor(run),
            statusColor: const Color(0xFF7C3AED),
            onTap: () => _pushRoute(
              _PMPrototypeRoute(_PMPrototypeView.productionDetail, run.id),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductionDetailView(String? runId) {
    final run = _firstWhereOrNull(_productionRuns, (item) => item.id == runId);
    if (run == null) {
      return const _PrototypeMissingState(
        title: 'Run not found',
        message: 'This is static prototype data. Try opening another row.',
      );
    }

    final linkedOrder = _firstWhereOrNull(
      _orders,
      (order) => order.id == run.linkedOrderId,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: '${run.code} · ${run.pipeline}',
          subtitle:
              '${run.stage} · Current: ${_productionStatusFor(run)} · Owner ${run.owner}',
          actionLabel: 'Advance Status',
          onAction: () => _cycleProductionStatus(run),
        ),
        const SizedBox(height: 12),
        AppInfoPanel(
          title: 'Production detail snapshot',
          rows: [
            AppInfoRow(label: 'Stage', value: run.stage),
            AppInfoRow(label: 'Planned Qty', value: run.plannedQty.toString()),
            AppInfoRow(label: 'Actual Qty', value: run.actualQty.toString()),
            AppInfoRow(label: 'Shift', value: run.shift),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            AppButton(
              label: 'Open Linked Order',
              icon: Icons.receipt_long_outlined,
              onPressed: linkedOrder == null
                  ? null
                  : () => _pushRoute(
                      _PMPrototypeRoute(
                        _PMPrototypeView.orderDetail,
                        linkedOrder.id,
                      ),
                    ),
              variant: AppButtonVariant.secondary,
            ),
            AppButton(
              label: 'Mock Quality Check',
              icon: Icons.fact_check_outlined,
              onPressed: () => _showMockFeedback(
                'Prototype action only: quality-check flow simulated.',
              ),
              variant: AppButtonVariant.secondary,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildConfiguratorPreviewView() {
    const items = <_ConfiguratorTile>[
      _ConfiguratorTile('Clients', 124, Icons.groups_outlined),
      _ConfiguratorTile('Items', 468, Icons.inventory_outlined),
      _ConfiguratorTile('Groups', 89, Icons.grid_view_outlined),
      _ConfiguratorTile('Units', 36, Icons.straighten_outlined),
      _ConfiguratorTile('Vendors', 52, Icons.storefront_outlined),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TitleRow(
          title: 'Configurator preview',
          subtitle:
              'Mock master-data summary for prototype-only navigation and density checks.',
          actionLabel: 'Mock Add Master Data',
          onAction: () => _showMockFeedback(
            'Prototype action only: master-data create flow simulated.',
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items
              .map(
                (item) => _MetricCard(
                  label: item.label,
                  value: item.count.toString(),
                  icon: item.icon,
                  accent: const Color(0xFFEDE9FE),
                  onTap: () => _showMockFeedback(
                    'Prototype only: opened ${item.label} mock panel.',
                  ),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  Widget _buildTaskListCard({
    required String title,
    required List<_PMTask> tasks,
  }) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          ...tasks.map(
            (task) => InkWell(
              onTap: () => _openTask(task),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.title,
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusPill(
                      label: task.priority,
                      color: task.priority == 'High'
                          ? const Color(0xFFB45309)
                          : const Color(0xFF0F766E),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModuleLaunchCard() {
    final launches = <_ModuleLaunch>[
      const _ModuleLaunch(
        title: 'Orders',
        subtitle: 'Open active order board',
        route: _PMPrototypeRoute(_PMPrototypeView.orders),
        icon: Icons.receipt_long_outlined,
      ),
      const _ModuleLaunch(
        title: 'Control Tower',
        subtitle: 'Open commitment blocker map',
        route: _PMPrototypeRoute(_PMPrototypeView.controlTower),
        icon: Icons.alt_route_rounded,
      ),
      const _ModuleLaunch(
        title: 'MSME Desk',
        subtitle: 'Open high-volume book workspace',
        route: _PMPrototypeRoute(_PMPrototypeView.msmeDesk),
        icon: Icons.menu_book_rounded,
      ),
      const _ModuleLaunch(
        title: 'Inventory',
        subtitle: 'Open stock health',
        route: _PMPrototypeRoute(_PMPrototypeView.inventory),
        icon: Icons.inventory_2_outlined,
      ),
      const _ModuleLaunch(
        title: 'Procurement',
        subtitle: 'Open supplier requests',
        route: _PMPrototypeRoute(_PMPrototypeView.procurement),
        icon: Icons.local_shipping_outlined,
      ),
      const _ModuleLaunch(
        title: 'Production',
        subtitle: 'Open run tracker',
        route: _PMPrototypeRoute(_PMPrototypeView.production),
        icon: Icons.precision_manufacturing_outlined,
      ),
    ];

    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: launches
            .map(
              (launch) => InkWell(
                onTap: () => _setRoot(launch.route),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Icon(launch.icon, color: const Color(0xFF6C63FF)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              launch.title,
                              style: const TextStyle(
                                color: Color(0xFF111827),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              launch.subtitle,
                              style: const TextStyle(color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  String _routeLabel(_PMPrototypeRoute route) {
    switch (route.view) {
      case _PMPrototypeView.dashboard:
        return 'Dashboard';
      case _PMPrototypeView.workQueue:
        return 'Work Queue';
      case _PMPrototypeView.controlTower:
        return 'Control Tower';
      case _PMPrototypeView.msmeDesk:
        return 'MSME Desk';
      case _PMPrototypeView.orders:
        return 'Orders';
      case _PMPrototypeView.orderDetail:
        final order = _firstWhereOrNull(
          _orders,
          (item) => item.id == route.entityId,
        );
        return order == null ? 'Order' : order.code;
      case _PMPrototypeView.inventory:
        return 'Inventory';
      case _PMPrototypeView.inventoryDetail:
        final group = _firstWhereOrNull(
          _inventoryGroups,
          (item) => item.id == route.entityId,
        );
        return group == null ? 'Inventory Detail' : group.name;
      case _PMPrototypeView.procurement:
        return 'Procurement';
      case _PMPrototypeView.procurementDetail:
        final request = _firstWhereOrNull(
          _procurementRequests,
          (item) => item.id == route.entityId,
        );
        return request == null ? 'Request' : request.code;
      case _PMPrototypeView.production:
        return 'Production';
      case _PMPrototypeView.productionDetail:
        final run = _firstWhereOrNull(
          _productionRuns,
          (item) => item.id == route.entityId,
        );
        return run == null ? 'Run' : run.code;
      case _PMPrototypeView.configurator:
        return 'Configurator';
    }
  }

  String _orderStatusFor(_PMOrder order) {
    return _orderStatusOverrides[order.id] ?? order.status;
  }

  _PMFlowNode? _selectedTowerNode(_PMPromiseFlow flow) {
    if (_selectedTowerNodeId != null) {
      final selected = _firstWhereOrNull(
        flow.nodes,
        (node) => node.id == _selectedTowerNodeId,
      );
      if (selected != null) {
        return selected;
      }
    }
    return _firstWhereOrNull(flow.nodes, (node) => node.status == 'Blocked') ??
        _firstWhereOrNull(flow.nodes, (_) => true);
  }

  String _defaultTowerNodeId(_PMPromiseFlow flow) {
    final preferred = _firstWhereOrNull(
      flow.nodes,
      (node) => node.status == 'Blocked',
    );
    return (preferred ?? flow.nodes.first).id;
  }

  void _selectTowerFlow(String flowId, {String? preferredNodeId}) {
    final flow = _firstWhereOrNull(_promiseFlows, (item) => item.id == flowId);
    if (flow == null) {
      return;
    }
    setState(() {
      _selectedTowerFlowId = flow.id;
      _selectedTowerNodeId = preferredNodeId ?? _defaultTowerNodeId(flow);
    });
  }

  void _toggleWatch(String flowId) {
    setState(() {
      if (_watchedTowerFlowIds.contains(flowId)) {
        _watchedTowerFlowIds.remove(flowId);
      } else {
        _watchedTowerFlowIds.add(flowId);
      }
    });
    _showMockFeedback('Prototype only: watchlist updated locally.');
  }

  void _toggleMitigation(_PMFlowNode node) {
    setState(() {
      if (_mitigatedTowerNodeIds.contains(node.id)) {
        _mitigatedTowerNodeIds.remove(node.id);
      } else {
        _mitigatedTowerNodeIds.add(node.id);
      }
    });
    _showMockFeedback(
      _mitigatedTowerNodeIds.contains(node.id)
          ? 'Prototype only: mitigation simulated for ${node.stage}.'
          : 'Prototype only: mitigation reset for ${node.stage}.',
    );
  }

  String _towerNodeStatus(_PMFlowNode node) {
    if (_mitigatedTowerNodeIds.contains(node.id)) {
      return 'Mitigated';
    }
    return node.status;
  }

  Color _riskColor(String risk) {
    switch (risk) {
      case 'High':
        return const Color(0xFFB91C1C);
      case 'Medium':
        return const Color(0xFFB45309);
      default:
        return const Color(0xFF047857);
    }
  }

  Color _towerStatusColor(String status) {
    switch (status) {
      case 'Blocked':
        return const Color(0xFFB91C1C);
      case 'At Risk':
      case 'Queued':
      case 'Pending':
        return const Color(0xFFB45309);
      case 'Mitigated':
        return const Color(0xFF0E7490);
      case 'Committed':
      case 'Ready':
      case 'Stable':
      case 'Released':
        return const Color(0xFF047857);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String _procurementStatusFor(_PMProcurementRequest request) {
    return _procurementStatusOverrides[request.id] ?? request.status;
  }

  String _productionStatusFor(_PMProductionRun run) {
    return _productionStatusOverrides[run.id] ?? run.status;
  }

  void _cycleOrderStatus(_PMOrder order) {
    const statuses = <String>[
      'Pending Review',
      'Planned',
      'In Production',
      'Ready to Dispatch',
      'Dispatched',
    ];
    setState(() {
      _orderStatusOverrides[order.id] = _nextStatus(
        current: _orderStatusFor(order),
        statuses: statuses,
      );
    });
  }

  void _cycleProcurementStatus(_PMProcurementRequest request) {
    const statuses = <String>[
      'Draft',
      'Raised',
      'Partially Received',
      'Closed',
    ];
    setState(() {
      _procurementStatusOverrides[request.id] = _nextStatus(
        current: _procurementStatusFor(request),
        statuses: statuses,
      );
    });
  }

  void _cycleProductionStatus(_PMProductionRun run) {
    const statuses = <String>[
      'Planned',
      'Running',
      'Quality Check',
      'Completed',
    ];
    setState(() {
      _productionStatusOverrides[run.id] = _nextStatus(
        current: _productionStatusFor(run),
        statuses: statuses,
      );
    });
  }

  void _showMockFeedback(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openTask(_PMTask task) {
    _pushRoute(task.route);
  }

  void _setRoot(_PMPrototypeRoute route) {
    setState(() {
      _history
        ..clear()
        ..add(route);
    });
  }

  void _pushRoute(_PMPrototypeRoute route) {
    setState(() {
      _history.add(route);
    });
  }

  void _goBack() {
    if (_history.length <= 1) {
      return;
    }
    setState(() {
      _history.removeLast();
    });
  }

  bool _isSectionSelected(_PMPrototypeView sectionView) {
    switch (sectionView) {
      case _PMPrototypeView.orders:
        return _current.view == _PMPrototypeView.orders ||
            _current.view == _PMPrototypeView.orderDetail;
      case _PMPrototypeView.inventory:
        return _current.view == _PMPrototypeView.inventory ||
            _current.view == _PMPrototypeView.inventoryDetail;
      case _PMPrototypeView.procurement:
        return _current.view == _PMPrototypeView.procurement ||
            _current.view == _PMPrototypeView.procurementDetail;
      case _PMPrototypeView.production:
        return _current.view == _PMPrototypeView.production ||
            _current.view == _PMPrototypeView.productionDetail;
      default:
        return _current.view == sectionView;
    }
  }

  String _nextStatus({
    required String current,
    required List<String> statuses,
  }) {
    final currentIndex = statuses.indexOf(current);
    final nextIndex = currentIndex == -1
        ? 0
        : (currentIndex + 1) % statuses.length;
    return statuses[nextIndex];
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(color: Color(0xFF6B7280))),
            ],
          ),
        ),
        AppButton(
          label: actionLabel,
          onPressed: onAction,
          variant: AppButtonVariant.secondary,
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
    this.icon,
  });

  final String label;
  final String value;
  final Color accent;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        width: 170,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0D000000),
              blurRadius: 14,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF374151),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: 18, color: const Color(0xFF6C63FF)),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PrototypeRowCard extends StatelessWidget {
  const _PrototypeRowCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String status;
  final Color statusColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
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
                        style: const TextStyle(
                          color: Color(0xFF111827),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(color: Color(0xFF6B7280)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _StatusPill(label: status, color: statusColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SelectablePrototypeCard extends StatelessWidget {
  const _SelectablePrototypeCard({
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusColor,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String status;
  final Color statusColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEEF2FF) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF6C63FF)
                  : const Color(0xFFE5E7EB),
            ),
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
                      style: const TextStyle(
                        color: Color(0xFF111827),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(color: Color(0xFF6B7280)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _StatusPill(label: status, color: statusColor),
            ],
          ),
        ),
      ),
    );
  }
}

class _TowerMetricPill extends StatelessWidget {
  const _TowerMetricPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Color(0xFF6B7280))),
        ],
      ),
    );
  }
}

class _TowerNodeCard extends StatelessWidget {
  const _TowerNodeCard({
    required this.stage,
    required this.headline,
    required this.status,
    required this.statusColor,
    required this.selected,
    required this.onTap,
  });

  final String stage;
  final String headline;
  final String status;
  final Color statusColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        width: 180,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? const Color(0xFF6C63FF) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              stage,
              style: const TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              headline,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _StatusPill(label: status, color: statusColor),
          ],
        ),
      ),
    );
  }
}

class _TowerInterventionCard extends StatelessWidget {
  const _TowerInterventionCard({
    required this.flowCode,
    required this.flowClient,
    required this.nodeHeadline,
    required this.nodeStage,
    required this.status,
    required this.statusColor,
    required this.stage,
    required this.onFocus,
    required this.onPrimaryAction,
    required this.onSecondaryAction,
  });

  final String flowCode;
  final String flowClient;
  final String nodeHeadline;
  final String nodeStage;
  final String status;
  final Color statusColor;
  final _PMInterventionStage stage;
  final VoidCallback onFocus;
  final VoidCallback onPrimaryAction;
  final VoidCallback onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final primaryLabel = stage == _PMInterventionStage.detect
        ? 'Move to Decide'
        : stage == _PMInterventionStage.decide
        ? 'Simulate Deliver'
        : 'Delivered';
    final secondaryLabel = stage == _PMInterventionStage.detect
        ? 'Already Detect'
        : stage == _PMInterventionStage.decide
        ? 'Back to Detect'
        : 'Back to Decide';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$flowCode · $flowClient',
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$nodeStage: $nodeHeadline',
              style: const TextStyle(color: Color(0xFF4B5563)),
            ),
            const SizedBox(height: 8),
            _StatusPill(label: status, color: statusColor),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                TextButton(onPressed: onFocus, child: const Text('Focus')),
                TextButton(
                  onPressed: stage == _PMInterventionStage.deliver
                      ? null
                      : onPrimaryAction,
                  child: Text(primaryLabel),
                ),
                TextButton(
                  onPressed: stage == _PMInterventionStage.detect
                      ? null
                      : onSecondaryAction,
                  child: Text(secondaryLabel),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PrototypeNavChip extends StatelessWidget {
  const _PrototypeNavChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEEF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFF6C63FF) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFF4338CA) : const Color(0xFF374151),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _PrototypeMissingState extends StatelessWidget {
  const _PrototypeMissingState({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, color: Color(0xFF6B7280), size: 28),
            const SizedBox(height: 10),
            Text(
              title,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF6B7280)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PMPrototypeNavEntry {
  const _PMPrototypeNavEntry({required this.label, required this.route});

  final String label;
  final _PMPrototypeRoute route;
}

class _ModuleLaunch {
  const _ModuleLaunch({
    required this.title,
    required this.subtitle,
    required this.route,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final _PMPrototypeRoute route;
  final IconData icon;
}

class _ConfiguratorTile {
  const _ConfiguratorTile(this.label, this.count, this.icon);

  final String label;
  final int count;
  final IconData icon;
}

enum _PMPrototypeView {
  dashboard,
  workQueue,
  controlTower,
  msmeDesk,
  orders,
  orderDetail,
  inventory,
  inventoryDetail,
  procurement,
  procurementDetail,
  production,
  productionDetail,
  configurator,
}

enum _PMControlTowerPerspective { promise, constraint, time }

enum _PMControlTowerDeliveryMode { cockpit, interventionBoard }

enum _PMInterventionStage { detect, decide, deliver }

enum _PMMsmeDeskPresentation { familiar, premium }

class _PMPrototypeRoute {
  const _PMPrototypeRoute(this.view, [this.entityId]);

  final _PMPrototypeView view;
  final String? entityId;
}

class _PMTask {
  const _PMTask({
    required this.id,
    required this.title,
    required this.module,
    required this.assignee,
    required this.due,
    required this.priority,
    required this.blocked,
    required this.route,
  });

  final String id;
  final String title;
  final String module;
  final String assignee;
  final String due;
  final String priority;
  final bool blocked;
  final _PMPrototypeRoute route;
}

class _PMOrder {
  const _PMOrder({
    required this.id,
    required this.code,
    required this.client,
    required this.itemName,
    required this.quantity,
    required this.owner,
    required this.dueDate,
    required this.amount,
    required this.status,
    required this.inventoryGroupId,
    required this.procurementRequestId,
  });

  final String id;
  final String code;
  final String client;
  final String itemName;
  final int quantity;
  final String owner;
  final String dueDate;
  final double amount;
  final String status;
  final String inventoryGroupId;
  final String procurementRequestId;
}

class _PMInventoryGroup {
  const _PMInventoryGroup({
    required this.id,
    required this.name,
    required this.barcodePrefix,
    required this.onHand,
    required this.allocated,
    required this.available,
    required this.reorderLevel,
    required this.qualityHolds,
    required this.health,
  });

  final String id;
  final String name;
  final String barcodePrefix;
  final int onHand;
  final int allocated;
  final int available;
  final int reorderLevel;
  final int qualityHolds;
  final String health;
}

class _PMProcurementRequest {
  const _PMProcurementRequest({
    required this.id,
    required this.code,
    required this.supplier,
    required this.etaDate,
    required this.amount,
    required this.status,
    required this.owner,
    required this.lineItems,
    required this.linkedOrderId,
  });

  final String id;
  final String code;
  final String supplier;
  final String etaDate;
  final double amount;
  final String status;
  final String owner;
  final int lineItems;
  final String linkedOrderId;
}

class _PMProductionRun {
  const _PMProductionRun({
    required this.id,
    required this.code,
    required this.pipeline,
    required this.stage,
    required this.plannedQty,
    required this.actualQty,
    required this.status,
    required this.owner,
    required this.shift,
    required this.linkedOrderId,
  });

  final String id;
  final String code;
  final String pipeline;
  final String stage;
  final int plannedQty;
  final int actualQty;
  final String status;
  final String owner;
  final String shift;
  final String linkedOrderId;
}

class _PMPromiseFlow {
  const _PMPromiseFlow({
    required this.id,
    required this.code,
    required this.client,
    required this.dueDate,
    required this.owner,
    required this.value,
    required this.riskLevel,
    required this.nodes,
  });

  final String id;
  final String code;
  final String client;
  final String dueDate;
  final String owner;
  final double value;
  final String riskLevel;
  final List<_PMFlowNode> nodes;
}

class _PMFlowNode {
  const _PMFlowNode({
    required this.id,
    required this.stage,
    required this.headline,
    required this.summary,
    required this.status,
    required this.owner,
    required this.etaImpact,
  });

  final String id;
  final String stage;
  final String headline;
  final String summary;
  final String status;
  final String owner;
  final String etaImpact;
}

class _PMConstraintLens {
  const _PMConstraintLens({
    required this.id,
    required this.title,
    required this.summary,
    required this.severity,
    required this.flowId,
    required this.nodeId,
  });

  final String id;
  final String title;
  final String summary;
  final String severity;
  final String flowId;
  final String nodeId;
}

class _PMTimeLens {
  const _PMTimeLens({
    required this.id,
    required this.windowLabel,
    required this.summary,
    required this.priority,
    required this.flowId,
    required this.nodeId,
  });

  final String id;
  final String windowLabel;
  final String summary;
  final String priority;
  final String flowId;
  final String nodeId;
}

class _PMMsmeLedgerEntry {
  const _PMMsmeLedgerEntry({
    required this.id,
    required this.book,
    required this.bookCode,
    required this.reference,
    required this.party,
    required this.item,
    required this.quantity,
    required this.amount,
    required this.dueBucket,
    required this.status,
  });

  final String id;
  final String book;
  final String bookCode;
  final String reference;
  final String party;
  final String item;
  final int quantity;
  final double amount;
  final String dueBucket;
  final String status;
}

class _PMFlowNodeRef {
  const _PMFlowNodeRef({required this.flow, required this.node});

  final _PMPromiseFlow flow;
  final _PMFlowNode node;
}

const List<String> _msmeBookFilters = <String>[
  'All Books',
  'Sales Book',
  'Purchase Book',
  'Stock Book',
  'Production Book',
];

const List<String> _msmeActionFilters = <String>[
  'All',
  'Today',
  'Needs Action',
  'Blocked',
];

final List<_PMMsmeLedgerEntry> _msmeLedgerEntries = _buildMsmeLedgerEntries();

List<_PMMsmeLedgerEntry> _buildMsmeLedgerEntries() {
  const bookNames = <String>[
    'Sales Book',
    'Purchase Book',
    'Stock Book',
    'Production Book',
  ];
  const bookCodes = <String>['SAL', 'PUR', 'STK', 'PRD'];
  const parties = <String>[
    'BrightMart',
    'Zen Retail',
    'Swift Supplies',
    'Metro Wholesale',
    'NorthCart Packaging',
    'Blue Ridge Stores',
    'Cityline Traders',
    'United Pulp Co.',
  ];
  const items = <String>[
    'Paper Funnel Medium',
    'Spout Insert',
    'Paper Core',
    'Kraft Roll 120 GSM',
    'Outer Carton',
    'Adhesive Pack',
  ];
  const statuses = <String>[
    'Blocked',
    'At Risk',
    'Follow-up',
    'Ready',
    'Closed',
  ];
  const dueBuckets = <String>['Today', 'Tomorrow', 'This Week'];

  final entries = <_PMMsmeLedgerEntry>[];
  for (var i = 0; i < 56; i++) {
    final row = i + 1;
    final bookIndex = i % bookNames.length;
    final bookCode = bookCodes[bookIndex];
    entries.add(
      _PMMsmeLedgerEntry(
        id: 'ledger_$row',
        book: bookNames[bookIndex],
        bookCode: bookCode,
        reference: '$bookCode-${1900 + row}',
        party: parties[i % parties.length],
        item: items[(i * 2) % items.length],
        quantity: 60 + ((i * 17) % 900),
        amount: 22000 + ((i * 1375) % 185000),
        dueBucket: dueBuckets[i % dueBuckets.length],
        status: statuses[i % statuses.length],
      ),
    );
  }
  return entries;
}

const List<_PMPromiseFlow> _promiseFlows = <_PMPromiseFlow>[
  _PMPromiseFlow(
    id: 'flow_1042',
    code: 'OR-1042',
    client: 'BrightMart',
    dueDate: '26 Apr 2026',
    owner: 'Nikhil',
    value: 278000,
    riskLevel: 'High',
    nodes: <_PMFlowNode>[
      _PMFlowNode(
        id: 'flow_1042_commit',
        stage: 'Order',
        headline: 'Commitment locked',
        summary: 'Order commitment is accepted and visible to all teams.',
        status: 'Committed',
        owner: 'Nikhil',
        etaImpact: 'None',
      ),
      _PMFlowNode(
        id: 'flow_1042_inventory',
        stage: 'Inventory',
        headline: 'Paper cone shortage',
        summary: 'Available buffer is below reorder threshold by 400 units.',
        status: 'Blocked',
        owner: 'Rahul',
        etaImpact: '+18h',
      ),
      _PMFlowNode(
        id: 'flow_1042_procurement',
        stage: 'Procurement',
        headline: 'Supplier ETA unstable',
        summary: 'Supplier flagged transport congestion at origin facility.',
        status: 'At Risk',
        owner: 'Aditi',
        etaImpact: '+12h',
      ),
      _PMFlowNode(
        id: 'flow_1042_production',
        stage: 'Production',
        headline: 'Run queued behind urgent rework',
        summary: 'Current shift has one rework batch ahead in funnel assembly.',
        status: 'Queued',
        owner: 'Shreya',
        etaImpact: '+8h',
      ),
      _PMFlowNode(
        id: 'flow_1042_dispatch',
        stage: 'Dispatch',
        headline: 'Carrier window pending',
        summary: 'Dispatch slot is held until upstream blockers clear.',
        status: 'Pending',
        owner: 'Kiran',
        etaImpact: '+6h',
      ),
    ],
  ),
  _PMPromiseFlow(
    id: 'flow_1038',
    code: 'OR-1038',
    client: 'Zen Retail',
    dueDate: '24 Apr 2026',
    owner: 'Aarav',
    value: 154000,
    riskLevel: 'Medium',
    nodes: <_PMFlowNode>[
      _PMFlowNode(
        id: 'flow_1038_commit',
        stage: 'Order',
        headline: 'Commitment locked',
        summary: 'Commercial approval is complete for this promise.',
        status: 'Committed',
        owner: 'Aarav',
        etaImpact: 'None',
      ),
      _PMFlowNode(
        id: 'flow_1038_inventory',
        stage: 'Inventory',
        headline: 'Buffer healthy',
        summary: 'Inventory is sufficient for planned quantity.',
        status: 'Ready',
        owner: 'Rahul',
        etaImpact: 'None',
      ),
      _PMFlowNode(
        id: 'flow_1038_procurement',
        stage: 'Procurement',
        headline: 'Partial receipt follow-up',
        summary: 'Last lot not yet received from supplier.',
        status: 'At Risk',
        owner: 'Aditi',
        etaImpact: '+6h',
      ),
      _PMFlowNode(
        id: 'flow_1038_production',
        stage: 'Production',
        headline: 'Quality release in progress',
        summary: 'Batch is in quality check, waiting final signoff.',
        status: 'Queued',
        owner: 'Dev',
        etaImpact: '+4h',
      ),
      _PMFlowNode(
        id: 'flow_1038_dispatch',
        stage: 'Dispatch',
        headline: 'Routing pre-assigned',
        summary: 'Primary route and backup route already identified.',
        status: 'Pending',
        owner: 'Kiran',
        etaImpact: '+2h',
      ),
    ],
  ),
  _PMPromiseFlow(
    id: 'flow_1031',
    code: 'OR-1031',
    client: 'Swift Supplies',
    dueDate: '23 Apr 2026',
    owner: 'Kiran',
    value: 91000,
    riskLevel: 'Low',
    nodes: <_PMFlowNode>[
      _PMFlowNode(
        id: 'flow_1031_commit',
        stage: 'Order',
        headline: 'Commitment locked',
        summary: 'Promise accepted and communicated to customer.',
        status: 'Committed',
        owner: 'Kiran',
        etaImpact: 'None',
      ),
      _PMFlowNode(
        id: 'flow_1031_inventory',
        stage: 'Inventory',
        headline: 'Material staged',
        summary: 'Required materials are staged at the dock.',
        status: 'Ready',
        owner: 'Rahul',
        etaImpact: 'None',
      ),
      _PMFlowNode(
        id: 'flow_1031_procurement',
        stage: 'Procurement',
        headline: 'All lines closed',
        summary: 'No open procurement dependencies remain.',
        status: 'Stable',
        owner: 'Meera',
        etaImpact: 'None',
      ),
      _PMFlowNode(
        id: 'flow_1031_production',
        stage: 'Production',
        headline: 'Run complete',
        summary: 'Production and quality checks are complete.',
        status: 'Released',
        owner: 'Neha',
        etaImpact: 'None',
      ),
      _PMFlowNode(
        id: 'flow_1031_dispatch',
        stage: 'Dispatch',
        headline: 'Truck loaded',
        summary: 'Shipment has a confirmed dispatch slot.',
        status: 'Stable',
        owner: 'Kiran',
        etaImpact: 'None',
      ),
    ],
  ),
];

const List<_PMConstraintLens> _constraintLenses = <_PMConstraintLens>[
  _PMConstraintLens(
    id: 'constraint_buffer',
    title: 'Material buffer collapse',
    summary: 'Inventory shortfall is threatening OR-1042 commitment.',
    severity: 'High',
    flowId: 'flow_1042',
    nodeId: 'flow_1042_inventory',
  ),
  _PMConstraintLens(
    id: 'constraint_supplier_eta',
    title: 'Supplier ETA volatility',
    summary: 'Last lot for OR-1038 is partially received and time sensitive.',
    severity: 'Medium',
    flowId: 'flow_1038',
    nodeId: 'flow_1038_procurement',
  ),
  _PMConstraintLens(
    id: 'constraint_quality_release',
    title: 'Quality release queue',
    summary: 'Quality signoff queues can delay shipment readiness.',
    severity: 'Medium',
    flowId: 'flow_1038',
    nodeId: 'flow_1038_production',
  ),
];

const List<_PMTimeLens> _timeLenses = <_PMTimeLens>[
  _PMTimeLens(
    id: 'time_today',
    windowLabel: 'Today',
    summary: 'Close dispatch readiness checks for OR-1031.',
    priority: 'Low',
    flowId: 'flow_1031',
    nodeId: 'flow_1031_dispatch',
  ),
  _PMTimeLens(
    id: 'time_24h',
    windowLabel: 'Next 24h',
    summary: 'Follow supplier receipt to prevent OR-1038 delay.',
    priority: 'Medium',
    flowId: 'flow_1038',
    nodeId: 'flow_1038_procurement',
  ),
  _PMTimeLens(
    id: 'time_72h',
    windowLabel: 'Next 72h',
    summary: 'Recover material + production queue for OR-1042.',
    priority: 'High',
    flowId: 'flow_1042',
    nodeId: 'flow_1042_inventory',
  ),
];

const List<_PMTask> _tasks = <_PMTask>[
  _PMTask(
    id: 'task_1',
    title: 'Approve procurement request PR-2418',
    module: 'Procurement',
    assignee: 'Aditi',
    due: 'Today 3:00 PM',
    priority: 'High',
    blocked: false,
    route: _PMPrototypeRoute(_PMPrototypeView.procurementDetail, 'pr_2418'),
  ),
  _PMTask(
    id: 'task_2',
    title: 'Resolve material shortage for OR-1042',
    module: 'Inventory',
    assignee: 'Rahul',
    due: 'Today 5:00 PM',
    priority: 'High',
    blocked: true,
    route: _PMPrototypeRoute(
      _PMPrototypeView.inventoryDetail,
      'inv_paper_cone',
    ),
  ),
  _PMTask(
    id: 'task_3',
    title: 'Release run RN-501 to quality check',
    module: 'Production',
    assignee: 'Shreya',
    due: 'Tomorrow 10:30 AM',
    priority: 'Medium',
    blocked: false,
    route: _PMPrototypeRoute(_PMPrototypeView.productionDetail, 'run_501'),
  ),
  _PMTask(
    id: 'task_4',
    title: 'Confirm dispatch date with BrightMart',
    module: 'Orders',
    assignee: 'Nikhil',
    due: 'Tomorrow 2:00 PM',
    priority: 'Medium',
    blocked: false,
    route: _PMPrototypeRoute(_PMPrototypeView.orderDetail, 'order_1042'),
  ),
];

const List<_PMOrder> _orders = <_PMOrder>[
  _PMOrder(
    id: 'order_1042',
    code: 'OR-1042',
    client: 'BrightMart',
    itemName: 'Paper Funnel (Medium)',
    quantity: 3400,
    owner: 'Nikhil',
    dueDate: '26 Apr 2026',
    amount: 278000,
    status: 'Pending Review',
    inventoryGroupId: 'inv_paper_cone',
    procurementRequestId: 'pr_2418',
  ),
  _PMOrder(
    id: 'order_1038',
    code: 'OR-1038',
    client: 'Zen Retail',
    itemName: 'Spout Insert',
    quantity: 5600,
    owner: 'Aarav',
    dueDate: '24 Apr 2026',
    amount: 154000,
    status: 'In Production',
    inventoryGroupId: 'inv_spout',
    procurementRequestId: 'pr_2416',
  ),
  _PMOrder(
    id: 'order_1031',
    code: 'OR-1031',
    client: 'Swift Supplies',
    itemName: 'Paper Core',
    quantity: 2100,
    owner: 'Kiran',
    dueDate: '23 Apr 2026',
    amount: 91000,
    status: 'Ready to Dispatch',
    inventoryGroupId: 'inv_core',
    procurementRequestId: 'pr_2411',
  ),
];

const List<_PMInventoryGroup> _inventoryGroups = <_PMInventoryGroup>[
  _PMInventoryGroup(
    id: 'inv_paper_cone',
    name: 'Paper Cone Group',
    barcodePrefix: 'PCN',
    onHand: 8200,
    allocated: 5600,
    available: 2600,
    reorderLevel: 3000,
    qualityHolds: 2,
    health: 'Low buffer',
  ),
  _PMInventoryGroup(
    id: 'inv_spout',
    name: 'Spout Insert Group',
    barcodePrefix: 'SPI',
    onHand: 14500,
    allocated: 7100,
    available: 7400,
    reorderLevel: 5000,
    qualityHolds: 0,
    health: 'Healthy',
  ),
  _PMInventoryGroup(
    id: 'inv_core',
    name: 'Paper Core Group',
    barcodePrefix: 'PCR',
    onHand: 6300,
    allocated: 4200,
    available: 2100,
    reorderLevel: 2000,
    qualityHolds: 1,
    health: 'Healthy',
  ),
];

const List<_PMProcurementRequest> _procurementRequests =
    <_PMProcurementRequest>[
      _PMProcurementRequest(
        id: 'pr_2418',
        code: 'PR-2418',
        supplier: 'United Pulp Co.',
        etaDate: '25 Apr 2026',
        amount: 124000,
        status: 'Raised',
        owner: 'Aditi',
        lineItems: 3,
        linkedOrderId: 'order_1042',
      ),
      _PMProcurementRequest(
        id: 'pr_2416',
        code: 'PR-2416',
        supplier: 'NorthCart Packaging',
        etaDate: '24 Apr 2026',
        amount: 86000,
        status: 'Partially Received',
        owner: 'Aditi',
        lineItems: 2,
        linkedOrderId: 'order_1038',
      ),
      _PMProcurementRequest(
        id: 'pr_2411',
        code: 'PR-2411',
        supplier: 'Dyna Fibers',
        etaDate: '22 Apr 2026',
        amount: 62000,
        status: 'Closed',
        owner: 'Meera',
        lineItems: 2,
        linkedOrderId: 'order_1031',
      ),
    ];

const List<_PMProductionRun> _productionRuns = <_PMProductionRun>[
  _PMProductionRun(
    id: 'run_501',
    code: 'RN-501',
    pipeline: 'Funnel Assembly',
    stage: 'Welding',
    plannedQty: 3400,
    actualQty: 1780,
    status: 'Running',
    owner: 'Shreya',
    shift: 'Shift B',
    linkedOrderId: 'order_1042',
  ),
  _PMProductionRun(
    id: 'run_498',
    code: 'RN-498',
    pipeline: 'Spout Molding',
    stage: 'Quality Check',
    plannedQty: 5600,
    actualQty: 5600,
    status: 'Quality Check',
    owner: 'Dev',
    shift: 'Shift A',
    linkedOrderId: 'order_1038',
  ),
  _PMProductionRun(
    id: 'run_492',
    code: 'RN-492',
    pipeline: 'Core Rolling',
    stage: 'Packing',
    plannedQty: 2100,
    actualQty: 2100,
    status: 'Completed',
    owner: 'Neha',
    shift: 'Shift C',
    linkedOrderId: 'order_1031',
  ),
];

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) predicate) {
  for (final value in values) {
    if (predicate(value)) {
      return value;
    }
  }
  return null;
}
