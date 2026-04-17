import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';

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

  DateTime _selectedDate = DateTime.now();
  bool _loading = true;
  bool _loadingDay = false;
  bool _savingEntry = false;
  bool _searchingEdamam = false;
  int _searchSeq = 0;

  List<Map<String, dynamic>> _foods = [];
  List<Map<String, dynamic>> _meals = [];
  List<Map<String, dynamic>> _savedMealTemplates = [];
  Map<String, List<Map<String, dynamic>>> _carryoverByMealType = {};
  final Map<String, Map<String, List<Map<String, dynamic>>>> _carryoverByDate = {};
  final Map<String, Set<String>> _suppressedCarryoverByDate = {};
  final Map<String, Set<int>> _excludedEntryIdsByDate = {};
  final Set<int> _excludedEntryIds = <int>{};

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
  final TextEditingController _quantityCtrl = TextEditingController(text: '100');
  Timer? _foodSearchDebounce;

  List<Map<String, dynamic>> _foodSuggestions = [];
  bool _showFoodSuggestions = false;
  Map<String, dynamic>? _selectedExternalFood;
  bool _firstAccessTipsScheduled = false;
  bool _showMetricCoachTips = false;

  bool get _isPastDay {
    final selected = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return selected.year != today.year ||
        selected.month != today.month ||
        selected.day != today.day;
  }

  String get _excludedEntryIdsStateKey => 'diet_excluded_entry_ids_by_date_${widget.userId}';
  String get _suppressedCarryoverStateKey => 'diet_suppressed_carryover_by_date_${widget.userId}';
  String get _carryoverStateKey => 'diet_carryover_by_date_${widget.userId}';
  String get _firstAccessTipsKey {
    final role = widget.isTrainerSide ? 'trainer' : 'student';
    return 'diet_first_access_tips_v1_$role';
  }

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
          final mealMapDecoded = mealMapRaw as Map<String, dynamic>? ?? const {};
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

    final carryoverPayload = <String, Map<String, List<Map<String, dynamic>>>>{};
    _carryoverByDate.forEach((dateIso, mealMap) {
      if (mealMap.isEmpty) return;
      final normalizedMealMap = <String, List<Map<String, dynamic>>>{};
      mealMap.forEach((mealType, entries) {
        if (entries.isEmpty) return;
        normalizedMealMap[mealType] = entries.map((e) => Map<String, dynamic>.from(e)).toList();
      });
      if (normalizedMealMap.isNotEmpty) {
        carryoverPayload[dateIso] = normalizedMealMap;
      }
    });

    await prefs.setString(_excludedEntryIdsStateKey, jsonEncode(excludedPayload));
    await prefs.setString(_suppressedCarryoverStateKey, jsonEncode(suppressedPayload));
    await prefs.setString(_carryoverStateKey, jsonEncode(carryoverPayload));
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
    final qty = _toDouble(entry['quantityGrams']).toStringAsFixed(1);
    if (foodId > 0) return '${mealType.toLowerCase()}|id:$foodId|$qty';
    return '${mealType.toLowerCase()}|name:$foodName|$qty';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_initStateAndLoad());
  }

  Future<void> _initStateAndLoad() async {
    try {
      await _restoreLocalDietState();
    } catch (_) {
      // If local restore fails, continue with remote data load.
    }
    await _loadAll();
    await _maybeShowFirstAccessTips();
  }

  Future<void> _maybeShowFirstAccessTips() async {
    if (_firstAccessTipsScheduled || !mounted) return;
    _firstAccessTipsScheduled = true;

    final prefs = await SharedPreferences.getInstance();
    final alreadySeen = prefs.getBool(_firstAccessTipsKey) ?? false;
    if (alreadySeen || !mounted) return;

    setState(() => _showMetricCoachTips = true);
    await prefs.setBool(_firstAccessTipsKey, true);
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

    try {
      final foods = await AuthService.getDietFoods(widget.userId);
      final daily = await AuthService.getDietEntriesByDate(
        userId: widget.userId,
        dateIso: _toDateIso(_selectedDate),
      );
      final previousDaily = await AuthService.getDietEntriesByDate(
        userId: widget.userId,
        dateIso: _toDateIso(_selectedDate.subtract(const Duration(days: 1))),
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

        final selectedDateIso = _toDateIso(_selectedDate);
        final previousDateIso = _toDateIso(_selectedDate.subtract(const Duration(days: 1)));

      final existingSignatures = <String>{};
      for (final meal in meals) {
        final mealType = (meal['mealType'] ?? '').toString().trim();
        final entries = (meal['entries'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e));
        for (final entry in entries) {
          existingSignatures.add(_entrySignature(mealType, entry));
        }
      }

      final carryoverByMealType = <String, List<Map<String, dynamic>>>{};
      final carryoverSignatures = <String>{};

      void addCarryover(String mealType, Map<String, dynamic> entry) {
        final normalizedMealType = mealType.trim();
        if (normalizedMealType.isEmpty) return;
        final signature = _entrySignature(normalizedMealType, entry);
        if (existingSignatures.contains(signature)) return;
        if (carryoverSignatures.contains(signature)) return;

        carryoverSignatures.add(signature);
        carryoverByMealType.putIfAbsent(normalizedMealType, () => <Map<String, dynamic>>[]).add({
          ...entry,
          'mealType': normalizedMealType,
        });
      }

      final previousMeals = (previousDaily['meals'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e));

      for (final meal in previousMeals) {
        final mealType = (meal['mealType'] ?? '').toString().trim();
        if (mealType.isEmpty) continue;

        final previousEntries = (meal['entries'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e));

        for (final entry in previousEntries) {
          addCarryover(mealType, entry);
        }
      }

      final previousSuppressedCarryover =
          _suppressedCarryoverByDate[previousDateIso] ?? const <String>{};
      final previousDayCarryover =
          _carryoverByDate[previousDateIso] ?? const <String, List<Map<String, dynamic>>>{};
      previousDayCarryover.forEach((mealType, entries) {
        if (previousSuppressedCarryover.contains(mealType)) return;
        for (final entry in entries) {
          addCarryover(mealType, Map<String, dynamic>.from(entry));
        }
      });

      final suppressedCarryover = _suppressedCarryoverByDate[selectedDateIso] ?? const <String>{};
      if (suppressedCarryover.isNotEmpty) {
        carryoverByMealType.removeWhere((mealType, _) => suppressedCarryover.contains(mealType));
      }

      final carryoverSnapshot = <String, List<Map<String, dynamic>>>{};
      carryoverByMealType.forEach((mealType, entries) {
        carryoverSnapshot[mealType] = entries.map((e) => Map<String, dynamic>.from(e)).toList();
      });

      final mealChoices = _resolveMealChoices(meals: meals, templates: savedMeals);
      final validEntryIds = meals
          .expand((meal) => (meal['entries'] as List<dynamic>? ?? const []))
          .whereType<Map>()
          .map((entry) => _toInt(entry['id']))
          .where((id) => id > 0)
          .toSet();

      final excludedForDate = Set<int>.from(_excludedEntryIdsByDate[selectedDateIso] ?? const <int>{})
        ..removeWhere((id) => !validEntryIds.contains(id));

      setState(() {
        _foods = foods;
        _meals = meals;
        _savedMealTemplates = savedMeals;
        _carryoverByMealType = carryoverByMealType;
        _carryoverByDate[selectedDateIso] = carryoverSnapshot;
        _excludedEntryIds
          ..clear()
          ..addAll(excludedForDate);
        _excludedEntryIdsByDate[selectedDateIso] = Set<int>.from(excludedForDate);
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
      unawaited(_persistLocalDietState());
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
      _showSnack('Digite um alimento válido para buscar na Edamam.');
      return;
    }

    final qty = _tryParseNumber(_quantityCtrl.text);
    if (qty == null || qty <= 0) {
      _showSnack('Informe uma quantidade válida em gramas.');
      return;
    }

    final kcal100 = _toDouble(selectedFood['caloriesPer100g']);
    if (kcal100 <= 0) {
      _showSnack('Não foi possível obter as calorias desse alimento na Edamam.');
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
      );
      await _loadAll(keepUi: true);
      if (!mounted) return;
      setState(() => _showFoodSuggestions = false);
      _showSnack('Alimento adicionado com sucesso.', color: const Color(0xFF16A34A));
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
      await AuthService.deleteDietEntry(userId: widget.userId, entryId: entryId);
      await _loadAll(keepUi: true);
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

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
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
              width: 460,
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
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  ...entries.map((entry) {
                    final name = (entry['foodName'] ?? '-').toString();
                    final grams = _toDouble(entry['quantityGrams']).toStringAsFixed(0);
                    final kcal = _toDouble(entry['calories']).toStringAsFixed(0);
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
        mealType: mealType,
        items: templateItems,
      );
      await _loadAll(keepUi: true);
      _showSnack('Refeição favorita salva com sucesso.', color: const Color(0xFF16A34A));
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
    final templateName = (template['name'] ?? template['mealType'] ?? '').toString().trim();

    String selectedMealType = _applyAsFavoriteNameOption;

    final applyConfirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialogState) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Adicionar favorito no dia'),
              content: SizedBox(
                width: 420,
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
                          child: Text('Adicionar no dia atual (nome do favorito)'),
                        ),
                        ...mealChoices.map((m) => DropdownMenuItem(value: m, child: Text(m))),
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

      await _loadAll(keepUi: true);
      _showSnack('Favorito adicionado em $targetMealType.', color: const Color(0xFF16A34A));
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

    final confirmed = await showDialog<bool>(
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
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

  Future<void> _unlockCarryoverEntry(String mealType, Map<String, dynamic> entry) async {
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
              (f) => (f?['name'] ?? '').toString().trim().toLowerCase() == name.toLowerCase(),
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

      await _loadAll(keepUi: true);
      _showSnack('Alimento desbloqueado e adicionado.', color: const Color(0xFF16A34A));
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

    final confirmed = await showDialog<bool>(
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626)),
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
        await AuthService.deleteDietEntry(userId: widget.userId, entryId: entryId);
      }

      final dateIso = _toDateIso(_selectedDate);
      _suppressedCarryoverByDate.putIfAbsent(dateIso, () => <String>{}).add(mealType);
      _carryoverByDate[dateIso]?.remove(mealType);
      _carryoverByMealType.remove(mealType);
      await _persistLocalDietState();

      await _loadAll(keepUi: true);
      _showSnack('Refeição "$mealType" excluída do dia.', color: const Color(0xFF16A34A));
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

    const defaultQuantity = 100.0;

    final nameCtrl = TextEditingController(text: (existing?['name'] ?? '').toString());
    final quantityCtrl = TextEditingController(text: defaultQuantity.toStringAsFixed(0));
    final kcalTotalCtrl = TextEditingController(
      text: existing == null ? '' : _toDouble(existing['caloriesPer100g']).toStringAsFixed(1),
    );
    final proteinTotalCtrl = TextEditingController(
      text: existing == null ? '' : _toDouble(existing['proteinPer100g']).toStringAsFixed(1),
    );
    final carbsTotalCtrl = TextEditingController(
      text: existing == null ? '' : _toDouble(existing['carbsPer100g']).toStringAsFixed(1),
    );
    final fatTotalCtrl = TextEditingController(
      text: existing == null ? '' : _toDouble(existing['fatPer100g']).toStringAsFixed(1),
    );

    final bool favorite = existing?['favorite'] == true;

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(existing == null ? 'Cadastrar Novo Alimento' : 'Editar Alimento'),
          content: SizedBox(
            width: 640,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Adicione um alimento que não está na lista. Informe a quantidade específica e os valores totais daquela quantidade.',
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
                    controller: quantityCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade em Gramas',
                      hintText: 'Ex: 200 ou 200,5',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'A quantidade específica que você quer registrar',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: kcalTotalCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Calorias Totais',
                      hintText: 'Ex: 830 ou 830,5',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Calorias totais desses Xg',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: proteinTotalCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Proteína (g)',
                            hintText: 'Ex: 15,5',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: carbsTotalCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Carboidratos (g)',
                            hintText: 'Ex: 112',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: fatTotalCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Gordura (g)',
                            hintText: 'Ex: 0,6',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Total desses Xg',
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
                final qty = _tryParseNumber(quantityCtrl.text);
                final kcalTotal = _tryParseNumber(kcalTotalCtrl.text);
                final proteinTotal = _tryParseNumber(proteinTotalCtrl.text);
                final carbsTotal = _tryParseNumber(carbsTotalCtrl.text);
                final fatTotal = _tryParseNumber(fatTotalCtrl.text);

                if (name.isEmpty ||
                    qty == null ||
                    kcalTotal == null ||
                    proteinTotal == null ||
                    carbsTotal == null ||
                    fatTotal == null ||
                    qty <= 0) {
                  _showSnack('Preencha todos os campos corretamente.');
                  return;
                }

                final factor = 100 / qty;

                try {
                  if (existing == null) {
                    await AuthService.createDietFood(
                      userId: widget.userId,
                      name: name,
                      caloriesPer100g: kcalTotal * factor,
                      proteinPer100g: proteinTotal * factor,
                      carbsPer100g: carbsTotal * factor,
                      fatPer100g: fatTotal * factor,
                      favorite: favorite,
                    );
                  } else {
                    await AuthService.updateDietFood(
                      userId: widget.userId,
                      foodId: _toInt(existing['id']),
                      name: name,
                      caloriesPer100g: kcalTotal * factor,
                      proteinPer100g: proteinTotal * factor,
                      carbsPer100g: carbsTotal * factor,
                      fatPer100g: fatTotal * factor,
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
    var filtered = List<Map<String, dynamic>>.from(_foods);

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          void applyFilter(String query) {
            final q = query.trim().toLowerCase();
            setDialogState(() {
              filtered = _foods.where((f) {
                final name = (f['name'] ?? '').toString().toLowerCase();
                return q.isEmpty || name.contains(q);
              }).toList();
            });
          }

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            title: const Text('Gerenciar Alimentos Personalizados'),
            content: SizedBox(
              width: 700,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Edite ou delete os alimentos personalizados que você cadastrou.',
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
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, i) {
                              final food = filtered[i];
                              final kcal100 = _toDouble(food['caloriesPer100g']);
                              final kcalGram = kcal100 / 100;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FBFF),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: const Color(0xFFDCE6F5)),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: Color(0xFFDC2626),
                                      ),
                                      onPressed: () async {
                                        try {
                                          await AuthService.deleteDietFood(
                                            userId: widget.userId,
                                            foodId: _toInt(food['id']),
                                          );
                                          await _loadAll(keepUi: true);
                                          applyFilter(searchCtrl.text);
                                        } catch (e) {
                                          _showSnack(
                                            e.toString().replaceFirst('Exception: ', ''),
                                            color: const Color(0xFFDC2626),
                                          );
                                        }
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

    final weightCtrl = TextEditingController();
    final heightCtrl = TextEditingController();
    final ageCtrl = TextEditingController();

    String? selectedSex;
    String? selectedActivity;

    const activityFactors = <String, double>{
      'Sedentário': 1.2,
      'Levemente ativo': 1.375,
      'Moderadamente ativo': 1.55,
      'Muito ativo': 1.725,
      'Extremamente ativo': 1.9,
    };

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Text('Calcular TMB'),
          content: SizedBox(
            width: 430,
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
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
                          decoration: const InputDecoration(
                            labelText: 'Altura (cm)',
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
                    onChanged: (v) => setDialogState(() => selectedActivity = v),
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
                final weight = _tryParseNumber(weightCtrl.text);
                final height = _tryParseNumber(heightCtrl.text);
                final age = _tryParseNumber(ageCtrl.text);
                if (weight == null ||
                    height == null ||
                    age == null ||
                    selectedSex == null ||
                    selectedActivity == null) {
                  _showSnack('Preencha todos os campos para calcular o TMB.');
                  return;
                }

                final tmbBase = (10 * weight) + (6.25 * height) - (5 * age);
                final tmb = selectedSex == 'M' ? tmbBase + 5 : tmbBase - 161;
                final activityFactor = activityFactors[selectedActivity] ?? 1.2;
                final suggestedTarget = tmb * activityFactor;

                try {
                  await AuthService.saveDietGoals(
                    userId: widget.userId,
                    basalKcal: tmb,
                    targetKcal: _targetKcal > 0 ? _targetKcal : suggestedTarget,
                  );
                  if (!ctx.mounted || !mounted) return;
                  Navigator.pop(ctx);
                  await _loadAll(keepUi: true);
                  _showSnack('TMB calculado e salvo com sucesso.', color: const Color(0xFF16A34A));
                } catch (e) {
                  _showSnack(
                    e.toString().replaceFirst('Exception: ', ''),
                    color: const Color(0xFFDC2626),
                  );
                }
              },
              child: const Text('Calcular TMB'),
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
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: targetCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
    if (query.isEmpty) {
      setState(() {
        _foodSuggestions = [];
        _showFoodSuggestions = false;
        _searchingEdamam = false;
        _selectedFoodId = null;
        _selectedExternalFood = null;
      });
      return;
    }

    final normalized = query.toLowerCase();
    final localMatches = _foods
        .where((food) => (food['name'] ?? '').toString().toLowerCase().contains(normalized))
        .take(6)
        .map((e) {
      final row = Map<String, dynamic>.from(e);
      row.putIfAbsent('source', () => 'local');
      return row;
    }).toList();

    setState(() {
      _foodSuggestions = localMatches;
      _showFoodSuggestions = true;
      _searchingEdamam = true;
      _selectedFoodId = null;
      _selectedExternalFood = null;
    });

    _foodSearchDebounce = Timer(
      const Duration(milliseconds: 450),
      () => _loadFoodSuggestions(query),
    );
  }

  Future<void> _loadFoodSuggestions(String query) async {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return;

    final requestSeq = ++_searchSeq;
    final localMatches = _foods
        .where((food) => (food['name'] ?? '').toString().toLowerCase().contains(normalized))
        .take(6)
        .map((e) {
      final row = Map<String, dynamic>.from(e);
      row.putIfAbsent('source', () => 'local');
      return row;
    }).toList();

    try {
      final remote = await AuthService.searchEdamamFoods(
        userId: widget.userId,
        query: query,
        limit: 12,
      );

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
        row.putIfAbsent('source', () => 'edamam');
        final name = (row['name'] ?? '').toString().trim().toLowerCase();
        if (name.isEmpty || names.contains(name)) continue;
        names.add(name);
        merged.add(row);
      }

      setState(() {
        _foodSuggestions = merged;
        _showFoodSuggestions = true;
        _searchingEdamam = false;
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
        _searchingEdamam = false;
      });
    }
  }

  void _selectFood(Map<String, dynamic> food) {
    final selectedId = _toInt(food['id']);
    final source = (food['source'] ?? '').toString().toLowerCase();
    final isLocal = selectedId > 0 && source != 'edamam';

    setState(() {
      _selectedFoodId = isLocal ? selectedId : null;
      _selectedExternalFood = isLocal ? null : Map<String, dynamic>.from(food);
      _foodSearchCtrl.text = (food['name'] ?? '').toString();
      _showFoodSuggestions = false;
      _foodSuggestions = [];
      _searchingEdamam = false;
    });
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
      final selectedName = (_selectedExternalFood!['name'] ?? '').toString().trim().toLowerCase();
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

    final exactSuggestion = _foodSuggestions.cast<Map<String, dynamic>?>().firstWhere(
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
          (f) => (f?['name'] ?? '').toString().trim().toLowerCase() == name.toLowerCase(),
          orElse: () => null,
        );
    if (localExisting != null) {
      return _toInt(localExisting['id']);
    }

    final caloriesPer100g = _toDouble(food['caloriesPer100g']);
    final proteinPer100g = _toDouble(food['proteinPer100g']);
    final carbsPer100g = _toDouble(food['carbsPer100g']);
    final fatPer100g = _toDouble(food['fatPer100g']);

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
      );
      return _toInt(created['id']);
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '').toLowerCase();
      if (!message.contains('já cadastrou') &&
          !message.contains('ja cadastrou') &&
          !message.contains('já existe alimento') &&
          !message.contains('ja existe alimento')) {
        rethrow;
      }

      await _loadAll(keepUi: true);
      final found = _foods.cast<Map<String, dynamic>?>().firstWhere(
            (f) => (f?['name'] ?? '').toString().trim().toLowerCase() == name.toLowerCase(),
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

  List<Map<String, dynamic>> _includedEntries(List<Map<String, dynamic>> entries) {
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

  double _macroForQty(String key) {
    final selected = _resolveFoodFromTypedText();
    if (selected == null) return 0;
    final qty = _tryParseNumber(_quantityCtrl.text) ?? 0;
    return (_toDouble(selected[key]) * qty) / 100;
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
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFDBA74)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lock_clock_rounded, color: Color(0xFFEA580C)),
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
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _isPastDay ? null : _showFoodDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0B4DBA),
                      side: const BorderSide(color: Color(0xFFBFD3F5)),
                      backgroundColor: const Color(0xFFF8FBFF),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(Icons.add_circle_outline_rounded, size: 17),
                    label: const Text('Cadastrar Manualmente'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isPastDay ? null : _showManageFoodsDialog,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0xFFD5DEEE)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(Icons.settings_rounded, size: 17),
                    label: const Text('Gerenciar Alimentos'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _showMetricCoachTips ? _hideCoachTips : _showCoachTips,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0B4DBA),
                      side: const BorderSide(color: Color(0xFFBFD3F5)),
                      backgroundColor: const Color(0xFFF8FBFF),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: Icon(
                      _showMetricCoachTips
                          ? Icons.visibility_off_rounded
                          : Icons.wb_cloudy_rounded,
                      size: 17,
                    ),
                    label: Text(
                      _showMetricCoachTips ? 'Ocultar dicas' : 'Ver dicas novamente',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0F172A),
                      side: const BorderSide(color: Color(0xFFD5DEEE)),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    icon: const Icon(Icons.logout_rounded, size: 17),
                    label: const Text('Sair'),
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 12),
                    actions,
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
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: isActive ? Colors.white : const Color(0xFF0B4DBA),
        backgroundColor:
            isActive ? const Color(0xFF1D4ED8) : const Color(0xFFF8FBFF),
        side: BorderSide(
          color: isActive ? const Color(0xFF1D4ED8) : const Color(0xFFBFD3F5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: Icon(icon, size: 17),
      label: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    Text(
                      isToday ? 'Hoje' : _formatDate(_selectedDate),
                      style: const TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        height: 1,
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
                      title: 'Restante',
                      value: remainingKcal.toStringAsFixed(0),
                      unit: 'kcal',
                      color: const Color(0xFFF59E0B),
                      icon: Icons.trending_down_rounded,
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
                title: 'Restante',
                value: remainingKcal.toStringAsFixed(0),
                unit: 'kcal',
                color: const Color(0xFFF59E0B),
                icon: Icons.trending_down_rounded,
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
        subtitle: const Text('Toque no card para adicionar no dia e escolher a refeição'),
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
                      (template['name'] ?? template['mealType'] ?? 'Refeição favorita').toString();
                  final mealType = (template['mealType'] ?? '').toString();
                  final items = (template['items'] as List<dynamic>? ?? const [])
                      .whereType<Map>()
                      .map((e) => Map<String, dynamic>.from(e))
                      .toList();
                  final kcal = items.fold<double>(0, (sum, item) => sum + _toDouble(item['calories']));

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
                                  const SizedBox(height: 2),
                                  Text(
                                    mealType,
                                    style: const TextStyle(
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...items.map((item) {
                                    final foodName = (item['foodName'] ?? '-').toString();
                                    final grams = _toDouble(item['quantityGrams']).toStringAsFixed(0);
                                    final itemKcal = _toDouble(item['calories']).toStringAsFixed(0);
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '• $foodName - ${grams}g ($itemKcal kcal)',
                                        style: const TextStyle(color: Color(0xFF475569)),
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
                                      : () => _deleteSavedMealTemplate(template),
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
                              hintText: 'Digite o alimento (busca automática Edamam)...',
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
                              icon: const Icon(Icons.edit_note_rounded, size: 18),
                              label: const Text('Nao encontrou? Cadastre manualmente'),
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
                                border: Border.all(color: const Color(0xFFD6E3FA)),
                              ),
                              child: _foodSuggestions.isEmpty
                                  ? Padding(
                                      padding: const EdgeInsets.all(10),
                                      child: _searchingEdamam
                                          ? const Row(
                                              children: [
                                                SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child: CircularProgressIndicator(strokeWidth: 2),
                                                ),
                                                SizedBox(width: 8),
                                                Text(
                                                  'Buscando na Edamam...',
                                                  style: TextStyle(color: Color(0xFF64748B)),
                                                ),
                                              ],
                                            )
                                          : const Text(
                                              'Nenhum alimento encontrado.',
                                              style: TextStyle(color: Color(0xFF64748B)),
                                            ),
                                    )
                                  : ListView.builder(
                                      shrinkWrap: true,
                                      itemCount: _foodSuggestions.length,
                                      itemBuilder: (_, i) {
                                        final food = _foodSuggestions[i];
                                        final source =
                                            (food['source'] ?? 'edamam').toString().toLowerCase();
                                        return ListTile(
                                          dense: true,
                                          title: Text((food['name'] ?? '').toString()),
                                          subtitle: Text(
                                            '${_toDouble(food['caloriesPer100g']).toStringAsFixed(0)} kcal/100g • '
                                            'P ${_toDouble(food['proteinPer100g']).toStringAsFixed(1)} g • '
                                            'C ${_toDouble(food['carbsPer100g']).toStringAsFixed(1)} g • '
                                            'G ${_toDouble(food['fatPer100g']).toStringAsFixed(1)} g'
                                            '${source == 'local' ? ' • Já cadastrado' : ' • Edamam'}',
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
                      title: 'Quantidade (g)',
                      accent: const Color(0xFF1D4ED8),
                      child: TextField(
                        controller: _quantityCtrl,
                        readOnly: _isPastDay,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(
                          hintText: '0',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: _isPastDay ? null : (_) => setState(() {}),
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
                            .map((m) => DropdownMenuItem(value: m, child: Text(m)))
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
              if (_searchingEdamam)
                const Padding(
                  padding: EdgeInsets.only(top: 10),
                  child: LinearProgressIndicator(minHeight: 3),
                ),
              const SizedBox(height: 14),
              SizedBox(
                width: 240,
                child: ElevatedButton.icon(
                  onPressed: (_savingEntry || _isPastDay) ? null : _addEntry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B4DBA),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: _savingEntry
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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

  List<Widget> _buildMealSections() {
    final mealByType = <String, Map<String, dynamic>>{};
    for (final meal in _meals) {
      final mealType = (meal['mealType'] ?? '').toString().trim();
      if (mealType.isEmpty) continue;
      mealByType[mealType] = meal;
    }

    final sections = <Widget>[];
    final orderedMealTypes = <String>[];

    for (final mealType in _mealTypes) {
      if (!orderedMealTypes.contains(mealType)) {
        orderedMealTypes.add(mealType);
      }
    }
    for (final mealType in mealByType.keys) {
      if (!orderedMealTypes.contains(mealType)) {
        orderedMealTypes.add(mealType);
      }
    }
    for (final mealType in _carryoverByMealType.keys) {
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
            style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  mealType,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 12),
              Column(
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
              ),
              IconButton(
                tooltip: 'Excluir refeição do dia',
                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                onPressed: (_isPastDay || _savingEntry)
                    ? null
                    : () => _deleteMealOfDay(mealType, entries, carryoverEntries),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: includedEntries.isEmpty
                    ? null
                    : () => _saveMealAsFavorite(mealType, includedEntries),
                icon: const Icon(Icons.star_border_rounded),
                label: const Text('Salvar Refeição'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...entries.map((entry) {
            final foodName = (entry['foodName'] ?? '-').toString();
            final grams = _toDouble(entry['quantityGrams']).toStringAsFixed(0);
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
                          '$grams g',
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
                    tooltip: 'Remover item',
                    icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626)),
                    onPressed: _isPastDay ? null : () => _deleteEntry(_toInt(entry['id'])),
                  ),
                ],
              ),
            );
          }),
          if (carryoverEntries.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...carryoverEntries.map((entry) {
              final foodName = (entry['foodName'] ?? '-').toString();
              final grams = _toDouble(entry['quantityGrams']).toStringAsFixed(0);
              final kcal = _toDouble(entry['calories']).toStringAsFixed(0);
              final p = _toDouble(entry['protein']).toStringAsFixed(1);
              final c = _toDouble(entry['carbs']).toStringAsFixed(1);
              final g = _toDouble(entry['fat']).toStringAsFixed(1);

              return Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
                            '$grams g',
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
      'Domingo'
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

  int _toInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  double? _tryParseNumber(String text) {
    return double.tryParse(text.trim().replaceAll(',', '.'));
  }
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
    final cardPadding = compact ? const EdgeInsets.all(12) : const EdgeInsets.all(14);
    final iconSize = compact ? 20.0 : 24.0;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: 200,
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

  const _MetricTipCloud({
    required this.text,
    required this.color,
  });

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
