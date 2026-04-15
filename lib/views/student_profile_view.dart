import 'package:flutter/material.dart';
import '../services/auth_service.dart';

// ─── Perfil do Aluno ──────────────────────────────────────────────────────────
// Aberto pelo personal para ver o perfil de um aluno.
// Permite ao personal avaliar o aluno com estrelas.

class StudentProfileView extends StatefulWidget {
  final int studentId;
  final String studentName;
  // Se fornecido, o personal pode avaliar o aluno
  final int? trainerId;
  final String? trainerName;

  const StudentProfileView({
    super.key,
    required this.studentId,
    required this.studentName,
    this.trainerId,
    this.trainerName,
  });

  @override
  State<StudentProfileView> createState() => _StudentProfileViewState();
}

class _StudentProfileViewState extends State<StudentProfileView> {
  Map<String, dynamic>? _userData;
  List<Map<String, dynamic>> _ratings = [];
  bool _loading = true;
  String? _error;

  // Avaliação atual do personal logado
  int _myRating = 0;
  bool _savingRating = false;
  final _commentCtrl = TextEditingController();
  String? _resolvedTrainerName;

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Se trainerName não foi passado, busca do backend
      String? resolvedTrainerName = widget.trainerName;
      if ((resolvedTrainerName == null || resolvedTrainerName.isEmpty) &&
          widget.trainerId != null) {
        try {
          final trainerData = await AuthService.getUserById(widget.trainerId!);
          resolvedTrainerName = (trainerData['name'] ?? 'Personal').toString();
        } catch (_) {
          resolvedTrainerName = 'Personal';
        }
      }

      final results = await Future.wait([
        AuthService.getUserById(widget.studentId),
        AuthService.getStudentRatings(widget.studentId),
      ]);
      if (!mounted) return;
      final userData = results[0] as Map<String, dynamic>;
      final ratings = results[1] as List<Map<String, dynamic>>;

      // Verifica se o personal já avaliou este aluno
      int myRating = 0;
      if (widget.trainerId != null) {
        final existing = ratings.where(
          (r) => r['trainerId']?.toString() == widget.trainerId.toString(),
        );
        if (existing.isNotEmpty) {
          myRating = (existing.first['stars'] as num?)?.toInt() ?? 0;
          final existingComment = existing.first['comment']?.toString() ?? '';
          _commentCtrl.text = existingComment;
        }
      }

      setState(() {
        _userData = userData;
        _ratings = ratings;
        _myRating = myRating;
        _resolvedTrainerName = resolvedTrainerName;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _submitRating(int stars) async {
    if (widget.trainerId == null) return;
    setState(() {
      _myRating = stars;
      _savingRating = true;
    });
    try {
      await AuthService.rateStudent(
        trainerId: widget.trainerId!,
        studentId: widget.studentId,
        trainerName: _resolvedTrainerName ?? widget.trainerName ?? 'Personal',
        stars: stars,
        comment: _commentCtrl.text.trim(),
      );
      if (!mounted) return;
      // Recarrega as avaliações para mostrar a nova média
      final ratings = await AuthService.getStudentRatings(widget.studentId);
      if (!mounted) return;
      setState(() {
        _ratings = ratings;
        _savingRating = false;
      });
      _showSnack('Avaliação enviada!', const Color(0xFF22C55E));
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingRating = false);
      _showSnack(
          e.toString().replaceFirst('Exception: ', ''), const Color(0xFFEF4444));
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  double get _avgRating {
    if (_ratings.isEmpty) return 0;
    final sum =
        _ratings.fold<int>(0, (acc, r) => acc + ((r['stars'] as num?)?.toInt() ?? 0));
    return sum / _ratings.length;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FB),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(
                          color: Color(0xFF0B4DBA), strokeWidth: 2.5),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.error_outline_rounded,
                                    size: 48, color: Color(0xFFEF4444)),
                                const SizedBox(height: 12),
                                Text(_error!,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: Colors.black54)),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _load,
                                  child: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : SingleChildScrollView(
                          padding:
                              const EdgeInsets.fromLTRB(20, 0, 20, 48),
                          child: Column(
                            children: [
                              _buildProfileCard(),
                              const SizedBox(height: 20),
                              if (widget.trainerId != null)
                                _buildRatingCard(),
                              const SizedBox(height: 20),
                              if (_ratings.isNotEmpty) _buildReviewsCard(),
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0B4DBA), Color(0xFF1A62D4)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x330B4DBA),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(4, 10, 16, 10),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.person_rounded, color: Colors.white, size: 22),
          const SizedBox(width: 10),
          const Text(
            'Perfil do Aluno',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard() {
    final name = _userData?['name']?.toString() ?? widget.studentName;
    final objetivos = _userData?['objetivos']?.toString();
    final nivel = _userData?['nivel']?.toString();

    return Container(
      margin: const EdgeInsets.only(top: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.1),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          // Banner
          Container(
            height: 110,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
              gradient: LinearGradient(
                colors: [Color(0xFF0B4DBA), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Transform.translate(
                      offset: const Offset(0, -40),
                      child: Container(
                        width: 82,
                        height: 82,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFD9E8FB), Color(0xFFBDD5F5)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF0B4DBA)
                                  .withValues(alpha: 0.2),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Center(
                          child: ClipOval(
                            child: Image.network(
                              AuthService.getUserPhotoUrl(widget.studentId),
                              fit: BoxFit.cover,
                              width: 82,
                              height: 82,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.person_rounded,
                                size: 36,
                                color: Color(0xFF0B4DBA),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF4FF),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                    color: const Color(0xFFBFD3F5)),
                              ),
                              child: const Text(
                                'Aluno',
                                style: TextStyle(
                                  color: Color(0xFF0B4DBA),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                // Média de estrelas
                if (_ratings.isNotEmpty) ...[
                  _StarRatingDisplay(avg: _avgRating, total: _ratings.length),
                  const SizedBox(height: 16),
                ],
                // Objetivos
                if (objetivos != null && objetivos.isNotEmpty) ...[
                  _InfoRow(
                    icon: Icons.track_changes_rounded,
                    label: 'Objetivos',
                    value: objetivos,
                  ),
                  const SizedBox(height: 10),
                ],
                // Nível
                if (nivel != null && nivel.isNotEmpty)
                  _InfoRow(
                    icon: Icons.fitness_center_rounded,
                    label: 'Nível',
                    value: nivel,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRatingCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: const Icon(Icons.star_rounded,
                    size: 20, color: Color(0xFFF59E0B)),
              ),
              const SizedBox(width: 12),
              const Text(
                'Avaliar Aluno',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
              if (_savingRating) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFF59E0B)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Toque nas estrelas para avaliar o desempenho do aluno',
            style: TextStyle(fontSize: 12.5, color: Colors.black45),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final star = index + 1;
              return GestureDetector(
                onTap: _savingRating ? null : () => _submitRating(star),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Icon(
                    star <= _myRating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 38,
                    color: star <= _myRating
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFFD1D5DB),
                  ),
                ),
              );
            }),
          ),
          if (_myRating > 0) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                _ratingLabel(_myRating),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFF59E0B),
                  fontSize: 13,
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _commentCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Escreva um comentário sobre o aluno (opcional)...',
              hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFFF7F9FD),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE7EBF3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE7EBF3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFF0B4DBA), width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_myRating == 0 || _savingRating)
                  ? null
                  : () => _submitRating(_myRating),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4DBA),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE7EBF3),
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: _savingRating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Salvar Avaliação',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.07),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFBFD3F5)),
                ),
                child: const Icon(Icons.reviews_rounded,
                    size: 18, color: Color(0xFF0B4DBA)),
              ),
              const SizedBox(width: 12),
              Text(
                'Avaliações (${_ratings.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final r in _ratings)
            _ReviewItem(
              trainerId: (r['trainerId'] as num?)?.toInt(),
              trainerName: (r['trainerName'] ?? 'Personal').toString(),
              stars: (r['stars'] as num?)?.toInt() ?? 0,
              comment: r['comment']?.toString(),
              date: r['createdAt']?.toString(),
            ),
        ],
      ),
    );
  }

  String _ratingLabel(int stars) {
    switch (stars) {
      case 1:
        return 'Precisa melhorar';
      case 2:
        return 'Regular';
      case 3:
        return 'Bom';
      case 4:
        return 'Muito bom';
      case 5:
        return 'Excelente!';
      default:
        return '';
    }
  }
}

// ─── Widgets auxiliares ───────────────────────────────────────────────────────

class _StarRatingDisplay extends StatelessWidget {
  final double avg;
  final int total;

  const _StarRatingDisplay({required this.avg, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...List.generate(5, (i) {
          final filled = i + 1 <= avg;
          final half = !filled && (i + 0.5) < avg;
          return Icon(
            filled
                ? Icons.star_rounded
                : half
                    ? Icons.star_half_rounded
                    : Icons.star_outline_rounded,
            size: 20,
            color: const Color(0xFFF59E0B),
          );
        }),
        const SizedBox(width: 6),
        Text(
          avg.toStringAsFixed(1),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
            color: Colors.black87,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '($total avaliação${total != 1 ? 'ões' : ''})',
          style: const TextStyle(fontSize: 12, color: Colors.black38),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EBF3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: const Color(0xFF0B4DBA)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewItem extends StatelessWidget {
  final int? trainerId;
  final String trainerName;
  final int stars;
  final String? comment;
  final String? date;

  const _ReviewItem({
    this.trainerId,
    required this.trainerName,
    required this.stars,
    this.comment,
    this.date,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE7EBF3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFEEF4FD),
                child: ClipOval(
                  child: trainerId != null
                      ? Image.network(
                          AuthService.getUserPhotoUrl(trainerId!),
                          fit: BoxFit.cover,
                          width: 32,
                          height: 32,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.person_rounded,
                            color: Color(0xFF0B4DBA),
                            size: 16,
                          ),
                        )
                      : const Icon(
                          Icons.person_rounded,
                          color: Color(0xFF0B4DBA),
                          size: 16,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  trainerName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 15,
                    color: const Color(0xFFF59E0B),
                  ),
                ),
              ),
            ],
          ),
          if (comment != null && comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              comment!,
              style: const TextStyle(
                  fontSize: 12.5, color: Colors.black54, height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}
