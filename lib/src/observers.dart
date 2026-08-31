/// Lifecycle observer registry.
library;

import 'exceptions.dart';
import 'model.dart';

/// Lifecycle hooks fired before/after CRUD operations.
///
/// Two registration styles are supported:
///
/// 1. Static methods on the Model subclass (Laravel-style).
/// 2. Registry map (Dart-idiomatic) via [Model.$observers].
///
/// Static methods take precedence if both are declared.
class ObserverSet {
  const ObserverSet({
    this.creating,
    this.created,
    this.updating,
    this.updated,
    this.deleting,
    this.deleted,
  });

  /// Return `false` to cancel the operation.
  final bool Function(Model)? creating;

  /// Fired after a successful INSERT.
  final void Function(Model)? created;

  /// Return `false` to cancel the operation.
  final bool Function(Model)? updating;

  /// Fired after a successful UPDATE.
  final void Function(Model)? updated;

  /// Return `false` to cancel the operation.
  final bool Function(Model)? deleting;

  /// Fired after a successful DELETE.
  final void Function(Model)? deleted;
}

/// Dispatch the [stage] hook on [model], combining the static method
/// (if any) and the registry (if any).
///
/// Static methods take precedence. Returning `false` from any cancelable
/// hook aborts the operation.
bool dispatchCancelable(String stage, Model model) {
  // Static method takes precedence.
  try {
    final method = _findStatic(model, stage);
    if (method != null) {
      final dyn = model as dynamic;
      final r = dyn is Model ? (method as dynamic).call() : method();
      if (r is bool && !r) return false;
    }
  } catch (_) {
    // No static method — fall through to registry.
  }

  final registry = model.$observers;
  final hook = _cancelableHook(registry, stage);
  if (hook != null) {
    if (!hook(model)) return false;
  }
  return true;
}

/// Dispatch the [stage] hook on [model] for after-the-fact hooks.
void dispatchVoid(String stage, Model model) {
  try {
    final method = _findStatic(model, stage);
    if (method != null) {
      (method as dynamic).call();
      return;
    }
  } catch (_) {
    // No static method — fall through.
  }

  final registry = model.$observers;
  final hook = _voidHook(registry, stage);
  hook?.call(model);
}

Function? _findStatic(Model model, String stage) {
  try {
    final dyn = model as dynamic;
    return switch (stage) {
      'creating' => dyn.creating as Function?,
      'created' => dyn.created as Function?,
      'updating' => dyn.updating as Function?,
      'updated' => dyn.updated as Function?,
      'deleting' => dyn.deleting as Function?,
      'deleted' => dyn.deleted as Function?,
      _ => null,
    };
  } catch (_) {
    return null;
  }
}

bool Function(Model)? _cancelableHook(ObserverSet s, String stage) {
  return switch (stage) {
    'creating' => s.creating,
    'updating' => s.updating,
    'deleting' => s.deleting,
    _ => null,
  };
}

void Function(Model)? _voidHook(ObserverSet s, String stage) {
  return switch (stage) {
    'created' => s.created,
    'updated' => s.updated,
    'deleted' => s.deleted,
    _ => null,
  };
}

/// Convenience: cancel a CRUD operation with a helpful exception.
Never cancelOperation(String stage, Model model) {
  throw OperationCancelledException(
    stage: stage,
    modelName: model.runtimeType.toString(),
  );
}