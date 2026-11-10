/// Declarative Navigator 2.0 navigation built on widgets only.
///
/// The navigation state is a list of pages owned by an [AlembicController]: every change goes through its guards, and
/// an [Alembic] widget renders it.
/// ```dart
/// import 'package:alembic/alembic.dart';
///
/// context.alembic.push(const SettingsPage());
/// context.alembic.change((state) => [...state, const SettingsPage()]);
/// context.alembic.popUntil(Routes.home);
/// ```
library;

export 'src/navigator/controller.dart';
export 'src/navigator/guard.dart';
export 'src/navigator/modal.dart';
export 'src/navigator/navigator.dart';
export 'src/navigator/page.dart';
export 'src/util/extension.dart';
