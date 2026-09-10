import '../../sheet_planning/domain/sheet_plan.dart';
import 'pipeline_template.dart';
import 'process_node.dart';

const List<String> seedItems = [
  'MS Sheet 1.2mm',
  'MS Sheet 0.8mm',
  'Brass Strip 0.6mm',
  'MS Slit Strips (8)',
  'Enclosure Blank 145×260',
  'Plated Enclosure Blank',
  'Precision Enclosure Sub-Assy',
];

const List<String> seedDies = [
  'D-SE-BLANK-01',
  'D-SE-PIERCE-01',
  'D-SE-FORM-01',
  'D-G9-BLANK-01',
];

const List<String> seedScrapItems = [
  'Edge Trim Scrap',
  'Offcut Tail Scrap',
  'MS Scrap',
  'Brass Scrap',
  'Aluminium Scrap',
];

class MachineGroupData {
  final String name;
  final List<String> machines;
  const MachineGroupData(this.name, this.machines);
}

const List<MachineGroupData> seedMachineGroups = [
  MachineGroupData('Shearing & Slitting', ['RS-1250', 'G-300']),
  MachineGroupData('Power Press', ['PP-40T-01', 'PP-40T-02', 'PP-63T-01']),
  MachineGroupData('Plating Line', ['PL-ZN-01', 'PL-NI-01']),
  MachineGroupData('Assembly Bay', ['AB-01', 'AB-02']),
  MachineGroupData('Material Handling', ['Overhead Crane']),
];

PipelineTemplate create5StagePipelineTemplate() {
  final slittingPlan = SheetPlan.empty().copyWith(
    sheetWidthInches: 48,
    sheetHeightInches: 96,
    sheetThicknessMm: 1.2,
    edgeTrimMm: 10,
    kerfMm: 2,
    materialName: 'Steel / MS',
    bands: [const Band(sizeMm: 145, count: 8)],
    subCuts: {},
  );

  final cuttingPlan = SheetPlan.empty().copyWith(
    sheetWidthInches: 48,
    sheetHeightInches: 96,
    sheetThicknessMm: 1.2,
    edgeTrimMm: 10,
    kerfMm: 2,
    materialName: 'Steel / MS',
    bands: [const Band(sizeMm: 145, count: 8)],
    subCuts: {
      0: [const SubCut(sizeMm: 260, count: 9)],
    },
    plannedPartName: 'Enclosure Blank 145×260',
  );

  final nodes = [
    const ProcessNode(
      id: 'st1',
      name: 'Raw Sheet Inward',
      processType: 'Input',
      stageIndex: 0,
      laneIndex: 0,
      isIntermediate: false,
      intakeQty: 1,
      allocations: [
        Alloc(id: 'a1', kind: AllocKind.material, value: 'MS Sheet 1.2mm'),
        Alloc(id: 'a2', kind: AllocKind.machine, value: 'Overhead Crane'),
      ],
    ),
    ProcessNode(
      id: 'st2',
      name: 'Slating (8 Strips)',
      stageIndex: 1,
      laneIndex: 0,
      allocations: const [
        Alloc(id: 'a3', kind: AllocKind.material, value: 'MS Sheet 1.2mm'),
        Alloc(id: 'a4', kind: AllocKind.item, value: 'MS Slit Strips (8)'),
        Alloc(id: 'a5', kind: AllocKind.machine, value: 'RS-1250'),
        Alloc(id: 'a6', kind: AllocKind.scrap, value: 'Edge Trim Scrap'),
      ],
      sheetPlan: slittingPlan,
    ),
    ProcessNode(
      id: 'st3',
      name: 'Cutting (72 Blanks)',
      stageIndex: 2,
      laneIndex: 0,
      allocations: const [
        Alloc(id: 'a7', kind: AllocKind.material, value: 'MS Slit Strips (8)'),
        Alloc(id: 'a8', kind: AllocKind.item, value: 'Enclosure Blank 145×260'),
        Alloc(id: 'a9', kind: AllocKind.machine, value: 'G-300'),
        Alloc(id: 'a10', kind: AllocKind.scrap, value: 'Offcut Tail Scrap'),
      ],
      sheetPlan: cuttingPlan,
    ),
    const ProcessNode(
      id: 'st4',
      name: 'Electroplating Bath',
      stageIndex: 3,
      laneIndex: 0,
      allocations: [
        Alloc(id: 'a11', kind: AllocKind.material, value: 'Enclosure Blank 145×260'),
        Alloc(id: 'a12', kind: AllocKind.item, value: 'Plated Enclosure Blank'),
        Alloc(id: 'a13', kind: AllocKind.machine, value: 'PL-ZN-01'),
      ],
    ),
    const ProcessNode(
      id: 'st5',
      name: 'Sub-Assembly Workstation',
      stageIndex: 4,
      laneIndex: 0,
      isAssembly: true,
      allocations: [
        Alloc(id: 'a14', kind: AllocKind.material, value: 'Plated Enclosure Blank'),
        Alloc(id: 'a15', kind: AllocKind.item, value: 'Precision Enclosure Sub-Assy'),
        Alloc(id: 'a16', kind: AllocKind.machine, value: 'AB-01'),
      ],
    ),
  ];

  final flows = [
    const PipelineFlow(fromNodeId: 'st1', toNodeId: 'st2'),
    const PipelineFlow(fromNodeId: 'st2', toNodeId: 'st3'),
    const PipelineFlow(fromNodeId: 'st3', toNodeId: 'st4'),
    const PipelineFlow(fromNodeId: 'st4', toNodeId: 'st5'),
  ];

  return PipelineTemplate(
    id: 'tpl-5stage',
    name: 'Precision Enclosure — 5 Stage Transformation Line',
    stageLabels: const ['Raw Stock', 'Slating (8 Strips)', 'Cutting (72 Blanks)', 'Plating', 'Sub-Assembly'],
    nodes: nodes,
    flows: flows,
  );
}

PipelineRun create5StagePipelineRun() {
  return const PipelineRun(
    id: 'r0',
    orderNo: 'ORD-9001',
    clientName: 'Siemens Precision',
    templateId: 'tpl-5stage',
    createdAt: '2026-09-05',
    nodeStatuses: {
      'st1': 'done',
      'st2': 'done',
      'st3': 'active',
      'st4': 'pending',
      'st5': 'pending',
    },
  );
}
