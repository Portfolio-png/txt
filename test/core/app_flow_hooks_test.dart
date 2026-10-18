import 'package:core_erp/core/app_flow_hooks.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
    tearDown(() {
      AppFlowHooks.createPipeline = null;
      AppFlowHooks.dieInspector = null;
      AppFlowHooks.machineInspector = null;
      AppFlowHooks.itemInspector = null;
    });

  test('an unregistered flow is not offered rather than crashing', () {
    AppFlowHooks.createPipeline = null;
    expect(AppFlowHooks.canCreatePipeline, isFalse);
    // Null means the caller hides the affordance; it must never be a callable
    // that throws when a host does not provide the flow.
    expect(
      AppFlowHooks.createPipelineFor(_FakeContext()),
      isNull,
    );
  });

  test('a registered flow is bound to the calling context', () async {
    BuildContext? seen;
    AppFlowHooks.createPipeline = (context) async {
      seen = context;
      return 'pipeline-7';
    };
    final context = _FakeContext();

    expect(AppFlowHooks.canCreatePipeline, isTrue);
    final bound = AppFlowHooks.createPipelineFor(context);
    expect(bound, isNotNull);
    expect(await bound!(), 'pipeline-7');
    expect(identical(seen, context), isTrue);
  });

  test('canInspect and inspectorFor support die, machine, and item', () {
    const context = _FakeContext();
    expect(AppFlowHooks.canInspect('die'), isFalse);
    expect(AppFlowHooks.canInspect('machine'), isFalse);
    expect(AppFlowHooks.canInspect('item'), isFalse);

    AppFlowHooks.dieInspector = (c, id) => const Text('die');
    AppFlowHooks.machineInspector = (c, id) => const Text('machine');
    AppFlowHooks.itemInspector = (c, id) => const Text('item');

    expect(AppFlowHooks.canInspect('die'), isTrue);
    expect(AppFlowHooks.canInspect('machine'), isTrue);
    expect(AppFlowHooks.canInspect('item'), isTrue);

    expect(AppFlowHooks.inspectorFor(context, 'die', '1'), isNotNull);
    expect(AppFlowHooks.inspectorFor(context, 'machine', '2'), isNotNull);
    expect(AppFlowHooks.inspectorFor(context, 'item', '3'), isNotNull);
    expect(AppFlowHooks.inspectorFor(context, 'unknown', '4'), isNull);
  });
}

class _FakeContext extends StatelessWidget implements BuildContext {
  const _FakeContext();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
