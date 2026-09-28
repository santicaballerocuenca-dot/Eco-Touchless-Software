import 'package:flutter/material.dart';

/// Identidad visual de ECO-TOUCHLESS.
///
/// Paleta pensada como "escáner ecológico": verdes profundos de bosque para
/// las superficies oscuras (donde vive la cámara), un verde lima vivo como
/// acento de acción/éxito, y un ámbar cálido para advertencia. Se evita el
/// verde Material genérico por defecto para que la app tenga una identidad
/// propia reconocible.
class AppColors {
  AppColors._();

  // Verdes de marca
  static const Color bosqueProfundo = Color(0xFF0B1220); // fondo base oscuro
  static const Color bosque = Color(0xFF132436);
  static const Color bosqueClaro = Color(0xFF276674);
  static const Color limaVivo = Color(0xFF63CDBD); // acento principal
  static const Color limaBrillante = Color(0xFFAEEDDE); // highlights

  // Estados
  static const Color ambar = Color(0xFFE8A33D); // dudoso / advertencia
  static const Color coral = Color(0xFFE76F51); // error
  static const Color info = Color(0xFF4EA8DE);
  static const Color neonCian = Color(0xFF35F2FF);
  static const Color neonMagenta = Color(0xFFFF4FD8);

  // Neutros para superficies claras (Configuración/Estadísticas en modo claro)
  static const Color crema = Color(0xFFF7F5F0);
  static const Color grafito = Color(0xFF1A1F1D);

  // Colores por tipo de residuo (coherente con el dataset del modelo)
  static const Map<String, Color> porTipoResiduo = {
    'Metal': Color(0xFF8D99AE),
    'NoAceptar': coral,
    'Organico': Color(0xFF7F5539),
    'Papel_carton': Color(0xFFD68C45),
    'Plastico': Color(0xFF4EA8DE),
    'Vidrio': limaVivo,
    'Fondo': Color(0xFF6C757D),
  };

  static Color colorParaResiduo(String label) =>
      porTipoResiduo[label] ?? limaVivo;
}

class AppTheme {
  AppTheme._();

  static const _fontDisplay = 'Roboto';

  static ThemeData claro() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.limaVivo,
      brightness: Brightness.light,
      primary: AppColors.bosqueClaro,
      secondary: AppColors.limaVivo,
      surface: AppColors.crema,
    );
    return _base(scheme, Brightness.light);
  }

  static ThemeData oscuro() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.limaVivo,
      brightness: Brightness.dark,
      primary: AppColors.limaBrillante,
      secondary: AppColors.limaVivo,
      surface: AppColors.bosque,
    );
    return _base(scheme, Brightness.dark);
  }

  static ThemeData _base(ColorScheme scheme, Brightness brightness) {
    final esOscuro = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      splashFactory: InkRipple.splashFactory,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.onSurface.withValues(alpha: 0.04),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)))),
      bottomSheetTheme: BottomSheetThemeData(
          backgroundColor: scheme.surface,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)))),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _fontDisplay,
          fontWeight: FontWeight.w700,
          fontSize: 20,
          letterSpacing: 0.5,
          color: esOscuro ? AppColors.limaBrillante : AppColors.bosque,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: esOscuro
            ? AppColors.bosqueProfundo.withValues(alpha: 0.98)
            : Colors.white,
        indicatorColor: AppColors.limaVivo.withValues(alpha: 0.22),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? AppColors.limaVivo
                : (esOscuro ? Colors.white70 : Colors.black54),
          );
        }),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: esOscuro ? Colors.white.withValues(alpha: 0.06) : Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(
            color: esOscuro
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.05),
          ),
        ),
        margin: EdgeInsets.zero,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.limaVivo,
        thumbColor: AppColors.limaVivo,
        overlayColor: AppColors.limaVivo.withValues(alpha: 0.15),
        inactiveTrackColor: esOscuro
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.08),
        valueIndicatorColor: AppColors.bosque,
        valueIndicatorTextStyle: const TextStyle(color: Colors.white),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected) ? AppColors.limaVivo : null),
        trackColor: WidgetStateProperty.resolveWith((states) =>
            states.contains(WidgetState.selected)
                ? AppColors.limaVivo.withValues(alpha: 0.4)
                : null),
      ),
      textTheme: TextTheme(
        titleLarge: TextStyle(
          fontFamily: _fontDisplay,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: scheme.onSurface,
        ),
        titleMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        bodyMedium: TextStyle(
          color: scheme.onSurface.withValues(alpha: 0.75),
          height: 1.35,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
