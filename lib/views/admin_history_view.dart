import 'package:flutter/material.dart';
import '../core/app_refresh_notifier.dart';
import '../core/date_utils.dart';
import '../services/admin_service.dart';

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

  void _applyFilter() {
    final s = search.toLowerCase();

    List<dynamic> list = users.where((u) {
      final name = (u['name'] ?? '').toString().toLowerCase();
      final email = (u['email'] ?? '').toString().toLowerCase();
      final status = (u['status'] ?? '').toString().toUpperCase();
      final deleted = (u['deleted'] == true) || status == 'DELETED';

      final matchesSearch = s.isEmpty || name.contains(s) || email.contains(s);

      final matchesStatus = statusFilter == 'ALL'
          ? true
          : statusFilter == 'DELETED'
              ? deleted
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

    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Excluir usuário'),
            content: Text(
              'Você tem certeza que deseja excluir $name?\n\n'
              'Essa ação não poderá ser desfeita. O usuário será removido e o '
              'histórico de conversa entre o admin e o usuário também será apagado.',
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

    setState(() => _deletingIds.add(id));
    try {
      await AdminService.deleteUser(id);
      await _load();
      _showSnack('Usuário excluído com sucesso.');
    } catch (_) {
      _showSnack('Não foi possível excluir o usuário.', error: true);
    } finally {
      if (mounted) {
        setState(() => _deletingIds.remove(id));
      }
    }
  }

  String _clearHistoryLabel(String status, String singularSegment) {
    switch (status) {
      case 'APPROVED':
        return 'o histórico dos usuários aprovados';
      case 'REJECTED':
        return 'o histórico dos usuários rejeitados';
      case 'DELETED':
        return 'o histórico dos usuários excluídos';
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
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Limpar só aprovados'),
              onTap: () => Navigator.pop(context, 'APPROVED'),
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
              'Os usuários que estão com status "Aprovado" não serão excluídos — '
              'apenas o histórico deles será removido.',
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
      if (status == 'APPROVED') return s == 'APPROVED' && !deleted;
      if (status == 'DELETED') return deleted;
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

  Widget _statusChip(String status, {bool deleted = false}) {
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
                            const SizedBox(width: 10),
                            _metricCard(
                              label: 'Excluídos',
                              value: _countByStatus('DELETED'),
                              icon: Icons.person_off,
                              color: Colors.blueGrey,
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
                              final status = (u['status'] ?? '')
                                  .toString()
                                  .toUpperCase();
                              final deleted =
                                  (u['deleted'] == true) || status == 'DELETED';
                              final created = (u['createdAt'] ?? '').toString();
                              final date = formatIsoDateToPtBr(created);
                              final isDeleting =
                                  id != null && _deletingIds.contains(id);
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
                                          if (status == 'REJECTED' &&
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
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _statusChip(status, deleted: deleted),
                                            if (status == 'REJECTED' ||
                                                deleted) ...[
                                              const SizedBox(width: 6),
                                              if (isDeleting)
                                                const SizedBox(
                                                  height: 18,
                                                  width: 18,
                                                  child: Padding(
                                                    padding: EdgeInsets.all(2),
                                                    child:
                                                        CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                                  ),
                                                )
                                              else
                                                InkWell(
                                                  onTap: id == null
                                                      ? null
                                                      : () => _confirmDelete(u),
                                                  borderRadius:
                                                      BorderRadius.circular(999),
                                                  child: const Padding(
                                                    padding: EdgeInsets.all(4),
                                                    child: Icon(
                                                      Icons.delete_outline,
                                                      size: 20,
                                                      color: Colors.red,
                                                    ),
                                                  ),
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
