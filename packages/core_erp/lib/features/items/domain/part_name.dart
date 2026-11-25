/// A part's name as people say it on the floor: with its number.
///
///     partNameWithNo('Patti', 1)  →  'Patti No. 1'
///     partNameWithNo('Patti', null) →  'Patti'
///
/// Owner, 2026-11-25: "when showing name of part show with number too … in
/// routing part will be Patti No. 1, then in raw material planning review
/// sheet show part name as Patti No. 1". The number is the part's Part No
/// (items.part_no) — the one the sheet's first line ends with.
String partNameWithNo(String name, int? partNo) {
  final trimmed = name.trim();
  if (partNo == null || partNo <= 0) return trimmed;
  // Already carries it (a label built twice must not read "No. 1 No. 1").
  if (trimmed.toLowerCase().endsWith(' no. $partNo')) return trimmed;
  return trimmed.isEmpty ? 'No. $partNo' : '$trimmed No. $partNo';
}
