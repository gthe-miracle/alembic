import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import 'page.dart';

/// {@template alembic_dialog_page}
/// Shows an [AlembicPage] as a dialog: centered above a barrier, with a fade.
///
/// The page is tagged [AlembicPage.modalTag], and its route is page-based and built on widgets only.
/// ```dart
/// final class ConfirmPage extends AppPage with AlembicDialogPage {
///   const ConfirmPage() : super(child: const ConfirmDialog());
///
///   @override
///   AlembicAlias get alias => Routes.confirm;
/// }
///
/// final confirmed = await controller.pushForResult<bool>(const ConfirmPage());
/// // in the dialog: Navigator.pop(context, true)
/// ```
/// {@endtemplate}
base mixin AlembicDialogPage on AlembicPage {
  /// Whether a tap on the barrier closes the dialog.
  bool get barrierDismissible => true;

  /// The color of the barrier.
  Color get barrierColor => const Color(0x8A000000);

  /// The semantic label of the barrier.
  String get barrierLabel => 'Dismiss';

  @override
  Set<String> get tags => {...super.tags, AlembicPage.modalTag};

  @override
  Route<Object?> createRoute(BuildContext context) => _DialogRoute(this);
}

/// {@template alembic_sheet_page}
/// Shows an [AlembicPage] as a modal bottom sheet, like Flutter's `showModalBottomSheet`: it slides up above a barrier,
/// spans the width, may take the full height (at most 9/16 of it when [isScrollControlled] is false), and closes on a
/// downward fling or when dragged below half its height.
///
/// The page is tagged [AlembicPage.modalTag], and its route is page-based and built on widgets only.
/// ```dart
/// final class FiltersPage extends AppPage with AlembicSheetPage {
///   const FiltersPage() : super(child: const FiltersSheet());
///
///   @override
///   AlembicAlias get alias => Routes.filters;
/// }
/// ```
/// {@endtemplate}
base mixin AlembicSheetPage on AlembicPage {
  /// Whether a tap on the barrier closes the sheet.
  bool get barrierDismissible => true;

  /// The color of the barrier.
  Color get barrierColor => const Color(0x8A000000);

  /// The semantic label of the barrier.
  String get barrierLabel => 'Dismiss';

  /// Whether a downward drag closes the sheet.
  bool get enableDrag => true;

  /// Whether the sheet may take the full height, e.g. for a [DraggableScrollableSheet]. When false, it takes at most
  /// 9/16 of it, like `showModalBottomSheet` by default.
  bool get isScrollControlled => true;

  /// Whether the sheet avoids the system intrusions at the top, left and right. Otherwise the top padding is removed
  /// from its [MediaQuery].
  bool get useSafeArea => false;

  @override
  Set<String> get tags => {...super.tags, AlembicPage.modalTag};

  @override
  Route<Object?> createRoute(BuildContext context) => _SheetRoute(this);
}

final class _DialogRoute extends PopupRoute<Object?> {
  _DialogRoute(AlembicDialogPage page) : super(settings: page);

  AlembicDialogPage get _page => settings as AlembicDialogPage;

  @override
  bool get barrierDismissible => _page.barrierDismissible;

  @override
  Color get barrierColor => _page.barrierColor;

  @override
  String get barrierLabel => _page.barrierLabel;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 150);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
      Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: SafeArea(child: Center(child: _page.child)),
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  );
}

// A widgets-only port of Flutter's ModalBottomSheetRoute: the same layout, timing, curves and drag rules.
final class _SheetRoute extends PopupRoute<Object?> {
  _SheetRoute(AlembicSheetPage page) : super(settings: page);

  static const Curve _curve = Cubic(0, 0, 0.2, 1);

  /// The downward speed, in logical pixels per second, that closes the sheet whatever its position.
  static const double _closingVelocity = 700;

  static const double _closeProgressThreshold = 0.5;

  static const double _maxHeightRatio = 9 / 16;

  final GlobalKey _childKey = GlobalKey(debugLabel: 'AlembicSheetPage child');

  /// Linear while a drag runs, so the sheet follows the finger; after it, the rest of the move eases from there.
  Curve _slideCurve = _curve;

  AlembicSheetPage get _page => settings as AlembicSheetPage;

  double get _childHeight => _childKey.currentContext!.size!.height;

  /// A sheet closed under the finger is on its way out, and the rest of the drag must not bring it back.
  bool get _dismissUnderway => controller!.status == AnimationStatus.reverse;

  @override
  bool get barrierDismissible => _page.barrierDismissible;

  @override
  Color get barrierColor => _page.barrierColor;

  @override
  String get barrierLabel => _page.barrierLabel;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) {
    Widget sheet = NotificationListener<DraggableScrollableNotification>(
      onNotification: _extentChanged,
      child: KeyedSubtree(key: _childKey, child: _page.child),
    );
    if (_page.enableDrag) {
      sheet = RawGestureDetector(
        excludeFromSemantics: true,
        gestures: {
          VerticalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<VerticalDragGestureRecognizer>(
            () => VerticalDragGestureRecognizer(debugOwner: this),
            (recognizer) => recognizer
              ..onStart = _handleDragStart
              ..onUpdate = _handleDragUpdate
              ..onEnd = _handleDragEnd
              ..onlyAcceptDragOnThreshold = true,
          ),
        },
        child: sheet,
      );
    }
    sheet = AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: ClipRect(
          child: CustomSingleChildLayout(
            delegate: _SheetLayout(
              progress: _slideCurve.transform(animation.value),
              maxHeightRatio: _page.isScrollControlled ? 1 : _maxHeightRatio,
            ),
            child: child,
          ),
        ),
      ),
      child: sheet,
    );
    return _page.useSafeArea
        ? SafeArea(bottom: false, child: sheet)
        : MediaQuery.removePadding(context: context, removeTop: true, child: sheet);
  }

  void _handleDragStart(DragStartDetails details) => _slideCurve = Curves.linear;

  void _handleDragUpdate(DragUpdateDetails details) {
    if (_dismissUnderway) return;
    controller!.value -= details.primaryDelta! / _childHeight;
  }

  void _handleDragEnd(DragEndDetails details) {
    if (_dismissUnderway) return;
    final controller = this.controller!;
    final velocity = details.velocity.pixelsPerSecond.dy;
    _slideCurve = Split(controller.value, endCurve: _curve);
    if (velocity > _closingVelocity) {
      if (controller.value > 0) unawaited(controller.fling(velocity: -velocity / _childHeight));
      _close();
    } else if (controller.value < _closeProgressThreshold) {
      if (controller.value > 0) unawaited(controller.fling(velocity: -1));
      _close();
    } else {
      unawaited(controller.forward());
    }
  }

  // A DraggableScrollableSheet dragged down to its minimum closes the sheet.
  bool _extentChanged(DraggableScrollableNotification notification) {
    if (notification.extent == notification.minExtent && notification.shouldCloseOnMinExtent) _close();
    return false;
  }

  void _close() {
    if (isCurrent) navigator?.pop();
  }
}

/// Spans the width, caps the height at [maxHeightRatio] of the screen, and slides the sheet up by [progress].
final class _SheetLayout extends SingleChildLayoutDelegate {
  const _SheetLayout({required this.progress, required this.maxHeightRatio});

  final double progress;
  final double maxHeightRatio;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints(
    minWidth: constraints.maxWidth,
    maxWidth: constraints.maxWidth,
    maxHeight: constraints.maxHeight * maxHeightRatio,
  );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(0, size.height - childSize.height * progress);

  @override
  bool shouldRelayout(_SheetLayout oldDelegate) =>
      progress != oldDelegate.progress || maxHeightRatio != oldDelegate.maxHeightRatio;
}
