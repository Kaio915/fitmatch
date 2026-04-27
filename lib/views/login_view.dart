import 'package:flutter/material.dart';
import '../core/app_refresh_notifier.dart';
import '../core/user_type.dart';
import '../services/auth_service.dart';
import '../widgets/fitmatch_logo.dart';
import 'register_student_view.dart';
import 'register_trainer_view.dart';
import '../routes/app_routes.dart';
import 'admin_view.dart';
import 'student_dashboard.dart';
import 'trainer_dashboard_view.dart';

class LoginView extends StatefulWidget {
  final UserType userType;

  const LoginView({super.key, required this.userType});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool loading = false;

  // controla borda vermelha
  String? _fieldError; // se != null, pinta os campos

  void _onGlobalRefresh() {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _emailController.clear();
      _passwordController.clear();
      _fieldError = null;
      loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    AppRefreshNotifier.signal.addListener(_onGlobalRefresh);
  }

  @override
  void dispose() {
    AppRefreshNotifier.signal.removeListener(_onGlobalRefresh);
    _emailController.dispose();
    _passwordController.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isCredentialsError(String msg) {
    final m = msg.toLowerCase();
    return m.contains('usuário não encontrado') || m.contains('senha inválida');
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    setState(() => _fieldError = null);

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Preencha email e senha');
      return;
    }

    setState(() => loading = true);

    try {
      final user = await AuthService.login(
        email: email,
        password: password,
        type: widget.userType.name,
      );

      if (!mounted) return;

      final type = (user['type'] ?? '').toString().toLowerCase();

      if (type == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminView()),
        );
        return;
      }

        if (type == 'aluno') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => StudentDashboard(
              studentId: user['id'] != null ? (user['id'] as num).toInt() : null,
              userName: (user['name'] ?? '').toString(),
              email: user['email']?.toString(),
              objetivos: user['objetivos']?.toString(),
              nivel: user['nivel']?.toString(),
            ),
          ),
        );
        return;
      }

      if (type == 'personal') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TrainerDashboardView(
              trainerId: user['id'] != null ? (user['id'] as num).toInt() : null,
              name: (user['name'] ?? '').toString(),
              cref: user['cref']?.toString(),
              cidade: user['cidade']?.toString(),
              especialidade: user['especialidade']?.toString(),
              valorHora: user['valorHora']?.toString(),
              horasPorSessao: user['horasPorSessao']?.toString(),
              bio: user['bio']?.toString(),
            ),
          ),
        );
        return;
      }

      _showSnack('Tipo de usuário desconhecido: $type');
    } catch (e) {
      if (!mounted) return;

      final msg = e.toString().replaceFirst('Exception: ', '');
      _showSnack(msg);

      // só pinta de vermelho quando for erro de credencial
      if (_isCredentialsError(msg)) {
        setState(() => _fieldError = msg);
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _onEmailSubmitted(String _) {
    FocusScope.of(context).requestFocus(_passwordFocusNode);
  }

  void _onPasswordSubmitted(String _) {
    if (loading) return;
    _login();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Center(
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const FitMatchLogo(height: 60),
                    const SizedBox(height: 20),
                    const Text(
                      'Entrar',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Acesse sua conta FitMatch',
                      style: TextStyle(color: Colors.black),
                    ),
                    const SizedBox(height: 24),

                    _input(
                      'Email',
                      'seu@email.com',
                      controller: _emailController,
                      forceError: _fieldError != null,
                      focusNode: _emailFocusNode,
                      textInputAction: TextInputAction.next,
                      onSubmitted: _onEmailSubmitted,
                    ),
                    _input(
                      'Senha',
                      'Sua senha',
                      obscure: true,
                      controller: _passwordController,
                      forceError: _fieldError != null,
                      focusNode: _passwordFocusNode,
                      textInputAction: TextInputAction.done,
                      onSubmitted: _onPasswordSubmitted,
                    ),

                    const SizedBox(height: 16),

                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4DBA),
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: loading ? null : _login,
                      child: loading
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Entrar',
                              style: TextStyle(color: Colors.white),
                            ),
                    ),

                    const SizedBox(height: 16),

                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: () {
                          if (widget.userType == UserType.aluno) {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                settings: const RouteSettings(
                                  name: AppRoutes.registerStudent,
                                ),
                                builder: (_) => const RegisterStudentView(),
                              ),
                            );
                          } else {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                settings: const RouteSettings(
                                  name: AppRoutes.registerTrainer,
                                ),
                                builder: (_) => const RegisterTrainerView(),
                              ),
                            );
                          }
                        },
                        child: const Text.rich(
                          TextSpan(
                            text: 'Não tem uma conta? ',
                            style: TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                            ),
                            children: [
                              TextSpan(
                                text: 'Cadastre-se',
                                style: TextStyle(
                                  color: Color(0xFF0B4DBA),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(
    String label,
    String hint, {
    bool obscure = false,
    required TextEditingController controller,
    bool forceError = false,
    FocusNode? focusNode,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    final borderColor = forceError ? Colors.red : const Color(0xFF0B4DBA);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor, width: 1.4),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: borderColor, width: 2),
          ),
        ),
      ),
    );
  }
}