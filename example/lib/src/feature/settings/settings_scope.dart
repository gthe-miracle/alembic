import 'package:alembic/alembic.dart';
import 'package:flutter/widgets.dart';

import '../../common/routes/routes.dart';

/// {@template settings_scope}
/// A nested Alembic with its own controller; inside it, `context.alembic` is that controller.
/// {@endtemplate}
class SettingsScope extends StatefulWidget {
  /// {@macro settings_scope}
  const SettingsScope({required this.data, super.key});

  final String data;

  @override
  State<SettingsScope> createState() => _SettingsScopeState();
}

class _SettingsScopeState extends State<SettingsScope> {
  late final AlembicController _controller = AlembicController(
    [SettingsPage(data: widget.data)],
    guards: const [ModalGuard()],
    name: AppRoutes.settings,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Alembic(controller: _controller);
}
