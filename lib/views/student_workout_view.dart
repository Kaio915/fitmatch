import 'dart:typed_data';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const List<String> _pdfLogoAssetPaths = [
    'assets/images/fitmatch_logo.png',
    'assets/images/fitmatch_logo_original.png',
  ];
  bool _loading = true;
  List<Map<String, dynamic>> _plans = [];
  final Set<String> _exportingPlanKeys = {};
  final Set<String> _expandedDays = {};
  final Set<String> _expandedTimes = {};
  pw.MemoryImage? _pdfLogoImage;
  bool _pdfLogoLoadAttempted = false;

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

  String _formatDateTimePt(DateTime value) {
    final dd = value.day.toString().padLeft(2, '0');
    final mm = value.month.toString().padLeft(2, '0');
    final yyyy = value.year.toString();
    final hh = value.hour.toString().padLeft(2, '0');
    final min = value.minute.toString().padLeft(2, '0');
    return '$dd/$mm/$yyyy $hh:$min';
  }

  Future<pw.MemoryImage?> _loadPdfLogo() async {
    if (_pdfLogoLoadAttempted) return _pdfLogoImage;
    _pdfLogoLoadAttempted = true;
    for (final assetPath in _pdfLogoAssetPaths) {
      try {
        final data = await rootBundle.load(assetPath);
        _pdfLogoImage = pw.MemoryImage(data.buffer.asUint8List());
        break;
      } catch (_) {
        _pdfLogoImage = null;
      }
    }
    return _pdfLogoImage;
  }

  pw.Widget _pdfHeaderCard({
    required pw.MemoryImage? logo,
    required String title,
    required String subtitle,
  }) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#EAF1FF'),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(
          color: PdfColor.fromHex('#C7DBFF'),
          width: 1,
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            width: 128,
            height: 44,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: PdfColor.fromHex('#BFDBFE'), width: 1),
            ),
            child: pw.Center(
              child: logo != null
                  ? pw.Image(
                      logo,
                      width: 108,
                      height: 26,
                      fit: pw.BoxFit.contain,
                    )
                  : pw.Text(
                      'FitMatch',
                      style: pw.TextStyle(
                        color: PdfColor.fromHex('#0B4DBA'),
                        fontWeight: pw.FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0B4DBA'),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  subtitle,
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    color: PdfColor.fromHex('#475569'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfInfoItem({required String label, required String value}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F8FAFC'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              fontSize: 9.5,
              color: PdfColor.fromHex('#64748B'),
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11.5,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#0F172A'),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfSectionTitle(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#0B4DBA'),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontWeight: pw.FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }

  pw.Widget _pdfExerciseTile({
    required int index,
    required String name,
    required String category,
  }) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0'), width: 1),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 18,
            height: 18,
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#DBEAFE'),
              shape: pw.BoxShape.circle,
            ),
            child: pw.Center(
              child: pw.Text(
                '$index',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#1D4ED8'),
                ),
              ),
            ),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  name,
                  style: pw.TextStyle(
                    fontSize: 11.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  category,
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColor.fromHex('#64748B'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
    final logo = await _loadPdfLogo();
    final dayName = (plan['dayName'] ?? 'Dia').toString();
    final time = (plan['time'] ?? '').toString().trim();
    final exercises = _extractExercises(plan['exercises']);
    final generatedAt = _formatDateTimePt(DateTime.now());

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 26),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Gerado em $generatedAt - Pagina ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColor.fromHex('#94A3B8'),
            ),
          ),
        ),
        build: (context) => [
          _pdfHeaderCard(
            logo: logo,
            title: 'FitMatch - Treino do Dia',
            subtitle: 'Treino personalizado para acompanhamento do aluno',
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            children: [
              pw.Expanded(
                child: _pdfInfoItem(label: 'Personal', value: widget.trainerName),
              ),
              pw.SizedBox(width: 8),
              pw.Expanded(
                child: _pdfInfoItem(label: 'Dia', value: dayName),
              ),
              if (time.isNotEmpty) ...[
                pw.SizedBox(width: 8),
                pw.Expanded(
                  child: _pdfInfoItem(label: 'Horario', value: time),
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 12),
          _pdfSectionTitle('Exercicios'),
          pw.SizedBox(height: 8),
          if (exercises.isEmpty)
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
              ),
              child: pw.Text(
                'Nenhum exercicio cadastrado para este treino.',
                style: pw.TextStyle(
                  fontSize: 11,
                  color: PdfColor.fromHex('#64748B'),
                ),
              ),
            )
          else
            ...exercises.asMap().entries.map(
                  (entry) => _pdfExerciseTile(
                    index: entry.key + 1,
                    name: entry.value['name'] ?? '',
                    category: entry.value['category'] ?? 'Outros',
                  ),
                ),
        ],
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
    final logo = await _loadPdfLogo();
    final grouped = _groupPlansByDayAndTime();
    final generatedAt = _formatDateTimePt(DateTime.now());

    final blocks = <pw.Widget>[];
    grouped.forEach((dayName, perTime) {
      blocks.add(
        pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(top: 10, bottom: 8),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#DBEAFE'),
            borderRadius: pw.BorderRadius.circular(8),
            border: pw.Border.all(color: PdfColor.fromHex('#BFDBFE'), width: 1),
          ),
          child: pw.Text(
            dayName,
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#1D4ED8'),
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
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(bottom: 6),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#ECFDF3'),
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColor.fromHex('#BBF7D0'), width: 1),
            ),
            child: pw.Text(
              time.isEmpty ? 'Sem horario definido' : 'Horario: $time',
              style: pw.TextStyle(
                fontSize: 11.5,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#166534'),
              ),
            ),
          ),
        );

        if (exercises.isEmpty) {
          blocks.add(
            pw.Container(
              width: double.infinity,
              margin: const pw.EdgeInsets.only(bottom: 8),
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#F8FAFC'),
                borderRadius: pw.BorderRadius.circular(8),
                border: pw.Border.all(color: PdfColor.fromHex('#E2E8F0')),
              ),
              child: pw.Text(
                'Nenhum exercicio cadastrado neste horario.',
                style: pw.TextStyle(
                  fontSize: 10.5,
                  color: PdfColor.fromHex('#64748B'),
                ),
              ),
            ),
          );
        } else {
          for (int i = 0; i < exercises.length; i++) {
            final ex = exercises[i];
            blocks.add(
              _pdfExerciseTile(
                index: i + 1,
                name: ex['name'] ?? '',
                category: ex['category'] ?? 'Outros',
              ),
            );
          }
        }
      });
    });

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(26, 24, 26, 26),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Gerado em $generatedAt - Pagina ${context.pageNumber}/${context.pagesCount}',
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColor.fromHex('#94A3B8'),
            ),
          ),
        ),
        build: (context) => [
          _pdfHeaderCard(
            logo: logo,
            title: 'FitMatch - Treino Completo',
            subtitle: 'Todos os treinos organizados por dia e horario',
          ),
          pw.SizedBox(height: 12),
          _pdfInfoItem(label: 'Personal', value: widget.trainerName),
          pw.SizedBox(height: 12),
          _pdfSectionTitle('Agenda de exercicios'),
          pw.SizedBox(height: 8),
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
