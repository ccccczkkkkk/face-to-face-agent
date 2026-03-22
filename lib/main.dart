import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_settings.dart';
import 'home_page.dart';
import 'l10n/app_localizations.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: appLocaleNotifier,
      builder: (context, locale, _) {
        const colorScheme = ColorScheme(
          brightness: Brightness.light,
          primary: Color(0xFF6E6A86),
          onPrimary: Colors.white,
          secondary: Color(0xFF8A86A3),
          onSecondary: Colors.white,
          error: Color(0xFFB3261E),
          onError: Colors.white,
          surface: Color(0xFFF7F7FA),
          onSurface: Color(0xFF1F2230),
          surfaceContainerHighest: Color(0xFFE8E7F0),
          onSurfaceVariant: Color(0xFF6A6C78),
          outline: Color(0xFFD9DAE3),
          outlineVariant: Color(0xFFE7E8EE),
          shadow: Color(0x1A11131A),
          scrim: Color(0x66000000),
          inverseSurface: Color(0xFF2C2F3A),
          onInverseSurface: Colors.white,
          inversePrimary: Color(0xFFD2CFE6),
          surfaceTint: Color(0xFF6E6A86),
        );

        return MaterialApp(
          locale: locale,
          onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: colorScheme,
            scaffoldBackgroundColor: const Color(0xFFF3F4F7),
            canvasColor: const Color(0xFFF3F4F7),
            appBarTheme: const AppBarTheme(
              backgroundColor: Color(0xFFF3F4F7),
              foregroundColor: Color(0xFF1F2230),
              elevation: 0,
              scrolledUnderElevation: 0,
              surfaceTintColor: Colors.transparent,
            ),
            cardTheme: CardThemeData(
              color: Colors.white,
              elevation: 0,
              margin: const EdgeInsets.all(0),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
            dialogTheme: DialogThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            bottomSheetTheme: const BottomSheetThemeData(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
            ),
            floatingActionButtonTheme: const FloatingActionButtonThemeData(
              backgroundColor: Color(0xFFF0F1F6),
              foregroundColor: Color(0xFF6E6A86),
              elevation: 6,
              focusElevation: 8,
              hoverElevation: 8,
              highlightElevation: 10,
            ),
          ),
          home: const HomePage(),
        );
      },
    );
  }
}
