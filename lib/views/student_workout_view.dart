import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/auth_service.dart';

class StudentWorkoutView extends StatefulWidget {
  final int studentId;
  final int trainerId;
  final String trainerName;

  const StudentWorkoutView({
    super.key,
    required this.studentId,
    required this.trainerId,
    required this.trainerName,
  });

  @override
  State<StudentWorkoutView> createState() => _StudentWorkoutViewState();
}

class _StudentWorkoutViewState extends State<StudentWorkoutView> {
  static const String _allPlansExportKey = '__ALL_PLANS__';
  bool _loading = true;
  List<Map<String, dynamic>> _plans = [];
  final Set<String> _exportingPlanKeys = {};
  final Set<String> _expandedDays = {};
  final Set<String> _expandedTimes = {};

  static const Map<String, int> _dayOrder = {
    'Segunda': 1,
    'Terça': 2,
    'Quarta': 3,
    'Quinta': 4,
    'Sexta': 5,
    'Sábado': 6,
    'Domingo': 7,
  };

  @override
  void initState() {
    super.initState();
    _loadPlans();
  }

  Future<void> _loadPlans() async {
    setState(() => _loading = true);
    try {
      final plans = await AuthService.getStudentWorkoutPlansByTrainer(
        studentId: widget.studentId,
        trainerId: widget.trainerId,
      );
      if (!mounted) return;
      setState(() {
        _plans = List<Map<String, dynamic>>.from(plans);
        _initializeExpandedSections();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
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

  String _weekdayToPt(int weekday) {
    switch (weekday) {
      case DateTime.monday:
        return 'Segunda';
      case DateTime.tuesday:
        return 'Terça';
      case DateTime.wednesday:
        return 'Quarta';
      case DateTime.thursday:
        return 'Quinta';
      case DateTime.friday:
        return 'Sexta';
      case DateTime.saturday:
        return 'Sábado';
      case DateTime.sunday:
        return 'Domingo';
      default:
        return '';
    }
  }

  Map<String, Map<String, List<Map<String, dynamic>>>> _groupPlansByDayAndTime() {
    final grouped = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (final plan in _plans) {
      final day = (plan['dayName'] ?? 'Dia').toString().trim();
      final time = (plan['time'] ?? '').toString().trim();
      if (day.isEmpty) continue;
      grouped.putIfAbsent(day, () => <String, List<Map<String, dynamic>>>{});
      grouped[day]!.putIfAbsent(time, () => <Map<String, dynamic>>[]);
      grouped[day]![time]!.add(plan);
    }

    final sortedDays = grouped.keys.toList()
      ..sort((a, b) => (_dayOrder[a] ?? 99).compareTo(_dayOrder[b] ?? 99));

    final sortedGrouped = <String, Map<String, List<Map<String, dynamic>>>>{};
    for (final day in sortedDays) {
      final times = grouped[day]!.keys.toList()
        ..sort((a, b) {
          if (a.isEmpty && b.isEmpty) return 0;
          if (a.isEmpty) return 1;
          if (b.isEmpty) return -1;
          return a.compareTo(b);
        });
      final perTime = <String, List<Map<String, dynamic>>>{};
      for (final time in times) {
        perTime[time] = grouped[day]![time]!;
      }
      sortedGrouped[day] = perTime;
    }

    return sortedGrouped;
  }

  void _initializeExpandedSections() {
    final grouped = _groupPlansByDayAndTime();
    if (grouped.isEmpty) {
      _expandedDays.clear();
      _expandedTimes.clear();
      return;
    }

    final todayDay = _weekdayToPt(DateTime.now().weekday);
    final initialDay = grouped.containsKey(todayDay)
        ? todayDay
        : grouped.keys.first;
    _expandedDays
      ..clear()
      ..add(initialDay);

    final initialTimes = grouped[initialDay]!.keys.toList();
    if (initialTimes.isNotEmpty) {
      final firstTime = initialTimes.first;
      _expandedTimes
        ..clear()
        ..add('$initialDay|$firstTime');
    } else {
      _expandedTimes.clear();
    }
  }

  Future<Uint8List> _buildPlanPdf(Map<String, dynamic> plan) async {
    final pdf = pw.Document();
    final dayName = (plan['dayName'] ?? 'Dia').toString();
    final time = (plan['time'] ?? '').toString().trim();
    final exercises = _extractExercises(plan['exercises']);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'FitMatch - Treino do Dia',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Text('Personal: ${widget.trainerName}'),
              pw.Text('Dia: $dayName'),
              if (time.isNotEmpty) pw.Text('Horário: $time'),
              pw.SizedBox(height: 14),
              pw.Text(
                'Exercícios',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 8),
              ...exercises.asMap().entries.map(
                (entry) => pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Text(
                    '${entry.key + 1}. ${entry.value['name']} (${entry.value['category']})',
                    style: const pw.TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );

    return pdf.save();
  }

  String _planExportKey(Map<String, dynamic> plan) {
    final id = (plan['id'] ?? '').toString();
    final day = (plan['dayName'] ?? '').toString().trim().toLowerCase();
    final time = (plan['time'] ?? '').toString().trim().toLowerCase();
    return '$id|$day|$time';
  }

  void _showErrorSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFEF4444),
      ),
    );
  }

  Future<void> _printPlan(Map<String, dynamic> plan) async {
    final key = _planExportKey(plan);
    if (_exportingPlanKeys.contains(key)) return;

    setState(() => _exportingPlanKeys.add(key));
    try {
      final bytes = await _buildPlanPdf(plan);
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (_) {
      _showErrorSnack('Não foi possível abrir a impressão deste treino.');
    } finally {
      if (mounted) {
        setState(() => _exportingPlanKeys.remove(key));
      }
    }
  }

  Future<void> _downloadPlan(Map<String, dynamic> plan) async {
    final key = _planExportKey(plan);
    if (_exportingPlanKeys.contains(key)) return;

    setState(() => _exportingPlanKeys.add(key));
    try {
      final bytes = await _buildPlanPdf(plan);
      final dayName = (plan['dayName'] ?? 'dia').toString().toLowerCase();
        final time = (plan['time'] ?? '').toString().trim().toLowerCase();
      final safeDay = dayName
          .replaceAll(' ', '_')
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
          .replaceAll('ç', 'c');
      final safeTime = time
          .replaceAll(':', '_')
          .replaceAll(' ', '_');

      await Printing.sharePdf(
        bytes: bytes,
        filename: safeTime.isEmpty
            ? 'treino_$safeDay.pdf'
            : 'treino_${safeDay}_$safeTime.pdf',
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      _showErrorSnack('A exportação demorou demais. Tente novamente.');
    } catch (_) {
      _showErrorSnack('Não foi possível baixar este treino agora.');
    } finally {
      if (mounted) {
        setState(() => _exportingPlanKeys.remove(key));
      }
    }
  }

  Future<Uint8List> _buildAllPlansPdf() async {
    final pdf = pw.Document();
    final grouped = _groupPlansByDayAndTime();

    final blocks = <pw.Widget>[];
    grouped.forEach((dayName, perTime) {
      blocks.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
          child: pw.Text(
            dayName,
            style: pw.TextStyle(
              fontSize: 16,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ),
      );

      perTime.forEach((time, plansAtTime) {
        final exercises = <Map<String, String>>[];
        for (final plan in plansAtTime) {
          exercises.addAll(_extractExercises(plan['exercises']));
        }

        blocks.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6, bottom: 4),
            child: pw.Text(
              time.isEmpty ? 'Sem horário' : 'Horário: $time',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        );

        if (exercises.isEmpty) {
          blocks.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text('Nenhum exercício cadastrado.'),
            ),
          );
        } else {
          for (int i = 0; i < exercises.length; i++) {
            final ex = exercises[i];
            blocks.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Text(
                  '${i + 1}. ${ex['name']} (${ex['category']})',
                  style: const pw.TextStyle(fontSize: 11.5),
                ),
              ),
            );
          }
        }
      });
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Text(
            'FitMatch - Treino Completo',
            style: pw.TextStyle(
              fontSize: 20,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Personal: ${widget.trainerName}'),
          pw.SizedBox(height: 12),
          ...blocks,
        ],
      ),
    );

    return pdf.save();
  }

  Future<void> _printAllPlans() async {
    if (_exportingPlanKeys.contains(_allPlansExportKey)) return;
    setState(() => _exportingPlanKeys.add(_allPlansExportKey));
    try {
      final bytes = await _buildAllPlansPdf();
      await Printing.layoutPdf(onLayout: (_) async => bytes);
    } catch (_) {
      _showErrorSnack('Não foi possível imprimir todos os treinos agora.');
    } finally {
      if (mounted) {
        setState(() => _exportingPlanKeys.remove(_allPlansExportKey));
      }
    }
  }

  Future<void> _downloadAllPlans() async {
    if (_exportingPlanKeys.contains(_allPlansExportKey)) return;
    setState(() => _exportingPlanKeys.add(_allPlansExportKey));
    try {
      final bytes = await _buildAllPlansPdf();
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'treino_completo_${widget.trainerName.toLowerCase().replaceAll(' ', '_')}.pdf',
      ).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      _showErrorSnack('A exportação completa demorou demais. Tente novamente.');
    } catch (_) {
      _showErrorSnack('Não foi possível baixar todos os treinos agora.');
    } finally {
      if (mounted) {
        setState(() => _exportingPlanKeys.remove(_allPlansExportKey));
      }
    }
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
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FB),
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Voltar',
        ),
        title: Text('Treinos • ${widget.trainerName}'),
        backgroundColor: const Color(0xFF0B4DBA),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF0B4DBA)),
            )
          : RefreshIndicator(
              onRefresh: _loadPlans,
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
                                Icons.menu_book_rounded,
                                color: Color(0xFF1D4ED8),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Treinos organizados pelo personal',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.black87,
                                    ),
                                  ),
                                  Text(
                                    '${_plans.length} treino(s) cadastrado(s)',
                                    style: const TextStyle(
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
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _plans.isEmpty || _exportingPlanKeys.contains(_allPlansExportKey)
                                  ? null
                                  : _printAllPlans,
                              icon: _exportingPlanKeys.contains(_allPlansExportKey)
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.print_rounded, size: 16),
                              label: const Text('Imprimir tudo'),
                            ),
                            ElevatedButton.icon(
                              onPressed: _plans.isEmpty || _exportingPlanKeys.contains(_allPlansExportKey)
                                  ? null
                                  : _downloadAllPlans,
                              icon: _exportingPlanKeys.contains(_allPlansExportKey)
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.download_rounded, size: 16),
                              label: const Text('Baixar tudo'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0B4DBA),
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_plans.isEmpty)
                    _sectionCard(
                      child: const Text(
                        'Seu personal ainda não organizou treinos para você.',
                        style: TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    )
                  else
                    ..._groupPlansByDayAndTime().entries.map((dayEntry) {
                      final dayName = dayEntry.key;
                      final plansPerTime = dayEntry.value;
                      final dayExpanded = _expandedDays.contains(dayName);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _sectionCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (dayExpanded) {
                                      _expandedDays.remove(dayName);
                                    } else {
                                      _expandedDays.add(dayName);
                                      final firstTime = plansPerTime.keys.first;
                                      _expandedTimes.add('$dayName|$firstTime');
                                    }
                                  });
                                },
                                borderRadius: BorderRadius.circular(10),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDBEAFE),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          dayName,
                                          style: const TextStyle(
                                            color: Color(0xFF1D4ED8),
                                            fontWeight: FontWeight.w700,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${plansPerTime.length} horário(s)',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.black54,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const Spacer(),
                                      Icon(
                                        dayExpanded
                                            ? Icons.keyboard_arrow_up_rounded
                                            : Icons.keyboard_arrow_down_rounded,
                                        color: const Color(0xFF64748B),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (dayExpanded) ...[
                                const SizedBox(height: 8),
                                ...plansPerTime.entries.map((timeEntry) {
                                  final time = timeEntry.key;
                                  final plansAtTime = timeEntry.value;
                                  final timeKey = '$dayName|$time';
                                  final timeExpanded = _expandedTimes.contains(timeKey);
                                  final primaryPlan = plansAtTime.first;
                                  final exercises = <Map<String, String>>[];
                                  for (final plan in plansAtTime) {
                                    exercises.addAll(_extractExercises(plan['exercises']));
                                  }

                                  final exportKey = _planExportKey(primaryPlan);
                                  final exporting = _exportingPlanKeys.contains(exportKey);

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: const Color(0xFFE2E8F0)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (timeExpanded) {
                                                _expandedTimes.remove(timeKey);
                                              } else {
                                                _expandedTimes.add(timeKey);
                                              }
                                            });
                                          },
                                          borderRadius: BorderRadius.circular(8),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(vertical: 2),
                                            child: Row(
                                              children: [
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
                                                    time.isEmpty ? 'Sem horário' : time,
                                                    style: const TextStyle(
                                                      color: Color(0xFF166534),
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 11.5,
                                                    ),
                                                  ),
                                                ),
                                                const Spacer(),
                                                Icon(
                                                  timeExpanded
                                                      ? Icons.keyboard_arrow_up_rounded
                                                      : Icons.keyboard_arrow_down_rounded,
                                                  color: const Color(0xFF64748B),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        if (timeExpanded) ...[
                                          const SizedBox(height: 8),
                                          Row(
                                            children: [
                                              OutlinedButton.icon(
                                                onPressed: exporting
                                                    ? null
                                                    : () => _printPlan(primaryPlan),
                                                icon: exporting
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                        ),
                                                      )
                                                    : const Icon(Icons.print_rounded, size: 16),
                                                label: const Text('Imprimir'),
                                              ),
                                              const SizedBox(width: 8),
                                              ElevatedButton.icon(
                                                onPressed: exporting
                                                    ? null
                                                    : () => _downloadPlan(primaryPlan),
                                                icon: exporting
                                                    ? const SizedBox(
                                                        width: 14,
                                                        height: 14,
                                                        child: CircularProgressIndicator(
                                                          strokeWidth: 2,
                                                          color: Colors.white,
                                                        ),
                                                      )
                                                    : const Icon(Icons.download_rounded, size: 16),
                                                label: const Text('Baixar'),
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF0B4DBA),
                                                  foregroundColor: Colors.white,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          if (exercises.isEmpty)
                                            const Text(
                                              'Nenhum exercício cadastrado para este horário.',
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: Colors.black54,
                                              ),
                                            )
                                          else
                                            ...exercises.map(
                                              (ex) => Container(
                                                margin: const EdgeInsets.only(bottom: 6),
                                                padding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 8,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(
                                                    color: const Color(0xFFE2E8F0),
                                                  ),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(
                                                      Icons.fitness_center_rounded,
                                                      size: 14,
                                                      color: Color(0xFF1D4ED8),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Text(
                                                        ex['name'] ?? '',
                                                        style: const TextStyle(
                                                          fontSize: 12.5,
                                                          color: Colors.black87,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFFEFF6FF),
                                                        borderRadius: BorderRadius.circular(999),
                                                      ),
                                                      child: Text(
                                                        ex['category'] ?? 'Outros',
                                                        style: const TextStyle(
                                                          fontSize: 10.5,
                                                          color: Color(0xFF1D4ED8),
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
