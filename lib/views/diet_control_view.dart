import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/app_refresh_notifier.dart';
import '../core/objective_options.dart';
import '../services/auth_service.dart';
import '../widgets/logout_confirmation_dialog.dart';

/// Dicionário de substituição simples para traduzir termos comuns de unidade
/// que a FatSecret retorna em inglês no `serving_description`, mesmo quando a
/// requisição usa `language=pt`. Aplicado antes de exibir a porção no dropdown.
const Map<String, String> _servingEnToPt = {
  'NS as to size': 'tamanho não especificado',
  'extra large': 'extra grande',
  'tablespoon': 'colher de sopa',
  'tablespoons': 'colheres de sopa',
  'teaspoon': 'colher de chá',
  'teaspoons': 'colheres de chá',
  'large': 'grande',
  'medium': 'médio',
  'small': 'pequeno',
  'tbsp': 'colher de sopa',
  'tsp': 'colher de chá',
  'cup': 'xícara',
  'cups': 'xícaras',
  'slice': 'fatia',
  'slices': 'fatias',
  'piece': 'pedaço',
  'pieces': 'pedaços',
  'serving': 'porção',
  'servings': 'porções',
  'oz': 'onças (oz)',
  'ounce': 'onça',
  'ounces': 'onças',
  'egg': 'ovo',
  'eggs': 'ovos',
};

/// Traduz/re-substitui os termos de unidade em inglês por seus equivalentes em
/// português. Termos mais longos são aplicados primeiro (ex.: "extra large").
String _translateServingDescription(String description) {
  if (description.trim().isEmpty) return description;
  var result = description;
  final entries = _servingEnToPt.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));
  for (final entry in entries) {
    result = result.replaceAll(
      RegExp(r'\b' + RegExp.escape(entry.key) + r'\b', caseSensitive: false),
      entry.value,
    );
  }
  return result;
}

class DietControlView extends StatefulWidget {
  final int userId;
  final String userName;
  final bool isTrainerSide;

  const DietControlView({
    super.key,
    required this.userId,
    required this.userName,
    required this.isTrainerSide,
  });

  @override
  State<DietControlView> createState() => _DietControlViewState();
}

class _DietControlViewState extends State<DietControlView> {
  static const String _applyAsFavoriteNameOption = '__APPLY_FAVORITE_NAME__';
  static const String _onlyTodayEditableMessage =
      'Somente o dia atual pode ser editado.';

  static const List<String> _mealTypes = [
    'Café da Manhã',
    'Lanche da Manhã',
    'Almoço',
    'Lanche da Tarde',
    'Jantar',
    'Ceia',
  ];

  static const List<String> _baseQuantityUnits = [
    'g',
    'ml',
  ];

  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  bool _loadingDay = false;
  bool _savingEntry = false;
  bool _searchingFoods = false;
  int _searchSeq = 0;

  List<Map<String, dynamic>> _foods = [];
  List<Map<String, dynamic>> _meals = [];
  List<Map<String, dynamic>> _savedMealTemplates = [];
  Map<String, List<Map<String, dynamic>>> _carryoverByMealType = {};
  final Map<String, Map<String, List<Map<String, dynamic>>>> _carryoverByDate =
      {};
  final Map<String, Set<String>> _suppressedCarryoverByDate = {};
  final Map<String, Set<int>> _excludedEntryIdsByDate = {};
  final Set<int> _excludedEntryIds = <int>{};
  final Map<String, Map<String, double>> _carryoverQuantityOverridesByDate = {};
  // mealType → data ISO a partir da qual foi suprimido permanentemente
  final Map<String, String> _suppressedMealTypeSince = {};

  double _basalKcal = 0;
  double _targetKcal = 0;
  double _consumedKcal = 0;
  double _remainingKcal = 0;
  double _protein = 0;
  double _carbs = 0;
  double _fat = 0;

  int? _selectedFoodId;
  String _selectedMeal = _mealTypes.first;

  final TextEditingController _foodSearchCtrl = TextEditingController();
  final TextEditingController _quantityCtrl = TextEditingController(
    text: '100',
  );
  String _quantityUnit = 'g';
  List<Map<String, dynamic>> _selectedServings = [];
  Timer? _foodSearchDebounce;

  List<Map<String, dynamic>> _foodSuggestions = [];
  bool _showFoodSuggestions = false;
  Map<String, dynamic>? _selectedExternalFood;
  bool _showMetricCoachTips = false;

  void _onGlobalRefresh() {
    unawaited(_loadAll(keepUi: true));
  }

  bool get _isPastDay {
    final selected = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return selected.year != today.year ||
        selected.month != today.month ||
        selected.day != today.day;
  }

  String get _excludedEntryIdsStateKey =>
      'diet_excluded_entry_ids_by_date_${widget.userId}';
  String get _suppressedCarryoverStateKey =>
      'diet_suppressed_carryover_by_date_${widget.userId}';
  String get _carryoverStateKey => 'diet_carryover_by_date_${widget.userId}';
  String get _carryoverQuantityOverridesStateKey =>
      'diet_carryover_quantity_overrides_by_date_${widget.userId}';
  String get _suppressedMealTypeSinceKey =>
      'diet_suppressed_meal_type_since_${widget.userId}';
  Future<void> _restoreLocalDietState() async {
    final prefs = await SharedPreferences.getInstance();

    final excludedRaw = prefs.getString(_excludedEntryIdsStateKey);
    if (excludedRaw != null && excludedRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(excludedRaw) as Map<String, dynamic>;
        _excludedEntryIdsByDate.clear();
        decoded.forEach((dateIso, value) {
          final ids = (value as List<dynamic>? ?? const [])
              .map((v) => int.tryParse(v.toString()) ?? 0)
              .where((id) => id > 0)
              .toSet();
          if (ids.isNotEmpty) {
            _excludedEntryIdsByDate[dateIso] = ids;
          }
        });
      } catch (_) {
        _excludedEntryIdsByDate.clear();
      }
    }

    final suppressedRaw = prefs.getString(_suppressedCarryoverStateKey);
    if (suppressedRaw != null && suppressedRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(suppressedRaw) as Map<String, dynamic>;
        _suppressedCarryoverByDate.clear();
        decoded.forEach((dateIso, value) {
          final mealTypes = (value as List<dynamic>? ?? const [])
              .map((v) => v.toString().trim())
              .where((v) => v.isNotEmpty)
              .toSet();
          if (mealTypes.isNotEmpty) {
            _suppressedCarryoverByDate[dateIso] = mealTypes;
          }
        });
      } catch (_) {
        _suppressedCarryoverByDate.clear();
      }
    }

    final carryoverRaw = prefs.getString(_carryoverStateKey);
    if (carryoverRaw != null && carryoverRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(carryoverRaw) as Map<String, dynamic>;
        _carryoverByDate.clear();
        decoded.forEach((dateIso, mealMapRaw) {
          final mealMap = <String, List<Map<String, dynamic>>>{};
          final mealMapDecoded =
              mealMapRaw as Map<String, dynamic>? ?? const {};
          mealMapDecoded.forEach((mealType, entriesRaw) {
            final entries = (entriesRaw as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList();
            if (entries.isNotEmpty) {
              mealMap[mealType] = entries;
            }
          });
          if (mealMap.isNotEmpty) {
            _carryoverByDate[dateIso] = mealMap;
          }
        });
      } catch (_) {
        _carryoverByDate.clear();
      }
    }

    final sinceRaw = prefs.getString(_suppressedMealTypeSinceKey);
    if (sinceRaw != null && sinceRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(sinceRaw) as Map<String, dynamic>;
        _suppressedMealTypeSince.clear();
        decoded.forEach((mealType, dateVal) {
          final dateStr = dateVal?.toString().trim() ?? '';
          if (mealType.isNotEmpty && dateStr.isNotEmpty) {
            _suppressedMealTypeSince[mealType] = dateStr;
          }
        });
      } catch (_) {
        _suppressedMealTypeSince.clear();
      }
    }

    final overridesRaw = prefs.getString(_carryoverQuantityOverridesStateKey);
    if (overridesRaw != null && overridesRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(overridesRaw) as Map<String, dynamic>;
        _carryoverQuantityOverridesByDate.clear();
        decoded.forEach((dateIso, valuesRaw) {
          final values = <String, double>{};
          final decodedValues = valuesRaw as Map<String, dynamic>? ?? const {};
          decodedValues.forEach((signature, quantity) {
            final parsed = _toDouble(quantity);
            if (parsed > 0) values[signature] = parsed;
          });
          if (values.isNotEmpty) {
            _carryoverQuantityOverridesByDate[dateIso] = values;
          }
        });
      } catch (_) {
        _carryoverQuantityOverridesByDate.clear();
      }
    }
  }

  Future<void> _persistLocalDietState() async {
    final prefs = await SharedPreferences.getInstance();

    final excludedPayload = <String, List<int>>{};
    _excludedEntryIdsByDate.forEach((dateIso, ids) {
      if (ids.isEmpty) return;
      excludedPayload[dateIso] = ids.toList()..sort();
    });

    final suppressedPayload = <String, List<String>>{};
    _suppressedCarryoverByDate.forEach((dateIso, mealTypes) {
      if (mealTypes.isEmpty) return;
      final sorted = mealTypes.toList()..sort();
      suppressedPayload[dateIso] = sorted;
    });

    final carryoverPayload =
        <String, Map<String, List<Map<String, dynamic>>>>{};
    _carryoverByDate.forEach((dateIso, mealMap) {
      if (mealMap.isEmpty) return;
      final normalizedMealMap = <String, List<Map<String, dynamic>>>{};
      mealMap.forEach((mealType, entries) {
        if (entries.isEmpty) return;
        normalizedMealMap[mealType] = entries
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
      if (normalizedMealMap.isNotEmpty) {
        carryoverPayload[dateIso] = normalizedMealMap;
      }
    });

    await prefs.setString(
      _excludedEntryIdsStateKey,
      jsonEncode(excludedPayload),
    );
    await prefs.setString(
      _suppressedCarryoverStateKey,
      jsonEncode(suppressedPayload),
    );
    await prefs.setString(_carryoverStateKey, jsonEncode(carryoverPayload));
    if (_suppressedMealTypeSince.isNotEmpty) {
      await prefs.setString(
        _suppressedMealTypeSinceKey,
        jsonEncode(Map<String, String>.from(_suppressedMealTypeSince)),
      );
    }
    await prefs.setString(
      _carryoverQuantityOverridesStateKey,
      jsonEncode(_carryoverQuantityOverridesByDate),
    );
  }

  /// Persiste apenas os dados de carryover/supressão — nunca os IDs de
  /// entradas excluídas. Usado pelo [_loadAll] para não sobrescrever o estado
  /// de exclusão que foi restaurado do SharedPreferences antes de qualquer
  /// chamada de rede.
  Future<void> _persistCarryoverState() async {
    final prefs = await SharedPreferences.getInstance();

    final suppressedPayload = <String, List<String>>{};
    _suppressedCarryoverByDate.forEach((dateIso, mealTypes) {
      if (mealTypes.isEmpty) return;
      final sorted = mealTypes.toList()..sort();
      suppressedPayload[dateIso] = sorted;
    });

    final carryoverPayload =
        <String, Map<String, List<Map<String, dynamic>>>>{};
    _carryoverByDate.forEach((dateIso, mealMap) {
      if (mealMap.isEmpty) return;
      final normalizedMealMap = <String, List<Map<String, dynamic>>>{};
      mealMap.forEach((mealType, entries) {
        if (entries.isEmpty) return;
        normalizedMealMap[mealType] = entries
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });
      if (normalizedMealMap.isNotEmpty) {
        carryoverPayload[dateIso] = normalizedMealMap;
      }
    });

    await prefs.setString(
      _suppressedCarryoverStateKey,
      jsonEncode(suppressedPayload),
    );
    await prefs.setString(_carryoverStateKey, jsonEncode(carryoverPayload));
    if (_suppressedMealTypeSince.isNotEmpty) {
      await prefs.setString(
        _suppressedMealTypeSinceKey,
        jsonEncode(Map<String, String>.from(_suppressedMealTypeSince)),
      );
    }
    await prefs.setString(
      _carryoverQuantityOverridesStateKey,
      jsonEncode(_carryoverQuantityOverridesByDate),
    );
  }

  List<String> _resolveMealChoices({
    required List<Map<String, dynamic>> meals,
    required List<Map<String, dynamic>> templates,
  }) {
    final options = List<String>.from(_mealTypes);

    bool containsIgnoreCase(String value) {
      return options.any((item) => item.toLowerCase() == value.toLowerCase());
    }

    void addOption(String raw) {
      final value = raw.trim();
      if (value.isEmpty) return;
      if (containsIgnoreCase(value)) return;
      options.add(value);
    }

    for (final meal in meals) {
      addOption((meal['mealType'] ?? '').toString());
    }

    for (final template in templates) {
      addOption((template['name'] ?? '').toString());
    }

    return options;
  }

  List<String> get _mealChoices =>
      _resolveMealChoices(meals: _meals, templates: _savedMealTemplates);

  String _entrySignature(String mealType, Map<String, dynamic> entry) {
    final foodId = _toInt(entry['foodId']);
    final foodName = (entry['foodName'] ?? '').toString().trim().toLowerCase();
    // Não inclui quantidade: se o alimento já existe nessa refeição no dia,
    // não deve ser duplicado como carryover mesmo que a qty seja diferente.
    if (foodId > 0) return '${mealType.toLowerCase()}|id:$foodId';
    return '${mealType.toLowerCase()}|name:$foodName';
  }

  Map<String, dynamic> _entryWithQuantity(
    Map<String, dynamic> entry,
    double quantity,
  ) {
    final currentQuantity = _toDouble(entry['quantityGrams']);
    if (currentQuantity <= 0) return entry;
    final factor = quantity / currentQuantity;
    return {
      ...entry,
      'quantityGrams': quantity,
      'calories': _toDouble(entry['calories']) * factor,
      'protein': _toDouble(entry['protein']) * factor,
      'carbs': _toDouble(entry['carbs']) * factor,
      'fat': _toDouble(entry['fat']) * factor,
    };
  }

  @override
  void initState() {
    super.initState();
    AppRefreshNotifier.signal.addListener(_onGlobalRefresh);
    unawaited(_initStateAndLoad());
  }

  Future<Map<String, dynamic>?> _findLatestPreviousDayWithMeals({
    required DateTime baseDate,
    int maxDaysBack = 30,
  }) async {
    for (var i = 1; i <= maxDaysBack; i++) {
      final candidate = baseDate.subtract(Duration(days: i));
      final candidateDaily = await AuthService.getDietEntriesByDate(
        userId: widget.userId,
        dateIso: _toDateIso(candidate),
      );
      final candidateMeals =
          (candidateDaily['meals'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
      if (candidateMeals.isNotEmpty) {
        return {'dateIso': _toDateIso(candidate), 'daily': candidateDaily};
      }
    }
    return null;
  }

  Future<void> _initStateAndLoad() async {
    try {
      await _restoreLocalDietState();
    } catch (_) {
      // If local restore fails, continue with remote data load.
    }
    await _loadAll();
  }

  void _showCoachTips() {
    if (!mounted) return;
    setState(() => _showMetricCoachTips = true);
  }

  void _hideCoachTips() {
    if (!mounted) return;
    setState(() => _showMetricCoachTips = false);
  }

  @override
  void dispose() {
    AppRefreshNotifier.signal.removeListener(_onGlobalRefresh);
    _foodSearchDebounce?.cancel();
    _foodSearchCtrl.dispose();
    _quantityCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll({bool keepUi = false}) async {
    if (keepUi) {
      if (mounted) setState(() => _loadingDay = true);
    } else {
      if (mounted) setState(() => _loading = true);
    }

    // Captura a data no início, antes de qualquer await, para evitar race condition:
    // se _selectedDate mudar durante as chamadas assíncronas, ainda usamos a data
    // correta em todos os cálculos e no setState final.
    final capturedDateIso = _toDateIso(_selectedDate);

    try {
      final foods = await AuthService.getDietFoods(widget.userId);
      final daily = await AuthService.getDietEntriesByDate(
        userId: widget.userId,
        dateIso: capturedDateIso,
      );

      // Busca os últimos 7 dias em paralelo para carryover robusto (sem depender de SP)
      const int carryoverWindowDays = 7;
      final lookbackDates = List.generate(carryoverWindowDays, (i) {
        // Parseia capturedDateIso para evitar usar _selectedDate mutável
        final parts = capturedDateIso.split('-');
        final base = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
        return _toDateIso(base.subtract(Duration(days: i + 1)));
      });
      final lookbackDailies = await Future.wait(
        lookbackDates.map(
          (d) => AuthService.getDietEntriesByDate(
            userId: widget.userId,
            dateIso: d,
          ),
        ),
      );
      if (!mounted) return;

      final totals = (daily['totals'] as Map<String, dynamic>?) ?? const {};
      final meals = (daily['meals'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final savedMeals = (daily['savedMeals'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      // Usa a data capturada no início (não relê _selectedDate para evitar race condition)
      final selectedDateIso = capturedDateIso;

      // Verifica se há alguma entrada nos últimos 7 dias (para fallback além do window)
      final recentHasEntries = lookbackDailies.any(
        (d) => ((d['meals'] as List<dynamic>?) ?? const []).isNotEmpty,
      );

      // Fallback para além de 7 dias (caso usuário não use o app por mais tempo)
      Map<String, dynamic>? fallbackCarryoverDaily;
      String? fallbackCarryoverDateIso;
      if (!recentHasEntries) {
        final fallback = await _findLatestPreviousDayWithMeals(
          baseDate: DateTime(
            int.parse(capturedDateIso.split('-')[0]),
            int.parse(capturedDateIso.split('-')[1]),
            int.parse(capturedDateIso.split('-')[2]),
          ).subtract(const Duration(days: carryoverWindowDays)),
        );
        if (!mounted) return;
        if (fallback != null) {
          fallbackCarryoverDateIso = (fallback['dateIso'] ?? '').toString();
          fallbackCarryoverDaily = Map<String, dynamic>.from(
            fallback['daily'] as Map<String, dynamic>,
          );
        }
      }

      final existingSignatures = <String>{};
      final existingEntryCounts = <String, int>{};
      for (final meal in meals) {
        final mealType = (meal['mealType'] ?? '').toString().trim();
        final entries = (meal['entries'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e));
        for (final entry in entries) {
          final signature = _entrySignature(mealType, entry);
          existingSignatures.add(signature);
          existingEntryCounts[signature] =
              (existingEntryCounts[signature] ?? 0) + 1;
        }
      }

      final historicalEntryCounts = <String, int>{};
      final historicalSourceByFood = <String, String>{};

      void countHistoricalEntry(
        String mealType,
        Map<String, dynamic> entry,
        String sourceDateIso,
      ) {
        final signature = _entrySignature(mealType.trim(), entry);
        final previousSourceDate = historicalSourceByFood[signature];
        if (previousSourceDate != null && previousSourceDate != sourceDateIso) {
          return;
        }
        historicalSourceByFood[signature] = sourceDateIso;
        historicalEntryCounts[signature] =
            (historicalEntryCounts[signature] ?? 0) + 1;
      }

      for (var i = 0; i < lookbackDates.length; i++) {
        final dateIso = lookbackDates[i];
        final dayData = lookbackDailies[i];
        final pastMeals = (dayData['meals'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e));
        for (final meal in pastMeals) {
          final mealType = (meal['mealType'] ?? '').toString().trim();
          if (mealType.isEmpty) continue;
          final suppressionDate = _suppressedMealTypeSince[mealType];
          if (suppressionDate != null &&
              suppressionDate.compareTo(dateIso) > 0) {
            continue;
          }
          final pastEntries = (meal['entries'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e));
          for (final entry in pastEntries) {
            countHistoricalEntry(mealType, entry, dateIso);
          }
        }
      }

      final carryoverByMealType = <String, List<Map<String, dynamic>>>{};
      final carryoverSignatures = <String>{};
      final carryoverEntryCounts = <String, int>{};
      final carryoverSourceByFood = <String, String>{};

      void addCarryover(
        String mealType,
        Map<String, dynamic> entry,
        String sourceDateIso,
      ) {
        final normalizedMealType = mealType.trim();
        if (normalizedMealType.isEmpty) return;
        final signature = _entrySignature(normalizedMealType, entry);
        final existingCount = existingEntryCounts[signature] ?? 0;
        final carryoverCount = carryoverEntryCounts[signature] ?? 0;
        final historicalCount = historicalEntryCounts[signature] ?? 1;
        if (existingCount + carryoverCount >= historicalCount) return;

        final foodKey = signature;
        final previousSourceDate = carryoverSourceByFood[foodKey];
        if (previousSourceDate != null && previousSourceDate != sourceDateIso) {
          return;
        }
        carryoverSourceByFood[foodKey] = sourceDateIso;

        final entrySignature = _entryIdentitySignature(
          normalizedMealType,
          entry,
        );
        if (carryoverSignatures.contains(entrySignature)) return;

        carryoverSignatures.add(entrySignature);
        carryoverEntryCounts[signature] = carryoverCount + 1;
        carryoverByMealType
            .putIfAbsent(normalizedMealType, () => <Map<String, dynamic>>[])
            .add({...entry, 'mealType': normalizedMealType});
      }

      // Acumula carryover dos últimos 7 dias do backend (do mais recente ao mais antigo)
      for (int i = 0; i < lookbackDates.length; i++) {
        final dateIso = lookbackDates[i];
        final dayData = lookbackDailies[i];
        final pastMeals = (dayData['meals'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e));

        for (final meal in pastMeals) {
          final mealType = (meal['mealType'] ?? '').toString().trim();
          if (mealType.isEmpty) continue;

          // Pula se o mealType foi suprimido permanentemente APÓS esta data de entrada
          final suppressionDate = _suppressedMealTypeSince[mealType];
          if (suppressionDate != null &&
              suppressionDate.compareTo(dateIso) > 0) {
            continue;
          }

          final pastEntries = (meal['entries'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e));
          for (final entry in pastEntries) {
            addCarryover(mealType, entry, dateIso);
          }
        }
      }

      // Fallback para além de 7 dias (via backend + cadeia SP)
      if (fallbackCarryoverDaily != null && fallbackCarryoverDateIso != null) {
        final fallbackMeals =
            (fallbackCarryoverDaily['meals'] as List<dynamic>? ?? const [])
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e));
        for (final meal in fallbackMeals) {
          final mealType = (meal['mealType'] ?? '').toString().trim();
          if (mealType.isEmpty) continue;
          final suppressionDate = _suppressedMealTypeSince[mealType];
          if (suppressionDate != null &&
              suppressionDate.compareTo(fallbackCarryoverDateIso) > 0) {
            continue;
          }
          final pastEntries = (meal['entries'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e));
          for (final entry in pastEntries) {
            addCarryover(mealType, entry, fallbackCarryoverDateIso);
          }
        }
        // Cadeia SP do fallback
        final fallbackChain =
            _carryoverByDate[fallbackCarryoverDateIso] ??
            const <String, List<Map<String, dynamic>>>{};
        fallbackChain.forEach((mealType, entries) {
          final suppressionDate = _suppressedMealTypeSince[mealType];
          if (suppressionDate != null &&
              suppressionDate.compareTo(fallbackCarryoverDateIso!) > 0) {
            return;
          }
          for (final entry in entries) {
            addCarryover(
              mealType,
              Map<String, dynamic>.from(entry),
              fallbackCarryoverDateIso!,
            );
          }
        });
      }

      // Remove mealTypes explicitamente suprimidos HOJE (via lixeira no dia atual)
      final suppressedCarryover =
          _suppressedCarryoverByDate[selectedDateIso] ?? const <String>{};
      if (suppressedCarryover.isNotEmpty) {
        carryoverByMealType.removeWhere(
          (mealType, _) => suppressedCarryover.contains(mealType),
        );
      }

      final quantityOverrides =
          _carryoverQuantityOverridesByDate[selectedDateIso] ??
          const <String, double>{};
      quantityOverrides.forEach((signature, quantity) {
        for (final entryGroup in carryoverByMealType.entries) {
          for (var i = 0; i < entryGroup.value.length; i++) {
            final entry = entryGroup.value[i];
            if (_entryIdentitySignature(entryGroup.key, entry) == signature) {
              entryGroup.value[i] = _entryWithQuantity(entry, quantity);
            }
          }
        }
      });

      final carryoverSnapshot = <String, List<Map<String, dynamic>>>{};
      carryoverByMealType.forEach((mealType, entries) {
        carryoverSnapshot[mealType] = entries
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      });

      final mealChoices = _resolveMealChoices(
        meals: meals,
        templates: savedMeals,
      );
      final validEntryIds = meals
          .expand((meal) => (meal['entries'] as List<dynamic>? ?? const []))
          .whereType<Map>()
          .map((entry) => _toInt(entry['id']))
          .where((id) => id > 0)
          .toSet();

      final excludedForDate = Set<int>.from(
        _excludedEntryIdsByDate[selectedDateIso] ?? const <int>{},
      )..removeWhere((id) => !validEntryIds.contains(id));

      setState(() {
        _foods = foods;
        _meals = meals;
        _savedMealTemplates = savedMeals;
        _carryoverByMealType = carryoverByMealType;
        _carryoverByDate[selectedDateIso] = carryoverSnapshot;
        _excludedEntryIds
          ..clear()
          ..addAll(excludedForDate);
        _excludedEntryIdsByDate[selectedDateIso] = Set<int>.from(
          excludedForDate,
        );
        _basalKcal = _toDouble(daily['basalKcal']);
        _targetKcal = _toDouble(daily['targetKcal']);
        _consumedKcal = _toDouble(totals['consumedKcal']);
        _remainingKcal = _toDouble(totals['remainingKcal']);
        _protein = _toDouble(totals['protein']);
        _carbs = _toDouble(totals['carbs']);
        _fat = _toDouble(totals['fat']);

        if (_selectedFoodId != null &&
            !_foods.any((f) => _toInt(f['id']) == _selectedFoodId)) {
          _selectedFoodId = null;
        }
        if (!mealChoices.contains(_selectedMeal)) {
          _selectedMeal = mealChoices.first;
        }
      });
      unawaited(_persistCarryoverState());
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFDC2626),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingDay = false;
        });
      }
    }
  }

  Future<void> _changeDay(int deltaDays) async {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: deltaDays));
      _showFoodSuggestions = false;
    });
    await _loadAll(keepUi: true);
  }

  Future<void> _jumpToToday() async {
    final now = DateTime.now();
    if (_isSameDate(_selectedDate, now)) return;
    setState(() {
      _selectedDate = DateTime(now.year, now.month, now.day);
      _showFoodSuggestions = false;
    });
    await _loadAll(keepUi: true);
  }

  Future<void> _addEntry() async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }

    if (_savingEntry) return;

    final selectedFood = _resolveFoodFromTypedText();
    if (selectedFood == null) {
      _showSnack('Digite um alimento válido para buscar.');
      return;
    }

    final qty = _tryParseNumber(_quantityCtrl.text);
    if (qty == null || qty <= 0) {
      _showSnack('Informe uma quantidade válida.');
      return;
    }

    final kcal100 = _toDouble(selectedFood['caloriesPer100g']);
    if (kcal100 <= 0) {
      _showSnack('Não foi possível obter as calorias desse alimento.');
      return;
    }

    setState(() => _savingEntry = true);
    try {
      final resolvedFoodId = await _ensureLocalFoodId(selectedFood);

      await AuthService.addDietEntry(
        userId: widget.userId,
        foodId: resolvedFoodId,
        mealType: _selectedMeal,
        quantityGrams: qty,
        dateIso: _toDateIso(_selectedDate),
        unit: _quantityUnit,
      );
      // Usuário adicionou item: remove supressão permanente do mealType
      _suppressedMealTypeSince.remove(_selectedMeal);
      await _loadAll(keepUi: true);
      if (!mounted) return;
      setState(() => _showFoodSuggestions = false);
      _showSnack(
        'Alimento adicionado com sucesso.',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFDC2626),
      );
    } finally {
      if (mounted) setState(() => _savingEntry = false);
    }
  }

  Future<void> _deleteEntry(int entryId) async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }

    try {
      await AuthService.deleteDietEntry(
        userId: widget.userId,
        entryId: entryId,
      );
      await _loadAll(keepUi: true);
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFDC2626),
      );
    }
  }

  Future<void> _showEditEntryQuantityDialog(Map<String, dynamic> entry) async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }

    final entryId = _toInt(entry['id']);
    final currentQty = _toDouble(entry['quantityGrams']);
    final foodName = (entry['foodName'] ?? 'Alimento').toString();
    final mealType = (entry['mealType'] ?? '').toString().trim();
    final entrySignature = _entryIdentitySignature(mealType, entry);

    String _fmt(double v) => v.toStringAsFixed(v == v.roundToDouble() ? 0 : 1);

    final qtyCtrl = TextEditingController(text: _fmt(currentQty));
    String scope = 'TODAY';
    final editServings = _extractServings(entry);
    final editUnitChoices = _buildUnitChoices(editServings);
    String selectedUnit = (entry['unit'] ?? 'g').toString();
    if (!editUnitChoices.contains(selectedUnit)) selectedUnit = 'g';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text('Editar $foodName'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Quantidade',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: editUnitChoices.contains(selectedUnit)
                          ? selectedUnit
                          : 'g',
                      underline: const SizedBox.shrink(),
                      borderRadius: BorderRadius.circular(8),
                      items: editUnitChoices
                          .map(
                            (u) => DropdownMenuItem(
                              value: u,
                              child: Text(u),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() => selectedUnit = v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'Os valores nutricionais serão calculados com base nos dados cadastrados para este alimento.',
                  style: TextStyle(fontSize: 11, color: Colors.black45),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Aplicar quantidade em:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ChoiceChip(
                      label: const Text('Apenas hoje'),
                      selected: scope == 'TODAY',
                      onSelected: (_) => setDialogState(() => scope = 'TODAY'),
                    ),
                    ChoiceChip(
                      label: const Text('Hoje e dias futuros'),
                      selected: scope == 'FUTURE',
                      onSelected: (_) => setDialogState(() => scope = 'FUTURE'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4DBA),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );

    qtyCtrl.dispose();

    if (confirmed != true) return;

    final qty = _tryParseNumber(qtyCtrl.text);
    if (qty == null || qty <= 0) {
      _showSnack('Informe uma quantidade válida.');
      return;
    }

    try {
      await AuthService.updateDietEntryQuantity(
        userId: widget.userId,
        entryId: entryId,
        quantityGrams: qty,
        scope: scope,
        unit: selectedUnit,
      );

      final selectedDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      if (scope == 'TODAY') {
        for (var i = 1; i <= 30; i++) {
          final futureDate = _toDateIso(selectedDate.add(Duration(days: i)));
          _carryoverQuantityOverridesByDate.putIfAbsent(
            futureDate,
            () => <String, double>{},
          )[entrySignature] = currentQty;
        }
      } else {
        for (final overrides in _carryoverQuantityOverridesByDate.values) {
          overrides.remove(entrySignature);
        }
        _carryoverQuantityOverridesByDate.removeWhere(
          (_, values) => values.isEmpty,
        );
      }
      await _persistCarryoverState();

      await _loadAll(keepUi: true);
      if (!mounted) return;
      _showSnack(
        scope == 'TODAY'
            ? 'Alimento atualizado para hoje.'
            : 'Alimento atualizado para hoje e dias futuros.',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFDC2626),
      );
    }
  }

  Future<void> _saveMealAsFavorite(
    String mealType,
    List<Map<String, dynamic>> entries,
  ) async {
    if (entries.isEmpty) {
      _showSnack('Adicione itens nessa refeição antes de salvar.');
      return;
    }

    final nameCtrl = TextEditingController(text: '$mealType - Favorito');

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 20,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                const Expanded(child: Text('Salvar Refeição como Favorita')),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx, false),
                ),
              ],
            ),
            content: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Esta refeição será nomeada e aparecerá automaticamente todos os dias a partir de hoje.',
                    style: TextStyle(color: Color(0xFF4B5563), fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nome do favorito',
                      hintText: 'Ex: Jantar leve',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Alimentos incluídos (${entries.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...entries.map((entry) {
                    final name = (entry['foodName'] ?? '-').toString();
                    final grams = _toDouble(
                      entry['quantityGrams'],
                    ).toStringAsFixed(0);
                    final kcal = _toDouble(
                      entry['calories'],
                    ).toStringAsFixed(0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $name - ${grams}g ($kcal kcal)'),
                    );
                  }),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF059669),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar Favorito'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) {
      nameCtrl.dispose();
      return;
    }

    final favoriteName = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (favoriteName.isEmpty) {
      _showSnack('Informe um nome para a refeição favorita.');
      return;
    }

    final normalizedFavoriteName = favoriteName.toLowerCase();
    Map<String, dynamic>? existingTemplate;
    for (final template in _savedMealTemplates) {
      final templateName = (template['name'] ?? template['mealType'] ?? '')
          .toString()
          .trim();
      if (templateName.toLowerCase() == normalizedFavoriteName) {
        existingTemplate = template;
        break;
      }
    }

    final targetMealType = favoriteName;
    var replacingExisting = false;
    var existingSavedMealId = 0;
    var existingMealType = '';
    if (existingTemplate != null) {
      final existingDisplayName =
          (existingTemplate['name'] ??
                  existingTemplate['mealType'] ??
                  'Refeição')
              .toString();
      existingSavedMealId = _toInt(existingTemplate['id']);
      existingMealType = (existingTemplate['mealType'] ?? mealType)
          .toString()
          .trim();

      if (!mounted) return;
      final replaceConfirmed =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Nome já existe'),
              content: Text(
                'Já existe uma refeição favorita com o nome "$existingDisplayName".\n\nDeseja substituir a refeição salva por esta nova?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B4DBA),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Substituir'),
                ),
              ],
            ),
          ) ??
          false;

      if (!replaceConfirmed) {
        return;
      }

      replacingExisting = true;
    }

    final templateItems = entries
        .map(
          (entry) => {
            'foodId': _toInt(entry['foodId']),
            'foodName': (entry['foodName'] ?? '').toString(),
            'quantityGrams': _toDouble(entry['quantityGrams']),
            'calories': _toDouble(entry['calories']),
            'protein': _toDouble(entry['protein']),
            'carbs': _toDouble(entry['carbs']),
            'fat': _toDouble(entry['fat']),
          },
        )
        .toList();

    try {
      await AuthService.saveDietSavedMeal(
        userId: widget.userId,
        name: favoriteName,
        mealType: targetMealType,
        items: templateItems,
      );

      if (replacingExisting &&
          existingSavedMealId > 0 &&
          existingMealType.toLowerCase() != targetMealType.toLowerCase()) {
        try {
          await AuthService.deleteDietSavedMeal(
            userId: widget.userId,
            savedMealId: existingSavedMealId,
          );
        } catch (_) {
          // Se falhar na limpeza do registro antigo, mantém o novo salvo.
        }
      }

      await _loadAll(keepUi: true);
      _showSnack(
        replacingExisting
            ? 'Refeição favorita substituída com sucesso.'
            : 'Refeição favorita salva com sucesso.',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFDC2626),
      );
    }
  }

  Future<void> _applySavedMealTemplate(Map<String, dynamic> template) async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }

    final savedMealId = _toInt(template['id']);
    if (savedMealId <= 0) {
      _showSnack('Refeição salva inválida.');
      return;
    }

    final mealChoices = _mealChoices;
    final templateName = (template['name'] ?? template['mealType'] ?? '')
        .toString()
        .trim();

    String selectedMealType = _applyAsFavoriteNameOption;

    final applyConfirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text('Adicionar favorito no dia'),
              content: SizedBox(
                width: double.infinity,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Favorito: ${(template['name'] ?? template['mealType'] ?? 'Sem nome').toString()}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: selectedMealType,
                      decoration: const InputDecoration(
                        labelText: 'Em qual refeição deseja adicionar?',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: _applyAsFavoriteNameOption,
                          child: Text(
                            'Adicionar no dia atual (nome do favorito)',
                          ),
                        ),
                        ...mealChoices.map(
                          (m) => DropdownMenuItem(value: m, child: Text(m)),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => selectedMealType = value);
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Adicionar'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (!applyConfirmed) return;

    final items = (template['items'] as List<dynamic>? ?? const []);
    if (items.isEmpty) {
      _showSnack('Template de refeição inválido.');
      return;
    }

    setState(() => _savingEntry = true);
    try {
      final targetMealType = selectedMealType == _applyAsFavoriteNameOption
          ? templateName
          : selectedMealType;
      if (targetMealType.trim().isEmpty) {
        throw Exception('Nome da refeição favorita inválido.');
      }

      await AuthService.applyDietSavedMeal(
        userId: widget.userId,
        savedMealId: savedMealId,
        targetMealType: targetMealType,
        dateIso: _toDateIso(_selectedDate),
      );

      // Usuário aplicou favorito: remove supressão permanente do mealType de destino
      _suppressedMealTypeSince.remove(targetMealType);
      await _loadAll(keepUi: true);
      _showSnack(
        'Favorito adicionado em $targetMealType.',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFDC2626),
      );
    } finally {
      if (mounted) setState(() => _savingEntry = false);
    }
  }

  Future<void> _deleteSavedMealTemplate(Map<String, dynamic> template) async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }

    final savedMealId = _toInt(template['id']);
    if (savedMealId <= 0) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Excluir refeição favorita'),
            content: Text(
              'Deseja excluir "${(template['name'] ?? template['mealType'] ?? 'Refeição').toString()}"?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      final savedMealType = (template['mealType'] ?? '').toString().trim();
      final defaultMealType = _defaultMealTypeForFavorite(savedMealType);
      if (defaultMealType != null) {
        await AuthService.renameDietEntriesMealType(
          userId: widget.userId,
          oldMealType: savedMealType,
          newMealType: defaultMealType,
          dateIso: _toDateIso(_selectedDate),
        );
      }

      await AuthService.deleteDietSavedMeal(
        userId: widget.userId,
        savedMealId: savedMealId,
      );

      await _loadAll(keepUi: true);
      _showSnack('Refeição favorita excluída.', color: const Color(0xFF16A34A));
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFDC2626),
      );
    }
  }

  String? _defaultMealTypeForFavorite(String mealType) {
    for (final defaultMealType in _mealTypes) {
      if (mealType.toLowerCase() ==
          '$defaultMealType - favorito'.toLowerCase()) {
        return defaultMealType;
      }
    }
    return null;
  }

  Future<void> _unlockCarryoverEntry(
    String mealType,
    Map<String, dynamic> entry,
  ) async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }
    if (_savingEntry) return;

    setState(() => _savingEntry = true);
    try {
      var foodId = _toInt(entry['foodId']);
      final quantity = _toDouble(entry['quantityGrams']);
      if (quantity <= 0) {
        throw Exception('Quantidade inválida para adicionar o alimento.');
      }

      if (foodId <= 0 || !_foods.any((f) => _toInt(f['id']) == foodId)) {
        final name = (entry['foodName'] ?? '').toString().trim();
        if (name.isEmpty) {
          throw Exception('Alimento inválido para desbloquear.');
        }

        final existing = _foods.cast<Map<String, dynamic>?>().firstWhere(
          (f) =>
              (f?['name'] ?? '').toString().trim().toLowerCase() ==
              name.toLowerCase(),
          orElse: () => null,
        );

        if (existing != null) {
          foodId = _toInt(existing['id']);
        } else {
          final factor = 100 / quantity;
          final created = await AuthService.createDietFood(
            userId: widget.userId,
            name: name,
            caloriesPer100g: _toDouble(entry['calories']) * factor,
            proteinPer100g: _toDouble(entry['protein']) * factor,
            carbsPer100g: _toDouble(entry['carbs']) * factor,
            fatPer100g: _toDouble(entry['fat']) * factor,
            custom: false,
          );
          foodId = _toInt(created['id']);
        }
      }

      await AuthService.addDietEntry(
        userId: widget.userId,
        foodId: foodId,
        mealType: mealType,
        quantityGrams: quantity,
        dateIso: _toDateIso(_selectedDate),
      );

      // Usuário ativou este mealType: remove supressão permanente
      _suppressedMealTypeSince.remove(mealType);
      await _persistLocalDietState();

      await _loadAll(keepUi: true);
      _showSnack(
        'Alimento desbloqueado e adicionado.',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFDC2626),
      );
    } finally {
      if (mounted) setState(() => _savingEntry = false);
    }
  }

  Future<void> _deleteMealOfDay(
    String mealType,
    List<Map<String, dynamic>> entries,
    List<Map<String, dynamic>> carryoverEntries,
  ) async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }
    if (_savingEntry) return;

    final hasEntries = entries.isNotEmpty;
    final hasCarryover = carryoverEntries.isNotEmpty;
    if (!hasEntries && !hasCarryover) return;

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Excluir refeição do dia'),
            content: Text(
              'Deseja excluir "$mealType" deste dia?\n\nItens do dia serão removidos e os itens herdados ficarão ocultos hoje.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    setState(() => _savingEntry = true);
    try {
      for (final entry in entries) {
        final entryId = _toInt(entry['id']);
        if (entryId <= 0) continue;
        await AuthService.deleteDietEntry(
          userId: widget.userId,
          entryId: entryId,
        );
      }

      final dateIso = _toDateIso(_selectedDate);
      _suppressedCarryoverByDate
          .putIfAbsent(dateIso, () => <String>{})
          .add(mealType);
      _carryoverByDate[dateIso]?.remove(mealType);
      _carryoverByMealType.remove(mealType);
      // Suprime permanentemente: este mealType não deve reaparecer em dias futuros
      // até que o usuário adicione novamente um item a ele
      _suppressedMealTypeSince[mealType] = dateIso;
      await _persistLocalDietState();

      await _loadAll(keepUi: true);
      _showSnack(
        'Refeição "$mealType" excluída do dia.',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFDC2626),
      );
    } finally {
      if (mounted) setState(() => _savingEntry = false);
    }
  }

  Future<void> _showFoodDialog({Map<String, dynamic>? existing}) async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }

    final nameCtrl = TextEditingController(
      text: (existing?['name'] ?? '').toString(),
    );
    final kcalTotalCtrl = TextEditingController(
      text: existing == null
          ? ''
          : (_toDouble(existing['caloriesPer100g']) / 100).toStringAsFixed(2),
    );
    final proteinTotalCtrl = TextEditingController(
      text: existing == null
          ? ''
          : (_toDouble(existing['proteinPer100g']) / 100).toStringAsFixed(2),
    );
    final carbsTotalCtrl = TextEditingController(
      text: existing == null
          ? ''
          : (_toDouble(existing['carbsPer100g']) / 100).toStringAsFixed(2),
    );
    final fatTotalCtrl = TextEditingController(
      text: existing == null
          ? ''
          : (_toDouble(existing['fatPer100g']) / 100).toStringAsFixed(2),
    );

    final bool favorite = existing?['favorite'] == true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          existing == null ? 'Cadastrar Novo Alimento' : 'Editar Alimento',
        ),
        content: SizedBox(
          width: double.infinity,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Adicione um alimento que não está na lista. Pesquise a informação nutricional e informe quanto existe em 1 g do alimento.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Alimento',
                    hintText: 'Ex: Arroz',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: kcalTotalCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Calorias em 1 g',
                    hintText: 'Ex: 1,30',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pesquise quantas calorias existem em 1 g desse alimento.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: proteinTotalCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Proteína em 1 g',
                          hintText: 'Ex: 0,03',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: carbsTotalCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Carboidratos em 1 g',
                          hintText: 'Ex: 0,28',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: fatTotalCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Gordura em 1 g',
                          hintText: 'Ex: 0,01',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Os valores serão convertidos automaticamente quando você colocar a quantidade de gramas.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B4DBA),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = nameCtrl.text.trim();
              final kcalPerGram = _tryParseNumber(kcalTotalCtrl.text);
              final proteinPerGram = _tryParseNumber(proteinTotalCtrl.text);
              final carbsPerGram = _tryParseNumber(carbsTotalCtrl.text);
              final fatPerGram = _tryParseNumber(fatTotalCtrl.text);

              if (name.isEmpty ||
                  kcalPerGram == null ||
                  proteinPerGram == null ||
                  carbsPerGram == null ||
                  fatPerGram == null ||
                  kcalPerGram < 0 ||
                  proteinPerGram < 0 ||
                  carbsPerGram < 0 ||
                  fatPerGram < 0) {
                _showSnack('Preencha todos os campos corretamente.');
                return;
              }

              try {
                if (existing == null) {
                  await AuthService.createDietFood(
                    userId: widget.userId,
                    name: name,
                    caloriesPer100g: kcalPerGram * 100,
                    proteinPer100g: proteinPerGram * 100,
                    carbsPer100g: carbsPerGram * 100,
                    fatPer100g: fatPerGram * 100,
                    favorite: favorite,
                  );
                } else {
                  await AuthService.updateDietFood(
                    userId: widget.userId,
                    foodId: _toInt(existing['id']),
                    name: name,
                    caloriesPer100g: kcalPerGram * 100,
                    proteinPer100g: proteinPerGram * 100,
                    carbsPer100g: carbsPerGram * 100,
                    fatPer100g: fatPerGram * 100,
                    favorite: favorite,
                  );
                }

                if (!ctx.mounted || !mounted) return;
                Navigator.pop(ctx);
                await _loadAll(keepUi: true);
              } catch (e) {
                _showSnack(
                  e.toString().replaceFirst('Exception: ', ''),
                  color: const Color(0xFFDC2626),
                );
              }
            },
            child: Text(existing == null ? 'Cadastrar' : 'Atualizar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showManageFoodsDialog() async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }

    final searchCtrl = TextEditingController();
    var filtered = _foods
        .where((food) => food['custom'] != false)
        .map((food) => Map<String, dynamic>.from(food))
        .toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void applyFilter(String query) {
            final q = query.trim().toLowerCase();
            setDialogState(() {
              filtered = _foods.where((f) {
                if (f['custom'] == false) return false;
                final name = (f['name'] ?? '').toString().toLowerCase();
                return q.isEmpty || name.contains(q);
              }).toList();
            });
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 14,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: const Text('Gerenciar Alimentos Personalizados'),
            content: SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edite os alimentos personalizados que você cadastrou.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl,
                    onChanged: applyFilter,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded),
                      hintText: 'Buscar alimento...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.only(top: 24),
                              child: Text('Nenhum alimento encontrado.'),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final food = filtered[i];
                              final kcal100 = _toDouble(
                                food['caloriesPer100g'],
                              );
                              final kcalGram = kcal100 / 100;

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FBFF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFDCE6F5),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            (food['name'] ?? '').toString(),
                                            style: const TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${kcalGram.toStringAsFixed(2)} cal/g • ${kcal100.toStringAsFixed(2)} cal/100g',
                                            style: const TextStyle(
                                              color: Color(0xFF64748B),
                                              fontSize: 16,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.edit_rounded),
                                      onPressed: () async {
                                        await _showFoodDialog(existing: food);
                                        if (!mounted) return;
                                        applyFilter(searchCtrl.text);
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Fechar'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showTmbCalculatorDialog() async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }

    // Etapa 1 — dados biológicos: calcula TMB + Gasto Energético Total (GET).
    final step1 = await _showTmbStep1Dialog();
    if (step1 == null || !mounted) return;

    // Etapa 2 — objetivo: aplica défice/superávite sobre o GET.
    final selectedGoal = await _showTmbStep2Dialog();
    if (selectedGoal == null || !mounted) return;

    final dailyTarget =
        step1.totalEnergyExpenditure + kcalAdjustmentForObjective(selectedGoal);

    try {
      await AuthService.saveDietGoals(
        userId: widget.userId,
        basalKcal: step1.basalKcal,
        targetKcal: dailyTarget,
      );
      if (!mounted) return;
      await _loadAll(keepUi: true);
      _showSnack(
        'TMB calculado e salvo com sucesso.',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFDC2626),
      );
    }
  }

  Future<_TmbStep1Result?> _showTmbStep1Dialog() async {
    final weightCtrl = TextEditingController();
    final heightCtrl = TextEditingController();
    final ageCtrl = TextEditingController();
    final heightMask = MaskTextInputFormatter(
      mask: '0,00',
      filter: {'0': RegExp(r'[0-9]')},
    );

    String? selectedSex;
    String? selectedActivity;

    const activityFactors = <String, double>{
      'Sedentário': 1.2,
      'Levemente ativo': 1.375,
      'Moderadamente ativo': 1.55,
      'Muito ativo': 1.725,
      'Extremamente ativo': 1.9,
    };

    return await showDialog<_TmbStep1Result>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Calcular TMB'),
          content: SizedBox(
            width: double.infinity,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Preencha os dados abaixo para calcular seu TMB:',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: weightCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Peso (kg)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: heightCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [heightMask],
                          decoration: const InputDecoration(
                            labelText: 'Altura (m)',
                            hintText: 'Ex: 1,75',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: ageCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Idade',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedSex,
                    decoration: const InputDecoration(
                      labelText: 'Sexo',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'M', child: Text('Masculino')),
                      DropdownMenuItem(value: 'F', child: Text('Feminino')),
                    ],
                    onChanged: (v) => setDialogState(() => selectedSex = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedActivity,
                    decoration: const InputDecoration(
                      labelText: 'Nível de Atividade',
                      border: OutlineInputBorder(),
                    ),
                    items: activityFactors.keys
                        .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                        .toList(),
                    onChanged: (v) =>
                        setDialogState(() => selectedActivity = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4DBA),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final weight = _tryParseNumber(weightCtrl.text);
                final heightInMeters = _tryParseNumber(heightCtrl.text);
                final height = heightInMeters == null
                    ? null
                    : heightInMeters * 100;
                final age = _tryParseNumber(ageCtrl.text);
                if (weight == null ||
                    height == null ||
                    height <= 0 ||
                    age == null ||
                    selectedSex == null ||
                    selectedActivity == null) {
                  _showSnack('Preencha todos os campos para calcular o TMB.');
                  return;
                }

                // 1) Taxa Metabólica Basal — Fórmula de Mifflin-St Jeor.
                final tmbBase = (10 * weight) + (6.25 * height) - (5 * age);
                final tmb = selectedSex == 'M' ? tmbBase + 5 : tmbBase - 161;

                // 2) Gasto Energético Total (GET) = TMB × fator de atividade.
                final activityFactor = activityFactors[selectedActivity] ?? 1.2;
                final totalEnergyExpenditure = tmb * activityFactor;

                Navigator.pop(
                  ctx,
                  _TmbStep1Result(tmb, totalEnergyExpenditure),
                );
              },
              child: const Text('Avançar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _showTmbStep2Dialog() async {
    String? selectedGoal;

    return await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text('Definir Objetivo'),
          content: SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Para ajudar a calcular a sua meta diária, nos informe o seu objetivo:',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedGoal,
                  decoration: const InputDecoration(
                    labelText: 'Objetivo',
                    border: OutlineInputBorder(),
                  ),
                  items: kObjectiveOptions
                      .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedGoal = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Voltar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4DBA),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (selectedGoal == null || selectedGoal!.trim().isEmpty) {
                  _showSnack('Selecione seu objetivo.');
                  return;
                }
                Navigator.pop(ctx, selectedGoal);
              },
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTargetDailyDialog() async {
    if (_isPastDay) {
      _showSnack(_onlyTodayEditableMessage);
      return;
    }

    final targetCtrl = TextEditingController(
      text: _targetKcal > 0 ? _targetKcal.toStringAsFixed(0) : '',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('Meta de Calorias Diárias'),
        content: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: targetCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: '2000',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Insira sua meta diária de calorias (ex: 2000 kcal)',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0B4DBA),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final target = _tryParseNumber(targetCtrl.text);
              if (target == null || target <= 0) {
                _showSnack('Informe uma meta diária válida.');
                return;
              }

              try {
                await AuthService.saveDietGoals(
                  userId: widget.userId,
                  basalKcal: _basalKcal,
                  targetKcal: target,
                );
                if (!ctx.mounted || !mounted) return;
                Navigator.pop(ctx);
                await _loadAll(keepUi: true);
              } catch (e) {
                _showSnack(
                  e.toString().replaceFirst('Exception: ', ''),
                  color: const Color(0xFFDC2626),
                );
              }
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _onFoodSearchChanged(String value) {
    _foodSearchDebounce?.cancel();

    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _foodSuggestions = [];
        _showFoodSuggestions = false;
        _searchingFoods = false;
        _selectedFoodId = null;
        _selectedExternalFood = null;
      });
      return;
    }

    final normalized = query.toLowerCase();
    final localMatches = _foods
        .where(
          (food) => (food['name'] ?? '').toString().toLowerCase().contains(
            normalized,
          ),
        )
        .take(6)
        .map((e) {
          final row = Map<String, dynamic>.from(e);
          row.putIfAbsent('source', () => 'local');
          return row;
        })
        .toList();

    setState(() {
      _foodSuggestions = localMatches;
      _showFoodSuggestions = true;
      _searchingFoods = true;
      _selectedFoodId = null;
      _selectedExternalFood = null;
    });

    _foodSearchDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _loadFoodSuggestions(query),
    );
  }

  Future<void> _loadFoodSuggestions(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.length < 2) return;

    final requestSeq = ++_searchSeq;
    final localMatches = _foods
        .where(
          (food) => (food['name'] ?? '').toString().toLowerCase().contains(
            normalized,
          ),
        )
        .take(6)
        .map((e) {
          final row = Map<String, dynamic>.from(e);
          row.putIfAbsent('source', () => 'local');
          return row;
        })
        .toList();

    try {
      final remote = await AuthService.searchAlimentos(query: query);

      if (!mounted ||
          requestSeq != _searchSeq ||
          _foodSearchCtrl.text.trim().toLowerCase() != normalized) {
        return;
      }

      final merged = <Map<String, dynamic>>[];
      final names = <String>{};

      for (final food in localMatches) {
        final name = (food['name'] ?? '').toString().trim().toLowerCase();
        if (name.isEmpty || names.contains(name)) continue;
        names.add(name);
        merged.add(food);
      }

      for (final food in remote) {
        final row = Map<String, dynamic>.from(food);
        row.putIfAbsent('source', () => 'fatsecret');
        final name = (row['name'] ?? '').toString().trim().toLowerCase();
        if (name.isEmpty || names.contains(name)) continue;
        names.add(name);
        merged.add(row);
      }

      setState(() {
        _foodSuggestions = merged;
        _showFoodSuggestions = true;
        _searchingFoods = false;
      });
    } catch (_) {
      if (!mounted ||
          requestSeq != _searchSeq ||
          _foodSearchCtrl.text.trim().toLowerCase() != normalized) {
        return;
      }

      setState(() {
        _foodSuggestions = localMatches;
        _showFoodSuggestions = true;
        _searchingFoods = false;
      });
    }
  }

  void _selectFood(Map<String, dynamic> food) {
    final selectedId = _toInt(food['id']);
    final source = (food['source'] ?? '').toString().toLowerCase();
    final isLocal = selectedId > 0 && source == 'local';
    final servings = _extractServings(food);

    setState(() {
      _selectedFoodId = isLocal ? selectedId : null;
      _selectedExternalFood = isLocal ? null : Map<String, dynamic>.from(food);
      _selectedServings = servings;
      _foodSearchCtrl.text = (food['name'] ?? '').toString();
      _showFoodSuggestions = false;
      _foodSuggestions = [];
      _searchingFoods = false;
      // Ao trocar de alimento, evita manter uma porção inválida do alimento
      // anterior selecionada.
      if (!_quantityUnitChoices.contains(_quantityUnit)) {
        _quantityUnit = 'g';
      }
    });
  }

  String _foodSourceLabel(dynamic rawSource) {
    final source = rawSource?.toString().trim();
    if (source == null || source.isEmpty) return 'Fonte desconhecida';

    switch (source.toLowerCase()) {
      case 'local':
        return 'Já cadastrado';
      case 'fatsecret':
        return 'FatSecret';
      case 'openfoodfacts':
      case 'open food facts':
        return 'Open Food Facts';
      case 'edamam':
        return 'Edamam';
      default:
        return source[0].toUpperCase() + source.substring(1);
    }
  }

  Map<String, dynamic>? _resolveFoodFromTypedText() {
    final query = _foodSearchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return null;

    if (_selectedFoodId != null) {
      final selected = _foods.cast<Map<String, dynamic>?>().firstWhere(
        (f) => _toInt(f?['id']) == _selectedFoodId,
        orElse: () => null,
      );
      if (selected != null) {
        final row = Map<String, dynamic>.from(selected);
        row.putIfAbsent('source', () => 'local');
        return row;
      }
    }

    if (_selectedExternalFood != null) {
      final selectedName = (_selectedExternalFood!['name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (selectedName == query) {
        return Map<String, dynamic>.from(_selectedExternalFood!);
      }
    }

    final exactLocal = _foods.cast<Map<String, dynamic>?>().firstWhere(
      (f) => (f?['name'] ?? '').toString().trim().toLowerCase() == query,
      orElse: () => null,
    );
    if (exactLocal != null) {
      final row = Map<String, dynamic>.from(exactLocal);
      row.putIfAbsent('source', () => 'local');
      return row;
    }

    final exactSuggestion = _foodSuggestions
        .cast<Map<String, dynamic>?>()
        .firstWhere(
          (f) => (f?['name'] ?? '').toString().trim().toLowerCase() == query,
          orElse: () => null,
        );
    if (exactSuggestion == null) return null;
    return Map<String, dynamic>.from(exactSuggestion);
  }

  Future<int> _ensureLocalFoodId(Map<String, dynamic> food) async {
    final name = (food['name'] ?? '').toString().trim();
    if (name.isEmpty) {
      throw Exception('Nome do alimento inválido.');
    }

    final localExisting = _foods.cast<Map<String, dynamic>?>().firstWhere(
      (f) =>
          (f?['name'] ?? '').toString().trim().toLowerCase() ==
          name.toLowerCase(),
      orElse: () => null,
    );
    if (localExisting != null) {
      return _toInt(localExisting['id']);
    }

    final caloriesPer100g = _toDouble(food['caloriesPer100g']);
    final proteinPer100g = _toDouble(food['proteinPer100g']);
    final carbsPer100g = _toDouble(food['carbsPer100g']);
    final fatPer100g = _toDouble(food['fatPer100g']);
    final servingDescription = (food['servingDescription'] ?? '').toString();
    final servingAmountGrams = _toDoubleOrNull(food['servingAmountGrams']);
    final servingUnit = (food['servingUnit'] ?? '').toString();
    final servings = _extractServings(food);

    if (caloriesPer100g <= 0) {
      throw Exception('Calorias inválidas para cadastrar esse alimento.');
    }

    try {
      final created = await AuthService.createDietFood(
        userId: widget.userId,
        name: name,
        caloriesPer100g: caloriesPer100g,
        proteinPer100g: proteinPer100g,
        carbsPer100g: carbsPer100g,
        fatPer100g: fatPer100g,
        custom: false,
        servingDescription: servingDescription.isEmpty ? null : servingDescription,
        servingAmountGrams: servingAmountGrams,
        servingUnit: servingUnit.isEmpty ? null : servingUnit,
        servings: servings.isEmpty ? null : servings,
      );
      return _toInt(created['id']);
    } catch (e) {
      final message = e
          .toString()
          .replaceFirst('Exception: ', '')
          .toLowerCase();
      if (!message.contains('já cadastrou') &&
          !message.contains('ja cadastrou') &&
          !message.contains('já existe alimento') &&
          !message.contains('ja existe alimento')) {
        rethrow;
      }

      await _loadAll(keepUi: true);
      final found = _foods.cast<Map<String, dynamic>?>().firstWhere(
        (f) =>
            (f?['name'] ?? '').toString().trim().toLowerCase() ==
            name.toLowerCase(),
        orElse: () => null,
      );
      if (found == null) {
        throw Exception('Não foi possível localizar o alimento já cadastrado.');
      }
      return _toInt(found['id']);
    }
  }

  bool _isEntryIncluded(Map<String, dynamic> entry) {
    final entryId = _toInt(entry['id']);
    if (entryId <= 0) return true;
    return !_excludedEntryIds.contains(entryId);
  }

  void _toggleEntryIncluded(Map<String, dynamic> entry) {
    final entryId = _toInt(entry['id']);
    if (entryId <= 0) return;
    setState(() {
      if (_excludedEntryIds.contains(entryId)) {
        _excludedEntryIds.remove(entryId);
      } else {
        _excludedEntryIds.add(entryId);
      }

      final dateIso = _toDateIso(_selectedDate);
      _excludedEntryIdsByDate[dateIso] = Set<int>.from(_excludedEntryIds);
    });
    unawaited(_persistLocalDietState());
  }

  List<Map<String, dynamic>> _includedEntries(
    List<Map<String, dynamic>> entries,
  ) {
    return entries.where(_isEntryIncluded).toList();
  }

  Map<String, double> _includedTotals() {
    double consumed = 0;
    double protein = 0;
    double carbs = 0;
    double fat = 0;

    for (final meal in _meals) {
      final entries = (meal['entries'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e));

      for (final entry in entries) {
        if (!_isEntryIncluded(entry)) continue;
        consumed += _toDouble(entry['calories']);
        protein += _toDouble(entry['protein']);
        carbs += _toDouble(entry['carbs']);
        fat += _toDouble(entry['fat']);
      }
    }

    return {
      'consumedKcal': consumed,
      'protein': protein,
      'carbs': carbs,
      'fat': fat,
      'remainingKcal': _targetKcal - consumed,
    };
  }

  String _entryIdentitySignature(String mealType, Map<String, dynamic> entry) {
    final entryId = _toInt(entry['id']);
    if (entryId > 0) {
      return '${_entrySignature(mealType, entry)}|entry:$entryId';
    }
    return _entrySignature(mealType, entry);
  }

  /// Opções do dropdown de unidade: "g"/"ml" + as descrições das porções
  /// reais retornadas pela FatSecret para o alimento selecionado.
  List<String> get _quantityUnitChoices => _buildUnitChoices(_selectedServings);

  List<String> _buildUnitChoices(List<Map<String, dynamic>> servings) {
    final units = <String>[..._baseQuantityUnits];
    for (final s in servings) {
      final raw = (s['description'] ?? '').toString().trim();
      final label = _translateServingDescription(raw).trim();
      if (label.isNotEmpty && !units.contains(label)) {
        units.add(label);
      }
    }
    return units;
  }

  Map<String, dynamic>? _servingFromFoodByLabel(
    Map<String, dynamic> food,
    String label,
  ) {
    final normalized = _translateServingDescription(label).trim().toLowerCase();
    for (final s in _extractServings(food)) {
      final desc = _translateServingDescription(
        (s['description'] ?? '').toString(),
      ).trim().toLowerCase();
      if (desc == normalized) return s;
    }
    return null;
  }

  List<Map<String, dynamic>> _extractServings(Map<String, dynamic> food) {
    final raw = food['servings'];
    if (raw is! List) return const [];
    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        result.add(item);
      } else if (item is Map) {
        result.add(Map<String, dynamic>.from(item));
      }
    }
    return result;
  }

  String _servingMacroKey(String key) {
    switch (key) {
      case 'caloriesPer100g':
        return 'calories';
      case 'proteinPer100g':
        return 'protein';
      case 'carbsPer100g':
        return 'carbs';
      case 'fatPer100g':
        return 'fat';
      default:
        return key;
    }
  }

  /// Converte a quantidade informada (na unidade selecionada) para gramas.
  double _gramsForQuantity(
    Map<String, dynamic> food,
    double quantity,
    String unit,
  ) {
    final normalized = unit.trim().toLowerCase();
    if (normalized == 'g' || normalized == 'ml') {
      return quantity;
    }

    // Porção específica: usa o peso em gramas daquela porção (ex.: 1 unidade
    // de ovo = 50 g), em vez de assumir 1 g.
    final serving = _servingFromFoodByLabel(food, unit);
    final servingGrams = serving != null
        ? _toDoubleOrNull(serving['amountGrams'])
        : _toDoubleOrNull(food['servingAmountGrams']);
    if (servingGrams != null && servingGrams > 0) {
      return quantity * servingGrams;
    }

    // Sem dados de porção, mantém o valor informado (fallback seguro).
    return quantity;
  }

  /// Recalcula um macro conforme o texto e o dropdown mudam.
  ///
  /// - Cenário A ("g"/"ml"): (macros de 100g / 100) * quantidade digitada.
  /// - Cenário B (porção específica): macros daquela porção * quantidade; se a
  ///   porção não tiver macros prontos, converte pelo peso em gramas da unidade.
  double _macroForQty(String key) {
    final selected = _resolveFoodFromTypedText();
    if (selected == null) return 0;
    final qty = _tryParseNumber(_quantityCtrl.text) ?? 0;

    final unit = _quantityUnit.trim().toLowerCase();
    if (unit == 'g' || unit == 'ml') {
      return (_toDouble(selected[key]) / 100) * qty;
    }

    final serving = _servingFromFoodByLabel(selected, _quantityUnit);
    if (serving != null) {
      final servingMacro = _toDoubleOrNull(serving[_servingMacroKey(key)]);
      if (servingMacro != null && servingMacro > 0) {
        return servingMacro * qty;
      }
      final amountGrams = _toDoubleOrNull(serving['amountGrams']);
      if (amountGrams != null && amountGrams > 0) {
        return (_toDouble(selected[key]) / 100) * (qty * amountGrams);
      }
    }

    final grams = _gramsForQuantity(selected, qty, _quantityUnit);
    return (_toDouble(selected[key]) * grams) / 100;
  }

  double get _previewCalories => _macroForQty('caloriesPer100g');
  double get _previewProtein => _macroForQty('proteinPer100g');
  double get _previewCarbs => _macroForQty('carbsPer100g');
  double get _previewFat => _macroForQty('fatPer100g');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FB),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: RefreshIndicator(
                onRefresh: () => _loadAll(keepUi: true),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
                  children: [
                    _buildHeaderActions(),
                    const SizedBox(height: 16),
                    _buildDaySelector(),
                    if (_isPastDay) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFDBA74)),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.lock_clock_rounded,
                              color: Color(0xFFEA580C),
                            ),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Apenas o dia atual pode ser editado. Datas passadas e futuras ficam em modo somente leitura.',
                                style: TextStyle(
                                  color: Color(0xFF9A3412),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    _buildMetrics(),
                    const SizedBox(height: 16),
                    _buildFavoritesCard(),
                    const SizedBox(height: 14),
                    _buildAddMealCard(),
                    const SizedBox(height: 16),
                    ..._buildMealSections(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeaderActions() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFDCE6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 980;

              final title = RichText(
                text: const TextSpan(
                  children: [
                    TextSpan(
                      text: 'Controle de ',
                      style: TextStyle(
                        color: Color(0xFF0B4DBA),
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                    TextSpan(
                      text: 'Dieta',
                      style: TextStyle(
                        color: Color(0xFF1D4ED8),
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        height: 1.05,
                      ),
                    ),
                  ],
                ),
              );

              final actions = Wrap(
                spacing: isNarrow ? 6 : 8,
                runSpacing: isNarrow ? 6 : 8,
                children: [
                  if (!isNarrow)
                    OutlinedButton.icon(
                      onPressed: _onGlobalRefresh,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: const Color(0xFF0B4DBA),
                        side: const BorderSide(color: Color(0xFF0B4DBA)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                        ),
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? 10 : 14,
                          vertical: isNarrow ? 9 : 12,
                        ),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('Atualizar'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _isPastDay ? null : _showFoodDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0B4DBA),
                      side: const BorderSide(color: Color(0xFFBFD3F5)),
                      backgroundColor: const Color(0xFFF8FBFF),
                      padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? 10 : 14,
                        vertical: isNarrow ? 9 : 12,
                      ),
                    ),
                    icon: const Icon(
                      Icons.add_circle_outline_rounded,
                      size: 17,
                    ),
                    label: const Text('Cadastrar Manualmente'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isPastDay ? null : _showManageFoodsDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0xFFD5DEEE)),
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? 10 : 14,
                        vertical: isNarrow ? 9 : 12,
                      ),
                    ),
                    icon: const Icon(Icons.settings_rounded, size: 17),
                    label: const Text('Gerenciar Alimentos'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showMetricCoachTips
                        ? _hideCoachTips
                        : _showCoachTips,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0B4DBA),
                      side: const BorderSide(color: Color(0xFFBFD3F5)),
                      backgroundColor: const Color(0xFFF8FBFF),
                      padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? 10 : 14,
                        vertical: isNarrow ? 9 : 12,
                      ),
                    ),
                    icon: Icon(
                      _showMetricCoachTips
                          ? Icons.visibility_off_rounded
                          : Icons.wb_cloudy_rounded,
                      size: 17,
                    ),
                    label: Text(
                      _showMetricCoachTips
                          ? 'Ocultar dicas'
                          : 'Ver dicas novamente',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => showLogoutConfirmationDialog(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0xFFD5DEEE)),
                      backgroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: isNarrow ? 10 : 14,
                        vertical: isNarrow ? 9 : 12,
                      ),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: const Text('Sair'),
                  ),
                ],
              );

              final mobileMenu = PopupMenuButton<String>(
                tooltip: 'Mais opções',
                icon: const Icon(Icons.menu_rounded),
                onSelected: (value) {
                  switch (value) {
                    case 'manual':
                      if (!_isPastDay) _showFoodDialog();
                      break;
                    case 'foods':
                      if (!_isPastDay) _showManageFoodsDialog();
                      break;
                    case 'tips':
                      _showMetricCoachTips
                          ? _hideCoachTips()
                          : _showCoachTips();
                      break;
                    case 'logout':
                      showLogoutConfirmationDialog(context);
                      break;
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'manual',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.add_circle_outline_rounded),
                      title: Text('Cadastrar Manualmente'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'foods',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.settings_rounded),
                      title: Text('Gerenciar Alimentos'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'tips',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        _showMetricCoachTips
                            ? Icons.visibility_off_rounded
                            : Icons.wb_cloudy_rounded,
                      ),
                      title: Text(
                        _showMetricCoachTips ? 'Ocultar dicas' : 'Ver dicas',
                      ),
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'logout',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.logout_rounded),
                      title: Text('Sair'),
                    ),
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: title),
                        mobileMenu,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  actions,
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _sectionActionButton(
                  icon: Icons.person_rounded,
                  label: 'Meu perfil',
                  isActive: false,
                  onTap: () => Navigator.pop(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _sectionActionButton(
                  icon: Icons.restaurant_menu_rounded,
                  label: 'Controle de dieta',
                  isActive: true,
                  onTap: () {},
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
        ],
      ),
    );
  }

  Widget _sectionActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: isActive ? Colors.white : const Color(0xFF0B4DBA),
        backgroundColor: isActive
            ? const Color(0xFF1D4ED8)
            : const Color(0xFFF8FBFF),
        side: BorderSide(
          color: isActive ? const Color(0xFF1D4ED8) : const Color(0xFFBFD3F5),
        ),
        minimumSize: Size.fromHeight(isNarrow ? 44 : 0),
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 8 : 14,
          vertical: isNarrow ? 9 : 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: TextStyle(
          fontSize: isNarrow ? 12.5 : 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDaySelector() {
    final isToday = _isSameDate(_selectedDate, DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFDCE6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: [
          if (!isToday) ...[
            Align(
              alignment: Alignment.center,
              child: OutlinedButton.icon(
                onPressed: _loadingDay ? null : _jumpToToday,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0B4DBA),
                  side: const BorderSide(color: Color(0xFFBFD3F5)),
                  backgroundColor: const Color(0xFFF8FBFF),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                ),
                icon: const Icon(Icons.today_rounded, size: 18),
                label: const Text('Voltar para hoje'),
              ),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCE6F5)),
                ),
                child: IconButton(
                  onPressed: () => _changeDay(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                  color: const Color(0xFF0B4DBA),
                ),
              ),
              Expanded(
                child: Column(
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        isToday ? 'Hoje' : _formatDate(_selectedDate),
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF0F172A),
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _weekdayPt(_selectedDate),
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFDCE6F5)),
                ),
                child: IconButton(
                  onPressed: () => _changeDay(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                  color: const Color(0xFF0B4DBA),
                ),
              ),
            ],
          ),
          if (_loadingDay) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }

  Widget _buildMetrics() {
    final totals = _includedTotals();
    final consumedKcal = totals['consumedKcal'] ?? _consumedKcal;
    final protein = totals['protein'] ?? _protein;
    final carbs = totals['carbs'] ?? _carbs;
    final fat = totals['fat'] ?? _fat;
    final remainingKcal = totals['remainingKcal'] ?? _remainingKcal;
    final reachedDailyGoal = remainingKcal <= 0;
    final remainingValue = reachedDailyGoal
        ? '+${remainingKcal.abs().toStringAsFixed(0)}'
        : remainingKcal.toStringAsFixed(0);
    final remainingTitle = reachedDailyGoal ? 'Meta alcançada' : 'Restante';
    final remainingUnit = reachedDailyGoal ? 'kcal acima da meta' : 'kcal';
    final remainingColor = reachedDailyGoal
        ? const Color(0xFF16A34A)
        : const Color(0xFFF59E0B);
    final remainingIcon = reachedDailyGoal
        ? Icons.check_circle_outline_rounded
        : Icons.trending_down_rounded;
    final showTips = _showMetricCoachTips && !_isPastDay;

    Widget withCoachTip({
      required Widget card,
      required String tip,
      required Color color,
      required bool visible,
    }) {
      if (!visible) return card;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _MetricTipCloud(text: tip, color: color),
          const SizedBox(height: 8),
          card,
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = constraints.maxWidth;

        if (width >= 1200) {
          final row3w = (width - gap * 2) / 3;
          final row4w = (width - gap * 3) / 4;
          return Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: row3w,
                    child: withCoachTip(
                      visible: showTips,
                      tip: 'Aqui voce calcula e salva seu valor basal.',
                      color: const Color(0xFF0B4DBA),
                      card: _MetricCard(
                        title: 'TMB (Basal)',
                        value: _basalKcal.toStringAsFixed(0),
                        unit: 'kcal/dia',
                        color: const Color(0xFF0B4DBA),
                        icon: Icons.person_outline_rounded,
                        hint: _isPastDay ? null : 'Toque para calcular',
                        onTap: _isPastDay ? null : _showTmbCalculatorDialog,
                      ),
                    ),
                  ),
                  const SizedBox(width: gap),
                  SizedBox(
                    width: row3w,
                    child: withCoachTip(
                      visible: showTips,
                      tip: 'Aqui voce define sua meta diaria de calorias.',
                      color: const Color(0xFF2563EB),
                      card: _MetricCard(
                        title: 'Meta Diária',
                        value: _targetKcal.toStringAsFixed(0),
                        unit: 'kcal/dia',
                        color: const Color(0xFF2563EB),
                        icon: Icons.my_location_rounded,
                        hint: _isPastDay ? null : 'Toque para definir meta',
                        onTap: _isPastDay ? null : _showTargetDailyDialog,
                      ),
                    ),
                  ),
                  const SizedBox(width: gap),
                  SizedBox(
                    width: row3w,
                    child: _MetricCard(
                      title: remainingTitle,
                      value: remainingValue,
                      unit: remainingUnit,
                      color: remainingColor,
                      icon: remainingIcon,
                      hint: reachedDailyGoal
                          ? 'Você alcançou sua meta diária.'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: gap),
              Row(
                children: [
                  SizedBox(
                    width: row4w,
                    child: _MetricCard(
                      title: 'Consumido',
                      value: consumedKcal.toStringAsFixed(0),
                      unit: 'kcal',
                      color: const Color(0xFF0B4DBA),
                      icon: Icons.local_fire_department_outlined,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: gap),
                  SizedBox(
                    width: row4w,
                    child: _MetricCard(
                      title: 'Proteína',
                      value: protein.toStringAsFixed(1),
                      unit: 'g',
                      color: const Color(0xFF1D4ED8),
                      icon: Icons.bolt_rounded,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: gap),
                  SizedBox(
                    width: row4w,
                    child: _MetricCard(
                      title: 'Carboidratos',
                      value: carbs.toStringAsFixed(1),
                      unit: 'g',
                      color: const Color(0xFF3B82F6),
                      icon: Icons.grain_rounded,
                      compact: true,
                    ),
                  ),
                  const SizedBox(width: gap),
                  SizedBox(
                    width: row4w,
                    child: _MetricCard(
                      title: 'Gordura',
                      value: fat.toStringAsFixed(1),
                      unit: 'g',
                      color: const Color(0xFFDC2626),
                      icon: Icons.opacity_rounded,
                      compact: true,
                    ),
                  ),
                ],
              ),
            ],
          );
        }

        final cardWidth = width >= 760 ? (width - gap) / 2 : width;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            SizedBox(
              width: cardWidth,
              child: withCoachTip(
                visible: showTips,
                tip: 'Aqui voce calcula e salva seu valor basal.',
                color: const Color(0xFF0B4DBA),
                card: _MetricCard(
                  title: 'TMB (Basal)',
                  value: _basalKcal.toStringAsFixed(0),
                  unit: 'kcal/dia',
                  color: const Color(0xFF0B4DBA),
                  icon: Icons.person_outline_rounded,
                  hint: _isPastDay ? null : 'Toque para calcular',
                  onTap: _isPastDay ? null : _showTmbCalculatorDialog,
                ),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: withCoachTip(
                visible: showTips,
                tip: 'Aqui voce define sua meta diaria de calorias.',
                color: const Color(0xFF2563EB),
                card: _MetricCard(
                  title: 'Meta Diária',
                  value: _targetKcal.toStringAsFixed(0),
                  unit: 'kcal/dia',
                  color: const Color(0xFF2563EB),
                  icon: Icons.my_location_rounded,
                  hint: _isPastDay ? null : 'Toque para definir meta',
                  onTap: _isPastDay ? null : _showTargetDailyDialog,
                ),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: remainingTitle,
                value: remainingValue,
                unit: remainingUnit,
                color: remainingColor,
                icon: remainingIcon,
                hint: reachedDailyGoal
                    ? 'Você alcançou sua meta diária.'
                    : null,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Consumido',
                value: consumedKcal.toStringAsFixed(0),
                unit: 'kcal',
                color: const Color(0xFF0B4DBA),
                icon: Icons.local_fire_department_outlined,
                compact: true,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Proteína',
                value: protein.toStringAsFixed(1),
                unit: 'g',
                color: const Color(0xFF1D4ED8),
                icon: Icons.bolt_rounded,
                compact: true,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Carboidratos',
                value: carbs.toStringAsFixed(1),
                unit: 'g',
                color: const Color(0xFF3B82F6),
                icon: Icons.grain_rounded,
                compact: true,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _MetricCard(
                title: 'Gordura',
                value: fat.toStringAsFixed(1),
                unit: 'g',
                color: const Color(0xFFDC2626),
                icon: Icons.opacity_rounded,
                compact: true,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildFavoritesCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.star_rounded, color: Color(0xFF0B4DBA)),
            ),
            const SizedBox(width: 8),
            const Text(
              'Refeições Salvas',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '${_savedMealTemplates.length}',
                style: const TextStyle(
                  color: Color(0xFF1D4ED8),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        subtitle: const Text(
          'Toque no card para adicionar no dia e escolher a refeição',
        ),
        children: [
          if (_savedMealTemplates.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Nenhuma refeição salva ainda.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: _savedMealTemplates.map((template) {
                  final name =
                      (template['name'] ??
                              template['mealType'] ??
                              'Refeição favorita')
                          .toString();
                  final items =
                      (template['items'] as List<dynamic>? ?? const [])
                          .whereType<Map>()
                          .map((e) => Map<String, dynamic>.from(e))
                          .toList();
                  final kcal = items.fold<double>(
                    0,
                    (sum, item) => sum + _toDouble(item['calories']),
                  );

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: (_isPastDay || _savingEntry)
                          ? null
                          : () => _applySavedMealTemplate(template),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7FAF9),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFFDCE7E3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...items.map((item) {
                                    final foodName = (item['foodName'] ?? '-')
                                        .toString();
                                    final grams = _toDouble(
                                      item['quantityGrams'],
                                    ).toStringAsFixed(0);
                                    final itemKcal = _toDouble(
                                      item['calories'],
                                    ).toStringAsFixed(0);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• $foodName - ${grams}g ($itemKcal kcal)',
                                        style: const TextStyle(
                                          color: Color(0xFF475569),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              children: [
                                Text(
                                  kcal.toStringAsFixed(0),
                                  style: const TextStyle(
                                    color: Color(0xFF059669),
                                    fontSize: 36,
                                    fontWeight: FontWeight.w900,
                                    height: 1,
                                  ),
                                ),
                                const Text(
                                  'kcal',
                                  style: TextStyle(
                                    color: Color(0xFF475569),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Excluir favorito',
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    color: Color(0xFFDC2626),
                                  ),
                                  onPressed: _isPastDay
                                      ? null
                                      : () =>
                                            _deleteSavedMealTemplate(template),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAddMealCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 12.0;
          final width = constraints.maxWidth;
          final blockWidth = width >= 1200
              ? (width - gap * 3) / 4
              : width >= 760
              ? (width - gap) / 2
              : width;

          return Column(
            children: [
              Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: blockWidth,
                    child: _FormBlock(
                      icon: Icons.apple_rounded,
                      title: 'Alimento',
                      accent: const Color(0xFF0B4DBA),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _foodSearchCtrl,
                            onChanged: _isPastDay ? null : _onFoodSearchChanged,
                            readOnly: _isPastDay,
                            decoration: const InputDecoration(
                              hintText:
                                  'Digite o alimento (busca automática)...',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _isPastDay ? null : _showFoodDialog,
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(0, 32),
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              icon: const Icon(
                                Icons.edit_note_rounded,
                                size: 18,
                              ),
                              label: const Text(
                                'Nao encontrou? Cadastre manualmente',
                              ),
                            ),
                          ),
                          if (_showFoodSuggestions) ...[
                            const SizedBox(height: 8),
                            Container(
                              constraints: const BoxConstraints(maxHeight: 150),
                              width: double.infinity,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFFD6E3FA),
                                ),
                              ),
                              child: _foodSuggestions.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: _searchingFoods
                                          ? const Row(
                                              children: [
                                                SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Buscando alimentos...',
                                                  style: TextStyle(
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                            )
                                          : const Text(
                                              'Nenhum alimento encontrado.',
                                              style: TextStyle(
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: _foodSuggestions.length,
                                      itemBuilder: (_, i) {
                                        final food = _foodSuggestions[i];
                                        final sourceLabel = _foodSourceLabel(
                                          food['source'],
                                        );
                                        return ListTile(
                                          dense: true,
                                          title: Text(
                                            (food['name'] ?? '').toString(),
                                          ),
                                          subtitle: Text(
                                            '${_toDouble(food['caloriesPer100g']).toStringAsFixed(0)} kcal/100g • '
                                            'P ${_toDouble(food['proteinPer100g']).toStringAsFixed(1)} g • '
                                            'C ${_toDouble(food['carbsPer100g']).toStringAsFixed(1)} g • '
                                            'G ${_toDouble(food['fatPer100g']).toStringAsFixed(1)} g'
                                            ' • $sourceLabel',
                                          ),
                                          onTap: () => _selectFood(food),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: blockWidth,
                    child: _FormBlock(
                      icon: Icons.scale_rounded,
                      title: 'Quantidade',
                      accent: const Color(0xFF1D4ED8),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _quantityCtrl,
                              readOnly: _isPastDay,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                hintText: '0',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onChanged: _isPastDay
                                  ? null
                                  : (_) => setState(() {}),
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<String>(
                            value: _quantityUnitChoices.contains(_quantityUnit)
                                ? _quantityUnit
                                : 'g',
                            underline: const SizedBox.shrink(),
                            borderRadius: BorderRadius.circular(8),
                            items: _quantityUnitChoices
                                .map(
                                  (u) => DropdownMenuItem(
                                    value: u,
                                    child: Text(u),
                                  ),
                                )
                                .toList(),
                            onChanged: _isPastDay
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    setState(() => _quantityUnit = v);
                                  },
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: blockWidth,
                    child: _FormBlock(
                      icon: Icons.breakfast_dining_rounded,
                      title: 'Refeição',
                      accent: const Color(0xFF3B82F6),
                      child: DropdownButtonFormField<String>(
                        initialValue: _mealChoices.contains(_selectedMeal)
                            ? _selectedMeal
                            : _mealChoices.first,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: _mealChoices
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                        onChanged: _isPastDay
                            ? null
                            : (v) {
                                if (v == null) return;
                                setState(() => _selectedMeal = v);
                              },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: blockWidth,
                    child: _FormBlock(
                      icon: Icons.local_fire_department_outlined,
                      title: 'Calorias',
                      accent: const Color(0xFF0B4DBA),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_previewCalories.toStringAsFixed(0)} kcal',
                            style: const TextStyle(
                              fontSize: 37,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0B4DBA),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'P ${_previewProtein.toStringAsFixed(1)} g • '
                            'C ${_previewCarbs.toStringAsFixed(1)} g • '
                            'G ${_previewFat.toStringAsFixed(1)} g',
                            style: const TextStyle(
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              if (_searchingFoods)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_savingEntry || _isPastDay) ? null : _addEntry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B4DBA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: _savingEntry
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.add_rounded),
                  label: const Text(
                    'Adicionar Alimento',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Retorna o índice de ordenação de um tipo de refeição customizado,
  /// baseado no índice do tipo-pai em [_mealTypes] (ex: "Almoço - Favorito"
  /// → índice de "Almoço"). Tipos sem correspondência vão ao final.
  int _customMealTypeSortKey(String mealType) {
    final lower = mealType.trim().toLowerCase();
    for (int i = 0; i < _mealTypes.length; i++) {
      if (lower.startsWith(_mealTypes[i].toLowerCase())) return i;
    }
    // Sem prefixo padrão: ordena alfabeticamente após os tipos padrão
    return _mealTypes.length;
  }

  List<Widget> _buildMealSections() {
    final mealByType = <String, Map<String, dynamic>>{};
    for (final meal in _meals) {
      final mealType = (meal['mealType'] ?? '').toString().trim();
      if (mealType.isEmpty) continue;
      mealByType[mealType] = meal;
    }

    final sections = <Widget>[];
    final orderedMealTypes = <String>[];

    // Tipos padrão primeiro, na ordem definida em _mealTypes
    for (final mealType in _mealTypes) {
      if (!orderedMealTypes.contains(mealType)) {
        orderedMealTypes.add(mealType);
      }
    }

    // Tipos customizados: coleta de meals e carryover, ordena de forma estável
    final customTypes = <String>{};
    for (final mealType in mealByType.keys) {
      if (!_mealTypes.contains(mealType)) customTypes.add(mealType);
    }
    for (final mealType in _carryoverByMealType.keys) {
      if (!_mealTypes.contains(mealType)) customTypes.add(mealType);
    }
    final sortedCustom = customTypes.toList()
      ..sort((a, b) {
        final ka = _customMealTypeSortKey(a);
        final kb = _customMealTypeSortKey(b);
        if (ka != kb) return ka.compareTo(kb);
        return a.compareTo(b); // Desempate alfabético
      });
    for (final mealType in sortedCustom) {
      if (!orderedMealTypes.contains(mealType)) {
        orderedMealTypes.add(mealType);
      }
    }

    for (final mealType in orderedMealTypes) {
      final meal = mealByType[mealType];
      final carryoverEntries = _carryoverByMealType[mealType] ?? const [];

      if (meal == null && carryoverEntries.isEmpty) continue;

      final entries = (meal?['entries'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      sections.add(_buildMealCard(mealType, entries, carryoverEntries));
    }

    if (sections.isEmpty) {
      return [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 32),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFDCE6F5)),
          ),
          child: const Text(
            'Nenhum alimento registrado para este dia.',
            style: TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ];
    }

    return sections;
  }

  Widget _buildMealCard(
    String mealType,
    List<Map<String, dynamic>> entries,
    List<Map<String, dynamic>> carryoverEntries,
  ) {
    final includedEntries = _includedEntries(entries);
    final totalCalories = includedEntries.fold<double>(
      0,
      (sum, entry) => sum + _toDouble(entry['calories']),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE6F5)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 600;
              final title = Text(
                mealType,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isNarrow ? 19 : 30,
                  fontWeight: FontWeight.w900,
                ),
              );
              final total = Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'Total',
                    style: TextStyle(
                      color: Color(0xFF475569),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${totalCalories.toStringAsFixed(0)} kcal',
                    style: const TextStyle(
                      color: Color(0xFF059669),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              );
              final delete = IconButton(
                tooltip: 'Excluir refeição do dia',
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Color(0xFFDC2626),
                ),
                onPressed: (_isPastDay || _savingEntry)
                    ? null
                    : () =>
                          _deleteMealOfDay(mealType, entries, carryoverEntries),
              );
              final favorite = OutlinedButton.icon(
                onPressed: includedEntries.isEmpty
                    ? null
                    : () => _saveMealAsFavorite(mealType, includedEntries),
                icon: const Icon(Icons.star_border_rounded),
                label: const Text('Salvar Refeição'),
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(child: title),
                        const SizedBox(width: 8),
                        total,
                        delete,
                      ],
                    ),
                    const SizedBox(height: 6),
                    Align(alignment: Alignment.centerRight, child: favorite),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  total,
                  delete,
                  const SizedBox(width: 12),
                  favorite,
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          ...entries.map((entry) {
            final foodName = (entry['foodName'] ?? '-').toString();
            final grams = _toDouble(entry['quantityGrams']).toStringAsFixed(0);
            final unitLabel = (entry['unit'] ?? 'g').toString();
            final kcal = _toDouble(entry['calories']).toStringAsFixed(0);
            final p = _toDouble(entry['protein']).toStringAsFixed(1);
            final c = _toDouble(entry['carbs']).toStringAsFixed(1);
            final g = _toDouble(entry['fat']).toStringAsFixed(1);

            return Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => _toggleEntryIncluded(entry),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: _isEntryIncluded(entry)
                            ? const Color(0xFF059669)
                            : const Color(0xFFE2E8F0),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _isEntryIncluded(entry)
                              ? const Color(0xFF059669)
                              : const Color(0xFF94A3B8),
                        ),
                      ),
                      child: Icon(
                        _isEntryIncluded(entry)
                            ? Icons.check_rounded
                            : Icons.circle_outlined,
                        color: _isEntryIncluded(entry)
                            ? Colors.white
                            : const Color(0xFF64748B),
                        size: _isEntryIncluded(entry) ? 20 : 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          foodName,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _isEntryIncluded(entry)
                                ? const Color(0xFF0F172A)
                                : const Color(0xFF94A3B8),
                            decoration: _isEntryIncluded(entry)
                                ? TextDecoration.none
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$grams $unitLabel',
                          style: TextStyle(
                            color: _isEntryIncluded(entry)
                                ? Color(0xFF64748B)
                                : Color(0xFFA3B0C2),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Proteína: ${p}g   Gordura: ${g}g   Carboidrato: ${c}g',
                          style: TextStyle(
                            color: _isEntryIncluded(entry)
                                ? Color(0xFF334155)
                                : Color(0xFFA3B0C2),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        kcal,
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: _isEntryIncluded(entry)
                              ? const Color(0xFF059669)
                              : const Color(0xFF94A3B8),
                          height: 1,
                        ),
                      ),
                      const Text(
                        'kcal',
                        style: TextStyle(
                          color: Color(0xFF475569),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Editar quantidade',
                    icon: const Icon(
                      Icons.edit_rounded,
                      size: 20,
                      color: Color(0xFF2563EB),
                    ),
                    onPressed: _isPastDay
                        ? null
                        : () => _showEditEntryQuantityDialog(entry),
                  ),
                  IconButton(
                    tooltip: 'Remover item',
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFDC2626),
                    ),
                    onPressed: _isPastDay
                        ? null
                        : () => _deleteEntry(_toInt(entry['id'])),
                  ),
                ],
              ),
            );
          }),
          if (carryoverEntries.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...carryoverEntries.map((entry) {
              final foodName = (entry['foodName'] ?? '-').toString();
              final grams = _toDouble(
                entry['quantityGrams'],
              ).toStringAsFixed(0);
              final unitLabel = (entry['unit'] ?? 'g').toString();
              final kcal = _toDouble(entry['calories']).toStringAsFixed(0);
              final p = _toDouble(entry['protein']).toStringAsFixed(1);
              final c = _toDouble(entry['carbs']).toStringAsFixed(1);
              final g = _toDouble(entry['fat']).toStringAsFixed(1);

              return Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: (_isPastDay || _savingEntry)
                          ? null
                          : () => _unlockCarryoverEntry(mealType, entry),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF94A3B8)),
                        ),
                        child: const Icon(
                          Icons.lock_open_rounded,
                          color: Color(0xFF64748B),
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            foodName,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF94A3B8),
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '$grams $unitLabel',
                            style: const TextStyle(
                              color: Color(0xFFA3B0C2),
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Proteína: ${p}g   Gordura: ${g}g   Carboidrato: ${c}g',
                            style: const TextStyle(
                              color: Color(0xFFA3B0C2),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          kcal,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF94A3B8),
                            height: 1,
                          ),
                        ),
                        const Text(
                          'kcal',
                          style: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  void _showSnack(String message, {Color color = const Color(0xFF334155)}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _toDateIso(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _formatDate(DateTime value) {
    final d = value.day.toString().padLeft(2, '0');
    final m = value.month.toString().padLeft(2, '0');
    final y = value.year.toString();
    return '$d/$m/$y';
  }

  String _weekdayPt(DateTime value) {
    const labels = [
      'Segunda-Feira',
      'Terça-Feira',
      'Quarta-Feira',
      'Quinta-Feira',
      'Sexta-Feira',
      'Sábado',
      'Domingo',
    ];
    final idx = value.weekday - 1;
    if (idx < 0 || idx >= labels.length) return '';
    return labels[idx];
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse((value ?? '').toString()) ?? 0;
  }

  double? _toDoubleOrNull(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final parsed = double.tryParse(value.toString().trim());
    return parsed;
  }

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  double? _tryParseNumber(String text) {
    return double.tryParse(text.trim().replaceAll(',', '.'));
  }
}

class _TmbStep1Result {
  const _TmbStep1Result(this.basalKcal, this.totalEnergyExpenditure);

  final double basalKcal;
  final double totalEnergyExpenditure;
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final Color color;
  final IconData icon;
  final VoidCallback? onTap;
  final bool compact;
  final String? hint;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
    this.onTap,
    this.compact = false,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final valueSize = compact ? 30.0 : 40.0;
    final cardPadding = compact
        ? const EdgeInsets.all(12)
        : const EdgeInsets.all(14);
    final iconSize = compact ? 20.0 : 24.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 200),
        width: MediaQuery.sizeOf(context).width < 248 ? double.infinity : 200,
        padding: cardPadding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: iconSize),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: valueSize,
                      height: 0.95,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    unit,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if ((hint ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.touch_app_rounded,
                          size: 13,
                          color: color.withValues(alpha: 0.85),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            hint!,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: color.withValues(alpha: 0.9),
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricTipCloud extends StatelessWidget {
  final String text;
  final Color color;

  const _MetricTipCloud({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final bg = color.withValues(alpha: 0.12);
    final border = color.withValues(alpha: 0.35);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.wb_cloudy_rounded, size: 16, color: color),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: color.withValues(alpha: 0.95),
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                  ),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 28),
          child: Transform.rotate(
            angle: 0.785398,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: bg,
                border: Border(
                  right: BorderSide(color: border),
                  bottom: BorderSide(color: border),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FormBlock extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color accent;
  final Widget child;

  const _FormBlock({
    required this.icon,
    required this.title,
    required this.accent,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE6F5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
