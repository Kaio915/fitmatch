import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fitmatch/core/env/app_env.dart';

class AdminService {
  static const String _baseUrl = AppEnv.apiBaseUrl;

  static Future<List<dynamic>> getPendingStudents() async {
    final res = await http.get(Uri.parse('$_baseUrl/admin/pending/aluno'));
    if (res.statusCode != 200) {
      throw Exception('Erro ao buscar alunos pendentes');
    }
    return jsonDecode(res.body);
  }

  static Future<List<dynamic>> getPendingTrainers() async {
    final res = await http.get(Uri.parse('$_baseUrl/admin/pending/personal'));
    if (res.statusCode != 200) {
      throw Exception('Erro ao buscar personals pendentes');
    }
    return jsonDecode(res.body);
  }

  static Future<void> approveUser(int id) async {
    final res = await http.put(Uri.parse('$_baseUrl/admin/approve/$id'));
    if (res.statusCode != 200) {
      throw Exception('Erro ao aprovar usuário');
    }
  }

  // ✅ REJEITAR COM MOTIVO
  static Future<void> rejectUser(int id, {required String reason}) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/admin/reject/$id'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'reason': reason}),
    );

    if (res.statusCode != 200) {
      throw Exception('Erro ao rejeitar usuário');
    }
  }

  static Future<List<dynamic>> getUsersByType(String type, {String? status}) async {
    final uri = Uri.parse(
      status == null || status.isEmpty
          ? '$_baseUrl/admin/users/$type'
          : '$_baseUrl/admin/users/$type?status=$status',
    );

    final res = await http.get(uri);

    if (res.statusCode != 200) {
      throw Exception('Erro ao buscar usuários');
    }

    return jsonDecode(res.body);
  }

  static Future<void> deleteUser(int id) async {
    final res = await http.delete(Uri.parse('$_baseUrl/admin/users/$id'));
    if (res.statusCode != 200) {
      throw Exception('Erro ao excluir usuário');
    }
  }
}