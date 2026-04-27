import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../core/app_refresh_notifier.dart';
import '../services/admin_service.dart';
import 'admin_history_view.dart';
import 'admin_ticket_view.dart';

class AdminView extends StatefulWidget {
  const AdminView({super.key});

  @override
  State<AdminView> createState() => _AdminViewState();
}

class _AdminViewState extends State<AdminView> {
  List<dynamic> alunos = [];
  List<dynamic> trainers = [];
  bool loading = true;

  // ✅ Scroll + âncoras
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _trainersSectionKey = GlobalKey();
  final GlobalKey _alunosSectionKey = GlobalKey();

  void _onGlobalRefresh() {
    _scrollToTop();
    _load();
  }

  @override
  void initState() {
    super.initState();
    AppRefreshNotifier.signal.addListener(_onGlobalRefresh);
    _load();
  }

  @override
  void dispose() {
    AppRefreshNotifier.signal.removeListener(_onGlobalRefresh);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final a = await AdminService.getPendingStudents();
      final t = await AdminService.getPendingTrainers();

      if (!mounted) return;

      setState(() {
        alunos = a;
        trainers = t;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  // ✅ vai para o topo
  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
    );
  }

  // ✅ vai para uma âncora (seção)
  void _scrollTo(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;

    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  /// ✅ Mostra a foto (base64) como avatar
  Widget _avatar(dynamic u) {
    final base64 = (u['photoBase64'] ?? '').toString();
    final name = (u['name'] ?? '').toString().trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();

    if (base64.isEmpty) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: const Color(0xFFE8EEFF),
        child: Text(
          initial,
          style: const TextStyle(
            color: Color(0xFF0B4DBA),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      );
    }

    try {
      final Uint8List bytes = base64Decode(base64);
      return CircleAvatar(
        radius: 28,
        backgroundImage: MemoryImage(bytes),
      );
    } catch (_) {
      return CircleAvatar(
        radius: 28,
        backgroundColor: const Color(0xFFE8EEFF),
        child: Text(
          initial,
          style: const TextStyle(
            color: Color(0xFF0B4DBA),
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      );
    }
  }

  int get _pendingTotal => trainers.length + alunos.length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FA),
      body: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      controller: _scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                      children: [
                        _heroBanner(),
                        const SizedBox(height: 16),

                        // ✅ Cards do topo
                        _topCards(),
                        const SizedBox(height: 18),

                        // ===== PERSONAL =====
                        Container(
                          key: _trainersSectionKey,
                          child: _sectionTitle('Personal Trainers Pendentes'),
                        ),
                        const SizedBox(height: 10),
                        _clickableHistoryCard(
                          context,
                          'Personal Trainers Aprovados / Rejeitados',
                          'personal',
                        ),
                        trainers.isEmpty
                            ? _emptyBox('Nenhuma solicitação de Personal Trainer pendente')
                            : _pendingGrid(trainers),

                        const SizedBox(height: 32),

                        // ===== ALUNOS =====
                        Container(
                          key: _alunosSectionKey,
                          child: _sectionTitle('Alunos Pendentes'),
                        ),
                        const SizedBox(height: 10),
                        _clickableHistoryCard(
                          context,
                          'Alunos Aprovados / Rejeitados',
                          'aluno',
                        ),
                        alunos.isEmpty
                            ? _emptyBox('Nenhuma solicitação de Aluno pendente')
                            : _pendingGrid(alunos),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroBanner() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0B4DBA), Color(0xFF103A85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0B4DBA).withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.admin_panel_settings_rounded,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Central de Moderação',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Revise solicitações e mantenha a comunidade segura.',
                  style: TextStyle(
                    color: Color(0xFFDDE8FF),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.28),
              ),
            ),
            child: Text(
              '$_pendingTotal pendentes',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingGrid(List<dynamic> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 1;
        double childAspectRatio = 1.55;

        if (constraints.maxWidth > 1500) {
          crossAxisCount = 3;
          childAspectRatio = 1.75;
        } else if (constraints.maxWidth > 950) {
          crossAxisCount = 2;
          childAspectRatio = 1.65;
        }

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: childAspectRatio,
          ),
          itemBuilder: (context, index) => _userCard(items[index]),
        );
      },
    );
  }

  Widget _clickableHistoryCard(BuildContext context, String title, String type) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => AdminHistoryView(userType: type)),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 24),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7ECF3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EEFF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.history, color: Color(0xFF0B4DBA), size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Abrir histórico completo com filtros e exclusão',
                    style: TextStyle(fontSize: 12, color: Color(0xFF667085)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 24),
          ],
        ),
      ),
    );
  }

  // ✅ Cards do topo clicáveis
  Widget _topCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 920;

        final trainerCard = _statCard(
          title: 'Personal Trainers Pendentes',
          value: trainers.length,
          subtitle: 'Toque para navegar na seção',
          onTap: () {
            if (!_scrollController.hasClients) return;
            final offset = _scrollController.offset;
            if (offset > 80) {
              _scrollToTop();
            } else {
              _scrollTo(_trainersSectionKey);
            }
          },
          arrowIcon: Icons.arrow_upward_rounded,
        );

        final studentCard = _statCard(
          title: 'Alunos Pendentes',
          value: alunos.length,
          subtitle: 'Toque para navegar na seção',
          onTap: () => _scrollTo(_alunosSectionKey),
          arrowIcon: Icons.arrow_downward_rounded,
        );

        if (isCompact) {
          return Column(
            children: [
              trainerCard,
              const SizedBox(height: 10),
              studentCard,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: trainerCard),
            const SizedBox(width: 12),
            Expanded(child: studentCard),
          ],
        );
      },
    );
  }

  Widget _statCard({
    required String title,
    required int value,
    required String subtitle,
    required VoidCallback onTap,
    required IconData arrowIcon,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7ECF3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF344054),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value.toString(),
                    style: const TextStyle(
                      fontSize: 30,
                      height: 1,
                      color: Color(0xFF111827),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
                  ),
                ],
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFE8EEFF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(arrowIcon, color: const Color(0xFF0B4DBA), size: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _userCard(dynamic u) {
    final type = (u['type'] ?? '').toString().toLowerCase();
    final cpf = (u['cpf'] ?? '-').toString();
    final createdAt = u['createdAt']?.toString();
    final createdDate = (createdAt != null && createdAt.length >= 10) ? createdAt.substring(0, 10) : '-';
    final name = (u['name'] ?? '').toString();
    final email = (u['email'] ?? '').toString();

    const infoStyle = TextStyle(color: Color(0xFF344054));

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7ECF3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _avatar(u),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                color: Color(0xFF111827),
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              email,
                              style: const TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF4FF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFFD6E4FF)),
                        ),
                        child: Text(
                          type == 'personal' ? 'Personal' : 'Aluno',
                          style: const TextStyle(
                            color: Color(0xFF1D4ED8),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _infoRow(Icons.badge_outlined, 'CPF', cpf, infoStyle),
                  const SizedBox(height: 6),
                  _infoRow(Icons.event_note_outlined, 'Data de Cadastro', createdDate, infoStyle),
                  if (u['objetivos'] != null) ...[
                    const SizedBox(height: 6),
                    _infoRow(Icons.flag_outlined, 'Objetivos', '${u['objetivos']}', infoStyle),
                  ],
                  if (u['nivel'] != null) ...[
                    const SizedBox(height: 6),
                    _infoRow(Icons.trending_up_outlined, 'Nível', '${u['nivel']}', infoStyle),
                  ],
                  if (type == 'personal' && u['cref'] != null) ...[
                    const SizedBox(height: 6),
                    _infoRow(Icons.workspace_premium_outlined, 'CREF', '${u['cref']}', infoStyle),
                  ],
                  if (u['especialidade'] != null &&
                      u['especialidade'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _infoRow(Icons.fitness_center_outlined, 'Especialidade', '${u['especialidade']}', infoStyle),
                  ],
                  if (u['experiencia'] != null &&
                      u['experiencia'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _infoRow(Icons.school_outlined, 'Experiência', '${u['experiencia']}', infoStyle),
                  ],
                  if (u['cidade'] != null && u['cidade'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _infoRow(Icons.location_on_outlined, 'Cidade', '${u['cidade']}', infoStyle),
                  ],
                  if (u['bio'] != null && u['bio'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _infoRow(Icons.notes_outlined, 'Biografia', '${u['bio']}', infoStyle),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFEAECEF)),
          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Analisar'),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFF0B4DBA),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                final removed = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => AdminTicketView(user: Map<String, dynamic>.from(u))),
                );

                if (removed == true) {
                  setState(() {
                    if (type == 'personal') {
                      trainers.removeWhere((x) => x['id'] == u['id']);
                    } else {
                      alunos.removeWhere((x) => x['id'] == u['id']);
                    }
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, TextStyle style) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 15, color: const Color(0xFF98A2B3)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label: $value',
            style: style,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFF0B4DBA),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyBox(String text) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7ECF3)),
      ),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF4FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(Icons.inbox_outlined, color: Color(0xFF0B4DBA)),
          ),
          const SizedBox(height: 10),
          Text(
            text,
            style: const TextStyle(color: Color(0xFF667085), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF3F5FA),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EEFF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.shield_outlined, color: Color(0xFF0B4DBA)),
          ),
          const SizedBox(width: 10),
          const Text(
            'Painel Administrativo',
            style: TextStyle(
              color: Color(0xFF101828),
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 56),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0B4DBA),
                side: const BorderSide(color: Color(0xFF98A2B3)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              icon: const Icon(Icons.logout),
              label: const Text('Sair'),
            ),
          ),
        ],
      ),
    );
  }
}