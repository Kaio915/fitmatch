import 'package:flutter/material.dart';
import 'login_view.dart';
import '../core/user_type.dart';

class RegisterSuccessView extends StatelessWidget {
  final UserType userType;

  const RegisterSuccessView({
    super.key,
    required this.userType,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 420,
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 16,
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle,
                  size: 64, color: Colors.green),
              const SizedBox(height: 16),
              const Text(
                'Cadastro Enviado!',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Seu cadastro foi enviado e está aguardando aprovação do administrador.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => LoginView(userType: userType),
                    ),
                  );
                },
                child: const Text('Voltar para início'),
              )
            ],
          ),
        ),
      ),
    );
  }
}

