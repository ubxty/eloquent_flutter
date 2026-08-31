/// Lifecycle observer registry.
library;

import 'exceptions.dart';
import 'model.dart';

// ===== Global "events muted" switch =====
//
// When set to `true` via [setEventsMuted] (or by wrapping a block in
// `Model.withoutEvents(...)`), [dispatchCancelable] and [dispatchVoid]
// become no-ops. Useful for seeders, migrations, and bulk imports where
// firing per-row observers is expensive or unwanted.
bool _muted = false;

/// True while a `Model.withoutEvents(...)` block (or any caller of
/// [setEventsMuted]) is in effect.
bool get isEventsMuted => _muted;

/// Set the global muted flag. Prefer `Model.withoutEvents(...)` over
/// calling this directly — this exists so the static helper on Model
/// can flip the switch.
void setEventsMuted(bool value) {
  _muted = value;
}

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
    this.restoring,
    this.restored,
    this.forceDeleting,
    this.forceDeleted,
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

  /// Return `false` to cancel the restore.
  final bool Function(Model)? restoring;

  /// Fired after a soft-deletable model has been restored.
  final void Function(Model)? restored;

  /// Return `false` to cancel the hard-delete.
  final bool Function(Model)? forceDeleting;

  /// Fired after a soft-deletable model has been permanently deleted.
  final void Function(Model)? forceDeleted;
}

/// Stage names for which a `false` return aborts the operation.
///
/// Mirrors the `ObserverSet` cancelable hooks.
const Set<String> kCancelableStages = {
  'creating',
  'updating',
  'deleting',
  'restoring',
  'forceDeleting',
};

/// Stage names that run after the operation succeeds.
///
/// Mirrors the `ObserverSet` void hooks.
const Set<String> kAfterStages = {
  'created',
  'updated',
  'deleted',
  'restored',
  'forceDeleted',
};

/// Dispatch the [stage] hook on [model], combining the static method
/// (if any) and the registry (if any).
///
/// Static methods take precedence. Returning `false` from any cancelable
/// hook aborts the operation.
bool dispatchCancelable(String stage, Model model) {
  // When events are globally muted (see [Model.withoutEvents] /
  // [setEventsMuted]), short-circuit and let the operation proceed.
  if (isEventsMuted) return true;

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
  if (isEventsMuted) return;

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
      'restoring' => dyn.restoring as Function?,
      'restored' => dyn.restored as Function?,
      'forceDeleting' => dyn.forceDeleting as Function?,
      'forceDeleted' => dyn.forceDeleted as Function?,
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
    'restoring' => s.restoring,
    'forceDeleting' => s.forceDeleting,
    _ => null,
  };
}

void Function(Model)? _voidHook(ObserverSet s, String stage) {
  return switch (stage) {
    'created' => s.created,
    'updated' => s.updated,
    'deleted' => s.deleted,
    'restored' => s.restored,
    'forceDeleted' => s.forceDeleted,
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