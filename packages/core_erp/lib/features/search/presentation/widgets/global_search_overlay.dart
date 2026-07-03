import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../providers/search_provider.dart';
import '../../domain/search_result.dart';
import '../../../delivery_challans/presentation/widgets/challan_excel_view.dart';

class _ConfigItem {
  final String propertyName;
  final String? value;
  final bool isHeader;
  _ConfigItem({required this.propertyName, this.value, this.isHeader = false});
}

class GlobalSearchOverlay extends StatefulWidget {
  const GlobalSearchOverlay({super.key});

  @override
  State<GlobalSearchOverlay> createState() => _GlobalSearchOverlayState();
}

class _GlobalSearchOverlayState extends State<GlobalSearchOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  int _selectedIndex = 0;
  String _lastQuery = '';
  bool _showPreview = false;

  // Configuration Mode
  bool _configMode = false;
  int _configSelectedIndex = 0;
  List<_ConfigItem> _currentConfigs = [];

  // Ledger Mode
  SearchResult? _ledgerResult;

  // Scroll
  final ScrollController _scrollController = ScrollController();
  final ScrollController _configScrollController = ScrollController();

  final List<GlobalKey> _itemKeys = List.generate(100, (_) => GlobalKey());
  final List<GlobalKey> _configKeys = List.generate(200, (_) => GlobalKey());

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 200),
        )..addStatusListener((status) {
          if (status == AnimationStatus.dismissed) {
            setState(() {}); // Rebuild to return SizedBox.shrink()
          }
        });
    _scaleAnimation = Tween<double>(
      begin: 0.95,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    _configScrollController.dispose();
    super.dispose();
  }

  void _scrollToIndex(int index, List<GlobalKey> keys) {
    if (index >= 0 && index < keys.length) {
      final context = keys[index].currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      }
    }
  }

  List<_ConfigItem> _buildFlatConfigs(List<dynamic> configs) {
    final list = <_ConfigItem>[];
    for (final c in configs) {
      if (c is Map<String, dynamic>) {
        final name = c['name'] as String? ?? '';
        final values = c['values'] as List<dynamic>? ?? [];
        list.add(_ConfigItem(propertyName: name, isHeader: true));
        for (final v in values) {
          list.add(_ConfigItem(propertyName: name, value: v.toString()));
        }
      }
    }
    return list;
  }

  void _handleSelection(
    BuildContext context,
    SearchProvider provider,
    SearchResult? result,
  ) async {
    if (result == null) return;

    // Record click for backend learning
    provider.recordClick(result);

    // Open In/Out Sheet if it's an item
    if (result.type == 'item') {
      final baseItemIdStr =
          result.metadata['baseItemId']?.toString() ??
          result.id.split('_').first;
      final itemId = int.tryParse(baseItemIdStr);
      final variationId = result.metadata['variationId'] as int?;

      if (itemId != null) {
        setState(() {
          _ledgerResult = result;
        });
      }
    } else if (result.type == 'material') {
      // In the future, we could open material in/out sheet here
      provider.hideOverlay();
    }
  }

  bool _hasConfigs(SearchResult result) {
    if (result.type != 'item') return false;
    final configs = result.metadata['configurations'] as List<dynamic>? ?? [];
    return configs.isNotEmpty;
  }

  void _updateConfigsForSelectedItem(List<SearchResult> items) {
    if (items.isNotEmpty && _selectedIndex < items.length) {
      final r = items[_selectedIndex];
      final configs = r.metadata['configurations'] as List<dynamic>? ?? [];
      _currentConfigs = _buildFlatConfigs(configs);
      if (_configSelectedIndex >= _currentConfigs.length) {
        _configSelectedIndex = _currentConfigs.indexWhere((c) => !c.isHeader);
        if (_configSelectedIndex == -1) _configSelectedIndex = 0;
      }
    } else {
      _currentConfigs = [];
      _configSelectedIndex = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchProvider>(
      builder: (context, provider, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (provider.isOverlayVisible &&
              !_controller.isAnimating &&
              _controller.status != AnimationStatus.completed) {
            _controller.forward();
            _focusNode.requestFocus();
            if (_textController.text != provider.query) {
              _textController.text = provider.query;
            }
          } else if (!provider.isOverlayVisible &&
              !_controller.isAnimating &&
              _controller.status != AnimationStatus.dismissed) {
            _controller.reverse();
            _focusNode.unfocus();
          }
        });

        if (!provider.isOverlayVisible &&
            _controller.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }

        // Reset selection if query changes
        if (_lastQuery != provider.query) {
          _selectedIndex = 0;
          _showPreview = false;
          _lastQuery = provider.query;
        }

        final items = provider.query.isEmpty
            ? <SearchResult>[]
            : provider.results;
        final history = provider.query.isEmpty ? provider.history : <String>[];
        final totalCount = provider.query.isEmpty
            ? history.length
            : items.length;

        // Clamp index
        if (_selectedIndex >= totalCount && totalCount > 0) {
          _selectedIndex = totalCount - 1;
        }

        // Always ensure configs are in sync with the current selection
        _updateConfigsForSelectedItem(items);

        final bool hasConfigs = _currentConfigs.isNotEmpty;
        double containerWidth = 450;
        double maxHeight = 450;

        if (_ledgerResult != null) {
          containerWidth = MediaQuery.of(context).size.width * 0.95;
          maxHeight = MediaQuery.of(context).size.height * 0.95;
        } else {
          if (hasConfigs) containerWidth += 250;
          if (_showPreview && items.isNotEmpty) containerWidth += 300;
        }

        return Stack(
          children: [
            GestureDetector(
              onTap: () {
                provider.hideOverlay();
              },
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 5.0, sigmaY: 5.0),
                  child: Container(
                    color: SoftErpTheme.cardSurfaceAlt.withOpacity(0.4),
                  ),
                ),
              ),
            ),
            Center(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Material(
                    color: Colors.transparent,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      width: containerWidth,
                      constraints: BoxConstraints(maxHeight: maxHeight),
                      margin: _ledgerResult != null
                          ? EdgeInsets.zero
                          : const EdgeInsets.only(bottom: 150),
                      decoration: BoxDecoration(
                        color: SoftErpTheme.cardSurface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 40,
                            offset: const Offset(0, 15),
                          ),
                        ],
                        border: Border.all(
                          color: SoftErpTheme.border.withOpacity(0.5),
                        ),
                      ),
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            if (_ledgerResult != null) {
                              if (event.logicalKey ==
                                      LogicalKeyboardKey.delete ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.escape ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.backspace) {
                                setState(() {
                                  _ledgerResult = null;
                                });
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            }
                            if (_configMode) {
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                if (_currentConfigs.isNotEmpty) {
                                  setState(() {
                                    do {
                                      _configSelectedIndex = min(
                                        _configSelectedIndex + 1,
                                        _currentConfigs.length - 1,
                                      );
                                    } while (_currentConfigs[_configSelectedIndex]
                                            .isHeader &&
                                        _configSelectedIndex <
                                            _currentConfigs.length - 1);
                                  });
                                  _scrollToIndex(
                                    _configSelectedIndex,
                                    _configKeys,
                                  );
                                }
                                return KeyEventResult.handled;
                              } else if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                if (_currentConfigs.isNotEmpty) {
                                  setState(() {
                                    do {
                                      _configSelectedIndex = max(
                                        _configSelectedIndex - 1,
                                        0,
                                      );
                                    } while (_currentConfigs[_configSelectedIndex]
                                            .isHeader &&
                                        _configSelectedIndex > 0);
                                  });
                                  _scrollToIndex(
                                    _configSelectedIndex,
                                    _configKeys,
                                  );
                                }
                                return KeyEventResult.handled;
                              } else if (event.logicalKey ==
                                      LogicalKeyboardKey.backspace ||
                                  event.logicalKey ==
                                      LogicalKeyboardKey.delete) {
                                setState(() {
                                  _configMode = false;
                                });
                                return KeyEventResult.handled;
                              } else if (event.logicalKey ==
                                  LogicalKeyboardKey.enter) {
                                if (_currentConfigs.isNotEmpty &&
                                    !_currentConfigs[_configSelectedIndex]
                                        .isHeader) {
                                  final val =
                                      _currentConfigs[_configSelectedIndex]
                                          .value!;
                                  _textController.text =
                                      '${_textController.text.trim()} $val';
                                  provider.search(_textController.text);
                                  setState(() {
                                    _configMode = false;
                                  });
                                }
                                return KeyEventResult.handled;
                              }
                            } else {
                              if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowDown) {
                                if (totalCount > 0) {
                                  setState(() {
                                    _selectedIndex = min(
                                      _selectedIndex + 1,
                                      totalCount - 1,
                                    );
                                  });
                                  _scrollToIndex(_selectedIndex, _itemKeys);
                                }
                                return KeyEventResult.handled;
                              } else if (event.logicalKey ==
                                  LogicalKeyboardKey.arrowUp) {
                                setState(() {
                                  _selectedIndex = max(_selectedIndex - 1, 0);
                                });
                                _scrollToIndex(_selectedIndex, _itemKeys);
                                return KeyEventResult.handled;
                              } else if (event.logicalKey ==
                                      LogicalKeyboardKey.keyL &&
                                  HardwareKeyboard.instance.isShiftPressed &&
                                  HardwareKeyboard.instance.isAltPressed) {
                                if (items.isNotEmpty &&
                                    _hasConfigs(items[_selectedIndex])) {
                                  setState(() {
                                    _configMode = true;
                                  });
                                }
                                return KeyEventResult.handled;
                              } else if (event.logicalKey ==
                                  LogicalKeyboardKey.enter) {
                                if (provider.query.isEmpty &&
                                    history.isNotEmpty) {
                                  _textController.text =
                                      history[_selectedIndex];
                                  provider.search(history[_selectedIndex]);
                                } else if (items.isNotEmpty) {
                                  if (!_showPreview) {
                                    setState(() {
                                      _showPreview = true;
                                    });
                                  } else {
                                    _handleSelection(
                                      context,
                                      provider,
                                      items[_selectedIndex],
                                    );
                                  }
                                }
                                return KeyEventResult.handled;
                              }
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: _ledgerResult != null
                            ? _buildEmbeddedLedger()
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20.0,
                                      vertical: 16.0,
                                    ),
                                    child: TextField(
                                      controller: _textController,
                                      focusNode: _focusNode,
                                      decoration: InputDecoration(
                                        hintText:
                                            'Search inventory, materials... (Cmd+K)',
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        fillColor: Colors.transparent,
                                        filled: true,
                                        isDense: true,
                                        icon: const Icon(
                                          Icons.search,
                                          color: SoftErpTheme.textSecondary,
                                          size: 24,
                                        ),
                                        suffixIcon: provider.isLoading
                                            ? const Padding(
                                                padding: EdgeInsets.all(8.0),
                                                child: SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                              )
                                            : IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  size: 20,
                                                ),
                                                padding: EdgeInsets.zero,
                                                constraints:
                                                    const BoxConstraints(),
                                                onPressed: () {
                                                  _textController.clear();
                                                  provider.search('');
                                                  provider.hideOverlay();
                                                },
                                              ),
                                      ),
                                      style: const TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      onChanged: (val) {
                                        provider.search(val);
                                      },
                                      onSubmitted: (val) {
                                        provider.search(val);
                                      },
                                    ),
                                  ),
                                  const Divider(height: 1),
                                  Flexible(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        // Left Pane: Configs
                                        if (hasConfigs) ...[
                                          Expanded(
                                            flex: 4,
                                            child: _buildConfigList(
                                              provider,
                                              items[_selectedIndex],
                                            ),
                                          ),
                                          const VerticalDivider(width: 1),
                                        ],
                                        // Center Pane: Results
                                        Expanded(
                                          flex: 6,
                                          child: _buildResultsList(
                                            provider,
                                            items,
                                            history,
                                          ),
                                        ),
                                        // Right Pane: Preview
                                        if (items.isNotEmpty &&
                                            _showPreview) ...[
                                          const VerticalDivider(width: 1),
                                          Expanded(
                                            flex: 4,
                                            child: _buildPreviewPane(
                                              items.isNotEmpty &&
                                                      _selectedIndex <
                                                          items.length
                                                  ? items[_selectedIndex]
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmbeddedLedger() {
    if (_ledgerResult == null) return const SizedBox.shrink();

    final baseItemIdStr =
        _ledgerResult!.metadata['baseItemId']?.toString() ??
        _ledgerResult!.id.split('_').first;
    final itemId = int.tryParse(baseItemIdStr);
    final variationId = _ledgerResult!.metadata['variationId'] as int?;

    return ChallanExcelView(
      isEmbedded: true,
      filterItemId: itemId,
      filterVariationLeafNodeId: variationId,
      title: 'In/Out Ledger: ${_ledgerResult!.label}',
      onClose: () {
        setState(() {
          _ledgerResult = null;
        });
      },
    );
  }

  Widget _buildConfigList(SearchProvider provider, SearchResult? selectedItem) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: SoftErpTheme.accent.withOpacity(0.05),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back,
                  size: 16,
                  color: SoftErpTheme.textSecondary,
                ),
                onPressed: () => setState(() => _configMode = false),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 4),
              const Expanded(
                child: Text(
                  'Configurations (Press Delete to exit)',
                  style: TextStyle(
                    color: SoftErpTheme.textSecondary,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _configScrollController,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _currentConfigs.length,
            itemBuilder: (context, i) {
              final c = _currentConfigs[i];
              final isSelected = _configMode && i == _configSelectedIndex;

              if (c.isHeader) {
                return Container(
                  key: _configKeys[i],
                  padding: const EdgeInsets.only(left: 16, top: 16, bottom: 4),
                  child: Text(
                    c.propertyName.toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      color: _configMode
                          ? SoftErpTheme.textSecondary
                          : SoftErpTheme.textSecondary.withOpacity(0.5),
                    ),
                  ),
                );
              }

              return Container(
                key: _configKeys[i],
                color: isSelected
                    ? SoftErpTheme.accent.withOpacity(0.08)
                    : Colors.transparent,
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 32),
                  leading: Icon(
                    Icons.subdirectory_arrow_right,
                    size: 16,
                    color: _configMode
                        ? SoftErpTheme.textSecondary
                        : SoftErpTheme.textSecondary.withOpacity(0.3),
                  ),
                  title: Text(
                    c.value ?? '',
                    style: TextStyle(
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isSelected
                          ? SoftErpTheme.accent
                          : (_configMode
                                ? SoftErpTheme.textPrimary
                                : SoftErpTheme.textSecondary.withOpacity(0.6)),
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(
                          Icons.keyboard_return,
                          size: 16,
                          color: SoftErpTheme.textSecondary,
                        )
                      : null,
                  onTap: () {
                    final val = c.value!;
                    _textController.text =
                        '${_textController.text.trim()} $val';
                    provider.search(_textController.text);
                    setState(() {
                      _configMode = false;
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultsList(
    SearchProvider provider,
    List<SearchResult> items,
    List<String> history,
  ) {
    if (provider.query.isEmpty && history.isNotEmpty) {
      return ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(vertical: 8),
        shrinkWrap: true,
        itemCount: history.length,
        itemBuilder: (context, i) {
          final h = history[i];
          final isSelected = i == _selectedIndex;
          return Container(
            key: _itemKeys[i],
            color: isSelected
                ? SoftErpTheme.accent.withOpacity(0.08)
                : Colors.transparent,
            child: ListTile(
              dense: true,
              leading: const Icon(
                Icons.history,
                color: SoftErpTheme.textSecondary,
                size: 20,
              ),
              title: Text(
                h,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
              onTap: () {
                _textController.text = h;
                provider.search(h);
              },
            ),
          );
        },
      );
    }

    if (provider.query.isNotEmpty && items.isEmpty && !provider.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(
          child: Text(
            'No results found.',
            style: TextStyle(color: SoftErpTheme.textSecondary),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      shrinkWrap: true,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final r = items[i];
        final isSelected = i == _selectedIndex;
        return Container(
          key: _itemKeys[i],
          color: isSelected
              ? SoftErpTheme.accent.withOpacity(0.08)
              : Colors.transparent,
          child: ListTile(
            dense: true,
            leading: Icon(
              r.type == 'item' ? Icons.inventory_2 : Icons.category,
              color: isSelected
                  ? SoftErpTheme.accent
                  : SoftErpTheme.textSecondary,
            ),
            title: Text(
              r.label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            subtitle: Text(
              r.subLabel,
              style: const TextStyle(
                color: SoftErpTheme.textSecondary,
                fontSize: 12,
              ),
            ),
            trailing: isSelected && _showPreview
                ? const Icon(
                    Icons.keyboard_return,
                    size: 16,
                    color: SoftErpTheme.textSecondary,
                  )
                : null,
            onTap: () {
              if (_selectedIndex == i && _showPreview) {
                _handleSelection(context, provider, r);
              } else {
                setState(() {
                  _selectedIndex = i;
                  _showPreview = true;
                });
              }
            },
          ),
        );
      },
    );
  }

  Widget _buildPreviewPane(SearchResult? result) {
    if (result == null) return const SizedBox.shrink();

    final stock = result.metadata['stock']?.toString() ?? '0';
    final category = result.metadata['category']?.toString() ?? '-';

    return Container(
      color: SoftErpTheme.cardSurfaceAlt.withOpacity(0.3),
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: SoftErpTheme.accent.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                result.type == 'item' ? Icons.inventory_2 : Icons.category,
                size: 40,
                color: SoftErpTheme.accent,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            result.label,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: SoftErpTheme.textPrimary,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            result.subLabel,
            style: const TextStyle(
              fontSize: 13,
              color: SoftErpTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 16),
          _buildPreviewRow('Category', category),
          const SizedBox(height: 12),
          _buildPreviewRow('Current Stock', stock, highlight: true),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: SoftErpTheme.accent.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SoftErpTheme.accent.withOpacity(0.1)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.keyboard_return,
                  size: 16,
                  color: SoftErpTheme.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  result.type == 'item'
                      ? 'Open In/Out Sheet'
                      : 'Select Material',
                  style: const TextStyle(
                    color: SoftErpTheme.accent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewRow(
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: SoftErpTheme.textSecondary,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
            color: highlight
                ? SoftErpTheme.successText
                : SoftErpTheme.textPrimary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }
}
