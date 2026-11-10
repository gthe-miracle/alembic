import 'package:alembic/alembic.dart';
import 'package:flutter/cupertino.dart';

import '../../feature/home/home_screen.dart';
import '../../feature/settings/about_sheet.dart';
import '../../feature/settings/draggable_sheet.dart';
import '../../feature/settings/settings_dialog.dart';
import '../../feature/settings/settings_scope.dart';
import '../../feature/settings/settings_screen.dart';
import 'custom_route_transitions.dart';

/// The pages of the root Alembic; `app` names the root Alembic itself.
enum AppRoutes implements AlembicAlias {
  app('app'),
  home('home'),
  settings('settings_scope');

  const AppRoutes(this.alias);

  @override
  final String alias;
}

/// The pages of the settings Alembic, nested in [SettingsScopePage].
enum Settings implements AlembicAlias {
  settings('settings'),
  dialog('settings_dialog'),
  about('about'),
  draggable('draggable_sheet'),
  detail('settings_detail');

  const Settings(this.alias);

  @override
  final String alias;
}

/// Reads the child of its current page on every build, so a new page under the same key updates the screen.
final class AppPageRoute extends PageRoute<Object?> with CupertinoRouteTransitionMixin<Object?> {
  AppPageRoute(AppPage page) : super(settings: page);

  @override
  Widget buildContent(BuildContext context) => (settings as AppPage).child;

  /// Shown as the previous-page title by a `CupertinoNavigationBar`; none here.
  @override
  String? get title => null;

  @override
  bool get maintainState => true;
}

/// The base of every page: Cupertino transitions with the swipe-back gesture on every platform, page-based.
@immutable
sealed class AppPage extends AlembicPage {
  const AppPage({required super.child, super.arguments, super.key});

  @override
  Route<Object?> createRoute(BuildContext context) => AppPageRoute(this);
}

final class HomePage extends AppPage {
  const HomePage() : super(child: const HomeScreen());

  @override
  AlembicAlias get alias => AppRoutes.home;
}

final class SettingsScopePage extends AppPage {
  SettingsScopePage({required this.data})
    : super(
        child: SettingsScope(data: data),
        arguments: {'data': data},
      );

  final String data;

  @override
  AlembicAlias get alias => AppRoutes.settings;
}

final class SettingsPage extends AppPage {
  SettingsPage({required this.data})
    : super(
        child: SettingsScreen(data: data),
        arguments: {'data': data},
      );

  final String data;

  @override
  Route<Object?> createRoute(BuildContext context) => CustomMaterialRoute(page: this);

  @override
  AlembicAlias get alias => Settings.settings;
}

final class SettingsDetailPage extends AppPage {
  const SettingsDetailPage() : super(child: const SettingsScreenDetail());

  @override
  AlembicAlias get alias => Settings.detail;
}

/// Opened with `pushForResult<bool>`: the dialog pops `true` or `false`.
final class SettingsDialogPage extends AppPage with AlembicDialogPage {
  const SettingsDialogPage() : super(child: const SettingsDialog());

  @override
  AlembicAlias get alias => Settings.dialog;
}

final class AboutSheetPage extends AppPage with AlembicSheetPage {
  const AboutSheetPage() : super(child: const AboutSheet());

  @override
  AlembicAlias get alias => Settings.about;

  // The keyboard padding makes the sheet taller than the default 9/16 of the screen.
  @override
  bool get isScrollControlled => true;
}

final class DraggableSheetPage extends AppPage with AlembicSheetPage {
  const DraggableSheetPage() : super(child: const DraggableSheet());

  @override
  AlembicAlias get alias => Settings.draggable;

  // A DraggableScrollableSheet sizes itself as a fraction of the full height.
  @override
  bool get isScrollControlled => true;
}
