import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum BluePillThemeChoice {
  dark,
  light,
}

class ThemeController extends ValueNotifier<BluePillThemeChoice> {
  ThemeController._() : super(BluePillThemeChoice.dark);

  static final ThemeController instance = ThemeController._();
  static const _storageKey = 'bluepill_theme';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    value = stored == BluePillThemeChoice.light.name || stored == 'blueWhite'
        ? BluePillThemeChoice.light
        : BluePillThemeChoice.dark;
  }

  Future<void> setTheme(BluePillThemeChoice theme) async {
    if (value == theme) return;
    value = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, theme.name);
  }
}
