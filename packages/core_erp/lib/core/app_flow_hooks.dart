import 'package:flutter/widgets.dart';

/// Flows that live in the app shell but are needed from inside shared dialogs.
///
/// Creating a pipeline means pushing the pipeline builder, which the app owns
/// and this package cannot import. Without a way back to it, a dialog can offer
/// "create item" but the item it creates arrives with no way to give it a
/// pipeline — a dead end exactly where someone entering a factory's books needs
/// to keep going.
///
/// The app registers these once at startup; anything unset is simply not
/// offered, so a host that does not provide a flow degrades to hiding it.
class AppFlowHooks {
  const AppFlowHooks._();

  /// Opens the pipeline builder and resolves to the saved template id, or null
  /// if the user backed out.
  static Future<String?> Function(BuildContext context)? createPipeline;

  /// Opens the machine editor; resolves true when one was saved. Typed as a
  /// bool rather than a Machine so this package need not know that type.
  static Future<bool> Function(BuildContext context)? createMachine;

  /// Deletes a machine permanently.
  static Future<void> Function(BuildContext context, String machineId)? deleteMachine;

  /// Opens the die editor; resolves true when one was saved.
  static Future<bool> Function(BuildContext context)? createDie;

  /// Deletes a die permanently.
  static Future<void> Function(BuildContext context, String dieId)? deleteDie;

  static bool get canCreatePipeline => createPipeline != null;

  static Future<bool> Function()? createMachineFor(BuildContext context) {
    final handler = createMachine;
    if (handler == null) return null;
    return () => handler(context);
  }

  static Future<void> Function(String machineId)? deleteMachineFor(BuildContext context) {
    final handler = deleteMachine;
    if (handler == null) return null;
    return (id) => handler(context, id);
  }

  static Future<bool> Function()? createDieFor(BuildContext context) {
    final handler = createDie;
    if (handler == null) return null;
    return () => handler(context);
  }

  static Future<void> Function(String dieId)? deleteDieFor(BuildContext context) {
    final handler = deleteDie;
    if (handler == null) return null;
    return (id) => handler(context, id);
  }

  static Future<String?> Function()? createPipelineFor(BuildContext context) {
    final handler = createPipeline;
    if (handler == null) return null;
    return () => handler(context);
  }
}
