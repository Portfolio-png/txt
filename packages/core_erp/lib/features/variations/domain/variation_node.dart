/// One node of a master's variation tree: a property, or one of its values.
///
/// Mutable on purpose. This is what an editor holds while someone is typing
/// into it, and copying the whole tree on every keystroke to keep it immutable
/// would buy nothing — the tree is small and has exactly one editor.
class VariationNode {
  VariationNode({
    this.id,
    required this.kind,
    this.name = '',
    this.code = '',
    this.displayName = '',
    this.inputType = 'Text',
    this.numericMin,
    this.numericMax,
    this.materialTypeId,
    this.version = 1,
    List<VariationNode>? children,
  }) : children = children ?? <VariationNode>[];

  /// Null until the server has stored it — which is also what makes it an
  /// addition rather than a change, and so always allowed.
  int? id;

  /// 'property' or 'value'.
  final String kind;

  String name;
  String code;
  String displayName;

  /// 'Text', 'Numeric', 'Gauge', or 'Material'. Properties only.
  String inputType;

  double? numericMin;
  double? numericMax;

  /// Which material type this value stands for when under a 'Material' property.
  int? materialTypeId;

  /// The version this node was last written in. The tree is fixed while the
  /// owner's current version is no higher than this.
  int version;

  final List<VariationNode> children;

  bool get isProperty => kind == 'property';
  bool get isValue => kind == 'value';

  /// New here, so nothing downstream can have been derived from it.
  bool get isNew => id == null;

  VariationNode copy() => VariationNode(
    id: id,
    kind: kind,
    name: name,
    code: code,
    displayName: displayName,
    inputType: inputType,
    numericMin: numericMin,
    numericMax: numericMax,
    materialTypeId: materialTypeId,
    version: version,
    children: [for (final child in children) child.copy()],
  );

  static VariationNode? fromJson(Map<String, dynamic> json) {
    final kind = (json['kind'] as String?)?.trim();
    if (kind != 'property' && kind != 'value') return null;
    return VariationNode(
      id: json['id'] is int ? json['id'] as int : int.tryParse('${json['id']}'),
      kind: kind!,
      name: (json['name'] as String?)?.trim() ?? '',
      code: (json['code'] as String?)?.trim() ?? '',
      displayName: (json['displayName'] as String?)?.trim() ?? '',
      inputType: (json['inputType'] as String?)?.trim().isNotEmpty == true
          ? (json['inputType'] as String).trim()
          : 'Text',
      numericMin: (json['numericMin'] as num?)?.toDouble(),
      numericMax: (json['numericMax'] as num?)?.toDouble(),
      materialTypeId: json['materialTypeId'] is int
          ? json['materialTypeId'] as int
          : int.tryParse('${json['materialTypeId']}'),
      version: (json['version'] as num?)?.toInt() ?? 1,
      children: [
        for (final child in (json['children'] as List?) ?? const [])
          if (child is Map<String, dynamic>) ?VariationNode.fromJson(child),
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    if (id != null) 'id': id,
    'kind': kind,
    'name': name,
    'code': code,
    'displayName': displayName,
    'inputType': inputType,
    'numericMin': numericMin,
    'numericMax': numericMax,
    if (materialTypeId != null) 'materialTypeId': materialTypeId,
    'children': [for (final child in children) child.toJson()],
  };
}

/// A master's whole tree, and the version it is on.
class VariationTree {
  const VariationTree({
    required this.nodes,
    this.version = 1,
    this.label = '',
  });

  final List<VariationNode> nodes;
  final int version;

  /// What the shop calls this version — 'Rev B'. Empty until one is declared.
  final String label;

  static const VariationTree empty = VariationTree(nodes: []);

  bool get isEmpty => nodes.isEmpty;

  /// The highest version any node was written in. While the tree's own version
  /// is no higher than this, everything already in it is fixed: the current
  /// version describes the tree as it stands, so changing it would rewrite
  /// that description. See the backend's THE VERSION RULE.
  int get highestWritten =>
      nodes.isEmpty ? 0 : _highest(nodes);

  static int _highest(List<VariationNode> nodes) {
    var highest = 0;
    for (final node in nodes) {
      if (node.version > highest) highest = node.version;
      final deeper = _highest(node.children);
      if (deeper > highest) highest = deeper;
    }
    return highest;
  }

  /// True when what is already in the tree cannot be changed without a new
  /// version being declared first. Adding is never locked.
  bool get isLocked => nodes.isNotEmpty && version <= highestWritten;

  static VariationTree fromJson(Map<String, dynamic> json) => VariationTree(
    version: (json['version'] as num?)?.toInt() ?? 1,
    label: (json['label'] as String?)?.trim() ?? '',
    nodes: [
      for (final node in (json['nodes'] as List?) ?? const [])
        if (node is Map<String, dynamic>) ?VariationNode.fromJson(node),
    ],
  );
}
