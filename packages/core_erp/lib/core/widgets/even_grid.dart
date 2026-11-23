import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Children in even columns, read row by row — a form whose fields line up.
///
/// [columns] wide while each column can be at least [minColumnWidth]; when it
/// cannot, half as many (and half again), the children reflowing in the same
/// order. So a 4-wide grid of `A B C D / E F G H` becomes `A B / C D / E F /
/// G H` in a narrow window: still even, still read in the same order.
///
/// Only the positions change with the width, never the widgets: the fields
/// keep their state and focus as the window is resized. (A LayoutBuilder
/// choosing between layouts would rebuild them, and rebuilding tooltips
/// mid-layout is a crash this app has had — see the reorderable-list trap.)
///
/// A row is as tall as its tallest child, and the children sit on its bottom
/// edge, so boxes line up whatever is above them. A row of nothing (every
/// child zero-high, the empty cells of a grid) takes no room.
class EvenGrid extends MultiChildRenderObjectWidget {
  const EvenGrid({
    super.key,
    required this.columns,
    required this.minColumnWidth,
    this.spacing = 10,
    this.runSpacing = 8,
    this.responsive = false,
    super.children,
  });

  final int columns;
  final double minColumnWidth;
  final double spacing;
  final double runSpacing;
  final bool responsive;

  @override
  RenderEvenGrid createRenderObject(BuildContext context) => RenderEvenGrid(
        columns: columns,
        minColumnWidth: minColumnWidth,
        spacing: spacing,
        runSpacing: runSpacing,
        responsive: responsive,
      );

  @override
  void updateRenderObject(BuildContext context, RenderEvenGrid renderObject) {
    renderObject
      ..columns = columns
      ..minColumnWidth = minColumnWidth
      ..spacing = spacing
      ..runSpacing = runSpacing
      ..responsive = responsive;
  }
}

class EvenGridParentData extends ContainerBoxParentData<RenderBox> {}

class RenderEvenGrid extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, EvenGridParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, EvenGridParentData> {
  RenderEvenGrid({
    required int columns,
    required double minColumnWidth,
    required double spacing,
    required double runSpacing,
    bool responsive = true,
  })  : _columns = columns,
        _minColumnWidth = minColumnWidth,
        _spacing = spacing,
        _runSpacing = runSpacing,
        _responsive = responsive;

  bool _responsive;
  bool get responsive => _responsive;
  set responsive(bool value) {
    if (value == _responsive) return;
    _responsive = value;
    markNeedsLayout();
  }

  int _columns;
  set columns(int value) {
    if (value == _columns) return;
    _columns = value;
    markNeedsLayout();
  }

  double _minColumnWidth;
  set minColumnWidth(double value) {
    if (value == _minColumnWidth) return;
    _minColumnWidth = value;
    markNeedsLayout();
  }

  double _spacing;
  set spacing(double value) {
    if (value == _spacing) return;
    _spacing = value;
    markNeedsLayout();
  }

  double _runSpacing;
  set runSpacing(double value) {
    if (value == _runSpacing) return;
    _runSpacing = value;
    markNeedsLayout();
  }

  /// How many columns fit [width]: the full count, halved until each column
  /// has its minimum (or there is one).
  int columnsFor(double width) {
    var count = math.max(1, _columns);
    while (count > 1 &&
        (width - _spacing * (count - 1)) / count < _minColumnWidth) {
      count = math.max(1, count ~/ 2);
    }
    return count;
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! EvenGridParentData) {
      child.parentData = EvenGridParentData();
    }
  }

  Size _arrange(BoxConstraints constraints, {required bool dry}) {
    final width = constraints.hasBoundedWidth
        ? constraints.maxWidth
        : _columns * _minColumnWidth + _spacing * (_columns - 1);
    final count = columnsFor(width);
    final cell = math.max(0.0, (width - _spacing * (count - 1)) / count);
    final cellConstraints = BoxConstraints.tightFor(width: cell);

    var top = 0.0;
    var child = firstChild;
    while (child != null) {
      final row = <RenderBox>[];
      while (row.length < count && child != null) {
        row.add(child);
        child = childAfter(child);
      }

      final widths = <double>[];
      if (_responsive && row.length > 1) {
        final desired = [
          for (final box in row)
            box
                .getDryLayout(BoxConstraints(maxWidth: width))
                .width
                .clamp(_minColumnWidth, width),
        ];
        final isUniform = desired.every((d) => (d - desired.first).abs() < 1.0);
        if (isUniform) {
          for (var i = 0; i < row.length; i += 1) {
            widths.add(cell);
          }
        } else {
          final available = width - _spacing * (row.length - 1);
          final totalDesired = desired.fold(0.0, (sum, w) => sum + w);
          if (totalDesired <= available) {
            final extra = available - totalDesired;
            final perChildExtra = extra / row.length;
            for (final d in desired) {
              widths.add(d + perChildExtra);
            }
          } else {
            for (final d in desired) {
              final scaled = (d / totalDesired) * available;
              widths.add(math.max(_minColumnWidth, scaled));
            }
          }
        }
      } else {
        for (var i = 0; i < row.length; i += 1) {
          widths.add(cell);
        }
      }

      final sizes = [
        for (var i = 0; i < row.length; i += 1)
          if (dry)
            row[i].getDryLayout(BoxConstraints.tightFor(width: widths[i]))
          else
            (row[i]..layout(BoxConstraints.tightFor(width: widths[i]), parentUsesSize: true)).size,
      ];
      final height = sizes.fold(0.0, (tallest, s) => math.max(tallest, s.height));
      if (height > 0 && top > 0) top += _runSpacing;
      if (!dry) {
        var x = 0.0;
        for (var i = 0; i < row.length; i += 1) {
          (row[i].parentData! as EvenGridParentData).offset = Offset(
            x,
            top + height - sizes[i].height,
          );
          x += widths[i] + _spacing;
        }
      }
      top += height;
    }
    return constraints.constrain(Size(width, top));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) =>
      _arrange(constraints, dry: true);

  @override
  void performLayout() {
    size = _arrange(constraints, dry: false);
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
