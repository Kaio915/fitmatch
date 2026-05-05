import 'package:flutter/material.dart';
import 'routes/app_routes.dart';
import 'services/auth_service.dart';
import 'theme/app_theme.dart';
import 'views/home_view.dart';
import 'views/student_dashboard.dart';
import 'views/trainer_dashboard_view.dart';
import 'views/admin_view.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FitMatch',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const _SessionRouter(),
      routes: AppRoutes.routes,
    );
  }
}

// ─── Session Router ───────────────────────────────────────────────────────────
// Verifica sessão salva ao iniciar/recarregar a página e redireciona para o
// dashboard correto, sem passar pela tela inicial.

class _SessionRouter extends StatefulWidget {
  const _SessionRouter();

  @override
  State<_SessionRouter> createState() => _SessionRouterState();
}

class _SessionRouterState extends State<_SessionRouter> {
  @override
  void initState() {
    super.initState();
    _restoreSession();
  }

  Future<void> _restoreSession() async {
    final session = await AuthService.loadSession();

    if (!mounted) return;

    if (session == null) {
      _goHome();
      return;
    }

    final type = (session['type'] ?? '').toString().toLowerCase();

    if (type == 'admin') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/admin'),
          builder: (_) => const AdminView(),
        ),
      );
    } else if (type == 'aluno') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/student'),
          builder: (_) => StudentDashboard(
            studentId: session['id'] != null ? (session['id'] as num).toInt() : null,
            userName: (session['name'] ?? '').toString(),
            email: session['email']?.toString(),
            objetivos: session['objetivos']?.toString(),
            nivel: session['nivel']?.toString(),
          ),
        ),
      );
    } else if (type == 'personal') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          settings: const RouteSettings(name: '/trainer'),
          builder: (_) => TrainerDashboardView(
            trainerId: session['id'] != null ? (session['id'] as num).toInt() : null,
            name: (session['name'] ?? '').toString(),
            cref: session['cref']?.toString(),
            cidade: session['cidade']?.toString(),
            especialidade: session['especialidade']?.toString(),
            valorHora: session['valorHora']?.toString(),
            horasPorSessao: session['horasPorSessao']?.toString(),
            bio: session['bio']?.toString(),
          ),
        ),
      );
    } else {
      _goHome();
    }
  }

  void _goHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: AppRoutes.home),
        builder: (_) => const HomeView(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0B4DBA),
      body: Center(
        child: CircularProgressIndicator(
          color: Colors.white,
          strokeWidth: 2.5,
        ),
      ),
    );
  }
}