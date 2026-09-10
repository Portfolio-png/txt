import 'package:core_erp/core/app_flow_hooks.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => AppFlowHooks.createPipeline = null);

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
}

class _FakeContext extends StatelessWidget implements BuildContext {
  const _FakeContext();

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
