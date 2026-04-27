import 'package:flutter/material.dart';

import '../core/app_refresh_notifier.dart';
import '../services/auth_service.dart';

class TrainerWorkoutOrganizerView extends StatefulWidget {
  final int trainerId;
  final int studentId;
  final String studentName;
  final List<String> allowedDays;
  final List<Map<String, String>> allowedSlots;

  const TrainerWorkoutOrganizerView({
    super.key,
    required this.trainerId,
    required this.studentId,
    required this.studentName,
    this.allowedDays = const [],
    this.allowedSlots = const [],
  });

  @override
  State<TrainerWorkoutOrganizerView> createState() =>
      _TrainerWorkoutOrganizerViewState();
}

class _TrainerWorkoutOrganizerViewState
    extends State<TrainerWorkoutOrganizerView> {
  static const List<String> _allDays = [
    'Segunda',
    'Terça',
    'Quarta',
    'Quinta',
    'Sexta',
    'Sábado',
    'Domingo',
  ];

  static const List<String> _exerciseCategories = [
    'Máquina',
    'Halteres',
    'Core',
    'Aeróbico',
    'Mobilidade',
    'Funcional',
    'Alongamento',
    'Categoria livre',
  ];

  static const Map<String, int> _dayOrder = {
    'Segunda': 1,
    'Terça': 2,
    'Quarta': 3,
    'Quinta': 4,
    'Sexta': 5,
    'Sábado': 6,
    'Domingo': 7,
  };

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _favoriteNameCtrl = TextEditingController();
  final TextEditingController _customNameCtrl = TextEditingController();

  bool _loading = true;
  bool _savingPlan = false;
  bool _savingFavorite = false;
  bool _savingCustom = false;
  final Set<String> _savingPlanCardFavoriteKeys = {};
  final Set<String> _hiddenBaseExerciseKeys = {};
  final Set<int> _cloningFavoriteIds = {};

  String _selectedDay = 'Segunda';
  String _selectedTime = '';
  int? _editingPlanId;
  int? _editingFavoriteId;
  int? _editingCustomId;
  String _selectedCustomCategory = 'Categoria livre';

  List<Map<String, dynamic>> _baseCatalog = [];
  List<Map<String, dynamic>> _customCatalog = [];
  List<Map<String, dynamic>> _favorites = [];
  List<Map<String, dynamic>> _plans = [];

  final Map<String, Map<String, String>> _selectedExercises = {};

  void _onGlobalRefresh() {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _searchCtrl.clear();
    setState(() {
      _editingPlanId = null;
      _editingFavoriteId = null;
      _editingCustomId = null;
      _selectedExercises.clear();
      _selectedDay = _dayOptions.first;
      final times = _timeOptionsForSelectedDay;
      _selectedTime = times.isNotEmpty ? times.first : '';
    });
    _loadData();
  }

  List<String> get _dayOptions {
    final allowed =
        widget.allowedDays
            .map((d) => d.trim())
            .where((d) => _allDays.contains(d))
            .toSet()
            .toList()
          ..sort((a, b) => (_dayOrder[a] ?? 99).compareTo(_dayOrder[b] ?? 99));

    if (allowed.isEmpty) {
      return List<String>.from(_allDays);
    }
    return allowed;
  }

  List<Map<String, String>> get _slotOptions {
    final unique = <String, Map<String, String>>{};

    for (final slot in widget.allowedSlots) {
      final day = (slot['dayName'] ?? '').trim();
      final time = (slot['time'] ?? '').trim();
      if (!_allDays.contains(day)) continue;
      final key = '$day|$time';
      unique[key] = {
        'dayName': day,
        'time': time,
        'dateLabel': (slot['dateLabel'] ?? '').trim(),
        'dateIso': (slot['dateIso'] ?? '').trim(),
      };
    }

    if (unique.isEmpty) {
      for (final day in _dayOptions) {
        final key = '$day|';
        unique[key] = {
          'dayName': day,
          'time': '',
          'dateLabel': '',
          'dateIso': '',
        };
      }
    }

    final list = unique.values.toList();
    list.sort((a, b) {
      final dayCmp = (_dayOrder[a['dayName']] ?? 99).compareTo(
        _dayOrder[b['dayName']] ?? 99,
      );
      if (dayCmp != 0) return dayCmp;
      return (a['time'] ?? '').compareTo(b['time'] ?? '');
    });
    return list;
  }

  List<String> get _timeOptionsForSelectedDay {
    final times = _slotOptions
        .where((slot) => (slot['dayName'] ?? '') == _selectedDay)
        .map((slot) => (slot['time'] ?? '').trim())
        .where((time) => time.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    return times;
  }

  List<Map<String, dynamic>> get _catalog {
    final map = <String, Map<String, dynamic>>{};
    for (final item in _baseCatalog) {
      final name = (item['name'] ?? '').toString().trim();
      final category = (item['category'] ?? 'Outros').toString().trim();
      if (name.isEmpty) continue;
      final key = _exerciseKey(name, category);
      if (_hiddenBaseExerciseKeys.contains(key)) continue;
      map[key] = {'name': name, 'category': category, 'isCustom': false};
    }

    for (final item in _customCatalog) {
      final name = (item['name'] ?? '').toString().trim();
      final category = (item['category'] ?? 'Personalizado').toString().trim();
      if (name.isEmpty) continue;
      map[_exerciseKey(name, category)] = {
        ...item,
        'name': name,
        'category': category,
        'isCustom': true,
      };
    }

    final list = map.values.toList();
    list.sort((a, b) {
      final aCustom = a['isCustom'] == true ? 1 : 0;
      final bCustom = b['isCustom'] == true ? 1 : 0;
      if (aCustom != bCustom) return bCustom.compareTo(aCustom);
      return (a['name'] ?? '').toString().compareTo(
        (b['name'] ?? '').toString(),
      );
    });
    return list;
  }

  List<String> get _customCategoryOptions {
    final set = <String>{..._exerciseCategories};
    for (final item in [..._baseCatalog, ..._customCatalog]) {
      final category = (item['category'] ?? '').toString().trim();
      if (category.isNotEmpty) {
        set.add(category);
      }
    }
    final list = set.toList()..sort();
    if (_selectedCustomCategory.isNotEmpty &&
        !list.contains(_selectedCustomCategory)) {
      list.insert(0, _selectedCustomCategory);
    }
    return list;
  }

  @override
  void initState() {
    super.initState();
    AppRefreshNotifier.signal.addListener(_onGlobalRefresh);
    _selectedDay = _dayOptions.first;
    _selectedTime = _timeOptionsForSelectedDay.isNotEmpty
        ? _timeOptionsForSelectedDay.first
        : '';
    _selectedCustomCategory = _exerciseCategories.first;
    _loadData();
  }

  @override
  void dispose() {
    AppRefreshNotifier.signal.removeListener(_onGlobalRefresh);
    _searchCtrl.dispose();
    _favoriteNameCtrl.dispose();
    _customNameCtrl.dispose();
    super.dispose();
  }

  String _planCardKey({
    required int? planId,
    required String dayName,
    String? time,
  }) {
    final idPart = planId?.toString() ?? 'sem-id';
    final timePart = (time ?? '').trim().toLowerCase();
    return '$idPart|${dayName.trim().toLowerCase()}|$timePart';
  }

  String _normalizeDayName(String raw) {
    return raw
        .toLowerCase()
        .replaceAll('á', 'a')
        .replaceAll('à', 'a')
        .replaceAll('â', 'a')
        .replaceAll('ã', 'a')
        .replaceAll('é', 'e')
        .replaceAll('ê', 'e')
        .replaceAll('í', 'i')
        .replaceAll('ó', 'o')
        .replaceAll('ô', 'o')
        .replaceAll('õ', 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c')
        .trim();
  }

  String _normalizeTime(String raw) {
    final text = raw.trim();
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return text;
    final hh = (int.tryParse(match.group(1) ?? '') ?? 0)
        .toString()
        .padLeft(2, '0');
    final mm = (int.tryParse(match.group(2) ?? '') ?? 0)
        .toString()
        .padLeft(2, '0');
    return '$hh:$mm';
  }

  String _slotKey(String dayName, String time) {
    return '${_normalizeDayName(dayName)}|${_normalizeTime(time)}';
  }

  String _slotDisplayLabel(String dayName, String time) {
    final safeDay = dayName.trim();
    final safeTime = time.trim();
    if (safeTime.isEmpty) return safeDay;
    return '$safeDay $safeTime';
  }

  List<Map<String, String>> get _approvedSlotOptions {
    final unique = <String, Map<String, String>>{};
    for (final slot in widget.allowedSlots) {
      final day = (slot['dayName'] ?? '').trim();
      final time = (slot['time'] ?? '').trim();
      if (!_allDays.contains(day) || time.isEmpty) continue;
      unique[_slotKey(day, time)] = {
        'dayName': day,
        'time': time,
        'dateLabel': (slot['dateLabel'] ?? '').trim(),
        'dateIso': (slot['dateIso'] ?? '').trim(),
      };
    }

    if (unique.isNotEmpty) {
      final list = unique.values.toList();
      list.sort((a, b) {
        final dayCmp = (_dayOrder[a['dayName']] ?? 99).compareTo(
          _dayOrder[b['dayName']] ?? 99,
        );
        if (dayCmp != 0) return dayCmp;
        return (a['time'] ?? '').compareTo(b['time'] ?? '');
      });
      return list;
    }

    return _slotOptions;
  }

  bool _isOldPlan(Map<String, dynamic> plan) {
    final day = (plan['dayName'] ?? '').toString().trim();
    final time = (plan['time'] ?? '').toString().trim();

    if (day.isEmpty) return false;

    if (widget.allowedSlots.isNotEmpty) {
      final target = _slotKey(day, time);
      for (final slot in widget.allowedSlots) {
        final slotDay = (slot['dayName'] ?? '').trim();
        final slotTime = (slot['time'] ?? '').trim();
        if (slotDay.isEmpty) continue;
        if (slotTime.isEmpty) {
          if (_normalizeDayName(slotDay) == _normalizeDayName(day)) {
            return false;
          }
          continue;
        }
        if (_slotKey(slotDay, slotTime) == target) {
          return false;
        }
      }
      return true;
    }

    if (widget.allowedDays.isNotEmpty) {
      final allowed = widget.allowedDays
          .map(_normalizeDayName)
          .where((d) => d.isNotEmpty)
          .toSet();
      return !allowed.contains(_normalizeDayName(day));
    }

    return false;
  }

  Future<String?> _askFavoriteNameForPlan({
    required String dayName,
    String? time,
  }) async {
    final timeLabel = (time ?? '').trim();
    final defaultName = timeLabel.isEmpty
        ? 'Treino de $dayName'
        : 'Treino de $dayName $timeLabel';
    final controller = TextEditingController(text: defaultName);
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Salvar como favorito'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nome do treino',
                hintText: 'Ex.: Pernas iniciante',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<String?> _askCloneFavoriteName({required String currentName}) async {
    final base = currentName.trim().isEmpty ? 'Favorito' : currentName.trim();
    final controller = TextEditingController(text: '$base (copia)');
    try {
      return await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('Clonar treino favorito'),
            content: TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nome do novo treino',
                hintText: 'Ex.: Treino para iniciantes 2',
                border: OutlineInputBorder(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () =>
                    Navigator.of(dialogContext).pop(controller.text.trim()),
                child: const Text('Clonar'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        AuthService.getWorkoutCatalog(),
        AuthService.getTrainerCustomExercises(widget.trainerId),
        AuthService.getTrainerWorkoutFavorites(widget.trainerId),
        AuthService.getTrainerStudentWorkoutPlans(
          trainerId: widget.trainerId,
          studentId: widget.studentId,
        ),
      ]);

      if (!mounted) return;
      setState(() {
        _baseCatalog = List<Map<String, dynamic>>.from(results[0]);
        _customCatalog = List<Map<String, dynamic>>.from(results[1]);
        _favorites = List<Map<String, dynamic>>.from(results[2]);
        _plans = List<Map<String, dynamic>>.from(results[3]);
        if (!_dayOptions.contains(_selectedDay)) {
          _selectedDay = _dayOptions.first;
        }
        final times = _timeOptionsForSelectedDay;
        if (times.isNotEmpty && !times.contains(_selectedTime)) {
          _selectedTime = times.first;
        }
        if (times.isEmpty) {
          _selectedTime = '';
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    }
  }

  String _exerciseKey(String name, String category) {
    return '${name.trim().toLowerCase()}|${category.trim().toLowerCase()}';
  }

  String _favoriteSignature(List<Map<String, String>> exercises) {
    final keys =
        exercises
            .map((exercise) {
              final name = (exercise['name'] ?? '').trim().toLowerCase();
              final category = (exercise['category'] ?? 'Outros')
                  .trim()
                  .toLowerCase();
              if (name.isEmpty) return '';
              return '$name|$category';
            })
            .where((k) => k.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return keys.join('||');
  }

  bool _hasFavoriteWithSameExercises(
    List<Map<String, String>> exercises, {
    int? ignoreFavoriteId,
  }) {
    final target = _favoriteSignature(exercises);
    if (target.isEmpty) return false;

    for (final favorite in _favorites) {
      final favoriteId = int.tryParse((favorite['id'] ?? '').toString());
      if (ignoreFavoriteId != null && favoriteId == ignoreFavoriteId) {
        continue;
      }

      final currentExercises = _extractExercises(favorite['exercises']);
      if (_favoriteSignature(currentExercises) == target) {
        return true;
      }
    }

    return false;
  }

  Future<Map<String, String>?> _askCatalogEditValues({
    required String initialName,
    required String initialCategory,
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    String selectedCategory = _customCategoryOptions.contains(initialCategory)
        ? initialCategory
        : _customCategoryOptions.first;

    try {
      return await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Editar treino da lista'),
                content: SizedBox(
                  width: 360,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome do treino',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategory,
                        items: _customCategoryOptions
                            .map(
                              (category) => DropdownMenuItem<String>(
                                value: category,
                                child: Text(category),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => selectedCategory = value);
                        },
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Cancelar'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.of(dialogContext).pop({
                        'name': nameCtrl.text.trim(),
                        'category': selectedCategory,
                      });
                    },
                    child: const Text('Salvar'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      nameCtrl.dispose();
    }
  }

  Future<bool> _confirmCatalogDelete({required String exerciseName}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Excluir treino da lista'),
          content: Text('Deseja excluir "$exerciseName" da lista?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB91C1C),
                foregroundColor: Colors.white,
              ),
              child: const Text('Excluir'),
            ),
          ],
        );
      },
    );

    return result == true;
  }

  Future<void> _editCatalogExercise(Map<String, dynamic> item) async {
    final originalName = (item['name'] ?? '').toString().trim();
    final originalCategory = (item['category'] ?? 'Outros').toString().trim();
    final custom = item['isCustom'] == true;

    if (originalName.isEmpty) return;

    final result = await _askCatalogEditValues(
      initialName: originalName,
      initialCategory: originalCategory,
    );
    if (result == null || !mounted) return;

    final newName = (result['name'] ?? '').trim();
    final newCategory = (result['category'] ?? 'Outros').trim();

    if (newName.isEmpty) {
      _showSnack('Informe o nome do treino.', color: const Color(0xFF0B4DBA));
      return;
    }

    try {
      if (custom) {
        final id = int.tryParse((item['id'] ?? '').toString());
        if (id == null) {
          _showSnack(
            'Não foi possível editar esse treino.',
            color: const Color(0xFFEF4444),
          );
          return;
        }

        await AuthService.updateTrainerCustomExercise(
          trainerId: widget.trainerId,
          exerciseId: id,
          name: newName,
          category: newCategory,
        );
      } else {
        await AuthService.createTrainerCustomExercise(
          trainerId: widget.trainerId,
          name: newName,
          category: newCategory,
        );
      }

      final customCatalog = await AuthService.getTrainerCustomExercises(
        widget.trainerId,
      );

      if (!mounted) return;
      setState(() {
        _customCatalog = List<Map<String, dynamic>>.from(customCatalog);

        if (!custom) {
          _hiddenBaseExerciseKeys.add(
            _exerciseKey(originalName, originalCategory),
          );
        }

        final oldKey = _exerciseKey(originalName, originalCategory);
        final oldSelection = _selectedExercises.remove(oldKey);
        if (oldSelection != null) {
          _selectedExercises[_exerciseKey(newName, newCategory)] = {
            'name': newName,
            'category': newCategory,
          };
        }
      });

      _showSnack(
        custom
            ? 'Treino atualizado com sucesso.'
            : 'Treino padrão convertido em personalizado e editado.',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    }
  }

  Future<void> _deleteCatalogExercise(Map<String, dynamic> item) async {
    final name = (item['name'] ?? '').toString().trim();
    final category = (item['category'] ?? 'Outros').toString().trim();
    final custom = item['isCustom'] == true;
    if (name.isEmpty) return;

    final confirmed = await _confirmCatalogDelete(exerciseName: name);
    if (!confirmed || !mounted) return;

    if (custom) {
      final id = int.tryParse((item['id'] ?? '').toString());
      if (id == null) {
        _showSnack(
          'Não foi possível excluir esse treino.',
          color: const Color(0xFFEF4444),
        );
        return;
      }
      await _deleteCustomExercise(id);
      return;
    }

    setState(() {
      _hiddenBaseExerciseKeys.add(_exerciseKey(name, category));
      _selectedExercises.remove(_exerciseKey(name, category));
    });
    _showSnack(
      'Treino padrão removido da lista nesta edição.',
      color: const Color(0xFF0B4DBA),
    );
  }

  List<Map<String, String>> _extractExercises(dynamic raw) {
    final list = <Map<String, String>>[];
    if (raw is! List) return list;

    for (final item in raw) {
      if (item is! Map) continue;
      final name = (item['name'] ?? '').toString().trim();
      final category = (item['category'] ?? 'Outros').toString().trim();
      if (name.isEmpty) continue;
      list.add({
        'name': name,
        'category': category.isEmpty ? 'Outros' : category,
      });
    }

    return list;
  }

  List<Map<String, dynamic>> get _filteredCatalog {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _catalog;

    return _catalog.where((item) {
      final name = (item['name'] ?? '').toString().toLowerCase();
      final category = (item['category'] ?? '').toString().toLowerCase();
      return name.contains(query) || category.contains(query);
    }).toList();
  }

  void _toggleExercise(String name, String category) {
    final key = _exerciseKey(name, category);
    setState(() {
      if (_selectedExercises.containsKey(key)) {
        _selectedExercises.remove(key);
      } else {
        _selectedExercises[key] = {
          'name': name.trim(),
          'category': category.trim().isEmpty ? 'Outros' : category.trim(),
        };
      }
    });
  }

  void _applyExercises(List<Map<String, String>> exercises) {
    final next = <String, Map<String, String>>{};
    for (final exercise in exercises) {
      final name = (exercise['name'] ?? '').trim();
      final category = (exercise['category'] ?? 'Outros').trim();
      if (name.isEmpty) continue;
      final key = _exerciseKey(name, category);
      next[key] = {'name': name, 'category': category};
    }
    setState(() {
      _selectedExercises
        ..clear()
        ..addAll(next);
    });
  }

  Future<void> _savePlan() async {
    if (_selectedExercises.isEmpty) {
      _showSnack(
        'Selecione pelo menos um treino.',
        color: const Color(0xFF0B4DBA),
      );
      return;
    }

    setState(() => _savingPlan = true);
    try {
      final exercises = _selectedExercises.values.toList();

      if (_editingPlanId == null) {
        await AuthService.upsertTrainerStudentWorkoutPlan(
          trainerId: widget.trainerId,
          studentId: widget.studentId,
          dayName: _selectedDay,
          time: _selectedTime,
          exercises: exercises,
        );
      } else {
        await AuthService.updateTrainerStudentWorkoutPlan(
          trainerId: widget.trainerId,
          studentId: widget.studentId,
          planId: _editingPlanId!,
          dayName: _selectedDay,
          time: _selectedTime,
          exercises: exercises,
        );
      }

      await _refreshPlansOnly();

      if (!mounted) return;
      setState(() {
        _editingPlanId = null;
        _selectedExercises.clear();
      });

      _showSnack(
        'Treino do dia salvo com sucesso.',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) setState(() => _savingPlan = false);
    }
  }

  Future<void> _refreshPlansOnly() async {
    final plans = await AuthService.getTrainerStudentWorkoutPlans(
      trainerId: widget.trainerId,
      studentId: widget.studentId,
    );
    if (!mounted) return;
    setState(() {
      _plans = List<Map<String, dynamic>>.from(plans);
    });
  }

  Future<void> _saveFavorite() async {
    final name = _favoriteNameCtrl.text.trim();
    if (name.isEmpty) {
      _showSnack(
        'Informe um nome para o favorito.',
        color: const Color(0xFF0B4DBA),
      );
      return;
    }
    if (_selectedExercises.isEmpty) {
      _showSnack(
        'Selecione exercícios para salvar como favorito.',
        color: const Color(0xFF0B4DBA),
      );
      return;
    }

    setState(() => _savingFavorite = true);
    try {
      final exercises = _selectedExercises.values.toList();
      if (_hasFavoriteWithSameExercises(
        exercises,
        ignoreFavoriteId: _editingFavoriteId,
      )) {
        _showSnack(
          'Esse treino já foi salvo como favorito.',
          color: const Color(0xFF0B4DBA),
        );
        return;
      }

      if (_editingFavoriteId == null) {
        await AuthService.createTrainerWorkoutFavorite(
          trainerId: widget.trainerId,
          name: name,
          exercises: exercises,
        );
      } else {
        await AuthService.updateTrainerWorkoutFavorite(
          trainerId: widget.trainerId,
          favoriteId: _editingFavoriteId!,
          name: name,
          exercises: exercises,
        );
      }

      final favorites = await AuthService.getTrainerWorkoutFavorites(
        widget.trainerId,
      );
      if (!mounted) return;
      setState(() {
        _favorites = List<Map<String, dynamic>>.from(favorites);
        _editingFavoriteId = null;
        _favoriteNameCtrl.clear();
      });

      _showSnack('Favorito salvo com sucesso.', color: const Color(0xFF16A34A));
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) setState(() => _savingFavorite = false);
    }
  }

  Future<void> _saveCustomExercise() async {
    final name = _customNameCtrl.text.trim();
    final category = _selectedCustomCategory.trim().isEmpty
        ? 'Categoria livre'
        : _selectedCustomCategory.trim();

    if (name.isEmpty) {
      _showSnack(
        'Informe o nome do treino personalizado.',
        color: const Color(0xFF0B4DBA),
      );
      return;
    }

    setState(() => _savingCustom = true);
    try {
      if (_editingCustomId == null) {
        await AuthService.createTrainerCustomExercise(
          trainerId: widget.trainerId,
          name: name,
          category: category,
        );
      } else {
        await AuthService.updateTrainerCustomExercise(
          trainerId: widget.trainerId,
          exerciseId: _editingCustomId!,
          name: name,
          category: category,
        );
      }

      final custom = await AuthService.getTrainerCustomExercises(
        widget.trainerId,
      );
      if (!mounted) return;
      setState(() {
        _customCatalog = List<Map<String, dynamic>>.from(custom);
        _editingCustomId = null;
        _customNameCtrl.clear();
        _selectedCustomCategory = _exerciseCategories.first;
      });

      _showSnack(
        'Treino personalizado salvo na lista.',
        color: const Color(0xFF16A34A),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) setState(() => _savingCustom = false);
    }
  }

  Future<void> _deleteCustomExercise(int exerciseId) async {
    try {
      await AuthService.deleteTrainerCustomExercise(
        trainerId: widget.trainerId,
        exerciseId: exerciseId,
      );
      final custom = await AuthService.getTrainerCustomExercises(
        widget.trainerId,
      );
      if (!mounted) return;
      setState(() {
        _customCatalog = List<Map<String, dynamic>>.from(custom);
        if (_editingCustomId == exerciseId) {
          _editingCustomId = null;
          _customNameCtrl.clear();
          _selectedCustomCategory = _exerciseCategories.first;
        }
      });
      _showSnack(
        'Treino personalizado removido.',
        color: const Color(0xFF0B4DBA),
      );
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    }
  }

  Future<void> _deleteFavorite(int favoriteId) async {
    try {
      await AuthService.deleteTrainerWorkoutFavorite(
        trainerId: widget.trainerId,
        favoriteId: favoriteId,
      );
      final favorites = await AuthService.getTrainerWorkoutFavorites(
        widget.trainerId,
      );
      if (!mounted) return;
      setState(() {
        _favorites = List<Map<String, dynamic>>.from(favorites);
        if (_editingFavoriteId == favoriteId) {
          _editingFavoriteId = null;
          _favoriteNameCtrl.clear();
        }
      });
      _showSnack('Favorito removido.', color: const Color(0xFF0B4DBA));
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    }
  }

  Future<void> _cloneFavorite(Map<String, dynamic> favorite) async {
    final favoriteId = int.tryParse((favorite['id'] ?? '').toString());
    if (favoriteId == null) {
      _showSnack(
        'Não foi possível clonar esse favorito.',
        color: const Color(0xFFEF4444),
      );
      return;
    }

    final currentName = (favorite['name'] ?? 'Favorito').toString();
    final clonedName = await _askCloneFavoriteName(currentName: currentName);
    if (!mounted) return;

    final name = (clonedName ?? '').trim();
    if (name.isEmpty) {
      return;
    }

    setState(() => _cloningFavoriteIds.add(favoriteId));
    try {
      await AuthService.cloneTrainerWorkoutFavorite(
        trainerId: widget.trainerId,
        favoriteId: favoriteId,
        name: name,
      );

      final favorites = await AuthService.getTrainerWorkoutFavorites(
        widget.trainerId,
      );
      if (!mounted) return;
      setState(() {
        _favorites = List<Map<String, dynamic>>.from(favorites);
      });
      _showSnack('Treino clonado com sucesso.', color: const Color(0xFF16A34A));
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) {
        setState(() => _cloningFavoriteIds.remove(favoriteId));
      }
    }
  }

  Future<void> _deletePlan(int planId) async {
    try {
      await AuthService.deleteTrainerStudentWorkoutPlan(
        trainerId: widget.trainerId,
        studentId: widget.studentId,
        planId: planId,
      );
      await _refreshPlansOnly();
      if (!mounted) return;
      if (_editingPlanId == planId) {
        setState(() {
          _editingPlanId = null;
          _selectedExercises.clear();
        });
      }
      _showSnack('Treino do dia removido.', color: const Color(0xFF0B4DBA));
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    }
  }

  void _startEditPlan(Map<String, dynamic> plan) {
    final id = int.tryParse((plan['id'] ?? '').toString());
    final day = (plan['dayName'] ?? '').toString().trim();
    final time = (plan['time'] ?? '').toString().trim();
    final exercises = _extractExercises(plan['exercises']);

    setState(() {
      _editingPlanId = id;
      if (_dayOptions.contains(day)) {
        _selectedDay = day;
      }
      final availableTimes = _timeOptionsForSelectedDay;
      if (time.isNotEmpty && (availableTimes.isEmpty || availableTimes.contains(time))) {
        _selectedTime = time;
      } else if (availableTimes.isNotEmpty) {
        _selectedTime = availableTimes.first;
      } else {
        _selectedTime = '';
      }
    });
    _applyExercises(exercises);
  }

  void _startEditFavorite(Map<String, dynamic> favorite) {
    final id = int.tryParse((favorite['id'] ?? '').toString());
    final name = (favorite['name'] ?? '').toString();
    final exercises = _extractExercises(favorite['exercises']);

    setState(() {
      _editingFavoriteId = id;
      _favoriteNameCtrl.text = name;
    });
    _applyExercises(exercises);
  }

  Future<void> _savePlanAsFavorite(Map<String, dynamic> plan) async {
    final id = int.tryParse((plan['id'] ?? '').toString());
    final day = (plan['dayName'] ?? '').toString().trim();
    final time = (plan['time'] ?? '').toString().trim();
    final key = _planCardKey(planId: id, dayName: day, time: time);
    final exercises = _extractExercises(plan['exercises']);

    if (exercises.isEmpty) {
      _showSnack(
        'Não há exercícios neste treino para salvar.',
        color: const Color(0xFF0B4DBA),
      );
      return;
    }

    if (_hasFavoriteWithSameExercises(exercises)) {
      _showSnack(
        'Esse treino já foi salvo como favorito.',
        color: const Color(0xFF0B4DBA),
      );
      return;
    }

    final favoriteName = await _askFavoriteNameForPlan(
      dayName: day.isEmpty ? _selectedDay : day,
      time: time,
    );
    if (!mounted) return;

    final name = (favoriteName ?? '').trim();
    if (name.isEmpty) {
      return;
    }

    setState(() => _savingPlanCardFavoriteKeys.add(key));
    try {
      await AuthService.createTrainerWorkoutFavorite(
        trainerId: widget.trainerId,
        name: name,
        exercises: exercises,
      );

      final favorites = await AuthService.getTrainerWorkoutFavorites(
        widget.trainerId,
      );
      if (!mounted) return;
      setState(() {
        _favorites = List<Map<String, dynamic>>.from(favorites);
      });
      _showSnack('Treino salvo como favorito.', color: const Color(0xFF16A34A));
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    } finally {
      if (mounted) {
        setState(() => _savingPlanCardFavoriteKeys.remove(key));
      }
    }
  }

  Future<Map<String, String>?> _askApplyFavoriteSlot({
    required String favoriteName,
  }) async {
    final options = _approvedSlotOptions;
    if (options.isEmpty) {
      _showSnack(
        'Nenhum dia/horário aprovado disponível para aplicar o favorito.',
        color: const Color(0xFFEF4444),
      );
      return null;
    }

    Map<String, String> selected = options.first;
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Aplicar favorito'),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Escolha em qual dia e horário aprovado deseja aplicar "$favoriteName".',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _slotKey(
                        selected['dayName'] ?? '',
                        selected['time'] ?? '',
                      ),
                      items: options.map((slot) {
                        final key = _slotKey(
                          slot['dayName'] ?? '',
                          slot['time'] ?? '',
                        );
                        final dateLabel = (slot['dateLabel'] ?? '').trim();
                        final base = _slotDisplayLabel(
                          slot['dayName'] ?? '',
                          slot['time'] ?? '',
                        );
                        final label = dateLabel.isEmpty
                            ? base
                            : '$base ($dateLabel)';
                        return DropdownMenuItem<String>(
                          value: key,
                          child: Text(label),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        final picked = options.firstWhere(
                          (slot) =>
                              _slotKey(
                                slot['dayName'] ?? '',
                                slot['time'] ?? '',
                              ) ==
                              value,
                        );
                        setDialogState(() => selected = picked);
                      },
                      decoration: const InputDecoration(
                        labelText: 'Dia e horário',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.of(dialogContext).pop(selected),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );

    return result;
  }

  Future<void> _applyFavorite(Map<String, dynamic> favorite) async {
    final favoriteName = (favorite['name'] ?? 'Favorito').toString().trim();
    final favoriteExercises = _extractExercises(favorite['exercises']);
    if (favoriteExercises.isEmpty) {
      _showSnack(
        'Este favorito não possui exercícios para aplicar.',
        color: const Color(0xFFEF4444),
      );
      return;
    }

    final target = await _askApplyFavoriteSlot(favoriteName: favoriteName);
    if (target == null || !mounted) return;

    final targetDay = (target['dayName'] ?? '').trim();
    final targetTime = (target['time'] ?? '').trim();
    final targetKey = _slotKey(targetDay, targetTime);

    Map<String, dynamic>? existingPlan;
    for (final plan in _plans) {
      final day = (plan['dayName'] ?? '').toString().trim();
      final time = (plan['time'] ?? '').toString().trim();
      if (_slotKey(day, time) == targetKey) {
        existingPlan = plan;
        break;
      }
    }

    final currentExercises = existingPlan == null
      ? <Map<String, String>>[]
      : _extractExercises(existingPlan['exercises']);
    final replacementExercises = favoriteExercises;

    try {
      if (existingPlan == null) {
        await AuthService.upsertTrainerStudentWorkoutPlan(
          trainerId: widget.trainerId,
          studentId: widget.studentId,
          dayName: targetDay,
          time: targetTime,
          exercises: replacementExercises,
        );
      } else {
        final planId = int.tryParse((existingPlan['id'] ?? '').toString());
        if (planId == null) {
          _showSnack(
            'Não foi possível atualizar o treino desse horário.',
            color: const Color(0xFFEF4444),
          );
          return;
        }

        await AuthService.updateTrainerStudentWorkoutPlan(
          trainerId: widget.trainerId,
          studentId: widget.studentId,
          planId: planId,
          dayName: targetDay,
          time: targetTime,
          exercises: replacementExercises,
        );
      }

      await _refreshPlansOnly();

      if (!mounted) return;
      setState(() {
        if (_dayOptions.contains(targetDay)) {
          _selectedDay = targetDay;
        }
        _selectedTime = targetTime;
      });
      _applyExercises(replacementExercises);

      final targetLabel = _slotDisplayLabel(targetDay, targetTime);
      final changed = _favoriteSignature(currentExercises) !=
          _favoriteSignature(replacementExercises);
      if (existingPlan != null && !changed) {
        _showSnack(
          'O favorito já estava aplicado em $targetLabel.',
          color: const Color(0xFF0B4DBA),
        );
      } else if (existingPlan != null && changed) {
        _showSnack(
          'Favorito aplicado em $targetLabel substituindo o treino anterior.',
          color: const Color(0xFF16A34A),
        );
      } else {
        _showSnack(
          'Favorito aplicado e treino criado em $targetLabel.',
          color: const Color(0xFF16A34A),
        );
      }
    } catch (e) {
      _showSnack(
        e.toString().replaceFirst('Exception: ', ''),
        color: const Color(0xFFEF4444),
      );
    }
  }

  void _showSnack(String text, {required Color color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final customCount = _customCatalog.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FB),
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Voltar',
        ),
        title: const Text('Organizar treino'),
        backgroundColor: const Color(0xFF0B4DBA),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B4DBA)),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: const Color(0xFFDBEAFE),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.assignment_rounded,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.studentName,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  const Text(
                                    'Monte o treino por dia e horário permitidos do plano',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'Dias e horários permitidos',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _slotOptions
                              .map(
                                (slot) => Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFECFDF3),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: const Color(0xFF86EFAC),
                                    ),
                                  ),
                                  child: Text(
                                    (slot['time'] ?? '').toString().trim().isEmpty
                                        ? (slot['dayName'] ?? '').toString()
                                        : '${slot['dayName']} ${slot['time']}',
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF166534),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Montagem do treino',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 40,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _dayOptions.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 6),
                            itemBuilder: (_, index) {
                              final day = _dayOptions[index];
                              final selected = _selectedDay == day;
                              return ChoiceChip(
                                label: Text(day),
                                selected: selected,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedDay = day;
                                    final times = _timeOptionsForSelectedDay;
                                    if (times.isNotEmpty) {
                                      _selectedTime = times.first;
                                    } else {
                                      _selectedTime = '';
                                    }
                                  });
                                },
                                selectedColor: const Color(0xFFDBEAFE),
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? const Color(0xFF1D4ED8)
                                      : const Color(0xFF334155),
                                ),
                              );
                            },
                          ),
                        ),
                        if (_timeOptionsForSelectedDay.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 40,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: _timeOptionsForSelectedDay.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 6),
                              itemBuilder: (_, index) {
                                final time = _timeOptionsForSelectedDay[index];
                                final selected = _selectedTime == time;
                                return ChoiceChip(
                                  label: Text(time),
                                  selected: selected,
                                  onSelected: (_) {
                                    setState(() => _selectedTime = time);
                                  },
                                  selectedColor: const Color(0xFFECFDF3),
                                  labelStyle: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: selected
                                        ? const Color(0xFF166534)
                                        : const Color(0xFF334155),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            hintText:
                                'Pesquisar treino por nome ou categoria...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchCtrl.text.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.close_rounded),
                                  ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            isDense: true,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFDE68A)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.add_circle_outline_rounded,
                                    size: 17,
                                    color: Color(0xFF92400E),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Cadastrar treino personalizado ($customCount)',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF92400E),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final isCompact = constraints.maxWidth < 560;

                                  final categoryDropdown =
                                      DropdownButtonFormField<String>(
                                        initialValue: _selectedCustomCategory,
                                        items: _customCategoryOptions
                                            .map(
                                              (category) =>
                                                  DropdownMenuItem<String>(
                                                    value: category,
                                                    child: Text(category),
                                                  ),
                                            )
                                            .toList(),
                                        onChanged: (value) {
                                          if (value == null) return;
                                          setState(
                                            () =>
                                                _selectedCustomCategory = value,
                                          );
                                        },
                                        decoration: const InputDecoration(
                                          labelText: 'Categoria',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                        ),
                                      );

                                  if (isCompact) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        TextField(
                                          controller: _customNameCtrl,
                                          decoration: const InputDecoration(
                                            hintText: 'Nome do treino',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        categoryDropdown,
                                      ],
                                    );
                                  }

                                  return Row(
                                    children: [
                                      Expanded(
                                        child: TextField(
                                          controller: _customNameCtrl,
                                          decoration: const InputDecoration(
                                            hintText: 'Nome do treino',
                                            border: OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 180,
                                        child: categoryDropdown,
                                      ),
                                    ],
                                  );
                                },
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    onPressed: _savingCustom
                                        ? null
                                        : _saveCustomExercise,
                                    icon: _savingCustom
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.save_rounded,
                                            size: 16,
                                          ),
                                    label: Text(
                                      _editingCustomId == null
                                          ? 'Salvar na lista'
                                          : 'Atualizar treino',
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFD97706),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                  if (_editingCustomId != null) ...[
                                    const SizedBox(width: 8),
                                    OutlinedButton(
                                      onPressed: () {
                                        setState(() {
                                          _editingCustomId = null;
                                          _customNameCtrl.clear();
                                          _selectedCustomCategory =
                                              _exerciseCategories.first;
                                        });
                                      },
                                      child: const Text('Cancelar edição'),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Lista de treinos selecionáveis',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_selectedExercises.length} treino(s) selecionado(s)',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 320),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: _filteredCatalog.isEmpty
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(20),
                                    child: Text(
                                      'Nenhum treino encontrado na pesquisa.',
                                      style: TextStyle(color: Colors.black45),
                                    ),
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _filteredCatalog.length,
                                  separatorBuilder: (_, __) => const Divider(
                                    height: 1,
                                    color: Color(0xFFE2E8F0),
                                  ),
                                  itemBuilder: (_, index) {
                                    final item = _filteredCatalog[index];
                                    final name = (item['name'] ?? '')
                                        .toString();
                                    final category =
                                        (item['category'] ?? 'Outros')
                                            .toString();
                                    final custom = item['isCustom'] == true;
                                    final selected = _selectedExercises
                                        .containsKey(
                                          _exerciseKey(name, category),
                                        );

                                    return ListTile(
                                      dense: true,
                                      onTap: () =>
                                          _toggleExercise(name, category),
                                      leading: Checkbox(
                                        value: selected,
                                        onChanged: (_) =>
                                            _toggleExercise(name, category),
                                      ),
                                      title: Text(
                                        name,
                                        style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Row(
                                        children: [
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: custom
                                                      ? const Color(0xFFFEF3C7)
                                                      : const Color(0xFFEFF6FF),
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        999,
                                                      ),
                                                ),
                                                child: Text(
                                                  category,
                                                  style: TextStyle(
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: custom
                                                        ? const Color(
                                                            0xFF92400E,
                                                          )
                                                        : const Color(
                                                            0xFF1D4ED8,
                                                          ),
                                                  ),
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () =>
                                                    _editCatalogExercise(item),
                                                child: const Text(
                                                  'Editar',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFF0B4DBA),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              GestureDetector(
                                                onTap: () =>
                                                    _deleteCatalogExercise(
                                                      item,
                                                    ),
                                                child: const Text(
                                                  'Excluir',
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: Color(0xFFB91C1C),
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                        if (_selectedExercises.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: _selectedExercises.values
                                .map(
                                  (ex) => Chip(
                                    label: Text(
                                      '${ex['name']} (${ex['category']})',
                                    ),
                                    onDeleted: () => _toggleExercise(
                                      ex['name'] ?? '',
                                      ex['category'] ?? 'Outros',
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _selectedExercises.clear();
                                  _editingPlanId = null;
                                });
                              },
                              icon: const Icon(
                                Icons.restart_alt_rounded,
                                size: 16,
                              ),
                              label: const Text('Limpar seleção'),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _savingPlan ? null : _savePlan,
                                icon: _savingPlan
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.save_rounded, size: 16),
                                label: Text(
                                  _editingPlanId == null
                                    ? _selectedTime.trim().isEmpty
                                      ? 'Salvar treino de $_selectedDay'
                                      : 'Salvar treino de $_selectedDay $_selectedTime'
                                    : _selectedTime.trim().isEmpty
                                      ? 'Atualizar treino de $_selectedDay'
                                      : 'Atualizar treino de $_selectedDay $_selectedTime',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0B4DBA),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Favoritos do personal',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _favoriteNameCtrl,
                          decoration: InputDecoration(
                            hintText:
                                'Nome do favorito (ex.: Pernas iniciante)',
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _savingFavorite
                                    ? null
                                    : _saveFavorite,
                                icon: _savingFavorite
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(
                                        Icons.favorite_rounded,
                                        size: 16,
                                      ),
                                label: Text(
                                  _editingFavoriteId == null
                                      ? 'Salvar favorito'
                                      : 'Atualizar favorito',
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFFD97706),
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                            if (_editingFavoriteId != null) ...[
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: () {
                                  setState(() {
                                    _editingFavoriteId = null;
                                    _favoriteNameCtrl.clear();
                                  });
                                },
                                child: const Text('Cancelar edição'),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (_favorites.isEmpty)
                          const Text(
                            'Nenhum favorito salvo ainda.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.black54,
                            ),
                          )
                        else
                          Column(
                            children: _favorites.map((favorite) {
                              final id = int.tryParse(
                                (favorite['id'] ?? '').toString(),
                              );
                              final name = (favorite['name'] ?? 'Favorito')
                                  .toString();
                              final exercises = _extractExercises(
                                favorite['exercises'],
                              );
                              final cloning =
                                  id != null &&
                                  _cloningFavoriteIds.contains(id);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFFBEB),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: const Color(0xFFFDE68A),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              Text(
                                                '${exercises.length} exercício(s)',
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: Colors.black54,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              _applyFavorite(favorite),
                                          child: const Text('Aplicar'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              _startEditFavorite(favorite),
                                          child: const Text('Editar'),
                                        ),
                                        TextButton(
                                          onPressed: id == null || cloning
                                              ? null
                                              : () => _cloneFavorite(favorite),
                                          child: cloning
                                              ? const SizedBox(
                                                  width: 14,
                                                  height: 14,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Text('Clonar'),
                                        ),
                                        IconButton(
                                          onPressed: id == null
                                              ? null
                                              : () => _deleteFavorite(id),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                            color: Color(0xFFB91C1C),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (exercises.isNotEmpty) ...[
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 6,
                                        children: exercises
                                            .map(
                                              (ex) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 5,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFF8FAFC,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: const Color(
                                                      0xFFE2E8F0,
                                                    ),
                                                  ),
                                                ),
                                                child: Text(
                                                  '${ex['name']} (${ex['category']})',
                                                  style: const TextStyle(
                                                    fontSize: 11.5,
                                                    color: Colors.black87,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Treinos cadastrados do aluno (por dia e horário)',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (_plans.isEmpty)
                          const Text(
                            'Nenhum treino cadastrado para este aluno.',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.black54,
                            ),
                          )
                        else
                          Column(
                            children: _plans.map((plan) {
                              final id = int.tryParse(
                                (plan['id'] ?? '').toString(),
                              );
                              final day = (plan['dayName'] ?? '').toString();
                              final time = (plan['time'] ?? '').toString().trim();
                              final exercises = _extractExercises(
                                plan['exercises'],
                              );
                              final isOldPlan = _isOldPlan(plan);
                              final planCardKey = _planCardKey(
                                planId: id,
                                dayName: day,
                                time: (plan['time'] ?? '').toString(),
                              );
                              final savingCardFavorite =
                                  _savingPlanCardFavoriteKeys.contains(
                                    planCardKey,
                                  );
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isOldPlan
                                      ? const Color(0xFFF8FAFC)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isOldPlan
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFDBEAFE),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            day,
                                            style: const TextStyle(
                                              color: Color(0xFF1D4ED8),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11.5,
                                            ),
                                          ),
                                        ),
                                        if (time.isNotEmpty) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFECFDF3),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              time,
                                              style: const TextStyle(
                                                color: Color(0xFF166534),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                        if (isOldPlan) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFE2E8F0),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: const Text(
                                              'Treino antigo',
                                              style: TextStyle(
                                                color: Color(0xFF334155),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 11.5,
                                              ),
                                            ),
                                          ),
                                        ],
                                        const Spacer(),
                                        TextButton(
                                          onPressed: isOldPlan
                                              ? null
                                              : () => _startEditPlan(plan),
                                          child: const Text('Editar'),
                                        ),
                                        IconButton(
                                          onPressed: id == null
                                              ? null
                                              : () => _deletePlan(id),
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 18,
                                            color: Color(0xFFB91C1C),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: exercises
                                          .map(
                                            (ex) => Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 5,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: isOldPlan
                                                    ? const Color(0xFFE2E8F0)
                                                    : const Color(0xFFF1F5F9),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                border: Border.all(
                                                  color: const Color(
                                                    0xFFE2E8F0,
                                                  ),
                                                ),
                                              ),
                                              child: Text(
                                                '${ex['name']} (${ex['category']})',
                                                style: const TextStyle(
                                                  fontSize: 11.5,
                                                  color: Color(0xFF334155),
                                                ),
                                              ),
                                            ),
                                          )
                                          .toList(),
                                    ),
                                    if (isOldPlan) ...[
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Este treino pertence a um plano anterior. Você pode excluir ou salvar como favorito.',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: Color(0xFF64748B),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: ElevatedButton.icon(
                                        onPressed: savingCardFavorite
                                            ? null
                                            : () => _savePlanAsFavorite(plan),
                                        icon: savingCardFavorite
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.favorite_rounded,
                                                size: 16,
                                              ),
                                        label: const Text(
                                          'Salvar como favorito',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFFD97706,
                                          ),
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
