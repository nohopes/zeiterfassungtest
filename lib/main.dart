import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/root_shell.dart';
import 'theme/design_tokens.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de_DE', null);
  runApp(const ZeiterfassungApp());
}

class ZeiterfassungApp extends StatelessWidget {
  const ZeiterfassungApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Basis über fromSeed erzeugen (garantiert alle Tonal-Rollen inkl. der
    // neueren surfaceContainer*-Werte), dann gezielt auf die
    // "Werkstattbuch"-Palette umfärben.
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.amber,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.amber,
      onPrimary: const Color(0xFF241800),
      primaryContainer: AppColors.amberDim,
      onPrimaryContainer: AppColors.amber,
      secondary: AppColors.teal,
      onSecondary: const Color(0xFF04211C),
      secondaryContainer: AppColors.tealDim,
      onSecondaryContainer: AppColors.teal,
      error: AppColors.rust,
      surface: AppColors.bg,
      onSurface: AppColors.ink,
      onSurfaceVariant: AppColors.inkMuted,
      surfaceContainerHighest: AppColors.surfaceHigh,
      surfaceContainerHigh: AppColors.surfaceHigh,
      surfaceContainer: AppColors.surface,
      surfaceContainerLow: AppColors.surface,
      surfaceContainerLowest: AppColors.bg,
      outline: AppColors.line,
      outlineVariant: AppColors.line,
    );

    return MaterialApp(
      title: 'Stunden Logbuch',
      debugShowCheckedModeBanner: false,
      locale: const Locale('de', 'DE'),
      supportedLocales: const [Locale('de', 'DE')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Bewusst nur EIN Theme (dunkel) - App ignoriert die System-Einstellung
      // und läuft immer im Dark Mode.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: AppColors.bg,
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.bg,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: AppColors.ink,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
        // Karten werden bewusst kaum noch benutzt (die Eintragslisten laufen
        // über LedgerRow) - für vereinzelte Restfälle trotzdem ruhig/flach
        // gehalten statt als "schwebende" Material-Karte.
        cardTheme: CardThemeData(
          elevation: 0,
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: const BorderSide(color: AppColors.line),
          ),
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        listTileTheme: const ListTileThemeData(
          shape: RoundedRectangleBorder(),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppColors.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(4),
            borderSide: const BorderSide(color: AppColors.amber, width: 1.6),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.surface,
          side: const BorderSide(color: AppColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          indicatorColor: AppColors.amberDim,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.amber,
            foregroundColor: const Color(0xFF241800),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.line),
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: AppColors.amber,
          foregroundColor: const Color(0xFF241800),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.line,
          thickness: 1,
          space: 1,
        ),
      ),
      home: const RootShell(),
    );
  }
}
