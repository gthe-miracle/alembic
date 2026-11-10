import 'package:flutter/material.dart';

/// {@template about_sheet}
/// The content of a sheet page: drag it down, tap the barrier or press back to close it. The list scrolls on its own;
/// the rest of the sheet drags it.
/// {@endtemplate}
class AboutSheet extends StatelessWidget {
  /// {@macro about_sheet}
  const AboutSheet({super.key});

  @override
  Widget build(BuildContext context) => Material(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
    // A sheet has no Scaffold to avoid the keyboard: lift the content by its height.
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('About'),
                const SizedBox(height: 8),
                const TextField(),
                const Text('A sheet page: an ElixirPage with ElixirSheetPage.'),
                const SizedBox(height: 8),
                // Up to 240 high, and shorter when the keyboard needs the room.
                Flexible(
                  child: SizedBox(
                    height: 240,
                    child: ListView.builder(
                      itemCount: 30,
                      itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
