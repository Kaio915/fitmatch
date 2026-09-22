import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../core/app_refresh_notifier.dart';
import '../core/date_utils.dart';
import '../services/admin_service.dart';
import 'admin_ticket_view.dart';

const List<String> _exclusionReasons = [
  'Informações falsas ou fraudulentas no cadastro.',
  'Comportamento inadequado com outros usuários.',
  'Tentativa de fraude ou golpe.',
  'Conta duplicada.',
  'Uso indevido da plataforma (spam/propaganda).',
];

const String _otherExclusionReason = 'Outro';

class AdminHistoryView extends StatefulWidget {
  final String userType;

  const AdminHistoryView({super.key, required this.userType});

  @override
  State<AdminHistoryView> createState() => _AdminHistoryViewState();
}

class _AdminHistoryViewState extends State<AdminHistoryView> {
  List<dynamic> users = [];
  List<dynamic> filtered = [];

  bool loading = true;
  String? error;

  // filtros
  String statusFilter = 'ALL'; // ALL | APPROVED | REJECTED
  String search = '';

  // ordenação
  String sortBy = 'DATA'; // DATA | NOME

  final Set<int> _deletingIds = <int>{};
  final Set<int> _deletingHistoryIds = <int>{};
  final Set<int> _excludingIds = <int>{};
  final Set<int> _banningIds = <int>{};
  bool _clearing = false;

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
      final data = await AdminService.getUsersByType(widget.userType);

      users = data;
      _applyFilter();
    } catch (e) {
      error = 'Erro ao carregar histórico';
    }

    setState(() {
      loading = false;
    });
  }

  // ✅ Mostra a foto (base64) como avatar, com fallback para a inicial do nome.
  Widget _avatar(Map<String, dynamic> u, String fallbackLetter) {
    final base64 = (u['photoBase64'] ?? '').toString();

    if (base64.isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(base64);
        return CircleAvatar(
          radius: 24,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (_) {
        // base64 inválido → usa a inicial abaixo
      }
    }

    return CircleAvatar(
      radius: 24,
      backgroundColor: const Color(0xFFE6EEFF),
      child: Text(
        fallbackLetter,
        style: const TextStyle(
          color: Color(0xFF0B4DBA),
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
    );
  }

  void _applyFilter() {
    final s = search.toLowerCase();

    List<dynamic> list = users.where((u) {
      final name = (u['name'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      final status = (u['status'] ?? '').toString().toUpperCase();
      final deleted = (u['deleted'] == true) || status == 'DELETED';
      final banned = (u['banned'] == true);

      final matchesSearch = s.isEmpty || name.contains(s) || email.contains(s);

      final matchesStatus = statusFilter == 'ALL'
          ? true
          : statusFilter == 'DELETED'
              ? deleted
              : statusFilter == 'BANNED'
                  ? banned
                  : statusFilter == 'APPROVED'
                      ? (status == 'APPROVED' && !deleted)
                      : status == statusFilter;

      return matchesSearch && matchesStatus;
    }).toList();

    // ordenação fixa (sem asc/desc)
    list.sort((a, b) {
      if (sortBy == 'NOME') {
        return (a['name'] ?? '').toString().toLowerCase().compareTo(
          (b['name'] ?? '').toString().toLowerCase(),
        );
      } else {
        // DATA: mais recente primeiro
        return (b['createdAt'] ?? '').toString().compareTo(
          (a['createdAt'] ?? '').toString(),
        );
      }
    });

    setState(() {
      filtered = list;
    });
  }

  Color _statusColor(String status) {
    if (status == 'APPROVED') return Colors.green;
    if (status == 'REJECTED') return Colors.red;
    if (status == 'DELETED') return Colors.grey;
    return Colors.grey;
  }

  String _statusText(String status) {
    if (status == 'APPROVED') return 'Aprovado';
    if (status == 'REJECTED') return 'Rejeitado';
    if (status == 'DELETED') return 'Excluído';
    return status;
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

  Future<void> _confirmDelete(Map<String, dynamic> user) async {
    final id = user['id'];
    if (id is! int) return;

    final name = (user['name'] ?? 'Usuário').toString();
    final typeLabel = widget.userType == 'personal' ? 'Personal' : 'Aluno';

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Excluir todos os cadastros'),
            content: Text(
              'Você tem certeza que deseja excluir todos os cadastros de $name?\n\n'
              'Essa ação não poderá ser desfeita. Apenas os cadastros de '
              '$typeLabel deste usuário serão removidos. A conta e as '
              'conversas serão mantidas.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir tudo'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;

    setState(() => _deletingIds.add(id));
    try {
      await AdminService.deleteUserHistory(id, widget.userType);
      await _load();
      _showSnack('Cadastros excluídos com sucesso.');
    } catch (_) {
      _showSnack('Não foi possível excluir os cadastros.', error: true);
    } finally {
      if (mounted) {
        setState(() => _deletingIds.remove(id));
      }
    }
  }

  Future<void> _showDeleteOptions(Map<String, dynamic> user) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Excluir apenas este cadastro'),
              subtitle: const Text(
                'Remove somente esta tentativa do histórico.',
              ),
              onTap: () => Navigator.pop(context, 'ENTRY'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Excluir todos os cadastros deste usuário'),
              subtitle: const Text(
                'Remove todas as tentativas deste usuário neste tipo de '
                'cadastro.',
              ),
              onTap: () => Navigator.pop(context, 'ALL'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    if (choice == 'ENTRY') {
      await _confirmDeleteEntry(user);
    } else {
      await _confirmDelete(user);
    }
  }

  Future<void> _confirmDeleteEntry(Map<String, dynamic> user) async {
    final historyId = user['historyId'];
    if (historyId is! int) return;

    final name = (user['name'] ?? 'Usuário').toString();

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Excluir cadastro'),
            content: Text(
              'Você tem certeza que deseja excluir apenas este cadastro de '
              '$name?\n\n'
              'Essa ação não poderá ser desfeita. Os demais cadastros deste '
              'usuário serão mantidos.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldDelete) return;

    setState(() => _deletingHistoryIds.add(historyId));
    try {
      await AdminService.deleteHistoryEntry(historyId);
      await _load();
      _showSnack('Cadastro excluído com sucesso.');
    } catch (_) {
      _showSnack('Não foi possível excluir o cadastro.', error: true);
    } finally {
      if (mounted) {
        setState(() => _deletingHistoryIds.remove(historyId));
      }
    }
  }

  Future<void> _confirmExclude(Map<String, dynamic> user) async {
    final id = user['id'];
    if (id is! int) return;

    final name = (user['name'] ?? 'Usuário').toString();

    String? selectedReason;
    String otherReason = '';

    final shouldExclude = await showDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Excluir conta'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tem certeza que deseja excluir a conta de $name?\n'
                    'O usuário não conseguirá mais fazer login.',
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: selectedReason,
                    decoration: const InputDecoration(
                      labelText: 'Motivo da exclusão',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      ..._exclusionReasons.map(
                        (r) => DropdownMenuItem(value: r, child: Text(r)),
                      ),
                      const DropdownMenuItem(
                        value: _otherExclusionReason,
                        child: Text('Outro'),
                      ),
                    ],
                    onChanged: (v) => setDialogState(() => selectedReason = v),
                  ),
                  if (selectedReason == _otherExclusionReason) ...[
                    const SizedBox(height: 12),
                    TextField(
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Descreva o motivo',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          setDialogState(() => otherReason = v),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _canConfirmExclusion(selectedReason, otherReason)
                      ? () => Navigator.pop(context, true)
                      : null,
                  child: const Text('Excluir conta'),
                ),
              ],
            ),
          ),
        ) ??
        false;

    if (!shouldExclude) return;

    final String finalReason = selectedReason == _otherExclusionReason
        ? otherReason.trim()
        : (selectedReason ?? '').trim();

    setState(() => _excludingIds.add(id));
    try {
      await AdminService.excludeAccount(id, reason: finalReason);
      await _load();
      _showSnack('Conta excluída com sucesso.');
    } catch (_) {
      _showSnack('Não foi possível excluir a conta.', error: true);
    } finally {
      if (mounted) {
        setState(() => _excludingIds.remove(id));
      }
    }
  }

  bool _canConfirmExclusion(String? selectedReason, String otherReason) {
    if (selectedReason == null) return false;
    if (selectedReason == _otherExclusionReason) {
      return otherReason.trim().isNotEmpty;
    }
    return true;
  }

  Future<void> _confirmBan(Map<String, dynamic> user) async {
    final id = user['id'];
    if (id is! int) return;

    final name = (user['name'] ?? 'Usuário').toString();

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Banir usuário'),
            content: Text(
              'Tem certeza que deseja banir $name?\n\n'
              'O usuário será banido da plataforma e a conta será excluída '
              'automaticamente. Ele não poderá mais acessar ou criar uma nova '
              'conta.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7F1D1D),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Banir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _banningIds.add(id));
    try {
      await AdminService.banUser(id, reason: AdminService.banReason);
      await _load();
      _showSnack('Usuário banido com sucesso.');
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _showSnack('Não foi possível banir: $msg', error: true);
    } finally {
      if (mounted) {
        setState(() => _banningIds.remove(id));
      }
    }
  }

  // Um usuário que voltou a ficar PENDENTE/em análise ainda aparece no
  // histórico (registro antigo). Nesse caso o botão "Banir" fica desabilitado
  // (cinza), pois o banimento deve ser feito pelo chat (onde o botão já existe).
  bool _isCurrentlyPending(Map<String, dynamic> u) {
    final currentStatus = (u['currentStatus'] ?? '').toString().toUpperCase();
    return currentStatus == 'PENDING' ||
        currentStatus == 'TEMPORARILY_REJECTED';
  }

  Widget _banAccountButton(Map<String, dynamic> u, {bool disabled = false}) {
    final id = u['id'];
    final isBanning = id is int && _banningIds.contains(id);
    if (isBanning) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final color =
        disabled ? const Color(0xFF98A2B3) : const Color(0xFF7F1D1D);

    return InkWell(
      onTap: (id is int && !disabled) ? () => _confirmBan(u) : null,
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
            Icon(Icons.gavel, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              'Banir',
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

  Future<void> _confirmUnban(Map<String, dynamic> user) async {
    final id = user['id'];
    if (id is! int) return;

    final name = (user['name'] ?? 'Usuário').toString();

    final confirmed = await showDialog<bool>(
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

    setState(() => _banningIds.add(id));
    try {
      await AdminService.unbanUser(id);
      await _load();
      _showSnack('Usuário desbanido com sucesso.');
    } catch (e) {
      _showSnack('Não foi possível desbanir o usuário.', error: true);
    } finally {
      if (mounted) {
        setState(() => _banningIds.remove(id));
      }
    }
  }

  Widget _unbanButton(Map<String, dynamic> u) {
    final id = u['id'];
    final isBanning = id is int && _banningIds.contains(id);
    if (isBanning) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return InkWell(
      onTap: id is int ? () => _confirmUnban(u) : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF0B4DBA).withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFF0B4DBA).withValues(alpha: .3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_open, size: 14, color: Color(0xFF0B4DBA)),
            SizedBox(width: 4),
            Text(
              'Desbanir',
              style: TextStyle(
                color: Color(0xFF0B4DBA),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deleteIconButton(Map<String, dynamic> u, bool isDeleting) {
    final id = u['id'];
    if (isDeleting) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return InkWell(
      onTap: id == null ? null : () => _showDeleteOptions(u),
      borderRadius: BorderRadius.circular(999),
      child: const Padding(
        padding: EdgeInsets.all(4),
        child: Icon(
          Icons.delete_outline,
          size: 20,
          color: Colors.red,
        ),
      ),
    );
  }

  Widget _excludeAccountButton(Map<String, dynamic> u) {
    final id = u['id'];
    final isExcluding = id is int && _excludingIds.contains(id);
    if (isExcluding) {
      return const SizedBox(
        height: 18,
        width: 18,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return InkWell(
      onTap: id is int ? () => _confirmExclude(u) : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.red.withValues(alpha: .3)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_remove_outlined, size: 14, color: Colors.red),
            SizedBox(width: 4),
            Text(
              'Excluir conta',
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _clearHistoryLabel(String status, String singularSegment) {
    switch (status) {
      case 'APPROVED':
        return 'o histórico dos usuários aprovados';
      case 'REJECTED':
        return 'o histórico dos usuários rejeitados';
      case 'DELETED':
        return 'o histórico dos usuários excluídos';
      case 'BANNED':
        return 'o histórico dos usuários banidos';
      default:
        return 'todo o histórico de usuários $singularSegment';
    }
  }

  Future<void> _showClearHistoryOptions() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_sweep_outlined),
              title: const Text('Limpar todo o histórico'),
              onTap: () => Navigator.pop(context, 'ALL'),
            ),
            ListTile(
              leading: const Icon(Icons.cancel_outlined),
              title: const Text('Limpar só rejeitados'),
              onTap: () => Navigator.pop(context, 'REJECTED'),
            ),
            ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: const Text('Limpar só excluídos'),
              onTap: () => Navigator.pop(context, 'DELETED'),
            ),
            ListTile(
              leading: const Icon(Icons.gavel, color: Color(0xFF7F1D1D)),
              title: const Text('Limpar só banidos'),
              onTap: () => Navigator.pop(context, 'BANNED'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;
    final status = choice == 'ALL' ? null : choice;
    await _confirmClearHistory(status);
  }

  Future<void> _confirmClearHistory(String? status) async {
    final singularSegment = widget.userType == 'personal' ? 'Personal' : 'Aluno';
    final label = _clearHistoryLabel(status ?? 'ALL', singularSegment);

    final shouldClear = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Limpar histórico'),
            content: Text(
              'Você tem certeza que deseja excluir $label?\n\n'
              'Essa ação não poderá ser desfeita. O histórico de conversa entre o '
              'admin e o usuário também será apagado.\n\n'
              'Os usuários com status "Aprovado" não serão afetados.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Limpar histórico'),
              ),
            ],
          ),
        ) ??
        false;

    if (!shouldClear) return;

    setState(() => _clearing = true);
    try {
      await AdminService.clearHistory(widget.userType, status: status);
      await _load();
      _showSnack('Histórico limpo com sucesso.');
    } catch (_) {
      _showSnack('Não foi possível limpar o histórico.', error: true);
    } finally {
      if (mounted) {
        setState(() => _clearing = false);
      }
    }
  }

  int _countByStatus(String status) {
    return users.where((u) {
      final s = (u['status'] ?? '').toString().toUpperCase();
      final deleted = (u['deleted'] == true) || s == 'DELETED';
      final banned = (u['banned'] == true);
      if (status == 'APPROVED') return s == 'APPROVED' && !deleted;
      if (status == 'DELETED') return deleted;
      if (status == 'BANNED') return banned;
      return s == status;
    }).length;
  }

  Widget _metricCard({
    required String label,
    required int value,
    required IconData icon,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .18)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.toString(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF101828),
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF667085),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(String status, {bool deleted = false, bool banned = false}) {
    if (banned) {
      return _statusBadge('Banido', const Color(0xFF7F1D1D));
    }

    if (status == 'APPROVED' && deleted) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _statusBadge('Aprovado', Colors.grey),
          const SizedBox(width: 6),
          _statusBadge('Excluído', Colors.red),
        ],
      );
    }

    final color = _statusColor(status);
    return _statusBadge(_statusText(status), color);
  }

  Widget _statusBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

  void _openChat(Map<String, dynamic> u) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminTicketView(user: u, readOnly: true),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final segment = widget.userType == 'personal' ? 'Personais' : 'Alunos';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5FA),
      appBar: AppBar(
        elevation: 0,
        toolbarHeight: 76,
        titleSpacing: 20,
        actions: [
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
        title: Wrap(
          spacing: 10,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Histórico',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 30,
                color: Color(0xFF101828),
                height: 1.1,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0B4DBA).withValues(alpha: .10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: const Color(0xFF0B4DBA).withValues(alpha: .22),
                ),
              ),
              child: Text(
                segment,
                style: const TextStyle(
                  color: Color(0xFF0B4DBA),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFFF3F5FA),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(child: Text(error!))
          : Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0B4DBA), Color(0xFF0A3D93)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF0B4DBA).withValues(alpha: .22),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                height: 46,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: TextField(
                                  decoration: const InputDecoration(
                                    hintText: 'Buscar por nome ou email',
                                    prefixIcon: Icon(Icons.search),
                                    border: InputBorder.none,
                                    contentPadding: EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 12,
                                    ),
                                  ),
                                  onChanged: (v) {
                                    search = v;
                                    _applyFilter();
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: statusFilter,
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
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
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
                        Column(
                          children: [
                            Row(
                              children: [
                                _metricCard(
                                  label: 'Aprovados',
                                  value: _countByStatus('APPROVED'),
                                  icon: Icons.check_circle,
                                  color: Colors.green,
                                ),
                                const SizedBox(width: 10),
                                _metricCard(
                                  label: 'Rejeitados',
                                  value: _countByStatus('REJECTED'),
                                  icon: Icons.cancel,
                                  color: Colors.red,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _metricCard(
                                  label: 'Excluídos',
                                  value: _countByStatus('DELETED'),
                                  icon: Icons.person_off,
                                  color: Colors.blueGrey,
                                ),
                                const SizedBox(width: 10),
                                _metricCard(
                                  label: 'Banidos',
                                  value: _countByStatus('BANNED'),
                                  icon: Icons.block,
                                  color: const Color(0xFF7F1D1D),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed:
                                _clearing ? null : _showClearHistoryOptions,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white70,
                              side: const BorderSide(color: Colors.white70),
                              minimumSize: const Size.fromHeight(44),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_clearing)
                                  const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                else
                                  const Icon(
                                    Icons.delete_sweep_outlined,
                                    size: 18,
                                  ),
                                const SizedBox(width: 8),
                                Text(
                                  _clearing ? 'Limpando...' : 'Limpar histórico',
                                  style: const TextStyle(color: Colors.white),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.arrow_drop_down,
                                  color: Colors.white,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Nenhum usuário encontrado.',
                              style: TextStyle(
                                color: Color(0xFF667085),
                                fontSize: 15,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final u = Map<String, dynamic>.from(
                                filtered[index] as Map,
                              );
                              final id = u['id'] as int?;
                              final historyId = u['historyId'] as int?;
                              final status = (u['status'] ?? '')
                                  .toString()
                                  .toUpperCase();
                              final deleted =
                                  (u['deleted'] == true) || status == 'DELETED';
                              final banned = (u['banned'] == true);
                              final created = (u['createdAt'] ?? '').toString();
                              final date = formatIsoDateToPtBr(created);
                              final isDeleting =
                                  id != null && _deletingIds.contains(id);
                              final isDeletingEntry = historyId != null &&
                                  _deletingHistoryIds.contains(historyId);
                              final displayName = (u['name'] ?? '')
                                  .toString()
                                  .trim();
                              final avatarLetter = displayName.isEmpty
                                  ? '?'
                                  : displayName.characters.first.toUpperCase();

                              return Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE7ECF3),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: .03,
                                      ),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    _avatar(u, avatarLetter),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            displayName.isEmpty
                                                ? '-'
                                                : displayName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 20,
                                              color: Color(0xFF111827),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            (u['email'] ?? '-').toString(),
                                            style: const TextStyle(
                                              color: Color(0xFF667085),
                                              fontSize: 18,
                                            ),
                                          ),
                                          if (deleted &&
                                              (u['rejectionReason'] ?? '')
                                                  .toString()
                                                  .trim()
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Motivo da exclusão: ${(u['rejectionReason'] ?? '').toString().trim()}',
                                              style: const TextStyle(
                                                color: Color(0xFFB42318),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                          if ((u['cref'] ?? '')
                                              .toString()
                                              .trim()
                                              .isNotEmpty) ...[
                                            const SizedBox(height: 6),
                                            Text(
                                              'CREF: ${(u['cref'] ?? '').toString()}',
                                              style: const TextStyle(
                                                color: Color(0xFF0B4DBA),
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                          const SizedBox(height: 6),
                                          Text(
                                            'Cadastro: $date',
                                            style: const TextStyle(
                                              color: Color(0xFF98A2B3),
                                              fontSize: 16,
                                            ),
                                          ),
                                          if (!banned &&
                                              status == 'REJECTED' &&
                                              (u['rejectionReason'] ?? '')
                                                  .toString()
                                                  .trim()
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              'Motivo: ${(u['rejectionReason'] ?? '').toString().trim()}',
                                              style: const TextStyle(
                                                color: Color(0xFFB42318),
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        InkWell(
                                          onTap: () => _openChat(u),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                          child: const Padding(
                                            padding: EdgeInsets.all(4),
                                            child: Icon(
                                              Icons.chat_outlined,
                                              size: 20,
                                              color: Color(0xFF0B4DBA),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _statusChip(status,
                                                deleted: deleted, banned: banned),
                                            if (status == 'APPROVED' &&
                                                !deleted &&
                                                !banned) ...[
                                              const SizedBox(width: 6),
                                              _excludeAccountButton(u),
                                            ],
                                            const SizedBox(width: 6),
                                            if (banned)
                                              _unbanButton(u)
                                            else
                                              _banAccountButton(
                                                u,
                                                disabled:
                                                    _isCurrentlyPending(u),
                                              ),
                                            if (banned ||
                                                status == 'REJECTED' ||
                                                deleted) ...[
                                              const SizedBox(width: 6),
                                              _deleteIconButton(
                                                  u,
                                                  isDeleting ||
                                                      isDeletingEntry,
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        if (status == 'DELETED')
                                          const Text(
                                            'Conta desativada',
                                            style: TextStyle(
                                              color: Color(0xFF98A2B3),
                                              fontSize: 12,
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
                ],
              ),
            ),
    );
  }
}
