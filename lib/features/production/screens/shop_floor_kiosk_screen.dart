import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/production_provider.dart';
import '../providers/production_run_provider.dart';
import '../widgets/lock_key_setup_modal.dart';
import '../widgets/material_ledger_closure_dialog.dart';

class ShopFloorKioskScreen extends StatefulWidget {
  const ShopFloorKioskScreen({super.key});

  @override
  State<ShopFloorKioskScreen> createState() => _ShopFloorKioskScreenState();
}

class _ShopFloorKioskScreenState extends State<ShopFloorKioskScreen> {
  late final FocusNode _globalFocusNode;
  final StringBuffer _barcodeBuffer = StringBuffer();
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _globalFocusNode = FocusNode();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final productionProvider = Provider.of<ProductionProvider>(context);
    final stage = productionProvider.selectedStage;
    final runProvider = Provider.of<ProductionRunProvider>(context, listen: false);
    if (stage != null && runProvider.stageId != stage.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<ProductionRunProvider>().updateExpectedAssets(
            stageId: stage.id,
            machineId: stage.machineId,
            dieId: stage.dieId,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _globalFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _dispatchBarcode(String barcode) {
    final run = context.read<ProductionRunProvider>();
    final production = context.read<ProductionProvider>();
    run.verifyScannedAsset(
      barcode,
      onVerifiedAll: () {
        final machineId = run.scannedMachineId;
        final dieId = run.scannedDieId;
        if (machineId != null && dieId != null) {
          production.verifyAssetSetup(machineId, dieId);
          production.startRun();
          final runId =
              production.activeRun?.id ??
              'run-${DateTime.now().microsecondsSinceEpoch}';
          run.startRun(runId: runId);
        }
      },
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (FocusManager.instance.primaryFocus != _globalFocusNode) {
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    final logicalKey = event.logicalKey;

    if (logicalKey == LogicalKeyboardKey.enter ||
        logicalKey == LogicalKeyboardKey.numpadEnter) {
      _debounceTimer?.cancel();
      final barcode = _barcodeBuffer.toString().trim();
      _barcodeBuffer.clear();
      if (barcode.isNotEmpty) {
        _dispatchBarcode(barcode);
      }
      return KeyEventResult.handled;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty) {
      _debounceTimer?.cancel();
      _barcodeBuffer.write(char);
      _debounceTimer = Timer(const Duration(milliseconds: 50), () {
        _barcodeBuffer.clear();
      });
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.read<ProductionProvider>();
    final stage = provider.selectedStage;
    context.select<ProductionProvider, String?>(
      (provider) => provider.selectedStageId,
    );
    context.select<ProductionProvider, ProductionRunPhase>(
      (provider) => provider.phase,
    );
    context.select<ProductionRunProvider, ProductionState>(
      (provider) => provider.state,
    );

    return Focus(
      focusNode: _globalFocusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _StatusHero(provider: provider),
            const SizedBox(height: 12),
            _KioskPipelineVisualizer(provider: provider),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 3,
                    child: _RunTelemetry(stage: stage, provider: provider),
                  ),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: _LiveCounters(provider: provider)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _KioskControls(provider: provider),
          ],
        ),
      ),
    );
  }
}

class _KioskPipelineVisualizer extends StatelessWidget {
  const _KioskPipelineVisualizer({required this.provider});

  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    final stages = provider.blueprint.stages;
    final selectedId = provider.selectedStageId;
    final selectedIndex = stages.indexWhere((s) => s.id == selectedId);
    final runState = context.select<ProductionRunProvider, ProductionState>(
      (provider) => provider.state,
    );

    return SizedBox(
      width: double.infinity,
      height: 150,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final nodeWidth = constraints.maxWidth < 540
              ? constraints.maxWidth
              : 250.0;
          return SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var index = 0; index < stages.length; index++)
                  _KioskPipelineNode(
                    width: nodeWidth,
                    stage: stages[index],
                    index: index,
                    isSelected: stages[index].id == selectedId,
                    isCompleted: index < selectedIndex,
                    isActive:
                        stages[index].id == selectedId &&
                        (runState == ProductionState.running ||
                            runState == ProductionState.paused),
                    provider: provider,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _KioskPipelineNode extends StatefulWidget {
  const _KioskPipelineNode({
    required this.width,
    required this.stage,
    required this.index,
    required this.isSelected,
    required this.isCompleted,
    required this.isActive,
    required this.provider,
  });

  final double width;
  final PipelineStage stage;
  final int index;
  final bool isSelected;
  final bool isCompleted;
  final bool isActive;
  final ProductionProvider provider;

  @override
  State<_KioskPipelineNode> createState() => _KioskPipelineNodeState();
}

class _KioskPipelineNodeState extends State<_KioskPipelineNode>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isActive) {
      _glowController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant _KioskPipelineNode oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !_glowController.isAnimating) {
      _glowController.repeat(reverse: true);
    } else if (!widget.isActive) {
      _glowController.stop();
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage;
    final isSelected = widget.isSelected;
    final isCompleted = widget.isCompleted;
    final isActive = widget.isActive;

    Color cardBg = Colors.white;
    Color borderCol = const Color(0xFFE2E8F0);
    Color textColor = const Color(0xFF0F172A);
    Color subColor = const Color(0xFF64748B);

    if (isCompleted) {
      cardBg = const Color(0xFFECFDF5);
      borderCol = const Color(0xFF10B981).withValues(alpha: 0.4);
      textColor = const Color(0xFF065F46);
      subColor = const Color(0xFF047857);
    } else if (isSelected) {
      cardBg = Colors.white;
      borderCol = const Color(0xFF09090B);
      textColor = const Color(0xFF09090B);
      subColor = const Color(0xFF4B5563);
    }

    Widget content = Container(
      width: widget.width,
      height: 117,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderCol, width: isSelected ? 2.0 : 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'STAGE ${widget.index + 1}: ${stage.name}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                    color: textColor,
                  ),
                ),
              ),
              if (isCompleted) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.check_circle,
                  color: Color(0xFF10B981),
                  size: 14,
                ),
              ],
            ],
          ),
          Text(
            'MC: ${stage.machineId}  |  DIE: ${stage.dieId}',
            style: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              color: subColor,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _TransformationChip(
                label: 'INLET',
                material: stage.inputMaterial,
                isLeft: true,
                textColor: textColor,
              ),
              _TransformationChip(
                label: 'OUTLET',
                material: stage.outputMaterial,
                isLeft: false,
                textColor: textColor,
              ),
            ],
          ),
        ],
      ),
    );

    if (isActive) {
      content = AnimatedBuilder(
        animation: _glowController,
        builder: (context, child) {
          final glowVal = _glowController.value;
          return Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(
                    0xFF10B981,
                  ).withValues(alpha: 0.35 * glowVal),
                  blurRadius: 6 + 6 * glowVal,
                  spreadRadius: 1 + 1 * glowVal,
                ),
              ],
            ),
            child: child,
          );
        },
        child: content,
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          widget.provider.selectStage(stage.id);
        },
        child: content,
      ),
    );
  }
}

class _TransformationChip extends StatelessWidget {
  const _TransformationChip({
    required this.label,
    required this.material,
    required this.isLeft,
    required this.textColor,
  });

  final String label;
  final String material;
  final bool isLeft;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (context) {
            return Dialog(
              shape: const RoundedRectangleBorder(),
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(22),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Color(0xFF09090B), width: 3),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '$label SPECIFICATION',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF09090B),
                              letterSpacing: 0,
                            ),
                          ),
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'MATERIAL',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w900,
                        color: Color(0xFFA1A1AA),
                        fontSize: 10,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      material,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF09090B),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Divider(height: 1, color: Color(0xFFE4E4E7)),
                    const SizedBox(height: 14),
                    _buildSpecRow(
                      'State',
                      isLeft ? 'Raw Reel / Web' : 'Cut Sheet blanks',
                    ),
                    _buildSpecRow(
                      'Weight/Volume',
                      isLeft ? 'Parent Reel Stock' : 'WIP Board Lot',
                    ),
                    _buildSpecRow(
                      'Transformation',
                      isLeft
                          ? 'Preparation & Load'
                          : 'Finished Stack allocation',
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
        decoration: BoxDecoration(
          color: textColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isLeft ? Icons.login_rounded : Icons.logout_rounded,
              size: 9,
              color: textColor.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w900,
                color: textColor.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecRow(String name, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 126,
            child: Text(
              name.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w900,
                fontSize: 10,
                color: Color(0xFFA1A1AA),
                letterSpacing: 0,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF27272A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.provider});

  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    final runState = context.select<ProductionRunProvider, ProductionState>(
      (provider) => provider.state,
    );
    final running = runState == ProductionState.running;
    final paused = runState == ProductionState.paused;
    final text = running
        ? 'RUNNING'
        : paused
        ? 'PAUSED'
        : 'IDLE / SETUP';
    final runId = context.select<ProductionRunProvider, String>(
      (provider) => provider.runId ?? 'NO-RUN',
    );
    final operatorName = context.select<ProductionProvider, String>(
      (provider) => provider.activeOperator,
    );

    final Color backgroundColor;
    switch (runState) {
      case ProductionState.running:
        backgroundColor = const Color(0xFF22C55E);
      case ProductionState.paused:
      case ProductionState.idle:
      case ProductionState.setup:
      case ProductionState.completed:
        backgroundColor = const Color(0xFFF59E0B);
    }
    const textColor = Color(0xFF09090B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          _StatusDot(running: running),
          const SizedBox(width: 14),
          _MonoStatus(label: 'STATE', value: text, textColor: textColor),
          const SizedBox(width: 28),
          _MonoStatus(label: 'RUN', value: runId, textColor: textColor),
          const SizedBox(width: 28),
          _MonoStatus(
            label: 'OPERATOR',
            value: operatorName,
            textColor: textColor,
          ),
          const Spacer(),
          const _ElapsedClock(),
          const SizedBox(width: 20),
          InkWell(
            onTap: () => _showOperatorSwitcher(context),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: textColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(
                  color: textColor.withValues(alpha: 0.2),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: Text(
                  operatorName.isNotEmpty
                      ? operatorName.substring(0, 2).toUpperCase()
                      : 'OP',
                  style: const TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showOperatorSwitcher(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => OperatorSwitcherDialog(
        currentOperator: provider.activeOperator,
        onSwitch: (newOp) {
          provider.switchOperator(newOp);
        },
      ),
    );
  }
}

class OperatorSwitcherDialog extends StatefulWidget {
  const OperatorSwitcherDialog({
    super.key,
    required this.currentOperator,
    required this.onSwitch,
  });

  final String currentOperator;
  final ValueChanged<String> onSwitch;

  @override
  State<OperatorSwitcherDialog> createState() => _OperatorSwitcherDialogState();
}

class _ElapsedClock extends StatelessWidget {
  const _ElapsedClock();

  @override
  Widget build(BuildContext context) {
    return Selector<ProductionRunProvider, String>(
      selector: (context, provider) => provider.elapsedDisplay,
      builder: (context, elapsedDisplay, child) {
        return Text(
          elapsedDisplay,
          style: const TextStyle(
            color: Color(0xFF09090B),
            fontFamily: 'monospace',
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        );
      },
    );
  }
}

class _OperatorSwitcherDialogState extends State<OperatorSwitcherDialog> {
  final TextEditingController _pinController = TextEditingController();
  String _pin = '';

  void _handleNumberPress(String digit) {
    if (_pin.length < 4) {
      setState(() {
        _pin += digit;
        _pinController.text = _pin;
      });
      if (_pin.length == 4) {
        _submitPin();
      }
    }
  }

  void _handleClear() {
    setState(() {
      _pin = '';
      _pinController.text = '';
    });
  }

  void _submitPin() {
    String newOperator = 'OPERATOR-';
    if (_pin == '1234') {
      newOperator = 'OPERATOR-A';
    } else if (_pin == '9999') {
      newOperator = 'OPERATOR-B';
    } else if (_pin == '0000') {
      newOperator = 'FLOOR-ADMIN';
    } else {
      newOperator = 'OP-$_pin';
    }
    widget.onSwitch(newOperator);
    Navigator.of(context).pop();
  }

  void _simulateBadgeScan() {
    final simulatedBadgeId =
        'BADGE-${(1000 + (DateTime.now().millisecond % 9000))}';
    widget.onSwitch(simulatedBadgeId);
    Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 290,
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'OPERATOR SWITCHER',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Color(0xFF71717A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Current: ${widget.currentOperator}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Color(0xFF27272A),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (index) {
                final active = index < _pin.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: active
                        ? const Color(0xFF09090B)
                        : const Color(0xFFE4E4E7),
                    border: Border.all(
                      color: const Color(0xFFD4D4D8),
                      width: 1.5,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.4,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                if (index == 9) {
                  return _PinButton(
                    onTap: _handleClear,
                    child: const Text(
                      'CLR',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  );
                } else if (index == 10) {
                  return _PinButton(
                    onTap: () => _handleNumberPress('0'),
                    child: const Text(
                      '0',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                } else if (index == 11) {
                  return _PinButton(
                    color: const Color(0xFFE0E7FF),
                    onTap: _simulateBadgeScan,
                    child: const Icon(
                      Icons.contactless_outlined,
                      color: Color(0xFF4338CA),
                      size: 18,
                    ),
                  );
                } else {
                  final digit = (index + 1).toString();
                  return _PinButton(
                    onTap: () => _handleNumberPress(digit),
                    child: Text(
                      digit,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
            const Text(
              'Scan ID badge or enter PIN (e.g. 1234, 9999)',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 10, color: Color(0xFF71717A)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinButton extends StatelessWidget {
  const _PinButton({
    required this.child,
    required this.onTap,
    this.color = const Color(0xFFF4F4F5),
  });

  final Widget child;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Center(child: child),
      ),
    );
  }
}

class _StatusDot extends StatefulWidget {
  const _StatusDot({required this.running});

  final bool running;

  @override
  State<_StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<_StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _updateAnimation();
  }

  @override
  void didUpdateWidget(covariant _StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.running != widget.running) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    final isTest =
        const bool.fromEnvironment('FLUTTER_TEST') ||
        WidgetsBinding.instance.toString().contains(
          'TestWidgetsFlutterBinding',
        );
    if (widget.running && !isTest) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.running
        ? const Color(0xFF09090B)
        : const Color(0xFF7F1D1D);
    if (!widget.running) {
      return _Dot(size: 10, color: color);
    }
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 1).animate(_controller),
      child: _Dot(size: 10, color: color),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _MonoStatus extends StatelessWidget {
  const _MonoStatus({
    required this.label,
    required this.value,
    required this.textColor,
  });

  final String label;
  final String value;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle(
      style: TextStyle(
        fontFamily: 'monospace',
        letterSpacing: 0,
        color: textColor,
      ),
      child: Row(
        children: [
          Text(
            '$label ',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.6),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _RunTelemetry extends StatelessWidget {
  const _RunTelemetry({required this.stage, required this.provider});

  final PipelineStage? stage;
  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    final barcodeError = context.select<ProductionRunProvider, String?>(
      (p) => p.barcodeErrorMessage,
    );
    final errorMessage = provider.validationErrorMessage ?? barcodeError;

    return _KioskPanel(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ACTIVE MACHINE ROUTING',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF334155),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              stage?.name ?? 'No stage selected',
              style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 20),
            _TelemetryLine(label: 'Machine', value: stage?.machineId ?? '--'),
            _TelemetryLine(label: 'Die', value: stage?.dieId ?? '--'),
            _TelemetryLine(label: 'Input', value: stage?.inputMaterial ?? '--'),
            _TelemetryLine(
              label: 'Action',
              value: stage?.machineAction ?? '--',
            ),
            _TelemetryLine(
              label: 'Output',
              value: stage?.outputMaterial ?? '--',
            ),
            _TelemetryLine(label: 'Scrap', value: stage?.scrapPolicy ?? '--'),
            if (errorMessage != null) ...[
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.red.shade700),
                    bottom: BorderSide(color: Colors.red.shade700),
                  ),
                ),
                child: Text(
                  errorMessage,
                  style: const TextStyle(
                    color: Color(0xFF7F1D1D),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveCounters extends StatelessWidget {
  const _LiveCounters({required this.provider});

  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    final runCounters = context
        .select<ProductionRunProvider, ({int goodYield, int scrap})>(
          (provider) =>
              (goodYield: provider.goodYield, scrap: provider.setupScrap),
        );
    final parentReel = context.select<ProductionProvider, double>(
      (provider) => provider.parentReelConsumedKg,
    );
    final locked = context.select<ProductionRunProvider, bool>(
      (provider) => provider.isInputLocked,
    );

    return _KioskPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CounterTile(
            label: 'GOOD YIELD',
            value: runCounters.goodYield.toString(),
            onIncrement: locked
                ? null
                : () => context.read<ProductionRunProvider>().incrementYield(),
            onDecrement: locked
                ? null
                : () => context.read<ProductionRunProvider>().decrementYield(),
          ),
          const SizedBox(height: 14),
          _CounterTile(
            label: 'SETUP SCRAP',
            value: '${runCounters.scrap} Pcs',
            onIncrement: locked
                ? null
                : () => context.read<ProductionRunProvider>().addScrap(),
            onDecrement: locked
                ? null
                : () => context.read<ProductionRunProvider>().removeScrap(),
          ),
          const SizedBox(height: 14),
          _CounterTile(
            label: 'PARENT REEL',
            value: '-${parentReel.toStringAsFixed(2)} Kg',
          ),
        ],
      ),
    );
  }
}

class _KioskControls extends StatelessWidget {
  const _KioskControls({required this.provider});

  final ProductionProvider provider;

  @override
  Widget build(BuildContext context) {
    final runState = context.select<ProductionRunProvider, ProductionState>(
      (provider) => provider.state,
    );
    final isRunning = runState == ProductionState.running;
    final isPaused = runState == ProductionState.paused;
    final isInputLocked = context.select<ProductionRunProvider, bool>(
      (provider) => provider.isInputLocked,
    );

    return Row(
      children: [
        Expanded(
          child: _MacroButton(
            key: const Key('verify_start_button'),
            label: isRunning ? 'Running' : 'Verify + Start',
            icon: Icons.play_circle_fill,
            onPressed: isRunning || isInputLocked
                ? null
                : () => _verifyAndStart(context),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MacroButton(
            key: const Key('pause_resume_button'),
            label: isPaused ? 'Resume' : 'Pause',
            icon: isPaused ? Icons.play_arrow : Icons.pause,
            onPressed: isRunning || (isPaused && !isInputLocked)
                ? () => _togglePause(context, isPaused)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MacroButton(
            key: const Key('closure_button'),
            label: 'Close Ledger',
            icon: Icons.inventory_2_outlined,
            onPressed: isRunning || isPaused
                ? () => _openClosure(context)
                : null,
          ),
        ),
      ],
    );
  }

  Future<void> _verifyAndStart(BuildContext context) async {
    final production = context.read<ProductionProvider>();
    final run = context.read<ProductionRunProvider>();
    final verified = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black.withValues(alpha: 0.08),
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ProductionProvider>.value(value: production),
          ChangeNotifierProvider<ProductionRunProvider>.value(value: run),
        ],
        child: const LockKeySetupModal(),
      ),
    );
    if (verified == true && context.mounted) {
      production.startRun();
      final runId =
          production.activeRun?.id ??
          'run-${DateTime.now().microsecondsSinceEpoch}';
      run.startRun(runId: runId);
    }
  }

  Future<void> _togglePause(BuildContext context, bool isPaused) async {
    final production = context.read<ProductionProvider>();
    final run = context.read<ProductionRunProvider>();
    if (isPaused) {
      production.resumeRun();
      run.resumeRun();
      return;
    }
    production.pauseRun();
    await run.pauseRun();
  }

  Future<void> _openClosure(BuildContext context) async {
    final production = context.read<ProductionProvider>();
    final run = context.read<ProductionRunProvider>();
    production.beginClosure();
    await run.pauseRun();
    if (!context.mounted) {
      return;
    }
    final committed = await showDialog<bool>(
      context: context,
      builder: (_) => MultiProvider(
        providers: [
          ChangeNotifierProvider<ProductionProvider>.value(value: production),
          ChangeNotifierProvider<ProductionRunProvider>.value(value: run),
        ],
        child: const MaterialLedgerClosureDialog(),
      ),
    );
    if (!context.mounted) {
      return;
    }
    if (committed == true) {
      await run.completeRun();
    } else {
      production.cancelClosure();
      run.resumeRun();
    }
  }
}

class _MacroButton extends StatelessWidget {
  const _MacroButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 30),
        label: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF09090B),
          disabledForegroundColor: const Color(0xFF9CA3AF),
          minimumSize: const Size.fromHeight(64),
          shape: const RoundedRectangleBorder(),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
    );
  }
}

class _TelemetryLine extends StatelessWidget {
  const _TelemetryLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.label,
    required this.value,
    this.onIncrement,
    this.onDecrement,
  });

  final String label;
  final String value;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF71717A),
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (onDecrement != null)
                  _CounterButton(icon: Icons.remove, onPressed: onDecrement),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: Color(0xFF09090B),
                          fontSize: 34,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
                if (onIncrement != null)
                  _CounterButton(icon: Icons.add, onPressed: onIncrement),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterButton extends StatelessWidget {
  const _CounterButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 38,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        style: IconButton.styleFrom(
          foregroundColor: const Color(0xFF09090B),
          disabledForegroundColor: const Color(0xFFA1A1AA),
          side: const BorderSide(color: Color(0xFFE4E4E7)),
          shape: const RoundedRectangleBorder(),
        ),
      ),
    );
  }
}

class _KioskPanel extends StatelessWidget {
  const _KioskPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    );
  }
}
