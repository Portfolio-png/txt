import 'package:flutter/material.dart';
import '../../sheet_planning/domain/sheet_plan.dart';

enum AllocKind { material, item, die, scrap, machine }

class Alloc {
  final String id;
  final AllocKind kind;
  final String value;

  const Alloc({
    required this.id,
    required this.kind,
    required this.value,
  });

  Alloc copyWith({String? id, AllocKind? kind, String? value}) =>
      Alloc(id: id ?? this.id, kind: kind ?? this.kind, value: value ?? this.value);
}

class ProcessNode {
  final String id;
  final String name;
  final String processType; // 'Input' | 'Output' | 'Process'
  final int stageIndex;
  final int laneIndex;
  final bool isIntermediate;
  final bool isAssembly;
  final String customProcessCode;
  final String inputVar;
  final String outputVar;
  final List<Alloc> allocations;
  final SheetPlan? sheetPlan;
  final int intakeQty;

  const ProcessNode({
    required this.id,
    required this.name,
    this.processType = 'Process',
    this.stageIndex = 0,
    this.laneIndex = 0,
    this.isIntermediate = true,
    this.isAssembly = false,
    this.customProcessCode = '',
    this.inputVar = '(all)',
    this.outputVar = '(all)',
    this.allocations = const [],
    this.sheetPlan,
    this.intakeQty = 1,
  });

  ProcessNode copyWith({
    String? id,
    String? name,
    String? processType,
    int? stageIndex,
    int? laneIndex,
    bool? isIntermediate,
    bool? isAssembly,
    String? customProcessCode,
    String? inputVar,
    String? outputVar,
    List<Alloc>? allocations,
    SheetPlan? sheetPlan,
    int? intakeQty,
  }) {
    return ProcessNode(
      id: id ?? this.id,
      name: name ?? this.name,
      processType: processType ?? this.processType,
      stageIndex: stageIndex ?? this.stageIndex,
      laneIndex: laneIndex ?? this.laneIndex,
      isIntermediate: isIntermediate ?? this.isIntermediate,
      isAssembly: isAssembly ?? this.isAssembly,
      customProcessCode: customProcessCode ?? this.customProcessCode,
      inputVar: inputVar ?? this.inputVar,
      outputVar: outputVar ?? this.outputVar,
      allocations: allocations ?? this.allocations,
      sheetPlan: sheetPlan ?? this.sheetPlan,
      intakeQty: intakeQty ?? this.intakeQty,
    );
  }

  String? firstOf(AllocKind kind) {
    for (final a in allocations) {
      if (a.kind == kind && a.value.trim().isNotEmpty) return a.value;
    }
    return null;
  }

  List<Alloc> ofKind(AllocKind kind) =>
      allocations.where((a) => a.kind == kind).toList();
}

class ProcessCategory {
  final String key;
  final String label;
  final Color badgeBg;
  final Color badgeColor;
  final Color borderColor;

  const ProcessCategory({
    required this.key,
    required this.label,
    required this.badgeBg,
    required this.badgeColor,
    required this.borderColor,
  });
}

ProcessCategory getProcessCategory(ProcessNode node) {
  if (node.processType == 'Input') {
    return const ProcessCategory(
      key: 'input',
      label: 'RAW STOCK',
      badgeBg: Color(0xFFECFDF5),
      badgeColor: Color(0xFF059669),
      borderColor: Color(0xFFA7F3D0),
    );
  }
  if (node.processType == 'Output') {
    return const ProcessCategory(
      key: 'output',
      label: 'FINAL OUTPUT',
      badgeBg: Color(0xFFF0FDF4),
      badgeColor: Color(0xFF16A34A),
      borderColor: Color(0xFFBBF7D0),
    );
  }
  if (node.isAssembly || node.name.toLowerCase().contains('assembly')) {
    return const ProcessCategory(
      key: 'assembly',
      label: 'ASSEMBLY',
      badgeBg: Color(0xFFFFFBEB),
      badgeColor: Color(0xFFD97706),
      borderColor: Color(0xFFFDE68A),
    );
  }
  final name = node.name.toLowerCase();
  if (name.contains('slat') || name.contains('slit')) {
    return const ProcessCategory(
      key: 'slitting',
      label: 'SLITTING',
      badgeBg: Color(0xFFF0FDFA),
      badgeColor: Color(0xFF0D9488),
      borderColor: Color(0xFF99F6E4),
    );
  }
  if (name.contains('cut') || name.contains('blank') || name.contains('guillotine')) {
    return const ProcessCategory(
      key: 'cutting',
      label: 'BLANKING',
      badgeBg: Color(0xFFEEF2FF),
      badgeColor: Color(0xFF4F46E5),
      borderColor: Color(0xFFC7D2FE),
    );
  }
  if (name.contains('plat') || name.contains('bath') || name.contains('finish') || name.contains('zinc')) {
    return const ProcessCategory(
      key: 'plating',
      label: 'FINISHING',
      badgeBg: Color(0xFFFAF5FF),
      badgeColor: Color(0xFF9333EA),
      borderColor: Color(0xFFE9D5FF),
    );
  }
  return const ProcessCategory(
    key: 'process',
    label: 'PROCESS',
    badgeBg: Color(0xFFF8FAFC),
    badgeColor: Color(0xFF475569),
    borderColor: Color(0xFFE2E8F0),
  );
}
