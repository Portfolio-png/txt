import 'dart:ui';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:core_erp/core/theme/soft_erp_theme.dart';
import '../providers/search_provider.dart';
import '../../domain/search_result.dart';
import '../../../delivery_challans/presentation/widgets/challan_excel_view.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..addStatusListener((status) {
      if (status == AnimationStatus.dismissed) {
        setState(() {}); // Rebuild to return SizedBox.shrink()
      }
    });
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleSelection(BuildContext context, SearchProvider provider, SearchResult? result) async {
    if (result == null) return;
    
    // Record click for backend learning
    provider.recordClick(result);
    
    // Open In/Out Sheet if it's an item
    if (result.type == 'item') {
      final baseItemIdStr = result.metadata['baseItemId']?.toString() ?? result.id.split('_').first;
      final itemId = int.tryParse(baseItemIdStr);
      final variationId = result.metadata['variationId'] as int?;
      
      if (itemId != null) {
        provider.hideOverlay();
        await ChallanExcelView.show(
          context,
          filterItemId: itemId,
          filterVariationLeafNodeId: variationId,
          title: 'In/Out Ledger: ${result.label}',
        );
      }
    } else if (result.type == 'material') {
      // In the future, we could open material in/out sheet here
      provider.hideOverlay();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchProvider>(
      builder: (context, provider, child) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (provider.isOverlayVisible && !_controller.isAnimating && _controller.status != AnimationStatus.completed) {
            _controller.forward();
            _focusNode.requestFocus();
            if (_textController.text != provider.query) {
               _textController.text = provider.query;
            }
          } else if (!provider.isOverlayVisible && !_controller.isAnimating && _controller.status != AnimationStatus.dismissed) {
            _controller.reverse();
            _focusNode.unfocus();
          }
        });

        if (!provider.isOverlayVisible && _controller.status == AnimationStatus.dismissed) {
          return const SizedBox.shrink();
        }
        
        // Reset selection if query changes
        if (_lastQuery != provider.query) {
          _selectedIndex = 0;
          _showPreview = false;
          _lastQuery = provider.query;
        }
        
        final items = provider.query.isEmpty ? <SearchResult>[] : provider.results;
        final history = provider.query.isEmpty ? provider.history : <String>[];
        final totalCount = provider.query.isEmpty ? history.length : items.length;
        
        // Clamp index
        if (_selectedIndex >= totalCount && totalCount > 0) {
          _selectedIndex = totalCount - 1;
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
                      width: _showPreview && items.isNotEmpty ? 750 : 450,
                      constraints: const BoxConstraints(maxHeight: 450),
                      margin: const EdgeInsets.only(bottom: 150),
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
                        border: Border.all(color: SoftErpTheme.border.withOpacity(0.5)),
                      ),
                      child: Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent) {
                            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                              if (totalCount > 0) {
                                setState(() {
                                  _selectedIndex = min(_selectedIndex + 1, totalCount - 1);
                                  _showPreview = false;
                                });
                              }
                              return KeyEventResult.handled;
                            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
                              setState(() {
                                _selectedIndex = max(_selectedIndex - 1, 0);
                                _showPreview = false;
                              });
                              return KeyEventResult.handled;
                            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
                              if (provider.query.isEmpty && history.isNotEmpty) {
                                _textController.text = history[_selectedIndex];
                                provider.search(history[_selectedIndex]);
                              } else if (items.isNotEmpty) {
                                if (!_showPreview) {
                                  setState(() { _showPreview = true; });
                                } else {
                                  _handleSelection(context, provider, items[_selectedIndex]);
                                }
                              }
                              return KeyEventResult.handled;
                            }
                          }
                          return KeyEventResult.ignored;
                        },
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                              child: TextField(
                                controller: _textController,
                                focusNode: _focusNode,
                                decoration: InputDecoration(
                                  hintText: 'Search inventory, materials... (Cmd+K)',
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  fillColor: Colors.transparent,
                                  filled: true,
                                  isDense: true,
                                  icon: const Icon(Icons.search, color: SoftErpTheme.textSecondary, size: 24),
                                  suffixIcon: provider.isLoading 
                                      ? const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: SizedBox(
                                            width: 16, height: 16, 
                                            child: CircularProgressIndicator(strokeWidth: 2)
                                          )
                                        )
                                      : IconButton(
                                          icon: const Icon(Icons.close, size: 20),
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(),
                                          onPressed: () {
                                            _textController.clear();
                                            provider.search('');
                                            provider.hideOverlay();
                                          },
                                        )
                                ),
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w400),
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
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Left Pane: Results
                                  Expanded(
                                    flex: 5,
                                    child: _buildResultsList(provider, items, history),
                                  ),
                                  // Right Pane: Preview
                                  if (items.isNotEmpty && _showPreview) ...[
                                    const VerticalDivider(width: 1),
                                    Expanded(
                                      flex: 4,
                                      child: _buildPreviewPane(items.isNotEmpty && _selectedIndex < items.length ? items[_selectedIndex] : null),
                                    ),
                                  ]
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
  
  Widget _buildResultsList(SearchProvider provider, List<SearchResult> items, List<String> history) {
    if (provider.query.isEmpty && history.isNotEmpty) {
      return ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 8),
        shrinkWrap: true,
        itemCount: history.length,
        itemBuilder: (context, i) {
          final h = history[i];
          final isSelected = i == _selectedIndex;
          return Container(
            color: isSelected ? SoftErpTheme.accent.withOpacity(0.08) : Colors.transparent,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.history, color: SoftErpTheme.textSecondary, size: 20),
              title: Text(h, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
              onTap: () {
                _textController.text = h;
                provider.search(h);
              },
            ),
          );
        }
      );
    }
    
    if (provider.query.isNotEmpty && items.isEmpty && !provider.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(32.0),
        child: Center(child: Text('No results found.', style: TextStyle(color: SoftErpTheme.textSecondary))),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      shrinkWrap: true,
      itemCount: items.length,
      itemBuilder: (context, i) {
        final r = items[i];
        final isSelected = i == _selectedIndex;
        return Container(
          color: isSelected ? SoftErpTheme.accent.withOpacity(0.08) : Colors.transparent,
          child: ListTile(
            dense: true,
            leading: Icon(
              r.type == 'item' ? Icons.inventory_2 : Icons.category, 
              color: isSelected ? SoftErpTheme.accent : SoftErpTheme.textSecondary,
            ),
            title: Text(r.label, style: TextStyle(fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500)),
            subtitle: Text(r.subLabel, style: const TextStyle(color: SoftErpTheme.textSecondary, fontSize: 12)),
            trailing: isSelected && _showPreview ? const Icon(Icons.keyboard_return, size: 16, color: SoftErpTheme.textSecondary) : null,
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
                color: SoftErpTheme.accent
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            result.label,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: SoftErpTheme.textPrimary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            result.subLabel,
            style: const TextStyle(fontSize: 13, color: SoftErpTheme.textSecondary),
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
                const Icon(Icons.keyboard_return, size: 16, color: SoftErpTheme.accent),
                const SizedBox(width: 8),
                Text(result.type == 'item' ? 'Open In/Out Sheet' : 'Select Material', style: const TextStyle(color: SoftErpTheme.accent, fontWeight: FontWeight.w600, fontSize: 12)),
              ],
            ),
          )
        ],
      ),
    );
  }
  
  Widget _buildPreviewRow(String label, String value, {bool highlight = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: SoftErpTheme.textSecondary, fontSize: 13)),
        Text(
          value, 
          style: TextStyle(
            fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
            color: highlight ? SoftErpTheme.successText : SoftErpTheme.textPrimary,
            fontSize: 13
          )
        ),
      ],
    );
  }
}
