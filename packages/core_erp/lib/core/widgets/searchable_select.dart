import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SearchableSelectOption<T> {
  const SearchableSelectOption({
    required this.value,
    required this.label,
    this.searchText,
    this.highlightColor,
  });

  final T value;
  final String label;
  final String? searchText;
  final Color? highlightColor;

  String get normalizedSearchText => (searchText ?? label).trim().toLowerCase();

  /// Every whitespace-separated term has to appear somewhere in the search
  /// text, in any order. A single contiguous match is the one-term case, so
  /// this only ever widens what matches — "roma 10" finds "Anchor Roma Classic
  /// Socket 10A", which a substring match on the whole query would miss.
  bool matchesQuery(String query) {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return true;
    }
    final haystack = normalizedSearchText;
    for (final term in normalizedQuery.split(RegExp(r'\s+'))) {
      if (term.isNotEmpty && !haystack.contains(term)) {
        return false;
      }
    }
    return true;
  }
}

typedef SearchableSelectCanCreateOption<T> =
    bool Function(String query, List<SearchableSelectOption<T>> options);
typedef SearchableSelectCreateOption<T> =
    Future<SearchableSelectOption<T>?> Function(String query);
typedef SearchableSelectCreateLabelBuilder = String Function(String query);

Future<SearchableSelectOption<T>?> showSearchableSelectDialog<T>({
  required BuildContext context,
  required List<SearchableSelectOption<T>> options,
  String? title,
  String searchHintText = 'Search',
  T? selectedValue,
  String emptyText = 'No matching options',
  SearchableSelectCanCreateOption<T>? canCreateOption,
  SearchableSelectCreateOption<T>? onCreateOption,
  SearchableSelectCreateLabelBuilder? createOptionLabelBuilder,
  SearchableSelectCreateOption<T>? onSecondaryCreateOption,
  SearchableSelectCreateLabelBuilder? secondaryCreateOptionLabelBuilder,
  Rect? anchorRect,
  TextInputType? keyboardType,
}) {
  final overlayState = Overlay.maybeOf(context, rootOverlay: true);
  final overlayContext = overlayState?.context ?? context;
  final overlayBox = overlayContext.findRenderObject() as RenderBox?;
  final anchorBox = context.findRenderObject() as RenderBox?;
  final isTablet = MediaQuery.of(context).size.width >= 600;
  if (anchorRect == null && overlayBox != null && anchorBox != null && isTablet) {
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlayBox);
    anchorRect = topLeft & anchorBox.size;
  }

  return showGeneralDialog<SearchableSelectOption<T>>(
    context: context,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierDismissible: true,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        _SearchableSelectDialog<T>(
          title: title,
          searchHintText: searchHintText,
          emptyText: emptyText,
          options: options,
          selectedValue: selectedValue,
          anchorRect: anchorRect,
          canCreateOption: canCreateOption,
          onCreateOption: onCreateOption,
          createOptionLabelBuilder: createOptionLabelBuilder,
          onSecondaryCreateOption: onSecondaryCreateOption,
          secondaryCreateOptionLabelBuilder: secondaryCreateOptionLabelBuilder,
          keyboardType: keyboardType,
        ),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curvedAnimation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

class SearchableSelectField<T> extends FormField<T> {
  SearchableSelectField({
    super.key,
    required this.options,
    required this.onChanged,
    required this.decoration,
    this.tapTargetKey,
    this.value,
    this.fieldEnabled = true,
    this.dialogTitle,
    this.searchHintText = 'Search',
    this.emptyText,
    this.canCreateOption,
    this.onCreateOption,
    this.createOptionLabelBuilder,
    this.onSecondaryCreateOption,
    this.secondaryCreateOptionLabelBuilder,
    this.keyboardType,
    super.validator,
  }) : super(
         initialValue: value,
         builder: (state) {
           final field = state as _SearchableSelectFieldState<T>;
           final widget = field.widget;
           final selected = widget.options
               .where((option) => option.value == state.value)
               .firstOrNull;
           final tapTargetKey = widget.tapTargetKey == widget.key
               ? null
               : widget.tapTargetKey;
           final effectiveDecoration = widget.decoration.copyWith(
             errorText: state.errorText,
             suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
           );

           return Focus(
             focusNode: field.focusNode,
             canRequestFocus: widget.fieldEnabled,
             onKeyEvent: (node, event) {
               if (!widget.fieldEnabled || event is! KeyDownEvent) {
                 return KeyEventResult.ignored;
               }
               if (event.logicalKey == LogicalKeyboardKey.enter ||
                   event.logicalKey == LogicalKeyboardKey.numpadEnter ||
                   event.logicalKey == LogicalKeyboardKey.space) {
                 field.openSelector();
                 return KeyEventResult.handled;
               }
               return KeyEventResult.ignored;
             },
             child: Builder(
               builder: (context) {
                 final focused = Focus.of(context).hasFocus;
                 return InkWell(
                   key: tapTargetKey,
                   canRequestFocus: false,
                   borderRadius: BorderRadius.circular(12),
                   onTap: widget.fieldEnabled ? field.openSelector : null,
                   child: InputDecorator(
                     decoration: effectiveDecoration.copyWith(
                       focusedBorder: focused
                           ? const OutlineInputBorder(
                               borderRadius: BorderRadius.all(
                                 Radius.circular(12),
                               ),
                               borderSide: BorderSide(
                                 color: Color(0xFF7C6BFF),
                                 width: 1.4,
                               ),
                             )
                           : effectiveDecoration.focusedBorder,
                     ),
                     isFocused: focused,
                     isEmpty: selected == null,
                     child: selected == null
                         ? const SizedBox.shrink()
                         : Text(
                             selected.label,
                             maxLines: 1,
                             overflow: TextOverflow.ellipsis,
                             style: TextStyle(
                               fontSize:
                                   MediaQuery.of(context).size.width >= 600
                                   ? 16.0
                                   : 14.0,
                             ),
                           ),
                   ),
                 );
               },
             ),
           );
         },
       );

  final Key? tapTargetKey;
  final List<SearchableSelectOption<T>> options;
  final ValueChanged<T?> onChanged;
  final InputDecoration decoration;
  final T? value;
  final bool fieldEnabled;
  final String? dialogTitle;
  final String searchHintText;
  final String? emptyText;
  final SearchableSelectCanCreateOption<T>? canCreateOption;
  final SearchableSelectCreateOption<T>? onCreateOption;
  final SearchableSelectCreateLabelBuilder? createOptionLabelBuilder;
  final SearchableSelectCreateOption<T>? onSecondaryCreateOption;
  final SearchableSelectCreateLabelBuilder? secondaryCreateOptionLabelBuilder;
  final TextInputType? keyboardType;

  @override
  FormFieldState<T> createState() => _SearchableSelectFieldState<T>();
}

class _SearchableSelectFieldState<T> extends FormFieldState<T> {
  final FocusNode focusNode = FocusNode(debugLabel: 'searchable_select_field');

  @override
  SearchableSelectField<T> get widget =>
      super.widget as SearchableSelectField<T>;

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant SearchableSelectField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && widget.value != value) {
      setValue(widget.value);
    }
  }

  Future<void> openSelector() async {
    final selected = await showSearchableSelectDialog<T>(
      context: context,
      options: widget.options,
      title: widget.dialogTitle,
      searchHintText: widget.searchHintText,
      selectedValue: value,
      emptyText: widget.emptyText ?? 'No matching options',
      canCreateOption: widget.canCreateOption,
      onCreateOption: widget.onCreateOption,
      createOptionLabelBuilder: widget.createOptionLabelBuilder,
      onSecondaryCreateOption: widget.onSecondaryCreateOption,
      secondaryCreateOptionLabelBuilder:
          widget.secondaryCreateOptionLabelBuilder,
      keyboardType: widget.keyboardType,
    );
    if (selected == null) {
      return;
    }
    didChange(selected.value);
    widget.onChanged(selected.value);
  }
}

class _SearchableSelectDialog<T> extends StatefulWidget {
  const _SearchableSelectDialog({
    required this.options,
    required this.searchHintText,
    required this.emptyText,
    required this.selectedValue,
    required this.anchorRect,
    required this.canCreateOption,
    required this.onCreateOption,
    required this.createOptionLabelBuilder,
    this.onSecondaryCreateOption,
    this.secondaryCreateOptionLabelBuilder,
    this.title,
    this.keyboardType,
  });

  final List<SearchableSelectOption<T>> options;
  final String? title;
  final String searchHintText;
  final String emptyText;
  final T? selectedValue;
  final Rect? anchorRect;
  final SearchableSelectCanCreateOption<T>? canCreateOption;
  final SearchableSelectCreateOption<T>? onCreateOption;
  final SearchableSelectCreateLabelBuilder? createOptionLabelBuilder;
  final SearchableSelectCreateOption<T>? onSecondaryCreateOption;
  final SearchableSelectCreateLabelBuilder? secondaryCreateOptionLabelBuilder;
  final TextInputType? keyboardType;

  @override
  State<_SearchableSelectDialog<T>> createState() =>
      _SearchableSelectDialogState<T>();
}

class _SearchableSelectDialogState<T>
    extends State<_SearchableSelectDialog<T>> {
  final TextEditingController _searchController = TextEditingController();

  static const double _screenPadding = 16;
  static const double _verticalGap = 8;
  static const double _preferredWidth = 300;
  static const double _minHeight = 180;
  static const double _maxHeight = 420;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final visibleOptions = widget.options
        .where((option) => option.matchesQuery(query))
        .toList(growable: false);
    return Material(
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final layout = _resolveLayout(constraints.biggest);
          final menu = _SearchableSelectMenu<T>(
            title: widget.title,
            searchHintText: widget.searchHintText,
            emptyText: widget.emptyText,
            selectedValue: widget.selectedValue,
            options: visibleOptions,
            allOptions: widget.options,
            onQueryChanged: (_) => setState(() {}),
            searchController: _searchController,
            maxHeight: layout.maxHeight,
            canCreateOption: widget.canCreateOption,
            onCreateOption: widget.onCreateOption,
            createOptionLabelBuilder: widget.createOptionLabelBuilder,
            onSecondaryCreateOption: widget.onSecondaryCreateOption,
            secondaryCreateOptionLabelBuilder:
                widget.secondaryCreateOptionLabelBuilder,
            keyboardType: widget.keyboardType,
          );

          if (layout.centered) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Center(child: menu),
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.of(context).maybePop(),
                ),
              ),
              Positioned(
                left: layout.left,
                top: layout.top,
                bottom: layout.bottom,
                width: layout.width,
                child: menu,
              ),
            ],
          );
        },
      ),
    );
  }

  _SearchableSelectLayout _resolveLayout(Size overlaySize) {
    final anchorRect = widget.anchorRect;
    if (anchorRect == null || overlaySize.isEmpty) {
      return const _SearchableSelectLayout.centered();
    }

    final isTablet = overlaySize.width >= 600;
    final preferredWidth = isTablet ? 400.0 : _preferredWidth;
    final width = math.min(
      overlaySize.width - (_screenPadding * 2),
      math.max(anchorRect.width, preferredWidth),
    );
    final left = anchorRect.left.clamp(
      _screenPadding,
      overlaySize.width - _screenPadding - width,
    );
    final availableBelow =
        overlaySize.height - anchorRect.bottom - _verticalGap - _screenPadding;
    final availableAbove = anchorRect.top - _verticalGap - _screenPadding;
    final placeBelow =
        availableBelow >= _minHeight || availableBelow >= availableAbove;
    final maxHeight = math.max(
      _minHeight,
      math.min(placeBelow ? availableBelow : availableAbove, _maxHeight),
    );

    if (placeBelow) {
      return _SearchableSelectLayout(
        left: left,
        top: math.min(
          anchorRect.bottom + _verticalGap,
          overlaySize.height - _screenPadding - maxHeight,
        ),
        width: width,
        maxHeight: maxHeight,
      );
    }

    return _SearchableSelectLayout(
      left: left,
      bottom: overlaySize.height - anchorRect.top + _verticalGap,
      width: width,
      maxHeight: maxHeight,
    );
  }
}

class _SearchableSelectMenu<T> extends StatelessWidget {
  const _SearchableSelectMenu({
    required this.options,
    required this.selectedValue,
    required this.allOptions,
    required this.searchController,
    required this.onQueryChanged,
    required this.searchHintText,
    required this.emptyText,
    required this.maxHeight,
    required this.canCreateOption,
    required this.onCreateOption,
    required this.createOptionLabelBuilder,
    this.onSecondaryCreateOption,
    this.secondaryCreateOptionLabelBuilder,
    this.title,
    this.keyboardType,
  });

  final List<SearchableSelectOption<T>> options;
  final T? selectedValue;
  final List<SearchableSelectOption<T>> allOptions;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final String searchHintText;
  final String emptyText;
  final double maxHeight;
  final String? title;
  final SearchableSelectCanCreateOption<T>? canCreateOption;
  final SearchableSelectCreateOption<T>? onCreateOption;
  final SearchableSelectCreateLabelBuilder? createOptionLabelBuilder;
  final SearchableSelectCreateOption<T>? onSecondaryCreateOption;
  final SearchableSelectCreateLabelBuilder? secondaryCreateOptionLabelBuilder;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    final query = searchController.text.trim();
    final normalizedQuery = query.toLowerCase();
    final exactMatchExists = allOptions.any(
      (option) => option.normalizedSearchText == normalizedQuery,
    );
    final showCreateOption =
        onCreateOption != null &&
        query.isNotEmpty &&
        !exactMatchExists &&
        (canCreateOption?.call(query, allOptions) ?? true);
    final showSecondaryCreateOption =
        onSecondaryCreateOption != null &&
        query.isNotEmpty &&
        !exactMatchExists &&
        (canCreateOption?.call(query, allOptions) ?? true);
    final createOptionsCount =
        (showCreateOption ? 1 : 0) + (showSecondaryCreateOption ? 1 : 0);

    return FocusTraversalGroup(
      child: Material(
        elevation: 4,
        color: Colors.white,
        shadowColor: const Color(0x14000000),
        surfaceTintColor: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (title != null) ...[
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    14,
                    14,
                    14,
                    MediaQuery.of(context).size.width >= 600 ? 14 : 10,
                  ),
                  child: Text(
                    title!,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF2F3744),
                      fontSize: MediaQuery.of(context).size.width >= 600
                          ? 16.0
                          : 14.0,
                    ),
                  ),
                ),
              ] else
                SizedBox(
                  height: MediaQuery.of(context).size.width >= 600
                      ? 18.0
                      : 14.0,
                ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  0,
                  14,
                  MediaQuery.of(context).size.width >= 600 ? 16 : 12,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.width >= 600
                      ? 48.0
                      : 40.0,
                  child: TextField(
                    controller: searchController,
                    keyboardType: keyboardType,
                    autofocus:
                        Theme.of(context).platform != TargetPlatform.android &&
                        Theme.of(context).platform != TargetPlatform.iOS,
                    textInputAction: TextInputAction.next,
                    onChanged: onQueryChanged,
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width >= 600
                          ? 15.0
                          : 13.0,
                    ),
                    decoration: InputDecoration(
                      hintText: searchHintText,
                      hintStyle: TextStyle(
                        color: const Color(0xFF7B8494),
                        fontSize: MediaQuery.of(context).size.width >= 600
                            ? 15.0
                            : 13.0,
                        fontWeight: FontWeight.w500,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: MediaQuery.of(context).size.width >= 600
                            ? 22.0
                            : 18.0,
                        color: const Color(0xFF7B8494),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF7F8FB),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: MediaQuery.of(context).size.width >= 600
                            ? 14.0
                            : 10.0,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF7C6BFF)),
                      ),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: options.isEmpty && !showCreateOption
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                          child: Text(
                            emptyText,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: const Color(0xFF6B7280)),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        itemCount: options.length + createOptionsCount,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 2),
                        itemBuilder: (context, index) {
                          var currentCreateCount = 0;
                          if (showCreateOption && index == currentCreateCount) {
                            return _SearchableSelectCreateTile<T>(
                              query: query,
                              label:
                                  createOptionLabelBuilder?.call(query) ??
                                  'Create "$query"',
                              onCreateOption: onCreateOption!,
                              icon: Icons.add_circle_outline_rounded,
                            );
                          }
                          if (showCreateOption) currentCreateCount++;

                          if (showSecondaryCreateOption &&
                              index == currentCreateCount) {
                            return _SearchableSelectCreateTile<T>(
                              query: query,
                              label:
                                  secondaryCreateOptionLabelBuilder?.call(
                                    query,
                                  ) ??
                                  'Create secondary "$query"',
                              onCreateOption: onSecondaryCreateOption!,
                              icon: Icons.add_task_rounded,
                            );
                          }
                          if (showSecondaryCreateOption) currentCreateCount++;

                          final optionIndex = index - createOptionsCount;
                          final option = options[optionIndex];
                          return _SearchableSelectOptionTile<T>(
                            option: option,
                            isSelected: option.value == selectedValue,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchableSelectOptionTile<T> extends StatefulWidget {
  const _SearchableSelectOptionTile({
    required this.option,
    required this.isSelected,
  });

  final SearchableSelectOption<T> option;
  final bool isSelected;

  @override
  State<_SearchableSelectOptionTile<T>> createState() =>
      _SearchableSelectOptionTileState<T>();
}

class _SearchableSelectOptionTileState<T>
    extends State<_SearchableSelectOptionTile<T>> {
  bool _isFocused = false;
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final baseColor = widget.option.highlightColor;
    final active = _isFocused || _isHovered;
    final backgroundColor = active
        ? (baseColor != null
              ? baseColor.withValues(alpha: 0.25)
              : const Color(0xFFEDE9FF))
        : widget.isSelected
        ? const Color(0xFFF3F0FF)
        : (baseColor != null
              ? baseColor.withValues(alpha: 0.08)
              : Colors.white);

    void selectOption() {
      Navigator.of(context).pop(widget.option);
    }

    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            selectOption();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      onShowHoverHighlight: (hovered) {
        setState(() {
          _isHovered = hovered;
        });
      },
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          canRequestFocus: false,
          borderRadius: BorderRadius.circular(10),
          onTap: selectOption,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width >= 600
                  ? 16.0
                  : 12.0,
              vertical: MediaQuery.of(context).size.width >= 600 ? 14.0 : 11.0,
            ),
            child: Row(
              children: [
                if (baseColor != null) ...[
                  Container(
                    width: MediaQuery.of(context).size.width >= 600
                        ? 10.0
                        : 8.0,
                    height: MediaQuery.of(context).size.width >= 600
                        ? 10.0
                        : 8.0,
                    decoration: BoxDecoration(
                      color: baseColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  SizedBox(
                    width: MediaQuery.of(context).size.width >= 600
                        ? 10.0
                        : 8.0,
                  ),
                ],
                Expanded(
                  child: Tooltip(
                    message: widget.option.label,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Text(
                      widget.option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: const Color(0xFF2F3744),
                        fontSize: MediaQuery.of(context).size.width >= 600
                            ? 15.0
                            : 13.0,
                        fontWeight: widget.isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: MediaQuery.of(context).size.width >= 600 ? 12.0 : 10.0,
                ),
                AnimatedOpacity(
                  opacity: widget.isSelected ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Icon(
                    Icons.check_rounded,
                    size: MediaQuery.of(context).size.width >= 600
                        ? 22.0
                        : 18.0,
                    color: const Color(0xFF6C63FF),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchableSelectCreateTile<T> extends StatefulWidget {
  const _SearchableSelectCreateTile({
    required this.query,
    required this.label,
    required this.onCreateOption,
    this.icon = Icons.add_circle_outline_rounded,
  });

  final String query;
  final String label;
  final SearchableSelectCreateOption<T> onCreateOption;
  final IconData icon;

  @override
  State<_SearchableSelectCreateTile<T>> createState() =>
      _SearchableSelectCreateTileState<T>();
}

class _SearchableSelectCreateTileState<T>
    extends State<_SearchableSelectCreateTile<T>> {
  bool _isCreating = false;
  bool _isFocused = false;

  Future<void> _create() async {
    if (_isCreating) {
      return;
    }
    setState(() {
      _isCreating = true;
    });
    try {
      final created = await widget.onCreateOption(widget.query);
      if (!mounted || created == null) {
        return;
      }
      Navigator.of(context).pop(created);
    } finally {
      if (mounted) {
        setState(() {
          _isCreating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _isFocused
        ? const Color(0xFFEDE9FF)
        : const Color(0xFFF8FAFF);

    return FocusableActionDetector(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (intent) {
            _create();
            return null;
          },
        ),
      },
      onShowFocusHighlight: (focused) {
        setState(() {
          _isFocused = focused;
        });
      },
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: _isCreating ? null : _create,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width >= 600
                  ? 16.0
                  : 12.0,
              vertical: MediaQuery.of(context).size.width >= 600 ? 14.0 : 11.0,
            ),
            child: Row(
              children: [
                _isCreating
                    ? SizedBox(
                        width: MediaQuery.of(context).size.width >= 600
                            ? 22.0
                            : 18.0,
                        height: MediaQuery.of(context).size.width >= 600
                            ? 22.0
                            : 18.0,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        widget.icon,
                        size: MediaQuery.of(context).size.width >= 600
                            ? 22.0
                            : 18.0,
                        color: const Color(0xFF7C6BFF),
                      ),
                SizedBox(
                  width: MediaQuery.of(context).size.width >= 600 ? 12.0 : 10.0,
                ),
                Expanded(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF5E49E6),
                      fontWeight: FontWeight.w600,
                      fontSize: MediaQuery.of(context).size.width >= 600
                          ? 15.0
                          : 13.0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchableSelectLayout {
  const _SearchableSelectLayout({
    required this.left,
    required this.width,
    required this.maxHeight,
    this.top,
    this.bottom,
  }) : centered = false;

  const _SearchableSelectLayout.centered()
    : left = 0,
      width = 320,
      maxHeight = 420,
      top = null,
      bottom = null,
      centered = true;

  final double left;
  final double width;
  final double maxHeight;
  final double? top;
  final double? bottom;
  final bool centered;
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
