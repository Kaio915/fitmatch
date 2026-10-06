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
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 600;
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  // ================= HEADER =================
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isNarrow = constraints.maxWidth < 450;
                      final createAccountButton = ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B4DBA),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: isNarrow ? 14 : 20,
                            vertical: isNarrow ? 10 : 14,
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
                        child: Text(
                          isNarrow ? 'Criar conta' : 'Criar Conta Gratuita',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: isNarrow ? 13 : 14,
                          ),
                        ),
                      );
                      return Container(
                        width: isNarrow ? double.infinity : null,
                        height: isNarrow ? 96 : 92,
                        padding: EdgeInsets.symmetric(
                          horizontal: isNarrow ? 16 : 60,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            bottom: BorderSide(color: Color(0xFFE5E7EB)),
                          ),
                        ),
                        child: isNarrow
                            ? Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  FitMatchLogo(
                                    height: 58,
                                    assetPath:
                                        'assets/images/fitmatch_logo3.png',
                                  ),
                                  createAccountButton,
                                ],
                              )
                            : Row(
                                children: [
                                  const FitMatchLogo(
                                    height: 80,
                                    assetPath:
                                        'assets/images/fitmatch_logo3.png',
                                  ),
                                  const Spacer(),
                                  Padding(
                                    padding: const EdgeInsets.only(right: 56),
                                    child: createAccountButton,
                                  ),
                                ],
                              ),
                      );
                    },
                  ),

                  SizedBox(height: isMobile ? 12 : 60),

                  // ================= HERO =================
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: isMobile ? 20 : 40,
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Conecte-se com os Melhores Personal Trainers',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: width < 700 ? (isMobile ? 25 : 32) : 42,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(height: isMobile ? 8 : 14),
                        Text(
                          'A plataforma que une profissionais de educação física qualificados com alunos em busca de resultados reais',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color.fromARGB(255, 56, 54, 54),
                            fontSize: isMobile ? 12 : 16,
                          ),
                        ),
                        SizedBox(height: isMobile ? 16 : 30),
                        Text(
                          'Deseja fazer login como?',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: isMobile ? 13 : 16,
                            color: Colors.black,
                          ),
                        ),
                        SizedBox(height: isMobile ? 10 : 20),

                        // ================= LOGIN CARDS =================
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const spacing = 30.0;
                            final cardWidth =
                                constraints.maxWidth >= 2 * 220 + spacing
                                ? 220.0
                                : (constraints.maxWidth - spacing) / 2;
                            final canFitTwoCards = cardWidth >= 145;

                            return Wrap(
                              spacing: spacing,
                              runSpacing: 20,
                              alignment: WrapAlignment.center,
                              children: [
                                SizedBox(
                                  width: canFitTwoCards
                                      ? cardWidth
                                      : constraints.maxWidth,
                                  child: LoginChoiceCard(
                                    title: 'Aluno',
                                    icon: Icons.person_outline,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => LoginView(
                                            userType: UserType.aluno,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                SizedBox(
                                  width: canFitTwoCards
                                      ? cardWidth
                                      : constraints.maxWidth,
                                  child: LoginChoiceCard(
                                    title: 'Personal Trainer',
                                    icon: Icons.assignment_outlined,
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => LoginView(
                                            userType: UserType.personal,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: isMobile ? 28 : 70),

                  // ================= FEATURES =================
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: width < 650 ? 16 : 60,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;

                        int columns = 3;
                        if (width < 1000) columns = 2;
                        if (width < 650) columns = 1;

                        final cardWidth =
                            (width - ((columns - 1) * 20)) / columns;

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
        },
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxWidth < 180;

        return MouseRegion(
          onEnter: (_) => setState(() => hover = true),
          onExit: (_) => setState(() => hover = false),
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              transform: Matrix4.translationValues(
                0.0,
                hover ? -4.0 : 0.0,
                0.0,
              ),
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 112, maxHeight: 180),
              padding: EdgeInsets.all(isCompact ? 10 : 18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: hover
                      ? const Color(0xFFBFD3FF)
                      : const Color(0xFFE5E7EB),
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
                    width: isCompact ? 42 : 64,
                    height: isCompact ? 42 : 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      widget.icon,
                      size: isCompact ? 23 : 34,
                      color: const Color(0xFF0B4DBA),
                    ),
                  ),
                  SizedBox(height: isCompact ? 8 : 14),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isCompact ? 12 : 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
        transform: Matrix4.translationValues(0.0, hover ? -4.0 : 0.0, 0.0),
        constraints: const BoxConstraints(minHeight: 210),
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
            Text(
              widget.description,
              style: const TextStyle(
                fontSize: 14.5,
                color: Colors.black,
                height: 1.35,
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
