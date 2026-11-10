import 'package:alembic/alembic.dart';
import 'package:flutter/material.dart';

import '../../common/routes/routes.dart';
import '../../common/widget/app.dart';

/// {@template home_screen}
/// HomeScreen widget.
/// {@endtemplate}
class HomeScreen extends StatelessWidget {
  /// {@macro home_screen}
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Home'),
      actions: [
        IconButton(
          icon: Icon(Theme.of(context).brightness == Brightness.dark ? Icons.light_mode : Icons.dark_mode),
          onPressed: () => App.toggleThemeOf(context),
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () => context.alembic.push(SettingsScopePage(data: 'Data from home')),
        ),
      ],
    ),
    // Alembic.stackOf rebuilds this text on every change of the root Alembic.
    body: SafeArea(
      child: Center(child: Text('Pages: ${Alembic.stackOf(context).map((page) => page.name).join(' > ')}')),
    ),
  );
}
