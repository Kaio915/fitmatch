import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/auth_service.dart';
import '../views/register_success_view.dart';
import '../core/user_type.dart';

class RegisterStudentController {
  String nome = '';
  String email = '';
  String senha = '';
  String objetivos = '';
  String nivel = '';

  // ✅ NOVOS CAMPOS
  String cpf = '';
  XFile? photo;

  Future<void> submit(BuildContext context) async {
    try {
      // ✅ validações mínimas (a validação forte já está no Form)
      if (cpf.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Preencha o CPF')),
        );
        return;
      }

      if (photo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tire uma foto pela câmera')),
        );
        return;
      }

      await AuthService.registerStudent(
        name: nome,
        email: email,
        password: senha,
        cpf: cpf,
        photo: photo!, // aqui garantimos que não é null
        objetivos: objetivos,
        nivel: nivel,
      );

      if (!context.mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const RegisterSuccessView(
            userType: UserType.aluno,
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;

      // ✅ mostra o erro real vindo do backend (se tiver)
      final msg = e.toString().replaceFirst('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg.isEmpty ? 'Erro ao cadastrar aluno' : msg)),
      );
    }
  }
}