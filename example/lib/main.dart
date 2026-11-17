import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'src/common/widget/app.dart';

void main() => runZonedGuarded<void>(
  () => runApp(const App()),
  (error, stackTrace) =>
      print('Top level exception: $error'), // ignore: avoid_print
);
