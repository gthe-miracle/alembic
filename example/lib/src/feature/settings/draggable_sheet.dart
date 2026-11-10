import 'package:flutter/material.dart';

/// {@template draggable_sheet}
/// The content of a sheet page built on a [DraggableScrollableSheet]: dragging the list grows and shrinks the sheet
/// before it scrolls, and shrinking it to its minimum closes the page. The handle drags the whole sheet.
/// {@endtemplate}
class DraggableSheet extends StatelessWidget {
  /// {@macro draggable_sheet}
  const DraggableSheet({super.key});

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    // The sheet page gives it the full height (isScrollControlled); it takes its own fraction of it.
    expand: false,
    initialChildSize: 0.5,
    minChildSize: 0.25,
    maxChildSize: 0.9,
    builder: (context, scrollController) => Material(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: Column(
        children: [
          const SizedBox(
            height: 24,
            child: Center(
              child: SizedBox(
                width: 32,
                height: 4,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: Colors.grey, borderRadius: BorderRadius.all(Radius.circular(2))),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              itemCount: 50,
              itemBuilder: (context, index) => ListTile(title: Text('Item $index')),
            ),
          ),
        ],
      ),
    ),
  );
}
