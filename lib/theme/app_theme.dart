import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'appearance.dart';

class AppTheme {
  AppTheme._();

  static ThemeData dark([Appearance palette = const Appearance()]) {
    final scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: palette.accent,
      onPrimary: palette.onAccent,
      primaryContainer: palette.wine,
      onPrimaryContainer: palette.accentGlow,
      secondary: palette.accentGlow,
      onSecondary: Color(0xFF1A0010),
      secondaryContainer: palette.accentMuted,
      onSecondaryContainer: palette.accentGlow,
      tertiary: Color(0xFFF38BDB),
      onTertiary: Color(0xFF1A0010),
      error: Color(0xFFFF4D6D),
      onError: Color(0xFFFFFFFF),
      surface: palette.card,
      onSurface: palette.onSurface,
      onSurfaceVariant: palette.muted,
      outline: palette.border,
      outlineVariant: Color(0xFF2A1C3A),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: palette.onSurface,
      onInverseSurface: palette.bg,
      inversePrimary: palette.accent,
      surfaceTint: palette.accent,
    );

    return ThemeData(
      useMaterial3: true,
      extensions: [palette],
      brightness: Brightness.dark,
      colorScheme: scheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      pageTransitionsTheme: palette.animations ? PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
          TargetPlatform.linux: FadeUpwardsPageTransitionsBuilder(),
        },
      ) : PageTransitionsTheme(builders: {
        for (final platform in TargetPlatform.values) platform: const _InstantTransitions(),
      }),
      scaffoldBackgroundColor: palette.bg,
      canvasColor: palette.bg,
      dividerColor: palette.border,
      splashColor: palette.accent.withValues(alpha: 0.20),
      highlightColor: palette.accent.withValues(alpha: 0.13),
      iconTheme: IconThemeData(color: palette.onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: palette.surface,
        foregroundColor: palette.onSurface,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(color: palette.onSurface, fontSize: 21, fontWeight: FontWeight.w700),
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: palette.surface,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: palette.card,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: palette.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: palette.card,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: palette.surface,
        indicatorColor: palette.wine,
        surfaceTintColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: palette.accent);
          }
          return IconThemeData(color: palette.muted);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            color: selected ? palette.accent : palette.muted,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
          );
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.card,
        disabledColor: palette.card,
        selectedColor: palette.accentMuted,
        secondarySelectedColor: palette.accentMuted,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: palette.border),
        ),
        labelStyle: TextStyle(color: palette.onSurface),
        secondaryLabelStyle: TextStyle(color: palette.accent),
        brightness: Brightness.dark,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: palette.accent,
        foregroundColor: palette.onAccent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.onSurface,
          side: BorderSide(color: palette.border),
          backgroundColor: palette.card,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: palette.accent,
          foregroundColor: palette.onAccent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.accentGlow,
        textColor: palette.onSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: palette.accent,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: palette.accent,
        thumbColor: palette.accent,
        inactiveTrackColor: palette.accent.withValues(alpha: 0.27),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.accent;
          return palette.muted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return palette.wine;
          return palette.border;
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.card,
        hintStyle: TextStyle(color: palette.muted),
        prefixIconColor: palette.muted,
        suffixIconColor: palette.muted,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: palette.accent, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: palette.card,
        contentTextStyle: TextStyle(color: palette.onSurface),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: DividerThemeData(color: palette.border),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(palette.accent.withValues(alpha: 0.53)),
        radius: Radius.circular(999),
      ),
    );
  }
}

class _InstantTransitions extends PageTransitionsBuilder {
  const _InstantTransitions();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
      Animation<double> animation, Animation<double> secondaryAnimation, Widget child) => child;
}
