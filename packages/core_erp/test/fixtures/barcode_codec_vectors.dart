// GENERATED — do not edit by hand.
//
// Produced from the real backend implementation (backend/kernel/barcodes.js)
// so the Dart mirror is checked against what the server actually does rather
// than against a reading of it. A mirror verified by hand-written expectations
// only proves the two agree with the author, not with each other.
//
// Regenerate: tool/regen_barcode_vectors.sh

class EncodeVector {
  const EncodeVector(this.type, this.id, this.code);
  final String type;
  final String id;
  final String? code;
}

class DecodeVector {
  const DecodeVector(this.input, {this.type, this.id, this.hasCheck, this.checkValid});
  final String input;
  final String? type;
  final String? id;
  final bool? hasCheck;
  final bool? checkValid;
  bool get isNull => type == null;
}

const List<EncodeVector> kEncodeVectors = <EncodeVector>[
  EncodeVector('MAT', 'REC-1-L1', 'MAT-REC-1-L1-Z'),
  EncodeVector('DC', 'REC-1-L1', 'DC-REC-1-L1-7'),
  EncodeVector('RC', 'REC-1-L1', 'RC-REC-1-L1-L'),
  EncodeVector('DCL', 'REC-1-L1', 'DCL-REC-1-L1-6'),
  EncodeVector('ORD', 'REC-1-L1', 'ORD-REC-1-L1-N'),
  EncodeVector('RUN', 'REC-1-L1', 'RUN-REC-1-L1-Q'),
  EncodeVector('MFG', 'REC-1-L1', 'MFG-REC-1-L1-6'),
  EncodeVector('EMP', 'REC-1-L1', 'EMP-REC-1-L1-3'),
  EncodeVector('DEP', 'REC-1-L1', 'DEP-REC-1-L1-M'),
  EncodeVector('PLN', 'REC-1-L1', 'PLN-REC-1-L1-6'),
  EncodeVector('CLI', 'REC-1-L1', 'CLI-REC-1-L1-E'),
  EncodeVector('VEN', 'REC-1-L1', 'VEN-REC-1-L1-Y'),
  EncodeVector('MCH', 'REC-1-L1', 'MCH-REC-1-L1-3'),
  EncodeVector('DIE', 'REC-1-L1', 'DIE-REC-1-L1-X'),
  EncodeVector('ITM', 'REC-1-L1', 'ITM-REC-1-L1-C'),
  EncodeVector('GRP', 'REC-1-L1', 'GRP-REC-1-L1-F'),
  EncodeVector('MOV', 'REC-1-L1', 'MOV-REC-1-L1-X'),
  EncodeVector('LOC', 'REC-1-L1', 'LOC-REC-1-L1-B'),
  EncodeVector('FLR', 'REC-1-L1', 'FLR-REC-1-L1-8'),
  EncodeVector('MAT', 'sheet-metal-flow', 'MAT-SHEET-METAL-FLOW-F'),
  EncodeVector('MAT', '  spaced  code ', 'MAT-SPACEDCODE-H'),
  EncodeVector('mat', 'lowercase-1', 'MAT-LOWERCASE-1-7'),
  EncodeVector('DC', '00042', 'DC-00042-L'),
  EncodeVector('RUN', '42', 'RUN-42-2'),
  EncodeVector('ITM', 'A', 'ITM-A-5'),
  EncodeVector('MFG', 'RUN-2026-0001', 'MFG-RUN-2026-0001-6'),
  EncodeVector('MAT', '', null),
  EncodeVector('NOPE', '1', null),
  EncodeVector('MAT', '   ', null),
  EncodeVector('LOC', 'MAIN', 'LOC-MAIN-5'),
  EncodeVector('LOC', 'Rack A1', 'LOC-RACKA1-V'),
  EncodeVector('FLR', 'Cutting bay', 'FLR-CUTTINGBAY-6'),
  EncodeVector('FLR', 'Assembly line 1', 'FLR-ASSEMBLYLINE1-Y'),
];

const List<DecodeVector> kDecodeVectors = <DecodeVector>[
  DecodeVector('MAT-REC-1-L1-K', type: 'MAT', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('DC-00042-L1', type: 'DC', id: '00042-L1', hasCheck: false, checkValid: true),
  DecodeVector('RUN-A', type: 'RUN', id: 'A', hasCheck: false, checkValid: true),
  DecodeVector('ITM-A', type: 'ITM', id: 'A', hasCheck: false, checkValid: true),
  DecodeVector(''),
  DecodeVector('FOO-1'),
  DecodeVector('MAT'),
  DecodeVector('mat-rec-1-l1-k', type: 'MAT', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector(' MAT-REC-1-L1-K ', type: 'MAT', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('MAT-REC-1-L1-Z', type: 'MAT', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('DC-00042', type: 'DC', id: '00042', hasCheck: false, checkValid: true),
  DecodeVector('MFG-RUN-2026-0001', type: 'MFG', id: 'RUN-2026-0001', hasCheck: false, checkValid: true),
  DecodeVector('MAT-REC-1-L1-0', type: 'MAT', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('DC-REC-1-L1-7', type: 'DC', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('DC-REC-1-L1-0', type: 'DC', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('RC-REC-1-L1-L', type: 'RC', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('RC-REC-1-L1-0', type: 'RC', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('DCL-REC-1-L1-6', type: 'DCL', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('DCL-REC-1-L1-0', type: 'DCL', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('ORD-REC-1-L1-N', type: 'ORD', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('ORD-REC-1-L1-0', type: 'ORD', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('RUN-REC-1-L1-Q', type: 'RUN', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('RUN-REC-1-L1-0', type: 'RUN', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('MFG-REC-1-L1-6', type: 'MFG', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('MFG-REC-1-L1-0', type: 'MFG', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('EMP-REC-1-L1-3', type: 'EMP', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('EMP-REC-1-L1-0', type: 'EMP', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('DEP-REC-1-L1-M', type: 'DEP', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('DEP-REC-1-L1-0', type: 'DEP', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('PLN-REC-1-L1-6', type: 'PLN', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('PLN-REC-1-L1-0', type: 'PLN', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('CLI-REC-1-L1-E', type: 'CLI', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('CLI-REC-1-L1-0', type: 'CLI', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('VEN-REC-1-L1-Y', type: 'VEN', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('VEN-REC-1-L1-0', type: 'VEN', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('MCH-REC-1-L1-3', type: 'MCH', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('MCH-REC-1-L1-0', type: 'MCH', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('DIE-REC-1-L1-X', type: 'DIE', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('DIE-REC-1-L1-0', type: 'DIE', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('ITM-REC-1-L1-C', type: 'ITM', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('ITM-REC-1-L1-0', type: 'ITM', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('GRP-REC-1-L1-F', type: 'GRP', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('GRP-REC-1-L1-0', type: 'GRP', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('MOV-REC-1-L1-X', type: 'MOV', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('MOV-REC-1-L1-0', type: 'MOV', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('LOC-REC-1-L1-B', type: 'LOC', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('LOC-REC-1-L1-0', type: 'LOC', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('FLR-REC-1-L1-8', type: 'FLR', id: 'REC-1-L1', hasCheck: true, checkValid: true),
  DecodeVector('FLR-REC-1-L1-0', type: 'FLR', id: 'REC-1-L1', hasCheck: true, checkValid: false),
  DecodeVector('MAT-SHEET-METAL-FLOW-F', type: 'MAT', id: 'SHEET-METAL-FLOW', hasCheck: true, checkValid: true),
  DecodeVector('MAT-SHEET-METAL-FLOW-0', type: 'MAT', id: 'SHEET-METAL-FLOW', hasCheck: true, checkValid: false),
  DecodeVector('MAT-SPACEDCODE-H', type: 'MAT', id: 'SPACEDCODE', hasCheck: true, checkValid: true),
  DecodeVector('MAT-SPACEDCODE-0', type: 'MAT', id: 'SPACEDCODE', hasCheck: true, checkValid: false),
  DecodeVector('MAT-LOWERCASE-1-7', type: 'MAT', id: 'LOWERCASE-1', hasCheck: true, checkValid: true),
  DecodeVector('MAT-LOWERCASE-1-0', type: 'MAT', id: 'LOWERCASE-1', hasCheck: true, checkValid: false),
  DecodeVector('DC-00042-L', type: 'DC', id: '00042', hasCheck: true, checkValid: true),
  DecodeVector('DC-00042-0', type: 'DC', id: '00042', hasCheck: true, checkValid: false),
  DecodeVector('RUN-42-2', type: 'RUN', id: '42', hasCheck: true, checkValid: true),
  DecodeVector('RUN-42-0', type: 'RUN', id: '42', hasCheck: true, checkValid: false),
  DecodeVector('ITM-A-5', type: 'ITM', id: 'A', hasCheck: true, checkValid: true),
  DecodeVector('ITM-A-0', type: 'ITM', id: 'A', hasCheck: true, checkValid: false),
  DecodeVector('MFG-RUN-2026-0001-6', type: 'MFG', id: 'RUN-2026-0001', hasCheck: true, checkValid: true),
  DecodeVector('MFG-RUN-2026-0001-0', type: 'MFG', id: 'RUN-2026-0001', hasCheck: true, checkValid: false),
  DecodeVector('LOC-MAIN-5', type: 'LOC', id: 'MAIN', hasCheck: true, checkValid: true),
  DecodeVector('LOC-MAIN-0', type: 'LOC', id: 'MAIN', hasCheck: true, checkValid: false),
  DecodeVector('LOC-RACKA1-V', type: 'LOC', id: 'RACKA1', hasCheck: true, checkValid: true),
  DecodeVector('LOC-RACKA1-0', type: 'LOC', id: 'RACKA1', hasCheck: true, checkValid: false),
  DecodeVector('FLR-CUTTINGBAY-6', type: 'FLR', id: 'CUTTINGBAY', hasCheck: true, checkValid: true),
  DecodeVector('FLR-CUTTINGBAY-0', type: 'FLR', id: 'CUTTINGBAY', hasCheck: true, checkValid: false),
  DecodeVector('FLR-ASSEMBLYLINE1-Y', type: 'FLR', id: 'ASSEMBLYLINE1', hasCheck: true, checkValid: true),
  DecodeVector('FLR-ASSEMBLYLINE1-0', type: 'FLR', id: 'ASSEMBLYLINE1', hasCheck: true, checkValid: false),
];
