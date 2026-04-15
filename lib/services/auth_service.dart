import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';

class AuthService {
  static const String _baseUrl = 'http://localhost:8080';

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

  static String _mimeFromFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    return 'image/jpeg'; // default
  }

  static Future<http.MultipartFile> _photoToMultipart(XFile photo) async {
    final fileName = (photo.name.isNotEmpty) ? photo.name : 'photo.jpg';
    final mime = _mimeFromFileName(fileName);

    if (kIsWeb) {
      // ✅ WEB: envia bytes
      final Uint8List bytes = await photo.readAsBytes();
      return http.MultipartFile.fromBytes(
        'photo',
        bytes,
        filename: fileName,
        contentType: MediaType.parse(mime),
      );
    }

    // ✅ MOBILE/DESKTOP: envia por path
    return http.MultipartFile.fromPath(
      'photo',
      photo.path,
      filename: fileName,
      contentType: MediaType.parse(mime),
    );
  }

  // ✅ REGISTER STUDENT (MULTIPART)
  static Future<void> registerStudent({
    required String name,
    required String email,
    required String password,
    required String cpf,
    required XFile photo,
    required String objetivos,
    required String nivel,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/register/student');

    final request = http.MultipartRequest('POST', uri)
      ..fields['name'] = name.trim()
      ..fields['email'] = email.trim()
      ..fields['password'] = password.trim()
      ..fields['cpf'] = cpf.trim()
      ..fields['objetivos'] = objetivos.trim()
      ..fields['nivel'] = nivel.trim();

    request.files.add(await _photoToMultipart(photo));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ REGISTER TRAINER (MULTIPART)
  static Future<void> registerTrainer({
    required String name,
    required String email,
    required String password,
    required String cpf,
    required XFile photo,
    required String cref,
    required String cidade,
    required String especialidade,
    required String valorHora,
    required String bio,
  }) async {
    final uri = Uri.parse('$_baseUrl/auth/register/trainer');

    final request = http.MultipartRequest('POST', uri)
      ..fields['name'] = name.trim()
      ..fields['email'] = email.trim()
      ..fields['password'] = password.trim()
      ..fields['cpf'] = cpf.trim()
      ..fields['cref'] = cref.trim()
      ..fields['cidade'] = cidade.trim()
      ..fields['especialidade'] = especialidade.trim()
      ..fields['valorHora'] = valorHora.trim()
      ..fields['bio'] = bio.trim();

    request.files.add(await _photoToMultipart(photo));

    final streamed = await request.send();
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ LOGIN (JSON)
  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String type,
  }) async {
    http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$_baseUrl/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': email.trim(),
              'password': password.trim(),
              'type': type.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw Exception(
        'Tempo de conexão esgotado no login. Verifique se a API está rodando na porta 8080.',
      );
    }

    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }

    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ✅ LISTAR TRAINERS APROVADOS (opcionalmente filtrado para aluno)
  static Future<List<Map<String, dynamic>>> fetchTrainers({int? studentId}) async {
    final uri = studentId == null
        ? Uri.parse('$_baseUrl/auth/trainers')
        : Uri.parse('$_baseUrl/auth/trainers?studentId=$studentId');
    final res = await http.get(uri);
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ URL da foto de perfil de usuário
  static String getUserPhotoUrl(int userId) {
    return '$_baseUrl/auth/user/$userId/photo';
  }

  // ✅ ALUNO ENVIA SOLICITAÇÃO AO PERSONAL
  static Future<void> sendRequest({
    required int trainerId,
    required int studentId,
    required String studentName,
    required String trainerName,
    required String dayName,
    required String time,
    String planType = 'DIARIO',
    String? daysJson,
  }) async {
    final body = <String, dynamic>{
      'trainerId': trainerId,
      'studentId': studentId,
      'studentName': studentName,
      'trainerName': trainerName,
      'dayName': dayName,
      'time': time,
      'planType': planType,
    };
    if (daysJson != null) body['daysJson'] = daysJson;
    final res = await http.post(
      Uri.parse('$_baseUrl/requests'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ PERSONAL BUSCA SOLICITAÇÕES PENDENTES
  static Future<List<Map<String, dynamic>>> getTrainerRequests(
      int trainerId) async {
    final res = await http.get(
        Uri.parse('$_baseUrl/requests/trainer/$trainerId'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ PERSONAL BUSCA SOLICITAÇÕES APROVADAS (seus alunos)
  static Future<List<Map<String, dynamic>>> getApprovedTrainerRequests(
      int trainerId) async {
    final res = await http.get(
        Uri.parse('$_baseUrl/requests/trainer/$trainerId/approved'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ PERSONAL BUSCA HISTÓRICO COMPLETO DE SOLICITAÇÕES
  static Future<List<Map<String, dynamic>>> getAllTrainerRequests(
      int trainerId) async {
    final res = await http.get(
        Uri.parse('$_baseUrl/requests/trainer/$trainerId/all'));

    if (res.statusCode == 200) {
      final List<dynamic> data = jsonDecode(res.body);
      return data.cast<Map<String, dynamic>>();
    }

    // Compatibilidade: se backend ainda não expôs /all,
    // usa endpoint legado de pendentes para não quebrar o fluxo do personal.
    if (res.statusCode == 404 || res.statusCode == 405) {
      return getTrainerRequests(trainerId);
    }

    throw Exception(_extractErrorMessage(res));
  }

  // ✅ ALUNO BUSCA PRÓPRIAS SOLICITAÇÕES
  static Future<List<Map<String, dynamic>>> getStudentRequests(
      int studentId) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    var res = await http.get(
      Uri.parse('$_baseUrl/requests/student/$studentId/all?t=$ts'),
    );
    if (res.statusCode == 200) {
      final List<dynamic> data = jsonDecode(res.body);
      return data.cast<Map<String, dynamic>>();
    }

    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.get(
        Uri.parse('$_baseUrl/requests/student/$studentId?t=$ts'),
      );
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.cast<Map<String, dynamic>>();
      }
    }

    throw Exception(_extractErrorMessage(res));
  }

  // ✅ ALUNO APAGA UMA SOLICITAÇÃO
  static Future<void> deleteRequest(int requestId) async {
    final res = await http.delete(
        Uri.parse('$_baseUrl/requests/$requestId'));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ ALUNO OCULTA SOLICITAÇÃO DA SUA LISTA SEM APAGAR DO BANCO
  static Future<void> hideRequestForStudent(int requestId) async {
    var res = await http.patch(
      Uri.parse('$_baseUrl/requests/$requestId/hide-for-student'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );
    if (res.statusCode == 200 || res.statusCode == 204) return;

    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.post(
        Uri.parse('$_baseUrl/requests/$requestId/hide-for-student'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      );
      if (res.statusCode == 200 || res.statusCode == 204) return;
    }

    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.delete(
        Uri.parse('$_baseUrl/requests/$requestId/hide-for-student'),
      );
      if (res.statusCode == 200 || res.statusCode == 204) return;
    }

    throw Exception(_extractErrorMessage(res));
  }

  // ✅ ALUNO CANCELA SOLICITAÇÃO/PLANO SEM APAGAR HISTÓRICO
  static Future<void> cancelStudentRequest(
    int requestId, {
    String? reason,
  }) async {
    final cancelUri = Uri.parse('$_baseUrl/requests/$requestId/cancel-by-student')
        .replace(
      queryParameters: {
        if (reason != null && reason.trim().isNotEmpty)
          'reason': reason.trim(),
      },
    );

    var res = await http.patch(
      cancelUri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );

    if (res.statusCode == 200 || res.statusCode == 204) return;

    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.post(
        cancelUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      );
      if (res.statusCode == 200 || res.statusCode == 204) return;
    }

    if (res.statusCode == 404 || res.statusCode == 405) {
      final rejectRes = await http.patch(
        Uri.parse('$_baseUrl/requests/$requestId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': 'REJECTED'}),
      );
      if (rejectRes.statusCode == 200 || rejectRes.statusCode == 204) {
        return;
      }
      throw Exception(_extractErrorMessage(rejectRes));
    }

    throw Exception(_extractErrorMessage(res));
  }

  // ✅ PERSONAL remove solicitação apenas da sua lista
  static Future<void> hideRequestForTrainer(int requestId) async {
    var res = await http.patch(
      Uri.parse('$_baseUrl/requests/$requestId/hide-for-trainer'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );

    if (res.statusCode == 200 || res.statusCode == 204) return;

    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.post(
        Uri.parse('$_baseUrl/requests/$requestId/hide-for-trainer'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({}),
      );
      if (res.statusCode == 200 || res.statusCode == 204) return;
    }

    if (res.statusCode == 404) {
      final msg = _extractErrorMessage(res);
      if (msg.toLowerCase().contains('solicitação não encontrada')) {
        throw Exception(msg);
      }
    }

    if (res.statusCode == 404 || res.statusCode == 405) {
      final rejectRes = await http.patch(
        Uri.parse('$_baseUrl/requests/$requestId/status'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'status': 'REJECTED'}),
      );
      if (rejectRes.statusCode == 200 || rejectRes.statusCode == 204) {
        return;
      }

      if (rejectRes.statusCode == 404 || rejectRes.statusCode == 405) {
        throw Exception('Rota de ocultar solicitação não encontrada no backend. Reinicie/atualize a API.');
      }

      throw Exception(_extractErrorMessage(rejectRes));
    }

    throw Exception(_extractErrorMessage(res));
  }

  // ✅ BUSCA SLOTS BLOQUEADOS DE UM PERSONAL
  static Future<List<Map<String, dynamic>>> getTrainerSlots(
      int trainerId) async {
    final res =
        await http.get(Uri.parse('$_baseUrl/slots/trainer/$trainerId'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ PERSONAL BLOQUEIA UM HORÁRIO
  static Future<void> blockSlot(
    int trainerId,
    String dayName,
    String time, {
    String repeatMode = 'WEEKLY',
    String? dateIso,
    bool blockFullDay = false,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/slots/trainer/$trainerId/block'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'dayName': dayName,
        'time': time,
        'repeatMode': repeatMode,
        'dateIso': dateIso,
        'blockFullDay': blockFullDay,
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
  }

  // ✅ PERSONAL DESBLOQUEIA UM HORÁRIO
  static Future<void> unblockSlot(
    int trainerId,
    String dayName,
    String time, {
    String repeatMode = 'WEEKLY',
    String? dateIso,
    bool blockFullDay = false,
  }) async {
    final req = http.Request(
        'DELETE', Uri.parse('$_baseUrl/slots/trainer/$trainerId/block'));
    req.headers['Content-Type'] = 'application/json';
    req.body = jsonEncode({
      'dayName': dayName,
      'time': time,
      'repeatMode': repeatMode,
      'dateIso': dateIso,
      'blockFullDay': blockFullDay,
    });
    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ PERSONAL APROVA OU REJEITA SOLICITAÇÃO
  static Future<void> updateRequestStatus(
      int requestId, String status) async {
    final res = await http.patch(
      Uri.parse('$_baseUrl/requests/$requestId/status'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'status': status}),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
  }

  // ✅ PERSONAL BLOQUEIA ALUNO (impede novas solicitações)
  static Future<void> blockStudent(
    int trainerId,
    int studentId, {
    int? requestId,
  }) async {
    final queryParameters = requestId != null
        ? {'requestId': requestId.toString()}
        : null;

    var res = await http.post(
      Uri.parse('$_baseUrl/requests/trainer/$trainerId/students/$studentId/block').replace(
        queryParameters: queryParameters,
      ),
    );
    if (res.statusCode == 200) return;

    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.post(
        Uri.parse('$_baseUrl/connections/trainer/$trainerId/students/$studentId/block').replace(
          queryParameters: queryParameters,
        ),
      );
      if (res.statusCode == 200) return;
    }

    if (res.statusCode == 404 || res.statusCode == 405) {
      throw Exception('Rota de bloqueio não encontrada no backend. Reinicie o servidor da API.');
    }

    throw Exception(_extractErrorMessage(res));
  }

  // ✅ PERSONAL DESBLOQUEIA ALUNO
  static Future<void> unblockStudent(int trainerId, int studentId) async {
    var res = await http.delete(
      Uri.parse('$_baseUrl/requests/trainer/$trainerId/students/$studentId/block'),
    );
    if (res.statusCode == 200 || res.statusCode == 204) return;

    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.delete(
        Uri.parse('$_baseUrl/connections/trainer/$trainerId/students/$studentId/block'),
      );
      if (res.statusCode == 200 || res.statusCode == 204) return;
    }

    if (res.statusCode == 404 || res.statusCode == 405) {
      throw Exception('Rota de desbloqueio não encontrada no backend. Reinicie o servidor da API.');
    }

    throw Exception(_extractErrorMessage(res));
  }

  // ✅ PERSONAL REMOVE ALUNO APROVADO E LIBERA HORÁRIOS DO PLANO
  static Future<void> removeTrainerStudent(
    int trainerId,
    int studentId, {
    int? requestId,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/requests/trainer/$trainerId/students/$studentId',
    ).replace(
      queryParameters: requestId != null
          ? {'requestId': requestId.toString()}
          : null,
    );

    final res = await http.delete(
      uri,
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ PERSONAL LISTA ALUNOS BLOQUEADOS
  static Future<List<Map<String, dynamic>>> getBlockedStudents(int trainerId) async {
    var res = await http.get(
      Uri.parse('$_baseUrl/requests/trainer/$trainerId/students/blocked'),
    );
    if (res.statusCode == 200) {
      final List<dynamic> data = jsonDecode(res.body);
      return data.cast<Map<String, dynamic>>();
    }

    if (res.statusCode == 404 || res.statusCode == 405) {
      res = await http.get(
        Uri.parse('$_baseUrl/connections/trainer/$trainerId/students/blocked'),
      );
      if (res.statusCode == 200) {
        final List<dynamic> data = jsonDecode(res.body);
        return data.cast<Map<String, dynamic>>();
      }
    }

    if (res.statusCode == 404 || res.statusCode == 405) {
      return [];
    }

    throw Exception(_extractErrorMessage(res));
  }

  static Future<bool> isStudentBlockedByTrainer(int trainerId, int studentId) async {
    final blocked = await getBlockedStudents(trainerId);
    return blocked.any((b) =>
        (b['studentId']?.toString() ?? '') == studentId.toString());
  }

  // ✅ PERSONAL ATUALIZA PERFIL (cidade, valorHora, horasPorSessao)
  static Future<void> updateTrainerProfile(
    int trainerId, {
    String? cidade,
    String? valorHora,
    String? horasPorSessao,
  }) async {
    final body = <String, String>{};
    if (cidade != null) body['cidade'] = cidade;
    if (valorHora != null) body['valorHora'] = valorHora;
    if (horasPorSessao != null) body['horasPorSessao'] = horasPorSessao;

    final res = await http.patch(
      Uri.parse('$_baseUrl/auth/trainer/$trainerId/profile'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
  }

  // ✅ BUSCA CIDADES
  static Future<List<Map<String, dynamic>>> buscarCidades(String nome) async {
    try {
      final uri = Uri.parse(
        'http://127.0.0.1:8080/cidades?nome=${Uri.encodeComponent(nome)}',
      );

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('Erro ao buscar cidades: $e');
      return [];
    }
  }
  // ✅ CRIAR CONEXÃO (aluno seguir personal)
  static Future<Map<String, dynamic>> createConnection({
    required int studentId,
    required int trainerId,
    String studentName = 'Aluno',
    String trainerName = 'Personal',
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/connections'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'studentId': studentId,
        'trainerId': trainerId,
        'studentName': studentName,
        'trainerName': trainerName,
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ✅ REMOVER CONEXÃO
  static Future<void> deleteConnection(int connectionId) async {
    final res = await http.delete(
        Uri.parse('$_baseUrl/connections/$connectionId'));
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ BUSCAR CONEXÕES DE UM TRAINER (quem o segue)
  static Future<List<Map<String, dynamic>>> getTrainerConnections(
      int trainerId) async {
    final res = await http.get(
        Uri.parse('$_baseUrl/connections/trainer/$trainerId'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ BUSCAR ALUNOS APROVADOS DE UM TRAINER (com plano aceito)
  static Future<List<Map<String, dynamic>>> getTrainerApprovedConnections(
      int trainerId) async {
    final res = await http.get(
        Uri.parse('$_baseUrl/connections/trainer/$trainerId/approved'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ BUSCAR TRAINERS QUE O ALUNO SEGUE
  static Future<List<Map<String, dynamic>>> getStudentConnections(
      int studentId) async {
    final res = await http.get(
        Uri.parse('$_baseUrl/connections/student/$studentId'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ BUSCAR TODOS OS ALUNOS APROVADOS DA PLATAFORMA
  static Future<List<Map<String, dynamic>>> fetchStudents() async {
    final res = await http.get(Uri.parse('$_baseUrl/auth/students'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ CATÁLOGO DE TREINOS
  static Future<List<Map<String, dynamic>>> getWorkoutCatalog({String? query}) async {
    final uri = Uri.parse('$_baseUrl/workouts/catalog').replace(
      queryParameters: (query != null && query.trim().isNotEmpty)
          ? {'q': query.trim()}
          : null,
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ TREINOS PERSONALIZADOS DO PERSONAL
  static Future<List<Map<String, dynamic>>> getTrainerCustomExercises(int trainerId) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/custom-exercises'),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> createTrainerCustomExercise({
    required int trainerId,
    required String name,
    required String category,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/custom-exercises'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name.trim(),
        'category': category.trim(),
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateTrainerCustomExercise({
    required int trainerId,
    required int exerciseId,
    required String name,
    required String category,
  }) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/custom-exercises/$exerciseId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name.trim(),
        'category': category.trim(),
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> deleteTrainerCustomExercise({
    required int trainerId,
    required int exerciseId,
  }) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/custom-exercises/$exerciseId'),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ FAVORITOS DE TREINO DO PERSONAL
  static Future<List<Map<String, dynamic>>> getTrainerWorkoutFavorites(int trainerId) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/favorites'),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> createTrainerWorkoutFavorite({
    required int trainerId,
    required String name,
    required List<Map<String, String>> exercises,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/favorites'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name.trim(),
        'exercises': exercises,
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateTrainerWorkoutFavorite({
    required int trainerId,
    required int favoriteId,
    required String name,
    required List<Map<String, String>> exercises,
  }) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/favorites/$favoriteId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name.trim(),
        'exercises': exercises,
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> deleteTrainerWorkoutFavorite({
    required int trainerId,
    required int favoriteId,
  }) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/favorites/$favoriteId'),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  static Future<Map<String, dynamic>> cloneTrainerWorkoutFavorite({
    required int trainerId,
    required int favoriteId,
    required String name,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/favorites/$favoriteId/clone'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name.trim()}),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ✅ TREINOS POR DIA PARA ALUNO (PERSONAL)
  static Future<List<Map<String, dynamic>>> getTrainerStudentWorkoutPlans({
    required int trainerId,
    required int studentId,
  }) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/students/$studentId/plans'),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> upsertTrainerStudentWorkoutPlan({
    required int trainerId,
    required int studentId,
    required String dayName,
    String? time,
    required List<Map<String, String>> exercises,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/students/$studentId/plans'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'dayName': dayName.trim(),
        if (time != null && time.trim().isNotEmpty) 'time': time.trim(),
        'exercises': exercises,
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateTrainerStudentWorkoutPlan({
    required int trainerId,
    required int studentId,
    required int planId,
    required String dayName,
    String? time,
    required List<Map<String, String>> exercises,
  }) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/students/$studentId/plans/$planId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'dayName': dayName.trim(),
        if (time != null && time.trim().isNotEmpty) 'time': time.trim(),
        'exercises': exercises,
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> deleteTrainerStudentWorkoutPlan({
    required int trainerId,
    required int studentId,
    required int planId,
  }) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/workouts/trainer/$trainerId/students/$studentId/plans/$planId'),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ TREINOS POR DIA PARA ALUNO (VISÃO DO ALUNO)
  static Future<List<Map<String, dynamic>>> getStudentWorkoutPlansByTrainer({
    required int studentId,
    required int trainerId,
  }) async {
    final res = await http.get(
      Uri.parse('$_baseUrl/workouts/student/$studentId/trainer/$trainerId/plans'),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ AVALIAR PERSONAL
  static Future<void> rateTrainer({
    required int trainerId,
    required int studentId,
    required String studentName,
    required int stars,
    String? comment,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/ratings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'trainerId': trainerId,
        'studentId': studentId,
        'studentName': studentName,
        'stars': stars,
        'comment': comment ?? '',
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
  }

  // ✅ BUSCAR AVALIAÇÕES DE UM PERSONAL
  static Future<List<Map<String, dynamic>>> getTrainerRatings(
      int trainerId) async {
    final res = await http.get(
        Uri.parse('$_baseUrl/ratings/trainer/$trainerId'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ BUSCAR DADOS PÚBLICOS DE UM USUÁRIO (aluno ou personal)
  static Future<Map<String, dynamic>> getUserById(int userId) async {
    final res = await http.get(Uri.parse('$_baseUrl/auth/user/$userId'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ✅ PERSONAL AVALIA ALUNO
  static Future<void> rateStudent({
    required int trainerId,
    required int studentId,
    required String trainerName,
    required int stars,
    String? comment,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/student-ratings'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'trainerId': trainerId,
        'studentId': studentId,
        'trainerName': trainerName,
        'stars': stars,
        'comment': comment ?? '',
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ BUSCAR AVALIAÇÕES DE UM ALUNO
  static Future<List<Map<String, dynamic>>> getStudentRatings(
      int studentId) async {
    final res = await http.get(
        Uri.parse('$_baseUrl/student-ratings/student/$studentId'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  // ✅ DIETA - ALIMENTOS
  static Future<List<Map<String, dynamic>>> getDietFoods(int userId) async {
    final res = await http.get(Uri.parse('$_baseUrl/diet/$userId/foods'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  static Future<List<Map<String, dynamic>>> searchEdamamFoods({
    required int userId,
    required String query,
    int limit = 12,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return [];

    final uri = Uri.parse('$_baseUrl/diet/$userId/edamam/search').replace(
      queryParameters: {
        'query': q,
        'limit': limit.toString(),
      },
    );

    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> createDietFood({
    required int userId,
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    bool favorite = false,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/diet/$userId/foods'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name.trim(),
        'caloriesPer100g': caloriesPer100g,
        'proteinPer100g': proteinPer100g,
        'carbsPer100g': carbsPer100g,
        'fatPer100g': fatPer100g,
        'favorite': favorite,
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateDietFood({
    required int userId,
    required int foodId,
    required String name,
    required double caloriesPer100g,
    required double proteinPer100g,
    required double carbsPer100g,
    required double fatPer100g,
    bool favorite = false,
  }) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/diet/$userId/foods/$foodId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name.trim(),
        'caloriesPer100g': caloriesPer100g,
        'proteinPer100g': proteinPer100g,
        'carbsPer100g': carbsPer100g,
        'fatPer100g': fatPer100g,
        'favorite': favorite,
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> setDietFoodFavorite({
    required int userId,
    required int foodId,
    required bool favorite,
  }) async {
    final res = await http.patch(
      Uri.parse('$_baseUrl/diet/$userId/foods/$foodId/favorite'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'favorite': favorite}),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<List<Map<String, dynamic>>> getDietSavedMeals(int userId) async {
    final res = await http.get(Uri.parse('$_baseUrl/diet/$userId/saved-meals'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }

  static Future<Map<String, dynamic>> saveDietSavedMeal({
    required int userId,
    required String name,
    required String mealType,
    required List<Map<String, dynamic>> items,
  }) async {
    final encodedMealType = Uri.encodeComponent(mealType.trim());
    final res = await http.put(
      Uri.parse('$_baseUrl/diet/$userId/saved-meals/$encodedMealType'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name.trim(), 'items': items}),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> applyDietSavedMeal({
    required int userId,
    required int savedMealId,
    required String targetMealType,
    required String dateIso,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/diet/$userId/saved-meals/$savedMealId/apply'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'date': dateIso, 'targetMealType': targetMealType.trim()}),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> deleteDietSavedMeal({
    required int userId,
    required int savedMealId,
  }) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/diet/$userId/saved-meals/$savedMealId'),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  static Future<void> deleteDietFood({
    required int userId,
    required int foodId,
  }) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/diet/$userId/foods/$foodId'),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ DIETA - METAS
  static Future<Map<String, dynamic>> getDietGoals(int userId) async {
    final res = await http.get(Uri.parse('$_baseUrl/diet/$userId/goals'));
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> saveDietGoals({
    required int userId,
    required double basalKcal,
    required double targetKcal,
  }) async {
    final res = await http.put(
      Uri.parse('$_baseUrl/diet/$userId/goals'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'basalKcal': basalKcal,
        'targetKcal': targetKcal,
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ✅ DIETA - DIÁRIO
  static Future<Map<String, dynamic>> getDietEntriesByDate({
    required int userId,
    required String dateIso,
  }) async {
    final uri = Uri.parse('$_baseUrl/diet/$userId/entries')
        .replace(queryParameters: {'date': dateIso});
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> addDietEntry({
    required int userId,
    required int foodId,
    required String mealType,
    required double quantityGrams,
    required String dateIso,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/diet/$userId/entries'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'foodId': foodId,
        'mealType': mealType,
        'quantityGrams': quantityGrams,
        'date': dateIso,
      }),
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<void> deleteDietEntry({
    required int userId,
    required int entryId,
  }) async {
    final res = await http.delete(
      Uri.parse('$_baseUrl/diet/$userId/entries/$entryId'),
    );
    if (res.statusCode != 200 && res.statusCode != 204) {
      throw Exception(_extractErrorMessage(res));
    }
  }

  // ✅ ENVIAR MENSAGEM DE CHAT
  static Future<Map<String, dynamic>> sendChatMessage({
    required int senderId,
    required int receiverId,
    required String text,
  }) async {
    final res = await http.post(
      Uri.parse('$_baseUrl/chat/send'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'senderId': senderId,
        'receiverId': receiverId,
        'text': text,
      }),
    );
    if (res.statusCode != 200 && res.statusCode != 201) {
      throw Exception(_extractErrorMessage(res));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ✅ BUSCAR MENSAGENS DO CHAT ENTRE DOIS USUÁRIOS
  static Future<List<Map<String, dynamic>>> getChatMessages({
    required int userId1,
    required int userId2,
    int? requestId,
  }) async {
    final uri = Uri.parse('$_baseUrl/chat/conversation').replace(
      queryParameters: {
        'userId1': userId1.toString(),
        'userId2': userId2.toString(),
        if (requestId != null) 'requestId': requestId.toString(),
      },
    );

    final res = await http.get(
      uri,
    );
    if (res.statusCode != 200) throw Exception(_extractErrorMessage(res));
    final List<dynamic> data = jsonDecode(res.body);
    return data.cast<Map<String, dynamic>>();
  }
}