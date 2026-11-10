import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'controller.dart';
import 'page.dart';

/// Handles the system back button instead of `navigator.maybePop()`; returns whether the press was handled.
typedef AlembicBackHandler = Future<bool> Function(NavigatorState navigator);

/// Called with a change of an Alembic or of an Alembic nested inside it, see [Alembic.listener].
typedef AlembicListener = void Function(AlembicNotification notification);

/// {@template alembic}
/// Renders an [AlembicController] with a [Navigator].
///
/// The widget is a thin adapter: it shows the pages of the controller, reports the pages the user closed (a swipe, a
/// barrier tap, `Navigator.pop(context, result)`) back with `controller.remove`, and handles the system back button.
/// ```dart
/// MaterialApp(builder: (context, _) => Alembic(controller: controller));
/// ```
///
/// Every committed change is dispatched as an [AlembicNotification], which bubbles up through the outer Alembics: one
/// [NotificationListener] above the root Alembic hears every navigator of the app.
///
/// The back button goes to the visible nested Alembics first, the newest first, then to [onBackButtonPressed], by
/// default `navigator.maybePop()`. So a dialog or a sheet on top closes first, `PopScope` is respected, and the last
/// page lets the platform close the app. A nested Alembic is visible while its route is current and it is not hidden
/// by a [Visibility], e.g. an inactive tab of an [IndexedStack].
///
/// While a visible nested Alembic can pop, it blocks the route hosting it, so the swipe-back of that route never closes
/// the route with an open sheet or with pages stacked inside it.
/// {@endtemplate}
class Alembic extends StatefulWidget {
  /// {@macro alembic}
  const Alembic({
    required this.controller,
    this.listener,
    this.observers = const <NavigatorObserver>[],
    this.transitionDelegate = const DefaultTransitionDelegate<Object?>(),
    this.onBackButtonPressed,
    this.restorationScopeId,
    this.reportsRouteUpdateToEngine = false,
    super.key,
  });

  /// The owner of the pages.
  final AlembicController controller;

  /// Called after every change of this Alembic and of every Alembic nested inside it; `controller.name` tells them
  /// apart. The notification keeps bubbling up whatever this does, and an error it throws is reported.
  /// ```dart
  /// Alembic(
  ///   controller: controller,
  ///   listener: (n) => log('${n.controller.name?.alias}: ${n.next.join(' > ')}'),
  /// );
  /// ```
  final AlembicListener? listener;

  /// Observers of the underlying [Navigator].
  final List<NavigatorObserver> observers;

  /// Decides how the routes are animated when the pages change.
  final TransitionDelegate<Object?> transitionDelegate;

  /// Replaces the default reaction to the back button, `navigator.maybePop()`.
  ///
  /// Called only when the press reaches this Alembic: no visible nested Alembic has handled it. A nested Alembic given
  /// this may decline the press, so it does not block the swipe-back of the route hosting it.
  /// ```dart
  /// onBackButtonPressed: (navigator) async {
  ///   if (controller.state.last.tags.contains('checkout')) {
  ///     controller.popUntil(Routes.cart);
  ///     return true;
  ///   }
  ///   return navigator.maybePop();
  /// },
  /// ```
  final AlembicBackHandler? onBackButtonPressed;

  /// Restores the state of the navigator when given, see [Navigator.restorationScopeId].
  final String? restorationScopeId;

  /// Whether the navigator reports the route changes to the engine, e.g. to the browser address bar.
  final bool reportsRouteUpdateToEngine;

  /// The controller of the closest Alembic above [context], if any.
  static AlembicController? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_AlembicScope>()?.state.widget.controller;

  /// The controller of the closest Alembic above [context].
  static AlembicController of(BuildContext context) => maybeOf(context) ?? _notFound();

  /// The pages of the closest Alembic above [context]; the widget is rebuilt when they change.
  static AlembicNavigationState stackOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AlembicScope>()?.pages ?? _notFound();

  /// The pages of every root Alembic and of the Alembics nested in them, as a tree for debug logs:
  /// ```text
  /// app
  /// ├─ home
  /// └─ settings
  ///    └─ profile {"id": 1, "data": "foo"}
  /// ```
  /// A page shows its name and its [AlembicPage.arguments] as JSON. The active pages, the ones on screen, are green with
  /// ANSI escape codes, which a console without colors prints as they are. A page hosting several Alembics, e.g. tabs,
  /// lists them under their `controller.name`. Only the mounted Alembics are shown: called from a [listener], the Alembic
  /// nested in a page that was just pushed appears after the frame.
  static String get treeView => _AlembicState._roots.map((root) => root._treeView).join('\n');

  /// [treeView] on one line for analytics, without colors: `app(home, settings(profile {"id": 1, "data": "foo"}))`.
  /// A page hosting several Alembics lists them by `controller.name`: `tabs(feed(post), profile(me))`.
  ///
  /// Read it after the frame, so the Alembic nested in a page that was just pushed is already there:
  /// ```dart
  /// listener: (_) => WidgetsBinding.instance.addPostFrameCallback((_) => analytics.log(Alembic.treeLine)),
  /// ```
  static String get treeLine => _AlembicState._roots.map((root) => root._treeLine).join(', ');

  static Never _notFound() => throw FlutterError('No Alembic found above this context.');

  @override
  State<Alembic> createState() => _AlembicState();
}

class _AlembicState extends State<Alembic> with WidgetsBindingObserver {
  /// The Alembics that take the back button from the binding: they are not nested into another Alembic.
  static final Set<_AlembicState> _roots = <_AlembicState>{};

  late final _Tracker _tracker = _Tracker((key, result) => _popped[key] = result);

  /// The results given to `Navigator.pop`, waiting for [_handleDidRemovePage].
  final Map<LocalKey, Object?> _popped = <LocalKey, Object?>{};

  late List<NavigatorObserver> _observers;
  late AlembicNavigationState _last;

  _AlembicState? _parent;

  /// The nested Alembics, in the order they were mounted.
  final List<_AlembicState> _children = <_AlembicState>[];

  /// The navigator a root Alembic is shown in, e.g. the one of a `MaterialApp`.
  NavigatorState? _host;

  /// The route of the outer navigator this Alembic is shown in.
  ModalRoute<Object?>? _route;
  bool _shown = true;
  bool _reportScheduled = false;

  /// Whether this nested Alembic blocks [_route]: the swipe of a route knows nothing about the navigator inside it.
  bool _holdsRoute = false;

  /* #region Lifecycle */
  @override
  void initState() {
    super.initState();
    _observers = <NavigatorObserver>[_tracker, ...widget.observers];
    _last = widget.controller.state;
    widget.controller.addListener(_handleChange);
    _register();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Only the back button depends on these: the guards never run here.
    _route = ModalRoute.of(context);
    _shown = Visibility.of(context);
    _reportBackButton();
  }

  @override
  void didUpdateWidget(covariant Alembic oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.observers, oldWidget.observers)) {
      _observers = <NavigatorObserver>[_tracker, ...widget.observers];
    }
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_handleChange);
      widget.controller.addListener(_handleChange);
      _last = widget.controller.state;
      _popped.clear();
    }
    _reportBackButton();
  }

  @override
  void activate() {
    super.activate();
    _register();
    _reportBackButton();
  }

  @override
  void deactivate() {
    final parent = _parent;
    _unregister();
    // The Alembics left behind may be the ones handling the back button now.
    (parent ?? _roots.firstOrNull)?._reportBackButton();
    if (parent == null && _roots.isEmpty) _reportNoAlembicLeft();
    super.deactivate();
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleChange);
    super.dispose();
  }
  /* #endregion */

  void _handleChange() {
    final previous = _last;
    final next = _last = widget.controller.state;
    if (!mounted || identical(previous, next)) return;
    setState(() {});
    final notification = AlembicNotification(widget.controller, previous, next);
    // The notification bubbles up from here, so the NotificationListener built below never sees it: call the listener.
    _callListener(notification);
    try {
      notification.dispatch(context);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, 'dispatching an AlembicNotification');
    }
  }

  /// The changes of the nested Alembics, on their way up.
  bool _handleNestedChange(AlembicNotification notification) {
    _callListener(notification);
    return false;
  }

  /// A throwing listener would stop the notification on its way up.
  void _callListener(AlembicNotification notification) {
    try {
      widget.listener?.call(notification);
    } on Object catch (error, stackTrace) {
      _report(error, stackTrace, 'calling the listener');
    }
  }

  void _report(Object error, StackTrace stackTrace, String action) => FlutterError.reportError(
    FlutterErrorDetails(
      exception: error,
      stack: stackTrace,
      library: 'alembic',
      context: ErrorDescription('while $action of ${widget.controller}'),
    ),
  );

  /// Called by the [Navigator] for a page the user or the framework closed.
  void _handleDidRemovePage(Page<Object?> page) {
    if (page is! AlembicPage) return;
    final controller = widget.controller..remove(page, _popped.remove(page.key));
    // A guard has kept the page that the navigator already dropped: build it again.
    if (mounted && controller.state.any((other) => other.key == page.key)) setState(() {});
  }

  /* #region Tree view */
  String get _label => widget.controller.name?.alias ?? 'alembic';

  String get _treeView {
    final out = StringBuffer(_label);
    _writeTree(out, '', shown: true);
    return '$out';
  }

  /// Writes the pages, one per line after [indent], each with the Alembics nested in it. The active page, the top one
  /// of an Alembic that is [shown] and [_visible], is green.
  // An Alembic in a route that is not one of the pages, e.g. a `showDialog`, is left out.
  void _writeTree(StringBuffer out, String indent, {required bool shown}) {
    final pages = widget.controller.state;
    for (final (index, page) in pages.indexed) {
      final last = index == pages.length - 1;
      final active = shown && last && _visible;
      final label = _pageLabel(page);
      final next = _writeNode(out, indent, active ? '\x1B[32m$label\x1B[0m' : label, last: last);
      final nested = _nestedIn(page);
      if (nested case [final child]) {
        child._writeTree(out, next, shown: active);
      } else {
        // Several Alembics in one page, e.g. tabs: name each one.
        for (final (index, child) in nested.indexed) {
          child._writeTree(out, _writeNode(out, next, child._label, last: index == nested.length - 1), shown: active);
        }
      }
    }
  }

  /// The name with the arguments as JSON, `profile {"id": 1, "data": "foo"}`; a value JSON has no form for is written
  /// with its `toString`.
  static String _pageLabel(AlembicPage page) {
    if (page.arguments.isEmpty) return page.name;
    final entries = page.arguments.entries.map(
      (entry) => '${jsonEncode(entry.key)}: ${jsonEncode(entry.value, toEncodable: (value) => '$value')}',
    );
    return '${page.name} {${entries.join(', ')}}';
  }

  /// Writes a branch to [label] and returns the indent of its children.
  static String _writeNode(StringBuffer out, String indent, String label, {required bool last}) {
    out.write('\n$indent${last ? '└─ ' : '├─ '}$label');
    return '$indent${last ? '   ' : '│  '}';
  }

  String get _treeLine => '$_label(${_pagesLine()})';

  /// The pages, each with the Alembics nested in it in parentheses.
  String _pagesLine() => widget.controller.state
      .map(
        (page) => switch (_nestedIn(page)) {
          [] => _pageLabel(page),
          [final child] => '${_pageLabel(page)}(${child._pagesLine()})',
          final nested => '${_pageLabel(page)}(${nested.map((child) => child._treeLine).join(', ')})',
        },
      )
      .join(', ');

  /// The Alembics nested in [page], in the order they were mounted.
  List<_AlembicState> _nestedIn(AlembicPage page) => [
    for (final child in _children)
      if (child._route?.settings case AlembicPage(:final key) when key == page.key) child,
  ];
  /* #endregion */

  /* #region Back button */
  void _register() {
    if (context.getInheritedWidgetOfExactType<_AlembicScope>()?.state case final parent?) {
      _parent = parent.._children.add(this);
    } else {
      _host = Navigator.maybeOf(context);
      _roots.add(this);
      WidgetsBinding.instance.addObserver(this);
    }
  }

  void _unregister() {
    if (_parent case final parent?) {
      parent._children.remove(this);
      _parent = null;
    } else {
      _roots.remove(this);
      WidgetsBinding.instance.removeObserver(this);
    }
  }

  @override
  Future<bool> didPopRoute() => _visible ? _handleBackButton() : SynchronousFuture<bool>(false);

  bool get _visible => mounted && _shown && (_route?.isCurrent ?? true);

  Future<bool> _handleBackButton() async {
    for (final child in _children.reversed.toList(growable: false)) {
      if (child._visible && await child._handleBackButton()) return true;
    }
    final navigator = _tracker.navigator;
    if (!mounted || navigator == null) return false;
    return (widget.onBackButtonPressed ?? _maybePop)(navigator);
  }

  static Future<bool> _maybePop(NavigatorState navigator) => navigator.maybePop();

  /// Whether a press reaching this Alembic would be handled, decided the way [_handleBackButton] does it.
  bool get _canHandlePop {
    if (!_visible) return false;
    if (_children.any((child) => child._canHandlePop) || widget.onBackButtonPressed != null) return true;
    final navigator = _tracker.navigator;
    return navigator != null && (navigator.canPop() || _tracker.top?.popDisposition == RoutePopDisposition.doNotPop);
  }

  /// The navigators report only themselves, so a nested one and its parent overwrite each other's report: swallow
  /// them, and let the roots report for the whole tree.
  bool _handleNavigationNotification(NavigationNotification notification) {
    _reportBackButton();
    return true;
  }

  /// Tells the platform whether the app handles the back button; without it, the predictive back gesture of Android
  /// closes the app without ever calling [didPopRoute].
  void _reportBackButton() {
    // The navigators report from the post frame callbacks: answer in the same frame.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.postFrameCallbacks) return _dispatchBackButton();
    if (_reportScheduled) return;
    _reportScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _reportScheduled = false;
        _dispatchBackButton();
      }, debugLabel: 'Alembic.reportBackButton')
      ..ensureVisualUpdate();
  }

  void _dispatchBackButton() {
    if (!mounted) return;
    // Only a nested Alembic: the navigator of a root one would swallow the press before the root gets it.
    final holdsRoute = _parent != null && widget.onBackButtonPressed == null && _canHandlePop;
    if (holdsRoute != _holdsRoute) setState(() => _holdsRoute = holdsRoute);
    if (_parent case final parent?) return parent._dispatchBackButton();
    // Deactivated, e.g. while it moves with a global key.
    if (!_roots.contains(this)) return;
    NavigationNotification(canHandlePop: _roots.any((root) => root._canHandlePop)).dispatch(context);
  }

  /// A pop of the route this Alembic blocks, e.g. the `BackButton` of an `AppBar` above it.
  // Two visible nested Alembics in one route both pop here; an outer `maybePop` is the only way to get here.
  void _handleRoutePopBlocked(bool didPop, Object? result) {
    if (!didPop && _holdsRoute) unawaited(_handleBackButton());
  }

  /// Withdraws the claim of the last root Alembic, which nothing else would replace.
  void _reportNoAlembicLeft() {
    final host = _host;
    if (host == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_roots.isEmpty && host.mounted) NavigationNotification(canHandlePop: host.canPop()).dispatch(host.context);
    }, debugLabel: 'Alembic.reportNoAlembicLeft');
  }
  /* #endregion */

  @override
  Widget build(BuildContext context) => _AlembicScope(
    state: this,
    pages: widget.controller.state,
    // Always in the tree, even without a listener: adding one later would remount the navigator.
    child: NotificationListener<AlembicNotification>(
      onNotification: _handleNestedChange,
      child: NotificationListener<NavigationNotification>(
        onNotification: _handleNavigationNotification,
        child: PopScope<Object?>(
          canPop: !_holdsRoute,
          onPopInvokedWithResult: _handleRoutePopBlocked,
          child: Navigator(
            // A new list, so the navigator also brings back a page a guard kept after the user closed it.
            pages: List<Page<Object?>>.of(widget.controller.state),
            onDidRemovePage: _handleDidRemovePage,
            observers: _observers,
            transitionDelegate: widget.transitionDelegate,
            restorationScopeId: widget.restorationScopeId,
            reportsRouteUpdateToEngine: widget.reportsRouteUpdateToEngine,
          ),
        ),
      ),
    ),
  );
}

/// Links an Alembic with its controller below and with the nested Alembics.
class _AlembicScope extends InheritedWidget {
  const _AlembicScope({required this.state, required this.pages, required super.child});

  final _AlembicState state;

  /// The pages this Alembic was built with.
  final AlembicNavigationState pages;

  @override
  bool updateShouldNotify(covariant _AlembicScope oldWidget) => !identical(oldWidget.pages, pages);
}

/// {@template alembic_notification}
/// A change committed by the controller of an [Alembic], bubbling up through the widget tree.
///
/// ```dart
/// NotificationListener<AlembicNotification>(
///   onNotification: (notification) {
///     log('${notification.controller.name}: ${notification.next}');
///     return false; // let it reach the listeners above
///   },
///   child: Alembic(controller: controller),
/// );
/// ```
///
/// A change committed during a build is dispatched after the frame, merged with the following ones of that frame.
/// {@endtemplate}
final class AlembicNotification extends Notification {
  /// {@macro alembic_notification}
  const AlembicNotification(this.controller, this.previous, this.next);

  /// The controller that committed the change; `controller.name` tells the Alembics apart.
  final AlembicController controller;

  /// The pages before the change.
  final AlembicNavigationState previous;

  /// The pages after the change.
  final AlembicNavigationState next;

  /// The pages whose keys are new.
  AlembicNavigationState get added => _without(next, previous);

  /// The pages whose keys are gone.
  AlembicNavigationState get removed => _without(previous, next);

  static AlembicNavigationState _without(AlembicNavigationState pages, AlembicNavigationState other) {
    final keys = {for (final page in other) page.key};
    return [
      for (final page in pages)
        if (!keys.contains(page.key)) page,
    ];
  }

  @override
  void debugFillDescription(List<String> description) {
    super.debugFillDescription(description);
    description.add('$controller');
  }
}

/// Reaches the [NavigatorState], keeps the visible route and catches the results given to `Navigator.pop`.
class _Tracker extends NavigatorObserver {
  _Tracker(this._onPop);

  final void Function(LocalKey key, Object? result) _onPop;

  /// The visible route, to see whether a `PopScope` blocks the back button.
  Route<Object?>? top;

  @override
  void didChangeTop(Route<Object?> topRoute, Route<Object?>? previousTopRoute) => top = topRoute;

  @override
  void didPush(Route<Object?> route, Route<Object?>? previousRoute) => _track(route);

  @override
  void didReplace({Route<Object?>? newRoute, Route<Object?>? oldRoute}) {
    if (newRoute != null) _track(newRoute);
  }

  void _track(Route<Object?> route) {
    if (route case ModalRoute<Object?>(settings: AlembicPage(:final key))) {
      route.registerPopEntry(_PopResult(key, _onPop));
    }
  }
}

/// A [PopEntry] that never blocks a pop and only records its result.
class _PopResult extends PopEntry<Object?> {
  _PopResult(this._key, this._onPop);

  final LocalKey _key;
  final void Function(LocalKey key, Object? result) _onPop;

  @override
  ValueListenable<bool> get canPopNotifier => const _AlwaysTrue();

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (didPop) _onPop(_key, result);
  }
}

/// A `true` that never changes, so it keeps no listeners of the routes.
class _AlwaysTrue implements ValueListenable<bool> {
  const _AlwaysTrue();

  @override
  bool get value => true;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
