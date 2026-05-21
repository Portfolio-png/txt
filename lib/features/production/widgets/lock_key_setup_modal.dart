import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/production_provider.dart';

class AssetSpecs {
  final String id;
  final String type; // 'machine' or 'die'
  final String name;
  final String dimensionLabel;
  final String dimensionValue;
  final Map<String, String> otherSpecs;

  const AssetSpecs({
    required this.id,
    required this.type,
    required this.name,
    required this.dimensionLabel,
    required this.dimensionValue,
    required this.otherSpecs,
  });
}

const Map<String, AssetSpecs> mockAssetRegistry = {
  'MC-SLIT-01': AssetSpecs(
    id: 'MC-SLIT-01',
    type: 'machine',
    name: 'Primary Slitter',
    dimensionLabel: 'Max Width',
    dimensionValue: '1500 mm',
    otherSpecs: {'Power': '45 kW', 'Speed': '150 m/min'},
  ),
  'MC-PUNCH-03': AssetSpecs(
    id: 'MC-PUNCH-03',
    type: 'machine',
    name: 'Heavy Puncher',
    dimensionLabel: 'Tonnage',
    dimensionValue: '40 Tons',
    otherSpecs: {'Speed': '80 m/min', 'Power': '30 kW'},
  ),
  'MC-FOLD-02': AssetSpecs(
    id: 'MC-FOLD-02',
    type: 'machine',
    name: 'Folder-Gluer',
    dimensionLabel: 'Max Width',
    dimensionValue: '800 mm',
    otherSpecs: {'Glue Pots': 'Dual-Heated', 'Speed': '200 m/min'},
  ),
  'DIE-1450-A': AssetSpecs(
    id: 'DIE-1450-A',
    type: 'die',
    name: '1450mm Slit Die',
    dimensionLabel: 'Blade Width',
    dimensionValue: '1450 mm',
    otherSpecs: {'Material': 'Carbide', 'Thickness': '12 mm'},
  ),
  'DIE-CARTON-22': AssetSpecs(
    id: 'DIE-CARTON-22',
    type: 'die',
    name: 'Carton Punch Die',
    dimensionLabel: 'Cut Width',
    dimensionValue: '600 mm',
    otherSpecs: {'Pattern': 'Standard Carton', 'Weight': '250 kg'},
  ),
  'DIE-GLUE-08': AssetSpecs(
    id: 'DIE-GLUE-08',
    type: 'die',
    name: 'Glue Applicator Head',
    dimensionLabel: 'Nozzles',
    dimensionValue: '8-Port',
    otherSpecs: {'Pattern': 'Linear', 'Voltage': '24V'},
  ),
  // Alternative scan assets for simulating error mismatches
  'MC-SLIT-02': AssetSpecs(
    id: 'MC-SLIT-02',
    type: 'machine',
    name: 'Secondary Slitter',
    dimensionLabel: 'Max Width',
    dimensionValue: '1200 mm',
    otherSpecs: {'Power': '37 kW', 'Speed': '120 m/min'},
  ),
  'DIE-1200-B': AssetSpecs(
    id: 'DIE-1200-B',
    type: 'die',
    name: '1200mm Slit Die',
    dimensionLabel: 'Blade Width',
    dimensionValue: '1200 mm',
    otherSpecs: {'Material': 'HSS Steel', 'Thickness': '10 mm'},
  ),
  'DIE-CARTON-20': AssetSpecs(
    id: 'DIE-CARTON-20',
    type: 'die',
    name: 'Small Carton Die',
    dimensionLabel: 'Cut Width',
    dimensionValue: '450 mm',
    otherSpecs: {'Pattern': 'Mini Carton', 'Weight': '180 kg'},
  ),
};

AssetSpecs _resolveAsset(String code, String type) {
  final norm = _normalize(code);
  if (mockAssetRegistry.containsKey(norm)) {
    return mockAssetRegistry[norm]!;
  }
  return AssetSpecs(
    id: norm,
    type: type,
    name: 'Generic ${type.toUpperCase()}',
    dimensionLabel: 'Dimension',
    dimensionValue: '1000 mm',
    otherSpecs: const {},
  );
}

String _normalize(String value) {
  final upper = value.trim().toUpperCase();
  if (upper.contains(':')) {
    return upper.split(':').last.trim();
  }
  if (upper.contains('|')) {
    return upper.split('|').last.trim();
  }
  return upper;
}

class LockKeySetupModal extends StatefulWidget {
  const LockKeySetupModal({super.key});

  @override
  State<LockKeySetupModal> createState() => _LockKeySetupModalState();
}

class _LockKeySetupModalState extends State<LockKeySetupModal> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _scannerFocusNode = FocusNode(
    debugLabel: 'scanner_input_focus',
  );

  String? _scannedMachine;
  String? _scannedDie;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scannerFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scannerFocusNode.dispose();
    super.dispose();
  }

  void _onSubmitted(String text) {
    if (text.trim().isEmpty) return;
    SystemSound.play(SystemSoundType.click);

    setState(() {
      _errorMessage = null;
      _scannedMachine ??= text.trim();
      if (_scannedMachine != text.trim()) {
        _scannedDie ??= text.trim();
      }
      _inputController.clear();
      _validateSetup();
    });

    _scannerFocusNode.requestFocus();
  }

  void _validateSetup() {
    final stage = context.read<ProductionProvider>().selectedStage;
    if (stage == null) return;

    if (_scannedMachine != null) {
      final actualMach = _normalize(_scannedMachine!);
      final expectedMach = _normalize(stage.machineId);
      if (actualMach != expectedMach) {
        _errorMessage =
            'Machine ID Mismatch: Expected "$expectedMach", scanned "$actualMach".';
        return;
      }
    }

    if (_scannedDie != null) {
      final actualDie = _normalize(_scannedDie!);
      final expectedDie = _normalize(stage.dieId);
      if (actualDie != expectedDie) {
        final expectedSpecs = _resolveAsset(stage.dieId, 'die');
        final actualSpecs = _resolveAsset(_scannedDie!, 'die');
        _errorMessage =
            'Die Dimension Mismatch: Expected ${expectedSpecs.dimensionValue} (${expectedSpecs.id}) vs Scanned ${actualSpecs.dimensionValue} (${actualSpecs.id}).';
        return;
      }
    }
  }

  void _resetScanner() {
    setState(() {
      _scannedMachine = null;
      _scannedDie = null;
      _errorMessage = null;
      _inputController.clear();
    });
    _scannerFocusNode.requestFocus();
  }

  void _confirmAndStart() {
    if (_scannedMachine != null &&
        _scannedDie != null &&
        _errorMessage == null) {
      try {
        context.read<ProductionProvider>().verifyAssetSetup(
          _scannedMachine!,
          _scannedDie!,
        );
        Navigator.of(context).pop(true);
      } catch (e) {
        setState(() {
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductionProvider>();
    final stage = provider.selectedStage;

    final expectedMachineId = stage?.machineId ?? '';
    final expectedDieId = stage?.dieId ?? '';

    final expMachineSpecs = _resolveAsset(expectedMachineId, 'machine');
    final expDieSpecs = _resolveAsset(expectedDieId, 'die');

    final actualMachineSpecs = _scannedMachine != null
        ? _resolveAsset(_scannedMachine!, 'machine')
        : null;
    final actualDieSpecs = _scannedDie != null
        ? _resolveAsset(_scannedDie!, 'die')
        : null;

    final isComplete = _scannedMachine != null && _scannedDie != null;
    final hasError = _errorMessage != null;

    // Sequential scanner state label
    String scannerPrompt = 'Scan Machine Barcode...';
    if (_scannedMachine != null && _scannedDie == null) {
      scannerPrompt = 'Scan Die Barcode...';
    } else if (isComplete) {
      scannerPrompt = 'Scan sequence complete.';
    }

    return Material(
      color: const Color(0xFF09090B), // Sleek industrial dark theme
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pull-down indicator bar
                  Center(
                    child: Container(
                      width: 48,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF27272A),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // Title
                  Row(
                    children: [
                      const Icon(
                        Icons.security_rounded,
                        color: Color(0xFF22C55E),
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'LOCK-KEY ASSET VERIFICATION',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF27272A),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            stage?.name ?? 'NO STAGE SELECTED',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFFA1A1AA),
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Sequence Stepper
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _StepChip(
                        stepNumber: '1',
                        label: 'Scan Machine',
                        isCompleted: _scannedMachine != null,
                        isActive: _scannedMachine == null,
                      ),
                      const SizedBox(
                        width: 32,
                        height: 1,
                        child: ColoredBox(color: Color(0xFF27272A)),
                      ),
                      _StepChip(
                        stepNumber: '2',
                        label: 'Scan Die',
                        isCompleted: _scannedDie != null,
                        isActive:
                            _scannedMachine != null && _scannedDie == null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Barcode text field wrapper to keep key compatible with widget tests
                  KeyedSubtree(
                    key: const Key('machine_scanner_field'),
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF18181B),
                        border: Border.all(
                          color: hasError
                              ? const Color(0xFFEF4444)
                              : isComplete
                              ? const Color(0xFF22C55E)
                              : const Color(0xFF27272A),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.qr_code_scanner_rounded,
                            color: hasError
                                ? const Color(0xFFEF4444)
                                : isComplete
                                ? const Color(0xFF22C55E)
                                : const Color(0xFFA1A1AA),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: TextField(
                              controller: _inputController,
                              focusNode: _scannerFocusNode,
                              enabled: !isComplete,
                              style: const TextStyle(
                                color: Colors.white,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                              onSubmitted: _onSubmitted,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                hintText: scannerPrompt,
                                hintStyle: const TextStyle(
                                  color: Color(0xFF52525B),
                                ),
                                border: InputBorder.none,
                              ),
                            ),
                          ),
                          if (isComplete || hasError)
                            IconButton(
                              icon: const Icon(
                                Icons.refresh_rounded,
                                color: Color(0xFFA1A1AA),
                              ),
                              onPressed: _resetScanner,
                              tooltip: 'Reset Scanner',
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Side-by-side expected vs actual comparison view
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final expected = _ComparisonCard(
                        title: 'EXPECTED SYSTEM SPEC',
                        cardColor: const Color(0xFF18181B),
                        borderColor: const Color(0xFF27272A),
                        machineSpecs: expMachineSpecs,
                        dieSpecs: expDieSpecs,
                      );
                      final actual = _ComparisonCard(
                        title: 'SCANNED ACTUAL ASSET',
                        cardColor: hasError
                            ? const Color(0xFF2A0F10)
                            : isComplete
                            ? const Color(0xFF0F2D1A)
                            : const Color(0xFF18181B),
                        borderColor: hasError
                            ? const Color(0xFF7F1D1D)
                            : isComplete
                            ? const Color(0xFF14532D)
                            : const Color(0xFF27272A),
                        machineSpecs: actualMachineSpecs,
                        dieSpecs: actualDieSpecs,
                        showPlaceholder: !isComplete && !hasError,
                      );

                      if (constraints.maxWidth < 760) {
                        return Column(
                          children: [
                            expected,
                            const SizedBox(height: 12),
                            actual,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: expected),
                          const SizedBox(width: 16),
                          Expanded(child: actual),
                        ],
                      );
                    },
                  ),

                  // Mismatch Warning Chip/Card
                  if (hasError) ...[
                    const SizedBox(height: 18),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7F1D1D).withValues(alpha: 0.3),
                        border: Border.all(
                          color: const Color(0xFFEF4444),
                          width: 1.5,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFEF4444),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'SPECIFICATION MISMATCH DETECTED',
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    color: Color(0xFFFCA5A5),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Action Row
                  OverflowBar(
                    alignment: MainAxisAlignment.spaceBetween,
                    overflowAlignment: OverflowBarAlignment.end,
                    overflowSpacing: 8,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFA1A1AA),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 16,
                          ),
                        ),
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (hasError)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: _resetScanner,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text(
                            'Reset & Scan Again',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          key: const Key('confirm_start_button'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF22C55E),
                            foregroundColor: const Color(0xFF09090B),
                            disabledBackgroundColor: const Color(0xFF27272A),
                            disabledForegroundColor: const Color(0xFF52525B),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 16,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          onPressed: (isComplete && !hasError)
                              ? _confirmAndStart
                              : null,
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text(
                            'Start Stage Run',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.stepNumber,
    required this.label,
    required this.isCompleted,
    required this.isActive,
  });

  final String stepNumber;
  final String label;
  final bool isCompleted;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    Color bg = const Color(0xFF18181B);
    Color text = const Color(0xFF52525B);
    Color circleBg = const Color(0xFF27272A);
    Color circleText = const Color(0xFF52525B);

    if (isCompleted) {
      bg = const Color(0xFF0F2D1A);
      text = const Color(0xFF4ADE80);
      circleBg = const Color(0xFF22C55E);
      circleText = const Color(0xFF09090B);
    } else if (isActive) {
      bg = const Color(0xFF27272A);
      text = Colors.white;
      circleBg = Colors.white;
      circleText = const Color(0xFF09090B);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: isActive ? Border.all(color: Colors.white24) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 8,
            backgroundColor: circleBg,
            child: isCompleted
                ? Icon(Icons.check, size: 10, color: circleText)
                : Text(
                    stepNumber,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: circleText,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: text,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _ComparisonCard extends StatelessWidget {
  const _ComparisonCard({
    required this.title,
    required this.cardColor,
    required this.borderColor,
    this.machineSpecs,
    this.dieSpecs,
    this.showPlaceholder = false,
  });

  final String title;
  final Color cardColor;
  final Color borderColor;
  final AssetSpecs? machineSpecs;
  final AssetSpecs? dieSpecs;
  final bool showPlaceholder;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: Color(0xFFA1A1AA),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 14),
          if (showPlaceholder)
            const SizedBox(
              height: 160,
              child: Center(
                child: Text(
                  'AWAITING SCANS...',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: Color(0xFF3F3F46),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            )
          else ...[
            _buildAssetSection('MACHINE', machineSpecs),
            const Divider(color: Colors.white10, height: 24),
            _buildAssetSection('DIE / TOOL', dieSpecs),
          ],
        ],
      ),
    );
  }

  Widget _buildAssetSection(String typeLabel, AssetSpecs? specs) {
    if (specs == null) {
      return SizedBox(
        height: 68,
        child: Center(
          child: Text(
            'WAITING FOR SCAN...',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                typeLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9,
                  color: Color(0xFF71717A),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                specs.id,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          specs.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        // Dimension spec row (Expected physical dimensions vs Scanned side-by-side)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                specs.dimensionLabel,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFA1A1AA), fontSize: 11),
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                specs.dimensionValue,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  color: Color(0xFF4ADE80),
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
        // Render other specs
        ...specs.otherSpecs.entries.map((e) {
          return Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    e.key,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF71717A),
                      fontSize: 11,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    e.value,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: Color(0xFFA1A1AA),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}
