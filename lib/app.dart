import 'package:flutter/material.dart';
import 'core/app_refresh_notifier.dart';
import 'routes/app_routes.dart';
import 'theme/app_theme.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final _RouteChangeObserver _routeObserver = _RouteChangeObserver(
    _handleRouteChange,
  );

  void _refreshCurrentScreen() {
    // Rebuild pontual da arvore atual sem reinicializar rotas.
    AppRefreshNotifier.trigger();
    final context = _navigatorKey.currentContext;
    if (context is Element) {
      context.markNeedsBuild();
    }
  }

  static void _handleRouteChange(Route<dynamic>? route) {
    final name = route?.settings.name;
    final shouldHide = name == AppRoutes.home || name == AppRoutes.dietControl;
    AppRefreshNotifier.setFloatingVisible(!shouldHide);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: [_routeObserver],
      title: 'FitMatch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      initialRoute: AppRoutes.home,
      routes: AppRoutes.routes,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final topOffset = media.padding.top + 12;

        return Stack(
          children: [
            if (child != null) child,
            ValueListenableBuilder<bool>(
              valueListenable: AppRefreshNotifier.floatingVisible,
              builder: (context, isVisible, _) {
                if (!isVisible) return const SizedBox.shrink();
                return Positioned(
                  top: topOffset,
                  right: 12,
                  child: SafeArea(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: _refreshCurrentScreen,
                        child: Ink(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B4DBA),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.88),
                              width: 1.4,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.refresh_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _RouteChangeObserver extends NavigatorObserver {
  _RouteChangeObserver(this.onRouteChanged);

  final void Function(Route<dynamic>? route) onRouteChanged;

  void _notify(Route<dynamic>? route) {
    if (route is PageRoute) {
      onRouteChanged(route);
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notify(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _notify(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _notify(newRoute);
  }
}
