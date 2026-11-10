# Alembic

Declarative Navigator 2.0 navigation for Flutter. The navigation state is a list of pages owned by one controller:
every change goes through pure guard rules, and a thin widget renders it.

```dart
controller.change((state) => [...state, const SettingsPage()]);
```

## Features

- ✅ The navigation state is a plain `List<AlembicPage>`; rewrite it and the screens follow
- ✅ One owner, `AlembicController`, that works and tests without widgets
- ✅ Guards: pure `(from, to) => to` rules applied to every change, re-run by a `Listenable`
- ✅ Results: `await controller.pushForResult<bool>(page)`, completed by `pop(result)` or `Navigator.pop(context, result)`
- ✅ Dialogs and bottom sheets as pages (`AlembicDialogPage`, `AlembicSheetPage`)
- ✅ Nested Alembics with innermost, newest-first system back handling and correct Android predictive back
- ✅ One `NotificationListener` at the root hears every navigator of the app
- ✅ No Material dependency: pages build any `Route` (Material, Cupertino or custom)

## Getting Started

```shell
flutter pub add alembic
```

or in `pubspec.yaml`:

```yaml
dependencies:
  alembic: ^0.6.1
```

Then import it:

```dart
import 'package:alembic/alembic.dart';
```

## Usage

### 1. Aliases

```dart
enum Routes implements AlembicAlias {
  app('app'), // names the root Alembic
  home('home'),
  product('product'),
  settings('settings'),
  confirm('confirm'),
  filters('filters');

  const Routes(this.alias);

  @override
  final String alias;
}
```

### 2. Pages

A page is an immutable value and also the `Page` given to the `Navigator`. Implement `alias` and `createRoute`, usually
once in a sealed base page:

```dart
@immutable
sealed class AppPage extends AlembicPage {
  const AppPage({required super.child, super.arguments, super.key});

  @override
  Route<Object?> createRoute(BuildContext context) => AppPageRoute(this);
}

/// Material transitions from the theme. Page-based: a new page under the same key updates the screen.
final class AppPageRoute extends PageRoute<Object?> with MaterialRouteTransitionMixin<Object?> {
  AppPageRoute(AppPage page) : super(settings: page);

  @override
  Widget buildContent(BuildContext context) => (settings as AppPage).child;

  @override
  bool get maintainState => true;
}

// Or Cupertino transitions with the swipe-back gesture on every platform; `title` is required by the mixin:
// final class AppPageRoute extends PageRoute<Object?> with CupertinoRouteTransitionMixin<Object?> {
//   ...same as above, plus:
//   @override
//   String? get title => null;
// }

final class HomePage extends AppPage {
  const HomePage() : super(child: const HomeScreen());

  @override
  AlembicAlias get alias => Routes.home;
}

final class ProductPage extends AppPage {
  ProductPage(this.id) : super(child: ProductScreen(id: id));

  final int id;

  // Parameters kept in fields need their own key, otherwise every product is one screen.
  @override
  LocalKey get key => ValueKey<String>('product/$id');

  @override
  AlembicAlias get alias => Routes.product;
}
```

Without Material, `AlembicPageRoute(this)` is a widgets-only page-based route with a `transitionsBuilder` hook.

The route must be page-based: it reads `(settings as AlembicPage).child` on every build. A `MaterialPageRoute(builder:)`
captures the first child, so a new instance of the page with the same key would never reach the screen.

### 3. Controller and widget

```dart
class _AppState extends State<App> {
  late final AlembicController _controller = AlembicController(
    [const HomePage()],
    guards: const [RootGuard(HomePage()), ModalGuard()],
    name: Routes.app,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    builder: (context, _) => Alembic(controller: _controller),
  );
}
```

### 4. Navigate

`context.alembic` is the controller of the closest Alembic:

```dart
context.alembic.push(const SettingsPage());            // a page already in the state moves to the top
context.alembic.pop();                                  // never removes the last page
context.alembic.popUntil(Routes.home);                  // to the topmost page with the alias
context.alembic.removeTag('checkout');
context.alembic.reset();                                // back to the initial state, through the guards
context.alembic.change((state) => [state.first, ProductPage(1)]);

final confirmed = await context.alembic.pushForResult<bool>(const ConfirmPage());
```

Inside a page, the usual `Navigator.maybePop(context)` and `Navigator.pop(context, result)` work too: the controller
learns about every page the user closes.

## Guards

A guard receives the committed state `from` and the requested state `to`, and returns the state to commit. Return
`to`, a redirect, or `from` to cancel. Guards see neither the controller nor a `BuildContext`: they are pure rules,
testable as functions. Their dependencies go to their constructor, and `revalidate` re-runs them:

```dart
final controller = AlembicController(
  [const HomePage()],
  guards: [
    const RootGuard(HomePage()),
    AlembicGuard((from, to) => auth.isSignedIn ? to : [const SignInPage()]),
  ],
  revalidate: auth, // a Listenable
);
```

Every change runs this pipeline:
1. dedupe by key, keeping the last page;
2. the guards in order;
3. dedupe again.

An empty result is reported and rejected. A result equal to the current state is ignored. A guard that throws is
reported to `FlutterError` and skipped. A guard with state of its own implements `AlembicGuard`.

Built-in guards:
- `RootGuard(page)` keeps a page at the bottom.
- `ModalGuard()` keeps dialogs and sheets above the screens.

To stop the user from closing a page, use `PopScope`.

## Dialogs and sheets

A modal is a page: add a mixin to it.

```dart
final class ConfirmPage extends AppPage with AlembicDialogPage {
  const ConfirmPage() : super(child: const ConfirmDialog());

  @override
  AlembicAlias get alias => Routes.confirm;
}

final class FiltersPage extends AppPage with AlembicSheetPage {
  const FiltersPage() : super(child: const FiltersSheet());

  @override
  AlembicAlias get alias => Routes.filters;
}
```

Both mixins tag the page `AlembicPage.modalTag`, so `controller.removeTag(AlembicPage.modalTag)` closes every modal at
once. Their routes are widgets-only and page-based. The mixins expose these getters:
- `barrierDismissible`
- `barrierColor`
- `barrierLabel`
- `enableDrag`, `isScrollControlled` and `useSafeArea` (sheet only)

A sheet works like Flutter's `showModalBottomSheet`: it spans the width, may take the full height (`isScrollControlled`
is true by default; set it to false to cap the sheet at 9/16 of the height), and closes on a downward fling or when
dragged below half its height. It draws nothing itself, so its child brings the background, shape and bottom padding.

## Observing navigation

Every committed change is dispatched as an `AlembicNotification` that bubbles up through the outer Alembics. `listener`
on an Alembic hears that Alembic and every Alembic nested inside it, so `listener` on the root hears the whole app:

```dart
Alembic(
  controller: controller,
  listener: (n) => analytics.screens(n.controller.name, added: n.added, removed: n.removed),
)
```

`controller.name` tells the Alembics apart. `listener` never stops the notification, and an error it throws is reported
instead of breaking the listeners above.

`listener` is a shortcut for a `NotificationListener<AlembicNotification>` wrapped around the Alembic. Use the
`NotificationListener` directly to hear the changes from a widget above the Alembic, or to stop one by returning `true`.

You can also watch the state directly:
- `AlembicController` is a `ValueListenable<List<AlembicPage>>`, so it works with `ListenableBuilder` and with code
  outside the widget tree.
- `Alembic.stackOf(context)` rebuilds a widget on every change.

For debug logs, `Alembic.treeView` draws every mounted Alembic, nested ones under their pages, each page with its
arguments as JSON and the pages on screen in green (ANSI colors):

```dart
Alembic(controller: controller, listener: (_) => log(Alembic.treeView));
```

```text
app
├─ home
├─ profile {"id": 1}
└─ settings
   └─ notifications
```

For analytics, `Alembic.treeLine` is the same tree on one line, without colors:
`app(home, profile {"id": 1}, settings(notifications))`. Read it after the frame, so the Alembic nested in a page that was
just pushed is already mounted:

```dart
listener: (_) => WidgetsBinding.instance.addPostFrameCallback((_) => analytics.log(Alembic.treeLine)),
```

## Back button

The system back button goes to the visible nested Alembics first, newest first, then to `navigator.maybePop()`. So:
- an open dialog or sheet closes first;
- `PopScope` is respected;
- a nested Alembic with one page hands the press to its parent;
- the root page lets the platform close the app.

A nested Alembic under a covered route, or in a hidden `IndexedStack` tab, is skipped. The root Alembic reports one
`canHandlePop` for the whole tree, so Android's predictive back gesture only closes the app when nothing can go back.

```dart
Alembic(
  controller: controller,
  onBackButtonPressed: (navigator) async {
    if (controller.state.last.tags.contains('checkout')) {
      controller.popUntil(Routes.home);
      return true;
    }
    return navigator.maybePop();
  },
)
```

### iOS swipe-back gesture

The example has a widgets-only port of Flutter's iOS edge swipe for custom routes: copy
`example/lib/src/common/cupertino_back/cupertino_back_gesture.dart` and see how
`example/lib/src/common/routes/custom_route_transitions.dart` uses it. Routes built with
`CupertinoRouteTransitionMixin` always have the swipe, and those built with `MaterialRouteTransitionMixin` get it from
a theme that uses `CupertinoPageTransitionsBuilder`.

Like the back button, the swipe respects a nested Alembic: while it is visible and can pop, the route hosting it can't be
swiped away. The swipe goes to its top page, and over an open dialog or sheet it does nothing. A nested Alembic with
`onBackButtonPressed` doesn't block its route, since the callback may decline the press.

## Core API

### AlembicPage

| Member          | Type                   | Description                                                           |
| --------------- | ---------------------- | --------------------------------------------------------------------- |
| `child`         | `Widget`               | The content of the page                                               |
| `alias`         | `AlembicAlias`          | Required; usually an enum value                                       |
| `name`          | `String`               | `alias.alias`                                                         |
| `tags`          | `Set<String>`          | Optional marks, used by `removeTag` and `ModalGuard`                  |
| `arguments`     | `Map<String, Object?>` | Optional; empty by default                                            |
| `key`           | `LocalKey`             | The given key, else `name` or `name?a=1&b` (escaped)                  |
| `createRoute()` | `Route<Object?>`       | Required; must be page-based                                          |

Pages compare by identity; the controller identifies them by `key`.

### AlembicController

| Member                         | Description                                                           |
| ------------------------------ | --------------------------------------------------------------------- |
| `AlembicController(initial, …)` | `guards`, `revalidate` (`Listenable`), `name` (`AlembicAlias`)         |
| `state` / `value`              | The current pages, unmodifiable                                       |
| `change(fn)`                   | Rewrites the state; every other method is a shortcut for it           |
| `push(page)`                   | Adds a page on top, or moves its key to the top                       |
| `pushForResult<T>(page)`       | Pushes and completes when the page leaves, with its result or `null`  |
| `pop([result])`                | Removes the top page unless it is the last one                        |
| `remove(page, [result])`       | Removes the page with that key                                        |
| `popUntil(alias)`              | Removes the pages above the topmost page with the alias               |
| `removeTag(tag)`               | Removes the pages with the tag                                        |
| `reset()`                      | Returns to the initial state, through the guards                      |
| `revalidate()`                 | Runs the guards on the current state again                            |

A change requested while another one is committed (from a listener, for example) is queued and applied after it. After
64 changes in a row the rest are reported and dropped.

### Alembic

| Parameter                    | Type                         | Description                                         |
| ---------------------------- | ---------------------------- | --------------------------------------------------- |
| `controller`                 | `AlembicController`           | Required                                            |
| `listener`                   | `AlembicListener?`            | Changes of this Alembic and of the nested ones       |
| `observers`                  | `List<NavigatorObserver>`    | Observers of the underlying `Navigator`             |
| `transitionDelegate`         | `TransitionDelegate<Object?>`| Defaults to `DefaultTransitionDelegate`             |
| `onBackButtonPressed`        | `AlembicBackHandler?`         | Replaces `navigator.maybePop()`                     |
| `restorationScopeId`         | `String?`                    | Enables state restoration of the navigator          |
| `reportsRouteUpdateToEngine` | `bool`                       | Defaults to `false`                                 |

Static access works as follows:
- `Alembic.of(context)` and `Alembic.maybeOf(context)` return the controller, the same as `context.alembic` and
  `context.maybeAlembic`;
- `Alembic.stackOf(context)` returns the pages and rebuilds on every change;
- `Alembic.treeView` returns the pages of every Alembic as a tree, nested Alembics under their pages;
- `Alembic.treeLine` returns the same tree on one line, for analytics.

## Design

| Rule | What it means |
| --- | --- |
| Guards are pure business rules | They run only inside the controller, never during a build, so no change is ever committed mid-frame. |
| Data flows one way | The controller knows no widgets. The widget renders the pages, and reports back only the pages the user closed. |
| Back is the Navigator's back | Dialogs, `PopScope` and `Page.canPop` work without special cases. |
| The page is the `Page` | The Navigator's own key diff keeps routes and their state. |
| A change carries its results | A pop result travels with the change that removed the page. |

## Migrating from elixir 0.5

The package was renamed from `elixir` to `alembic` in 0.6.0, because `elixir` is taken on pub.dev. The API is the same:

- the dependency is `alembic`, from `https://github.com/gthe-miracle/alembic.git`;
- `package:elixir/elixir.dart` becomes `package:alembic/alembic.dart`;
- every `Elixir*` type becomes `Alembic*` (`ElixirController` → `AlembicController`, `Elixir` → `Alembic`, …);
- `context.elixir` / `context.maybeElixir` become `context.alembic` / `context.maybeAlembic`.

## Migrating from elixir 0.4

| elixir 0.4 | alembic 0.6 |
| --- | --- |
| `ValueNotifier<ElixirNavigationState>` + `Elixir.controlled(controller:)` / `Elixir(pages:)` | `AlembicController(pages, guards:, revalidate:, name:)` + `Alembic(controller:)` |
| `guards: [(context, state) => …]` on the widget | `guards: [AlembicGuard((from, to) => …)]` on the controller; read dependencies when you create the controller |
| `state.toSet().toList()` guard | Built in: the last page of each key wins |
| `context.elixir` → `ElixirState` | `context.alembic` → `AlembicController` |
| `listeners: [(elixir, previous, next) {}]` | `listener: (notification) {}` |
| `context.elixir.observer.addListener(…)` | `listener` on the root Alembic, or a `NotificationListener<AlembicNotification>` above it |
| `onBackButtonPressed: (state) => (state:, handled:)` | `onBackButtonPressed: (navigator) async => …` |
| `super(name: …, child: …)`, required `tags`, `==` override | `super(child: …)`; `tags` optional; no `==` override |
| `Route<void> createRoute` with `MaterialPageRoute(builder:)` | `Route<Object?> createRoute` with a page-based route |
| `reset(page)` | `reset()` |
| `Elixir.stateOf` / `Elixir.navigatorOf` | `Alembic.stackOf` / `Navigator.of(pageContext)` |

## Example

See [example/](example/) for an app with:
- a nested Alembic;
- a dialog page that returns a result;
- a sheet page;
- a custom swipe-back route.

## License

MIT, see [LICENSE](LICENSE).

## Author

Created and maintained by [Miracle](https://github.com/gthe-miracle).
