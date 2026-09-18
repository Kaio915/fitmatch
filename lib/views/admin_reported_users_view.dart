import 'package:flutter/material.dart';
import '../core/app_refresh_notifier.dart';
import '../core/date_utils.dart';
import '../services/admin_service.dart';
import 'admin_ticket_view.dart';

const List<String> _reportExclusionReasons = [
  'Informações falsas ou fraudulentas no cadastro.',
  'Comportamento inadequado com outros usuários.',
  'Tentativa de fraude ou golpe.',
  'Conta duplicada.',
  'Uso indevido da plataforma (spam/propaganda).',
];

const String _otherExclusionReason = 'Outro';

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

      final matchesSearch = s.isEmpty ||
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
        builder: (_) => AdminTicketView(user: u),
      ),
    );
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
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Tem certeza que deseja excluir a conta de $name?\n'
                      'O usuário não conseguirá mais fazer login.',
                    ),
                    const SizedBox(height: 16),
                    for (final reason in _reportExclusionReasons)
                      RadioListTile<String>(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(reason),
                        value: reason,
                        groupValue: selectedReason,
                        onChanged: (v) =>
                            setDialogState(() => selectedReason = v),
                      ),
                    RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Outro'),
                      value: _otherExclusionReason,
                      groupValue: selectedReason,
                      onChanged: (v) =>
                          setDialogState(() => selectedReason = v),
                    ),
                    if (selectedReason == _otherExclusionReason)
                      TextField(
                        autofocus: true,
                        onChanged: (v) => setDialogState(() => otherReason = v),
                        decoration: const InputDecoration(
                          hintText: 'Descreva o motivo',
                          border: OutlineInputBorder(),
                        ),
                      ),
                  ],
                ),
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
                  onPressed:
                      _canConfirmExclusion(selectedReason, otherReason)
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

    final finalReason = selectedReason == _otherExclusionReason
        ? otherReason.trim()
        : (selectedReason ?? '').trim();

    setState(() => _busyIds.add(id));
    try {
      await AdminService.excludeAccount(id, reason: finalReason);
      await _load();
      _showSnack('Conta excluída com sucesso.');
    } catch (_) {
      _showSnack('Não foi possível excluir a conta.', error: true);
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
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
              'automaticamente.',
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

    setState(() => _busyIds.add(id));
    try {
      await AdminService.banUser(id, reason: AdminService.banReason);
      await _load();
      _showSnack('Usuário banido com sucesso.');
    } catch (e) {
      _showSnack(
        'Não foi possível banir: ${e.toString().replaceFirst('Exception: ', '')}',
        error: true,
      );
    } finally {
      if (mounted) setState(() => _busyIds.remove(id));
    }
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

  Future<void> _confirmDelete(Map<String, dynamic> user) async {
    final id = user['id'];
    if (id is! int) return;

    final name = (user['name'] ?? 'Usuário').toString();

    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Excluir usuário'),
            content: Text(
              'Tem certeza que deseja excluir $name?\n\n'
              'Essa ação não poderá ser desfeita. O usuário será removido e o '
              'histórico de conversa também será apagado.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Excluir'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    setState(() => _busyIds.add(id));
    try {
      await AdminService.deleteUser(id);
      await _load();
      _showSnack('Usuário excluído com sucesso.');
    } catch (_) {
      _showSnack('Não foi possível excluir o usuário.', error: true);
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
            : Padding(
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
                          borderSide: const BorderSide(color: Color(0xFFE7ECF3)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE7ECF3)),
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
                              border:
                                  Border.all(color: const Color(0xFFE7ECF3)),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: statusFilter,
                                isExpanded: true,
                                items: const [
                                  DropdownMenuItem(
                                      value: 'ALL', child: Text('Todos')),
                                  DropdownMenuItem(
                                      value: 'APPROVED',
                                      child: Text('Aprovados')),
                                  DropdownMenuItem(
                                      value: 'REJECTED',
                                      child: Text('Rejeitados')),
                                  DropdownMenuItem(
                                      value: 'DELETED',
                                      child: Text('Excluídos')),
                                  DropdownMenuItem(
                                      value: 'BANNED',
                                      child: Text('Banidos')),
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
                                    value: 'DATA', child: Text('Data')),
                                DropdownMenuItem(
                                    value: 'NOME', child: Text('Nome')),
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
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                error ?? 'Nenhum usuário reportado.',
                                style: const TextStyle(
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
                                return _reportCard(u);
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _reportCard(Map<String, dynamic> u) {
    final id = u['id'] as int?;
    final status = (u['status'] ?? '').toString().toUpperCase();
    final banned = (u['banned'] == true);
    final deleted = (u['deleted'] == true) || status == 'DELETED';
    final isNew = (u['new'] == true);
    final name = (u['name'] ?? '').toString().trim();
    final avatarLetter =
        name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final lastReportAt =
        formatIsoDateToPtBr((u['lastReportAt'] ?? '').toString());
    final reportCount =
        (u['reportCount'] is num) ? (u['reportCount'] as num).toInt() : 0;
    final reason = (u['lastReportReason'] ?? '').toString().trim();
    final details = (u['lastReportDetails'] ?? '').toString().trim();
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

    return Container(
      padding: const EdgeInsets.all(16),
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
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFE6EEFF),
            child: Text(
              avatarLetter,
              style: const TextStyle(
                color: Color(0xFF0B4DBA),
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
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
                            horizontal: 8, vertical: 3),
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
                const SizedBox(height: 6),
                Text(
                  'Denunciado em: $lastReportAt'
                  '${reportCount > 0 ? '  •  $reportCount denúncia(s)' : ''}',
                  style: const TextStyle(
                    color: Color(0xFF98A2B3),
                    fontSize: 14,
                  ),
                ),
                if (reason.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Motivo: $reason',
                    style: const TextStyle(
                      color: Color(0xFFB42318),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Detalhes: $details',
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 14,
                    ),
                  ),
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
                      _actionButton(
                        label: 'Excluir conta',
                        icon: Icons.person_off_outlined,
                        color: const Color(0xFFB42318),
                        onTap: id == null ? () {} : () => _confirmExclude(u),
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
                          onTap: id == null ? () {} : () => _confirmBan(u),
                        ),
                      InkWell(
                        onTap: id == null ? null : () => _confirmDelete(u),
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.delete_outline,
                            size: 22,
                            color: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
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
          ),
        ],
      ),
    );
  }
}







