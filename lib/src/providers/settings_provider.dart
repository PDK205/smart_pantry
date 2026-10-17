import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/gemini_service.dart';
import '../services/pantry_ai.dart';

/// Được override trong main() bằng instance đã load sẵn → không có màn trắng.
final sharedPrefsProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('sharedPrefsProvider chưa được override'),
);

class AppSettings {
  final String apiKey;
  final String model;
  final String baseUrl;
  final ThemeMode themeMode;
  final int householdSize;
  final String dietNotes;
  final bool onboarded;

  const AppSettings({
    this.apiKey = '',
    this.model = kDefaultModel,
    this.baseUrl = kDefaultBaseUrl,
    this.themeMode = ThemeMode.system,
    this.householdSize = 2,
    this.dietNotes = '',
    this.onboarded = false,
  });

  bool get hasApiKey => apiKey.trim().isNotEmpty;

  AppSettings copyWith({
    String? apiKey,
    String? model,
    String? baseUrl,
    ThemeMode? themeMode,
    int? householdSize,
    String? dietNotes,
    bool? onboarded,
  }) =>
      AppSettings(
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
        themeMode: themeMode ?? this.themeMode,
        householdSize: householdSize ?? this.householdSize,
        dietNotes: dietNotes ?? this.dietNotes,
        onboarded: onboarded ?? this.onboarded,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._prefs) : super(_read(_prefs));

  final SharedPreferences _prefs;

  static const _kKey = 'gemini_api_key';
  static const _kModel = 'gemini_model';
  static const _kBase = 'gemini_base_url';
  static const _kTheme = 'theme_mode';
  static const _kHouse = 'household_size';
  static const _kDiet = 'diet_notes';
  static const _kOnboard = 'onboarded_v2';

  static AppSettings _read(SharedPreferences p) {
    final model = p.getString(_kModel);
    return AppSettings(
      apiKey: p.getString(_kKey) ?? '',
      model: kGeminiModels.any((m) => m.id == model) ? model! : kDefaultModel,
      baseUrl: p.getString(_kBase) ?? kDefaultBaseUrl,
      themeMode: ThemeMode.values[(p.getInt(_kTheme) ?? 0).clamp(0, 2)],
      householdSize: p.getInt(_kHouse) ?? 2,
      dietNotes: p.getString(_kDiet) ?? '',
      onboarded: p.getBool(_kOnboard) ?? false,
    );
  }

  Future<void> setApiKey(String v) async {
    state = state.copyWith(apiKey: v.trim());
    await _prefs.setString(_kKey, v.trim());
  }

  Future<void> setModel(String v) async {
    state = state.copyWith(model: v);
    await _prefs.setString(_kModel, v);
  }

  Future<void> setBaseUrl(String v) async {
    final url = v.trim().isEmpty ? kDefaultBaseUrl : v.trim();
    state = state.copyWith(baseUrl: url);
    await _prefs.setString(_kBase, url);
  }

  Future<void> setThemeMode(ThemeMode m) async {
    state = state.copyWith(themeMode: m);
    await _prefs.setInt(_kTheme, m.index);
  }

  Future<void> setHouseholdSize(int n) async {
    state = state.copyWith(householdSize: n.clamp(1, 20));
    await _prefs.setInt(_kHouse, state.householdSize);
  }

  Future<void> setDietNotes(String v) async {
    state = state.copyWith(dietNotes: v);
    await _prefs.setString(_kDiet, v);
  }

  Future<void> setOnboarded() async {
    state = state.copyWith(onboarded: true);
    await _prefs.setBool(_kOnboard, true);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>(
  (ref) => SettingsNotifier(ref.watch(sharedPrefsProvider)),
);

/// null khi chưa có API key.
final geminiServiceProvider = Provider<GeminiService?>((ref) {
  final s = ref.watch(settingsProvider.select((s) => (s.apiKey, s.model, s.baseUrl)));
  if (s.$1.trim().isEmpty) return null;
  return GeminiService(apiKey: s.$1, model: s.$2, baseUrl: s.$3);
});

final pantryAiProvider = Provider<PantryAi?>((ref) {
  final gemini = ref.watch(geminiServiceProvider);
  if (gemini == null) return null;
  final p = ref.watch(settingsProvider.select((s) => (s.householdSize, s.dietNotes)));
  return PantryAi(gemini, householdSize: p.$1, dietNotes: p.$2);
});
