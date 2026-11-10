import 'package:flutter/widgets.dart';

import '../navigator/controller.dart';
import '../navigator/navigator.dart';

/// Shortcuts to the closest [AlembicController].
extension AlembicContextExtension on BuildContext {
  /// The controller of the closest Alembic above this context.
  /// ```dart
  /// context.alembic.push(const SettingsPage());
  /// ```
  AlembicController get alembic => Alembic.of(this);

  /// The controller of the closest Alembic above this context, if any.
  AlembicController? get maybeAlembic => Alembic.maybeOf(this);
}
