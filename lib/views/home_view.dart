import 'package:flutter/material.dart';

import '../views/register_student_view.dart';
import '../views/login_view.dart';
import '../core/user_type.dart';
import '../widgets/fitmatch_logo.dart';
import '../routes/app_routes.dart';

class HomeView extends StatelessWidget {
  const HomeView({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // ================= HEADER =================
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 16),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE5E7EB)),
                ),
              ),
              child: Row(
                children: [
                  // FitMatch totalmente à esquerda
                  const FitMatchLogo(height: 54),

                  const Spacer(),

                  // botão totalmente à direita
                  Padding(
                    padding: const EdgeInsets.only(right: 56),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4DBA),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            settings: const RouteSettings(
                              name: AppRoutes.registerStudent,
                            ),
                            builder: (_) => const RegisterStudentView(),
                          ),
                        );
                      },
                      child: const Text(
                        'Criar Conta Gratuita',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 60),

            // ================= HERO =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                children: [
                  Text(
                    'Conecte-se com os Melhores Personal Trainers',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: width < 700 ? 32 : 42,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'A plataforma que une profissionais de educação física qualificados com\nalunos em busca de resultados reais',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color.fromARGB(255, 56, 54, 54),
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Deseja fazer login como?',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ================= LOGIN CARDS =================
                  Wrap(
                    spacing: 30,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      LoginChoiceCard(
                        title: 'Aluno',
                        icon: Icons.person_outline,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  LoginView(userType: UserType.aluno),
                            ),
                          );
                        },
                      ),
                      LoginChoiceCard(
                        title: 'Personal Trainer',
                        icon: Icons.assignment_outlined,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  LoginView(userType: UserType.personal),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 70),

            // ================= FEATURES =================
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;

                  int columns = 3;
                  if (width < 1000) columns = 2;
                  if (width < 650) columns = 1;

                  final cardWidth = (width - ((columns - 1) * 20)) / columns;

                  final features = const [
                    _FeatureData(
                      icon: Icons.search,
                      title: 'Busca Inteligente',
                      description:
                          'Encontre personal trainers por especialidade, localização e disponibilidade.',
                    ),
                    _FeatureData(
                      icon: Icons.group,
                      title: 'Conexão Direta',
                      description:
                          'Conecte-se diretamente com profissionais qualificados e certificados.',
                    ),
                    _FeatureData(
                      icon: Icons.restaurant_menu,
                      title: 'Dieta',
                      description:
                          'Gerencie sua alimentação e acompanhe seu plano nutricional diariamente.',
                    ),
                  ];

                  return Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: features
                        .map(
                          (f) => SizedBox(
                            width: cardWidth,
                            child: FeatureCardLarge(
                              icon: f.icon,
                              title: f.title,
                              description: f.description,
                            ),
                          ),
                        )
                        .toList(),
                  );
                },
              ),
            ),

            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class LoginChoiceCard extends StatefulWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const LoginChoiceCard({
    super.key,
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  State<LoginChoiceCard> createState() => _LoginChoiceCardState();
}

class _LoginChoiceCardState extends State<LoginChoiceCard> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0.0, hover ? -4.0 : 0.0, 0.0),
          width: 220,
          height: 180,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hover ? const Color(0xFFBFD3FF) : const Color(0xFFE5E7EB),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .06),
                blurRadius: 16,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  widget.icon,
                  size: 34,
                  color: const Color(0xFF0B4DBA),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FeatureCardLarge extends StatefulWidget {
  final IconData icon;
  final String title;
  final String description;

  const FeatureCardLarge({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  @override
  State<FeatureCardLarge> createState() => _FeatureCardLargeState();
}

class _FeatureCardLargeState extends State<FeatureCardLarge> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 210,
        transform: Matrix4.translationValues(0.0, hover ? -4.0 : 0.0, 0.0),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: hover ? const Color(0xFFBFD3FF) : const Color(0xFFE5E7EB),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: .06),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(widget.icon, color: const Color(0xFF0B4DBA)),
            ),
            const SizedBox(height: 14),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Text(
                widget.description,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: Colors.black,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureData {
  final IconData icon;
  final String title;
  final String description;

  const _FeatureData({
    required this.icon,
    required this.title,
    required this.description,
  });
}