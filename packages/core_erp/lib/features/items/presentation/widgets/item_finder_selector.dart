import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/soft_erp_theme.dart';
import '../../../groups/domain/group_definition.dart';
import '../../../groups/presentation/providers/groups_provider.dart';
import '../../domain/item_definition.dart';
import '../providers/items_provider.dart';

class ItemFinderSelectorDialog extends StatefulWidget {
  const ItemFinderSelectorDialog({super.key});

  @override
  State<ItemFinderSelectorDialog> createState() => _ItemFinderSelectorDialogState();
}

class _ItemFinderSelectorDialogState extends State<ItemFinderSelectorDialog> {
  // The path of selected items: can contain Group or ItemDefinition
  final List<dynamic> _selectedPath = [];
  String _searchQuery = '';
  final ScrollController _horizontalScrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    final groupsProvider = context.watch<GroupsProvider>();
    final itemsProvider = context.watch<ItemsProvider>();

    final allGroupDefinitions = groupsProvider.groups;
    final allItems = itemsProvider.items;
    final baseItems = allItems.where((i) => i.baseItemId == null).toList();
    final variations = allItems.where((i) => i.baseItemId != null).toList();

    return Dialog(
      backgroundColor: SoftErpTheme.shellSurface,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 1000,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            Expanded(
              child: _searchQuery.isNotEmpty
                  ? _buildSearchResults(allGroupDefinitions, baseItems, variations)
                  : _buildFinderColumns(allGroupDefinitions, baseItems, variations),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const Text(
          'Select Item',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: SoftErpTheme.textPrimary,
          ),
        ),
        const SizedBox(width: 24),
        Expanded(
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search groups, base items, or variations...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: SoftErpTheme.cardSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (val) {
              setState(() {
                _searchQuery = val.trim().toLowerCase();
              });
            },
          ),
        ),
        const SizedBox(width: 16),
        IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildFinderColumns(
    List<GroupDefinition> allGroupDefinitions,
    List<ItemDefinition> baseItems,
    List<ItemDefinition> variations,
  ) {
    // Generate columns
    final columns = <Widget>[];

    // Column 0: Root
    columns.add(_buildColumn(
      level: 0,
      groups: allGroupDefinitions.where((g) => g.parentGroupId == null).toList(),
      items: baseItems.where((i) => allGroupDefinitions.where((g) => g.id == i.groupId).isEmpty || i.groupId == -1).toList(), // fallback
      allGroupDefinitions: allGroupDefinitions,
      baseItems: baseItems,
      variations: variations,
    ));

    // Subsequent columns based on path
    for (int i = 0; i < _selectedPath.length; i++) {
      final node = _selectedPath[i];
      if (node is GroupDefinition) {
        columns.add(_buildColumn(
          level: i + 1,
          groups: allGroupDefinitions.where((g) => g.parentGroupId == node.id).toList(),
          items: baseItems.where((item) => item.groupId == node.id).toList(),
          allGroupDefinitions: allGroupDefinitions,
          baseItems: baseItems,
          variations: variations,
        ));
      } else if (node is ItemDefinition) {
        columns.add(_buildColumn(
          level: i + 1,
          groups: [],
          items: variations.where((item) => item.baseItemId == node.id).toList(),
          allGroupDefinitions: allGroupDefinitions,
          baseItems: baseItems,
          variations: variations,
        ));
      }
    }

    // Auto-scroll to the right when a new column is added
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_horizontalScrollController.hasClients) {
        _horizontalScrollController.animateTo(
          _horizontalScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;

        if (isMobile) {
          // Mobile layout: show only the last active column with a back button
          return Column(
            children: [
              if (_selectedPath.isNotEmpty)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 14),
                    label: Text(_selectedPath.length == 1 ? 'Root' : _nameForNode(_selectedPath[_selectedPath.length - 2])),
                    onPressed: () {
                      setState(() {
                        _selectedPath.removeLast();
                      });
                    },
                  ),
                ),
              Expanded(child: columns.last),
            ],
          );
        }

        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: SoftErpTheme.border),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: ListView.separated(
            controller: _horizontalScrollController,
            scrollDirection: Axis.horizontal,
            itemCount: columns.length,
            separatorBuilder: (context, index) => const VerticalDivider(
              width: 1,
              thickness: 1,
              color: SoftErpTheme.border,
            ),
            itemBuilder: (context, index) {
              return SizedBox(
                width: 260, // Fixed width for finder columns
                child: columns[index],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildColumn({
    required int level,
    required List<GroupDefinition> groups,
    required List<ItemDefinition> items,
    required List<GroupDefinition> allGroupDefinitions,
    required List<ItemDefinition> baseItems,
    required List<ItemDefinition> variations,
  }) {
    if (groups.isEmpty && items.isEmpty) {
      return const Center(
        child: Text(
          'Empty',
          style: TextStyle(color: SoftErpTheme.textSecondary),
        ),
      );
    }

    // Sort: GroupDefinitions first, then Items
    groups.sort((a, b) => a.name.compareTo(b.name));
    items.sort((a, b) => a.displayName.compareTo(b.displayName));

    return ListView(
      children: [
        for (final g in groups) _buildGroupDefinitionTile(g, level),
        for (final i in items) _buildItemTile(i, level, variations),
      ],
    );
  }

  Widget _buildGroupDefinitionTile(GroupDefinition group, int level) {
    final isSelected = _selectedPath.length > level && _selectedPath[level] == group;
    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: SoftErpTheme.accentSoft,
      leading: const Icon(Icons.folder_outlined, color: SoftErpTheme.textSecondary, size: 20),
      title: Text(
        group.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? SoftErpTheme.accentDark : SoftErpTheme.textPrimary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 16, color: SoftErpTheme.textSecondary),
      onTap: () {
        setState(() {
          // Trim path up to this level, then add this group
          if (_selectedPath.length > level) {
            _selectedPath.removeRange(level, _selectedPath.length);
          }
          _selectedPath.add(group);
        });
      },
    );
  }

  Widget _buildItemTile(ItemDefinition item, int level, List<ItemDefinition> allVariations) {
    final isBase = item.baseItemId == null;
    final isSelected = _selectedPath.length > level && _selectedPath[level] == item;
    
    // Check if this base item has variations
    final hasVariations = isBase && allVariations.any((v) => v.baseItemId == item.id);

    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: SoftErpTheme.accentSoft,
      leading: Icon(
        isBase ? Icons.inventory_2_outlined : Icons.bubble_chart_outlined,
        color: SoftErpTheme.accent,
        size: 20,
      ),
      title: Text(
        item.displayName.isNotEmpty ? item.displayName : item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          color: isSelected ? SoftErpTheme.accentDark : SoftErpTheme.textPrimary,
        ),
      ),
      trailing: hasVariations
          ? const Icon(Icons.chevron_right_rounded, size: 16, color: SoftErpTheme.textSecondary)
          : null,
      onTap: () {
        if (hasVariations) {
          setState(() {
            // Trim path up to this level, then add this base item to open the variations column
            if (_selectedPath.length > level) {
              _selectedPath.removeRange(level, _selectedPath.length);
            }
            _selectedPath.add(item);
          });
        } else {
          // If it's a base item with no variations, or it IS a variation, we select it directly
          Navigator.of(context).pop(item.id);
        }
      },
    );
  }

  String _getFullPathForGroup(GroupDefinition group, List<GroupDefinition> allGroupDefinitions) {
    final pathSegments = <String>[group.name];
    GroupDefinition? currentGroup = allGroupDefinitions.where((g) => g.id == group.parentGroupId).firstOrNull;
    while (currentGroup != null) {
      pathSegments.insert(0, currentGroup.name);
      if (currentGroup.parentGroupId != null) {
        currentGroup = allGroupDefinitions.where((g) => g.id == currentGroup!.parentGroupId).firstOrNull;
      } else {
        currentGroup = null;
      }
    }
    return pathSegments.join(' / ');
  }

  String _getFullPathForItem(ItemDefinition item, List<GroupDefinition> allGroupDefinitions, List<ItemDefinition> baseItems) {
    final pathSegments = <String>[];
    
    ItemDefinition? baseItem;
    if (item.baseItemId != null) {
      baseItem = baseItems.where((i) => i.id == item.baseItemId).firstOrNull;
      if (baseItem != null) {
        pathSegments.insert(0, baseItem.displayName.isNotEmpty ? baseItem.displayName : baseItem.name);
      }
    } else {
      baseItem = item;
    }

    if (baseItem != null && baseItem.groupId > 0) {
      GroupDefinition? currentGroup = allGroupDefinitions.where((g) => g.id == baseItem!.groupId).firstOrNull;
      while (currentGroup != null) {
        pathSegments.insert(0, currentGroup.name);
        if (currentGroup.parentGroupId != null) {
          currentGroup = allGroupDefinitions.where((g) => g.id == currentGroup!.parentGroupId).firstOrNull;
        } else {
          currentGroup = null;
        }
      }
    }

    if (pathSegments.isEmpty) return 'Root';
    return pathSegments.join(' / ');
  }

  Widget _buildSearchResults(
    List<GroupDefinition> allGroupDefinitions,
    List<ItemDefinition> baseItems,
    List<ItemDefinition> variations,
  ) {
    final matchingGroupDefinitions = allGroupDefinitions.where((g) => g.name.toLowerCase().contains(_searchQuery)).toList();
    final matchingBase = baseItems.where((i) => 
      i.displayName.toLowerCase().contains(_searchQuery) || 
      i.name.toLowerCase().contains(_searchQuery) || 
      i.alias.toLowerCase().contains(_searchQuery)
    ).toList();
    final matchingVars = variations.where((i) => 
      i.displayName.toLowerCase().contains(_searchQuery) || 
      i.name.toLowerCase().contains(_searchQuery) || 
      i.alias.toLowerCase().contains(_searchQuery)
    ).toList();

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: SoftErpTheme.border),
        borderRadius: BorderRadius.circular(12),
        color: Colors.white,
      ),
      child: ListView(
        children: [
          if (matchingGroupDefinitions.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Groups', style: TextStyle(fontWeight: FontWeight.bold, color: SoftErpTheme.textSecondary)),
            ),
            for (final g in matchingGroupDefinitions)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(g.name),
                subtitle: Text(_getFullPathForGroup(g, allGroupDefinitions), style: const TextStyle(color: SoftErpTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  // Jump to this group in finder view
                  setState(() {
                    _searchQuery = '';
                    _buildPathToGroup(g, allGroupDefinitions);
                  });
                },
              ),
            const Divider(height: 1),
          ],
          if (matchingBase.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Base Items', style: TextStyle(fontWeight: FontWeight.bold, color: SoftErpTheme.textSecondary)),
            ),
            for (final i in matchingBase)
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(i.displayName.isNotEmpty ? i.displayName : i.name),
                subtitle: Text(_getFullPathForItem(i, allGroupDefinitions, baseItems), style: const TextStyle(color: SoftErpTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  final hasVariations = variations.any((v) => v.baseItemId == i.id);
                  if (hasVariations) {
                    setState(() {
                      _searchQuery = '';
                      _buildPathToBaseItem(i, allGroupDefinitions);
                    });
                  } else {
                    Navigator.of(context).pop(i.id);
                  }
                },
              ),
            const Divider(height: 1),
          ],
          if (matchingVars.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Variations', style: TextStyle(fontWeight: FontWeight.bold, color: SoftErpTheme.textSecondary)),
            ),
            for (final i in matchingVars)
              ListTile(
                leading: const Icon(Icons.bubble_chart_outlined),
                title: Text(i.displayName.isNotEmpty ? i.displayName : i.name),
                subtitle: Text(_getFullPathForItem(i, allGroupDefinitions, baseItems), style: const TextStyle(color: SoftErpTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.of(context).pop(i.id);
                },
              ),
          ],
        ],
      ),
    );
  }

  void _buildPathToGroup(GroupDefinition target, List<GroupDefinition> allGroupDefinitions) {
    _selectedPath.clear();
    final path = <GroupDefinition>[];
    GroupDefinition? current = target;
    while (current != null) {
      path.insert(0, current);
      if (current.parentGroupId == null) break;
      current = allGroupDefinitions.where((g) => g.id == current!.parentGroupId).firstOrNull;
    }
    _selectedPath.addAll(path);
  }

  void _buildPathToBaseItem(ItemDefinition target, List<GroupDefinition> allGroupDefinitions) {
    if (target.groupId <= 0) {
      _selectedPath.clear();
      _selectedPath.add(target);
      return;
    }
    final parentGroup = allGroupDefinitions.where((g) => g.id == target.groupId).firstOrNull;
    if (parentGroup != null) {
      _buildPathToGroup(parentGroup, allGroupDefinitions);
    } else {
      _selectedPath.clear();
    }
    _selectedPath.add(target);
  }

  String _nameForNode(dynamic node) {
    if (node is GroupDefinition) return node.name;
    if (node is ItemDefinition) return node.displayName.isNotEmpty ? node.displayName : node.name;
    return 'Unknown';
  }
}
