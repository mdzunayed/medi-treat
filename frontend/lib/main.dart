import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/network/dispatch_overlay.dart';
import 'core/theme/mt_theme.dart';
import 'core/router/app_router.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Medi-Treat',
      theme: MtTheme.light(),
      darkTheme: MtTheme.dark(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      // Wrap every routed screen so the authenticated socket stays alive
      // app-wide and the intrusive incoming-dispatch overlay can paint on
      // top of any screen the instant a `dispatch:incoming` event lands.
      builder: (context, child) =>
          DispatchOverlayHost(child: child ?? const SizedBox.shrink()),
    );
  }
}
