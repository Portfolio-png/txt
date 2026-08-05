/// Which optional sections the item editor shows.
///
/// This is a personal form layout, not a policy: it is stored per user (backend
/// key `item_form_sections`) and applies to every place the item editor opens,
/// so turning a section off here turns it off for new-item creation across the
/// app.
///
/// The identity fields — name, group, unit, naming format — are deliberately
/// not configurable; an item cannot be created without them.
class ItemFormSections {
  const ItemFormSections({
    this.itemImage = true,
    this.cadFile = true,
    this.additionalFiles = true,
    this.developedFor = true,
    this.defaultPipeline = true,
    this.variationTree = true,
    this.machines = false,
    this.dies = false,
  });

  /// Media group.
  final bool itemImage;
  final bool cadFile;
  final bool additionalFiles;

  /// The "Developed for" client link in Item Details.
  final bool developedFor;

  final bool defaultPipeline;
  final bool variationTree;
  final bool machines;
  final bool dies;

  /// Whether any member of the Media group is on — the group header hides
  /// entirely when they are all off.
  bool get hasAnyMedia => itemImage || cadFile || additionalFiles;

  ItemFormSections copyWith({
    bool? itemImage,
    bool? cadFile,
    bool? additionalFiles,
    bool? developedFor,
    bool? defaultPipeline,
    bool? variationTree,
    bool? machines,
    bool? dies,
  }) {
    return ItemFormSections(
      itemImage: itemImage ?? this.itemImage,
      cadFile: cadFile ?? this.cadFile,
      additionalFiles: additionalFiles ?? this.additionalFiles,
      developedFor: developedFor ?? this.developedFor,
      defaultPipeline: defaultPipeline ?? this.defaultPipeline,
      variationTree: variationTree ?? this.variationTree,
      machines: machines ?? this.machines,
      dies: dies ?? this.dies,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'itemImage': itemImage,
      'cadFile': cadFile,
      'additionalFiles': additionalFiles,
      'developedFor': developedFor,
      'defaultPipeline': defaultPipeline,
      'variationTree': variationTree,
      'machines': machines,
      'dies': dies,
    };
  }

  /// Missing keys fall back to [defaults], so a stored preference written by an
  /// older build keeps working when a new section is added.
  factory ItemFormSections.fromJson(Map<String, dynamic> json) {
    const defaults = ItemFormSections();
    bool read(String key, bool fallback) => json[key] as bool? ?? fallback;
    return ItemFormSections(
      itemImage: read('itemImage', defaults.itemImage),
      cadFile: read('cadFile', defaults.cadFile),
      additionalFiles: read('additionalFiles', defaults.additionalFiles),
      developedFor: read('developedFor', defaults.developedFor),
      defaultPipeline: read('defaultPipeline', defaults.defaultPipeline),
      variationTree: read('variationTree', defaults.variationTree),
      machines: read('machines', defaults.machines),
      dies: read('dies', defaults.dies),
    );
  }
}

/// Identifies one toggle, so the editor popover and the settings pane can both
/// render the same list without duplicating labels.
enum ItemFormSectionKey {
  itemImage,
  cadFile,
  additionalFiles,
  developedFor,
  defaultPipeline,
  variationTree,
  machines,
  dies,
}

extension ItemFormSectionKeyX on ItemFormSectionKey {
  String get label {
    switch (this) {
      case ItemFormSectionKey.itemImage:
        return 'Item image';
      case ItemFormSectionKey.cadFile:
        return 'CAD file';
      case ItemFormSectionKey.additionalFiles:
        return 'Additional files';
      case ItemFormSectionKey.developedFor:
        return 'Developed for';
      case ItemFormSectionKey.defaultPipeline:
        return 'Default pipeline';
      case ItemFormSectionKey.variationTree:
        return 'Variation tree';
      case ItemFormSectionKey.machines:
        return 'Machines';
      case ItemFormSectionKey.dies:
        return 'Dies';
    }
  }

  String get description {
    switch (this) {
      case ItemFormSectionKey.itemImage:
        return 'Product or reference photo.';
      case ItemFormSectionKey.cadFile:
        return 'Drawing or 3D model attached to the item.';
      case ItemFormSectionKey.additionalFiles:
        return 'Any number of extra files, each with your own label.';
      case ItemFormSectionKey.developedFor:
        return 'Link the item to the client it was developed for.';
      case ItemFormSectionKey.defaultPipeline:
        return 'Production pipeline this item defaults to.';
      case ItemFormSectionKey.variationTree:
        return 'Properties and values that spawn item variants.';
      case ItemFormSectionKey.machines:
        return 'Machines this item can be produced on.';
      case ItemFormSectionKey.dies:
        return 'Dies used to produce this item.';
    }
  }

  /// Media-group members render under a single collapsible header.
  bool get isMedia =>
      this == ItemFormSectionKey.itemImage ||
      this == ItemFormSectionKey.cadFile ||
      this == ItemFormSectionKey.additionalFiles;

  bool valueOf(ItemFormSections sections) {
    switch (this) {
      case ItemFormSectionKey.itemImage:
        return sections.itemImage;
      case ItemFormSectionKey.cadFile:
        return sections.cadFile;
      case ItemFormSectionKey.additionalFiles:
        return sections.additionalFiles;
      case ItemFormSectionKey.developedFor:
        return sections.developedFor;
      case ItemFormSectionKey.defaultPipeline:
        return sections.defaultPipeline;
      case ItemFormSectionKey.variationTree:
        return sections.variationTree;
      case ItemFormSectionKey.machines:
        return sections.machines;
      case ItemFormSectionKey.dies:
        return sections.dies;
    }
  }

  ItemFormSections applyTo(ItemFormSections sections, bool value) {
    switch (this) {
      case ItemFormSectionKey.itemImage:
        return sections.copyWith(itemImage: value);
      case ItemFormSectionKey.cadFile:
        return sections.copyWith(cadFile: value);
      case ItemFormSectionKey.additionalFiles:
        return sections.copyWith(additionalFiles: value);
      case ItemFormSectionKey.developedFor:
        return sections.copyWith(developedFor: value);
      case ItemFormSectionKey.defaultPipeline:
        return sections.copyWith(defaultPipeline: value);
      case ItemFormSectionKey.variationTree:
        return sections.copyWith(variationTree: value);
      case ItemFormSectionKey.machines:
        return sections.copyWith(machines: value);
      case ItemFormSectionKey.dies:
        return sections.copyWith(dies: value);
    }
  }
}
