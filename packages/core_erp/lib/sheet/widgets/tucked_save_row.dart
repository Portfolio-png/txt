import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A section's save row, lifted up onto the end of its last line of fields
/// when that line leaves room for it — owner, 2026-11-25: "shift Save Die and
/// Save Machine a little above to save space" (the arrows on the screenshot
/// ran from Save Die up to the end of the Ordered / Arrived line). When the
/// line is too full, or the row would sit on [avoid] (the photo tile), it goes
/// under the body as before.
///
/// Always at the right edge, so the Saves stay in the sheet's one column
/// ([SheetSaveRow]). Decided in layout, not after a frame: a field that grows
/// as it is typed into moves the last line, and the row moves with it.
///
///     final _last = SaveRowAnchor();
///     TuckedSaveRow(
///       anchor: _last,
///       body: … SaveRowAnchorMark(anchor: _last, child: lastField) …,
///       actions: SheetSaveRow(shrinkWrap: true, children: […]),
///     )
class TuckedSaveRow extends MultiChildRenderObjectWidget {
  TuckedSaveRow({
    super.key,
    required this.anchor,
    required Widget body,
    required Widget actions,
    this.avoid = const [],
    this.gap = 12,
  }) : super(children: [body, actions]);

  /// The last field: the row goes on its line, after it.
  final SaveRowAnchor anchor;

  /// What the row may not be drawn over.
  final List<SaveRowAnchor> avoid;

  /// Above the row when it is under the body.
  final double gap;

  /// Room kept between the last field and the row beside it.
  static const double besideGap = 16;

  @override
  RenderTuckedSaveRow createRenderObject(BuildContext context) =>
      RenderTuckedSaveRow(anchor: anchor, avoid: avoid, gap: gap);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderTuckedSaveRow renderObject,
  ) {
    renderObject
      ..anchor = anchor
      ..avoid = avoid
      ..gap = gap;
  }
}

/// Names a widget for [TuckedSaveRow] to find. Hold one per section.
class SaveRowAnchor {
  _RenderAnchorMark? _mark;
}

/// Marks [child] as [anchor]: its place is read when the row is laid out.
class SaveRowAnchorMark extends SingleChildRenderObjectWidget {
  const SaveRowAnchorMark({super.key, required this.anchor, super.child});

  final SaveRowAnchor anchor;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAnchorMark(anchor);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderAnchorMark).anchor = anchor;
  }
}

class _RenderAnchorMark extends RenderProxyBox {
  _RenderAnchorMark(this._anchor);

  SaveRowAnchor _anchor;
  set anchor(SaveRowAnchor value) {
    if (identical(value, _anchor)) return;
    if (identical(_anchor._mark, this)) _anchor._mark = null;
    _anchor = value;
    if (attached) value._mark = this;
    markNeedsLayout();
  }

  /// Its size as it last laid out — kept here, so the row reads it without
  /// reaching into a render box it is not the parent of.
  Size? laidOut;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _anchor._mark = this;
  }

  @override
  void detach() {
    if (identical(_anchor._mark, this)) _anchor._mark = null;
    laidOut = null;
    super.detach();
  }

  @override
  void performLayout() {
    super.performLayout();
    laidOut = size;
  }
}

class _TuckParentData extends ContainerBoxParentData<RenderBox> {}

class RenderTuckedSaveRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TuckParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TuckParentData> {
  RenderTuckedSaveRow({
    required SaveRowAnchor anchor,
    required List<SaveRowAnchor> avoid,
    required double gap,
  }) : _anchor = anchor,
       _avoid = avoid,
       _gap = gap;

  SaveRowAnchor _anchor;
  set anchor(SaveRowAnchor value) {
    if (identical(value, _anchor)) return;
    _anchor = value;
    markNeedsLayout();
  }

  List<SaveRowAnchor> _avoid;
  set avoid(List<SaveRowAnchor> value) {
    _avoid = value;
    markNeedsLayout();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsLayout();
  }

  /// Whether the row went up beside the last field (read by tests).
  bool tucked = false;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TuckParentData) {
      child.parentData = _TuckParentData();
    }
  }

  /// [mark]'s box in this one's coordinates, or null when it is not drawn
  /// inside this row's body.
  Rect? _rectOf(SaveRowAnchor anchor) {
    final mark = anchor._mark;
    final size = mark?.laidOut;
    if (mark == null || size == null || !mark.attached) return null;
    RenderObject? up = mark.parent;
    while (up != null && !identical(up, this)) {
      up = up.parent;
    }
    if (up == null) return null;
    final at = MatrixUtils.transformPoint(
      mark.getTransformTo(this),
      Offset.zero,
    );
    return at & size;
  }

  @override
  void performLayout() {
    final body = firstChild!;
    final actions = childAfter(body)!;
    final width = constraints.maxWidth;
    body.layout(BoxConstraints.tightFor(width: width), parentUsesSize: true);
    actions.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final row = actions.size;
    final left = width - row.width;

    final last = _rectOf(_anchor);
    Rect? beside;
    if (last != null) {
      final top = last.bottom - row.height;
      final spot = Rect.fromLTWH(left, top, row.width, row.height);
      final roomy = last.right + TuckedSaveRow.besideGap <= left && top >= 0;
      final clear = _avoid.every((a) {
        final other = _rectOf(a);
        return other == null || !other.inflate(8).overlaps(spot);
      });
      if (roomy && clear) beside = spot;
    }
    tucked = beside != null;

    (body.parentData! as _TuckParentData).offset = Offset.zero;
    final under = body.size.height + _gap;
    (actions.parentData! as _TuckParentData).offset =
        beside?.topLeft ?? Offset(left, under);
    size = constraints.constrain(
      Size(width, tucked ? body.size.height : under + row.height),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    // Without laying out there is no knowing the last line: the room it
    // takes at most, with the row under the body.
    final body = firstChild!;
    final actions = childAfter(body)!;
    final width = constraints.maxWidth;
    final b = body.getDryLayout(BoxConstraints.tightFor(width: width));
    final a = actions.getDryLayout(BoxConstraints(maxWidth: width));
    return constraints.constrain(Size(width, b.height + _gap + a.height));
  }

  @override
  double computeMinIntrinsicWidth(double height) => math2(
    firstChild!.getMinIntrinsicWidth(height),
    childAfter(firstChild!)!.getMinIntrinsicWidth(height),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => math2(
    firstChild!.getMaxIntrinsicWidth(height),
    childAfter(firstChild!)!.getMaxIntrinsicWidth(height),
  );

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild!.getMinIntrinsicHeight(width) +
      _gap +
      childAfter(firstChild!)!.getMinIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild!.getMaxIntrinsicHeight(width) +
      _gap +
      childAfter(firstChild!)!.getMaxIntrinsicHeight(width);

  static double math2(double a, double b) => a > b ? a : b;

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
