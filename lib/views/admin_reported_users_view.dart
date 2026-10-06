import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../core/app_refresh_notifier.dart';
import '../core/date_utils.dart';
import '../services/admin_service.dart';
import 'admin_ticket_view.dart';

const List<String> _banReasons = [
  'Excesso de solicitações de cadastro.',
  'Violação das diretrizes da plataforma.',
  'Tentativa de fraude ou golpe.',
  'Comportamento inadequado com outros usuários.',
  'Conta duplicada.',
  'Uso indevido da plataforma (spam/propaganda).',
];

class AdminReportedUsersView extends StatefulWidget {
  const AdminReportedUsersView({super.key});

  @override
  State<AdminReportedUsersView> createState() => _AdminReportedUsersViewState();
}

class _AdminReportedUsersViewState extends State<AdminReportedUsersView> {
  List<dynamic> users = [];
  List<dynamic> filtered = [];

  bool loading = true;
  String? error;

  String search = '';
  String statusFilter = 'ALL';
  String sortBy = 'DATA';

  final Set<int> _busyIds = <int>{};

  void _onGlobalRefresh() {
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final data = await AdminService.getReportedUsers();
      users = data;
      _applyFilter();
    } catch (_) {
      error = 'Erro ao carregar usuários reportados';
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  void _applyFilter() {
    final s = search.toLowerCase();

    List<dynamic> list = users.where((u) {
      final name = (u['name'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      final status = (u['status'] ?? '').toString().toUpperCase();
      final deleted = (u['deleted'] == true) || status == 'DELETED';
      final banned = (u['banned'] == true);
      final lastReportAt = (u['lastReportAt'] ?? '').toString();
      final date = formatIsoDateToPtBr(lastReportAt).toLowerCase();

      final matchesSearch =
          s.isEmpty ||
          name.contains(s) ||
          email.contains(s) ||
          date.contains(s);

      final matchesStatus = statusFilter == 'ALL'
          ? true
          : statusFilter == 'DELETED'
          ? deleted
          : statusFilter == 'BANNED'
          ? banned
          : status == statusFilter;

      return matchesSearch && matchesStatus;
    }).toList();

    list.sort((a, b) {
      if (sortBy == 'NOME') {
        return (a['name'] ?? '').toString().toLowerCase().compareTo(
          (b['name'] ?? '').toString().toLowerCase(),
        );
      }
      return (b['lastReportAt'] ?? '').toString().compareTo(
        (a['lastReportAt'] ?? '').toString(),
      );
    });

    setState(() => filtered = list);
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openChat(Map<String, dynamic> u) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminTicketView(user: u, blockMessaging: true),
      ),
    );
  }

  Future<void> _confirmRelease(Map<String, dynamic> user) async {
    final id = user['id'];
    if (id is! int) return;

    final name = (user['name'] ?? 'Usuário').toString();

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Liberar usuário'),
            content: Text(
              'Tem certeza que deseja liberar $name?\n\n'
              'O usuário sairá da lista de reportados e continuará usando o '
              'app normalmente.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF15803D),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Liberar'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _busyIds.add(id));
    try {
      await AdminService.releaseReportedUser(id);
      await _load();
      _showSnack('Usuário liberado com sucesso.');
    } catch (e) {
      _showSnack(
        'Não foi possível liberar: ${e.toString().replaceFirst('Exception: ', '')}',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _showBanReasonSheet(Map<String, dynamic> user) async {
    final id = user['id'];
    if (id is! int) return;

    String? selectedReason;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) => Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCE6F5)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .08),
                  blurRadius: 18,
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.gavel, color: Color(0xFF7F1D1D)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Selecione o motivo do banimento',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: Column(
                        children: _banReasons.map((reason) {
                          final checked = selectedReason == reason;
                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setModalState(() {
                              selectedReason = checked ? null : reason;
                            }),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    value: checked,
                                    onChanged: (_) => setModalState(() {
                                      selectedReason = checked ? null : reason;
                                    }),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 11),
                                      child: Text(reason),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final reason = (selectedReason ?? '').trim();
                        if (reason.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Selecione um motivo de banimento'),
                            ),
                          );
                          return;
                        }

                        Navigator.pop(sheetCtx);
                        await _banUser(id, reason);
                      },
                      icon: const Icon(Icons.gavel),
                      label: const Text('Banir usuário'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF7F1D1D),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _banUser(int id, String reason) async {
    setState(() => _busyIds.add(id));
    try {
      await AdminService.banUser(id, reason: reason);
      await _load();
      _showSnack('Usuário banido com sucesso.');
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _showSnack('Não foi possível banir: $msg', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  Future<void> _confirmUnban(Map<String, dynamic> user) async {
    final id = user['id'];
    if (id is! int) return;

    final name = (user['name'] ?? 'Usuário').toString();

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Desbanir usuário'),
            content: Text(
              'Tem certeza que deseja desbanir $name?\n\n'
              'O usuário voltará a poder fazer login e criar uma nova conta.',
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
                child: const Text('Desbanir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _busyIds.add(id));
    try {
      await AdminService.unbanUser(id);
      await _load();
      _showSnack('Usuário desbanido com sucesso.');
    } catch (_) {
      _showSnack('Não foi possível desbanir o usuário.', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
  }

  String _statusText(String status) {
    if (status == 'APPROVED') return 'Aprovado';
    if (status == 'REJECTED') return 'Rejeitado';
    if (status == 'DELETED') return 'Excluído';
    return status.isEmpty ? '-' : status;
  }

  Color _statusColor(String status) {
    if (status == 'APPROVED') return Colors.green;
    if (status == 'REJECTED') return Colors.red;
    if (status == 'DELETED') return Colors.grey;
    return Colors.grey;
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .24)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: .3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FA),
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: 76,
        titleSpacing: 20,
        actions: [
          if (MediaQuery.of(context).size.width >= 600)
            IconButton(
              onPressed: _onGlobalRefresh,
              tooltip: 'Atualizar',
              icon: Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF0B4DBA),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          const SizedBox(width: 4),
        ],
        title: const Text(
          'Usuários Reportados',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 26,
            color: Color(0xFF101828),
            height: 1.1,
          ),
        ),
      ),
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        onChanged: (v) {
                          search = v;
                          _applyFilter();
                        },
                        decoration: InputDecoration(
                          hintText: 'Buscar por nome, email ou data',
                          prefixIcon: const Icon(Icons.search),
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFE7ECF3),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(
                              color: Color(0xFFE7ECF3),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: const Color(0xFFE7ECF3),
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: statusFilter,
                                  isExpanded: true,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'ALL',
                                      child: Text('Todos'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'APPROVED',
                                      child: Text('Aprovados'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'REJECTED',
                                      child: Text('Rejeitados'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'DELETED',
                                      child: Text('Excluídos'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'BANNED',
                                      child: Text('Banidos'),
                                    ),
                                  ],
                                  onChanged: (v) {
                                    if (v == null) return;
                                    statusFilter = v;
                                    _applyFilter();
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE7ECF3)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: sortBy,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'DATA',
                                    child: Text('Data'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'NOME',
                                    child: Text('Nome'),
                                  ),
                                ],
                                onChanged: (v) {
                                  if (v == null) return;
                                  sortBy = v;
                                  _applyFilter();
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (filtered.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Text(
                            error ?? 'Nenhum usuário reportado.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF667085),
                              fontSize: 15,
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final u = Map<String, dynamic>.from(
                              filtered[index] as Map,
                            );
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _reportCard(u),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _reportCard(Map<String, dynamic> u) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final id = u['id'] as int?;
    final status = (u['status'] ?? '').toString().toUpperCase();
    final banned = (u['banned'] == true);
    final deleted = (u['deleted'] == true) || status == 'DELETED';
    final isNew = (u['new'] == true);
    final name = (u['name'] ?? '').toString().trim();
    final reports = (u['reports'] as List?) ?? const <dynamic>[];
    final isBusy = id != null && _busyIds.contains(id);

    final statusLabel = banned
        ? 'Banido'
        : deleted
        ? 'Excluído'
        : _statusText(status);
    final statusColor = banned
        ? const Color(0xFF7F1D1D)
        : deleted
        ? Colors.grey
        : _statusColor(status);

    Widget chatButton() => InkWell(
      onTap: () => _openChat(u),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFE8EEFF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(
          Icons.chat_outlined,
          size: 20,
          color: Color(0xFF0B4DBA),
        ),
      ),
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 14 : 16),
      decoration: BoxDecoration(
        color: isNew ? const Color(0xFFFFF7ED) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isNew ? const Color(0xFFF59E0B) : const Color(0xFFE7ECF3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(u, name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isMobile)
                      Expanded(
                        child: Text(
                          name.isEmpty ? '-' : name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: Color(0xFF111827),
                          ),
                        ),
                      )
                    else
                      Flexible(
                        child: Text(
                          name.isEmpty ? '-' : name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: Color(0xFF111827),
                          ),
                        ),
                      ),
                    if (isNew) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'Novo',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                    if (isMobile) chatButton(),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  (u['email'] ?? '-').toString(),
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${reports.length} denúncia(s)',
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                if (reports.isEmpty)
                  const Text(
                    'Nenhuma denúncia registrada.',
                    style: TextStyle(color: Color(0xFF98A2B3), fontSize: 14),
                  )
                else
                  for (final r in reports) ...[
                    _reportItem(Map<String, dynamic>.from(r as Map)),
                    const SizedBox(height: 8),
                  ],
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _statusBadge(statusLabel, statusColor),
                    if (isBusy)
                      const SizedBox(
                        height: 18,
                        width: 18,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else ...[
                      if (!banned)
                        _actionButton(
                          label: 'Liberar usuário',
                          icon: Icons.check_circle_outline,
                          color: const Color(0xFF15803D),
                          onTap: id == null ? () {} : () => _confirmRelease(u),
                        ),
                      if (banned)
                        _actionButton(
                          label: 'Desbanir',
                          icon: Icons.lock_open,
                          color: const Color(0xFF0B4DBA),
                          onTap: id == null ? () {} : () => _confirmUnban(u),
                        )
                      else
                        _actionButton(
                          label: 'Banir',
                          icon: Icons.gavel,
                          color: const Color(0xFF7F1D1D),
                          onTap: id == null
                              ? () {}
                              : () => _showBanReasonSheet(u),
                        ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (!isMobile) ...[const SizedBox(width: 12), chatButton()],
        ],
      ),
    );
  }

  // Mostra a foto (base64) como avatar, com fallback para a inicial do nome.
  Widget _avatar(Map<String, dynamic> u, String name) {
    final base64 = (u['photoBase64'] ?? '').toString();

    if (base64.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(base64);
        return CircleAvatar(radius: 24, backgroundImage: MemoryImage(bytes));
      } catch (_) {
        // base64 inválido → usa a inicial abaixo
      }
    }

    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFFE6EEFF),
      child: Text(
        letter,
        style: const TextStyle(
          color: Color(0xFF0B4DBA),
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }

  String _formatReportTimestamp(String? iso) {
    if (iso == null || iso.isEmpty) return '-';
    final date = formatIsoDateToPtBr(iso);
    final match = RegExp(r'T(\d{2}:\d{2})').firstMatch(iso);
    final time = match?.group(1);
    return time == null ? date : '$date $time';
  }

  Widget _reportItem(Map<String, dynamic> r) {
    final resolved = (r['resolved'] == true);
    final isNew = !resolved && r['seen'] != true;
    final reporterEmail = (r['reporterEmail'] ?? '').toString().trim();
    final reason = (r['reason'] ?? '').toString().trim();
    final details = (r['details'] ?? '').toString().trim();
    final createdAt = _formatReportTimestamp((r['createdAt'] ?? '').toString());
    final resolvedAt = _formatReportTimestamp(
      (r['resolvedAt'] ?? '').toString(),
    );

    final color = resolved
        ? const Color(0xFF667085)
        : isNew
        ? const Color(0xFFB42318)
        : const Color(0xFF667085);
    final badgeColor = resolved || !isNew
        ? const Color(0xFF94A3B8)
        : const Color(0xFFF59E0B);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: resolved ? const Color(0xFFF8FAFC) : const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: resolved ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                resolved
                    ? Icons.check_circle_outline
                    : Icons.report_gmailerrorred,
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  resolved ? 'Denúncia antiga (liberada)' : 'Denúncia nova',
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  resolved
                      ? 'Liberada'
                      : isNew
                      ? 'Novo'
                      : 'Antigo',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Denunciado por: ${reporterEmail.isEmpty ? 'Usuário removido' : reporterEmail}',
            style: const TextStyle(color: Color(0xFF334155), fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            'Data: $createdAt',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Motivo: $reason',
              style: const TextStyle(
                color: Color(0xFFB42318),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (details.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Detalhes: $details',
              style: const TextStyle(color: Color(0xFF475569), fontSize: 13),
            ),
          ],
          if (resolved && resolvedAt != '-') ...[
            const SizedBox(height: 2),
            Text(
              'Liberado em: $resolvedAt',
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
