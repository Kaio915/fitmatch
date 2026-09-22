import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fitmatch/core/env/app_env.dart';
import 'package:fitmatch/services/auth_service.dart';

class AdminService {
  static const String _baseUrl = AppEnv.apiBaseUrl;

  // Motivo padrão aplicado ao banir um usuário.
  static const String banReason =
      'Usuário banido da plataforma por violar as diretrizes.';

  static Future<List<dynamic>> getPendingStudents() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/admin/pending/aluno'),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception('Erro ao buscar alunos pendentes');
    }
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> getPendingTrainers() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/admin/pending/personal'),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception('Erro ao buscar personals pendentes');
    }
    return jsonDecode(res.body);
  }

  static Future<void> approveUser(int id) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/admin/approve/$id'),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception('Erro ao aprovar usuário');
    }
  }

  // ✅ REJEITAR COM MOTIVO
  static Future<void> rejectUser(int id, {required String reason}) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/admin/reject/$id'),
      headers: await AuthService.authHeaders(json: true),
      body: jsonEncode({'reason': reason}),
    );

    if (res.statusCode != 200) {
      throw Exception('Erro ao rejeitar usuário');
    }
  }

  // ✅ REJEITAR TEMPORARIAMENTE (libera edição para o usuário)
  static Future<void> temporarilyRejectUser(int id, {required String reason}) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/admin/temporary-reject/$id'),
      headers: await AuthService.authHeaders(json: true),
      body: jsonEncode({'reason': reason}),
    );

    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  static Future<List<dynamic>> getUsersByType(String type, {String? status}) async {
    final uri = Uri.parse(
      status == null || status.isEmpty
          ? '$_baseUrl/admin/users/$type'
          : '$_baseUrl/admin/users/$type?status=$status',
    );

    final res = await http.get(uri, headers: await AuthService.authHeaders());

    if (res.statusCode != 200) {
      throw Exception('Erro ao buscar usuários');
    }

    return jsonDecode(res.body);
  }

  static Future<void> deleteUser(int id) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/admin/users/$id'),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception('Erro ao excluir usuário');
    }
  }

  // Exclui apenas um cadastro (um único registro do histórico).
  static Future<void> deleteHistoryEntry(int historyId) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/admin/history-entry/$historyId'),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception('Erro ao excluir cadastro');
    }
  }

  // Exclui todos os cadastros de um usuário para um tipo específico
  // (aluno/personal), mantendo o histórico do outro tipo separado.
  static Future<void> deleteUserHistory(int id, String type) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/admin/users/$id/history?type=$type'),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception('Erro ao excluir cadastros');
    }
  }

  static Future<void> excludeAccount(int id, {required String reason}) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/admin/users/$id/exclude'),
      headers: await AuthService.authHeaders(json: true),
      body: jsonEncode({'reason': reason}),
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ Banir usuário (rejeita ou exclui a conta automaticamente)
  static Future<void> banUser(int id, {required String reason}) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/admin/ban/$id'),
      headers: await AuthService.authHeaders(json: true),
      body: jsonEncode({'reason': reason}),
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ Desbanir usuário (volta a permitir login/cadastro)
  static Future<void> unbanUser(int id) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/admin/unban/$id'),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ Busca a rejeição anterior de um email (motivo + última mensagem do admin)
  static Future<Map<String, dynamic>> getPreviousRejection(String email) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/admin/previous-rejection').replace(
        queryParameters: {'email': email.trim()},
      ),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ✅ Busca a exclusão de conta anterior de um email (motivo da exclusão)
  static Future<Map<String, dynamic>> getPreviousExclusion(String email) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/admin/previous-exclusion').replace(
        queryParameters: {'email': email.trim()},
      ),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ✅ Busca o banimento anterior de um email (motivo do banimento)
  static Future<Map<String, dynamic>> getPreviousBan(String email) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/admin/previous-ban').replace(
        queryParameters: {'email': email.trim()},
      ),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> clearHistory(String type, {String? status}) async {
    final query = (status == null || status.isEmpty) ? '' : '?status=$status';
    final res = await http.delete(
      Uri.parse('$_baseUrl/admin/history/$type$query'),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ USUÁRIOS REPORTADOS — contagem de não visualizados
  static Future<int> getReportCount() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/admin/reports/count'),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception('Erro ao buscar contagem de usuários reportados');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    return (data['count'] as num?)?.toInt() ?? 0;
  }

  // ✅ USUÁRIOS REPORTADOS — lista (marca como visto no servidor)
  static Future<List<dynamic>> getReportedUsers() async {
    final res = await http.get(
      Uri.parse('$_baseUrl/admin/reports'),
      headers: await AuthService.authHeaders(),
    );
    if (res.statusCode != 200) {
      throw Exception('Erro ao buscar usuários reportados');
    }
    return jsonDecode(res.body);
  }

  // ✅ Denunciar um usuário ao admin (usado por aluno/personal no chat)
  static Future<void> reportUser({
    required int reporterId,
    required int reportedUserId,
    required String reason,
    String? details,
  }) async {
    final body = <String, dynamic>{
      'reporterId': reporterId,
      'reportedUserId': reportedUserId,
      'reason': reason,
    };
    if (details != null && details.trim().isNotEmpty) {
      body['details'] = details.trim();
    }

    final res = await http.post(
      Uri.parse('$_baseUrl/reports'),
      headers: await AuthService.authHeaders(json: true),
      body: jsonEncode(body),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  static String _extractErrorMessage(http.Response res) {
    try {
      final data = jsonDecode(res.body);
      if (data is Map<String, dynamic>) {
        final msg = data['message'] ?? data['error'] ?? data['msg'];
        if (msg != null && msg.toString().trim().isNotEmpty) {
          return msg.toString();
        }
      }
    } catch (_) {
      // ignora se não for JSON
    }

    final raw = res.body.toString().trim();
    if (raw.isNotEmpty) return raw;

    return 'Erro (${res.statusCode})';
  }
}