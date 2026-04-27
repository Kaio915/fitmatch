import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import '../core/user_type.dart';
import '../services/auth_service.dart';
import '../widgets/fitmatch_logo.dart';
import 'login_view.dart';
import 'register_success_view.dart';
import 'register_trainer_view.dart';
import '../routes/app_routes.dart';
import '../core/app_refresh_notifier.dart';

class RegisterStudentView extends StatefulWidget {
  const RegisterStudentView({super.key});

  @override
  State<RegisterStudentView> createState() => _RegisterStudentViewState();
}

class _RegisterStudentViewState extends State<RegisterStudentView> {
  final _formKey = GlobalKey<FormState>();

  // controllers
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();
  final _cpfCtrl = TextEditingController();

  bool _showPassword = false;
  bool _showConfirmPassword = false;

  // ✅ Objetivo: dropdown + "Outro" com campo livre
  String? _objetivoSelecionado;
  final _objetivoOutroCtrl = TextEditingController();

  String? nivelSelecionado;
  bool loading = false;

  // CPF mask
  final _cpfMask = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {"#": RegExp(r'[0-9]')},
  );

  // Image
  final ImagePicker _picker = ImagePicker();
  XFile? _photo;
  Uint8List? _photoBytes; // ✅ preview no Web

  // ✅ Opções de objetivo
  final List<String> _objetivos = const [
    'Perder peso',
    'Ganhar massa muscular',
    'Definir / Hipertrofia',
    'Aumentar força',
    'Melhorar condicionamento',
    'Melhorar saúde e disposição',
    'Melhorar postura',
    'Reabilitação / Fortalecimento',
    'Preparação para prova (corrida, TAF, etc.)',
    'Outro',
  ];

  @override
  void initState() {
    super.initState();
    AppRefreshNotifier.signal.addListener(_handleRefresh);
  }

  void _handleRefresh() {
    if (!mounted) return;
    setState(() {
      _formKey.currentState?.reset();
      _nameCtrl.clear();
      _emailCtrl.clear();
      _passCtrl.clear();
      _confirmPassCtrl.clear();
      _cpfCtrl.clear();
      _cpfMask.clear();
      _objetivoOutroCtrl.clear();
      _objetivoSelecionado = null;
      nivelSelecionado = null;
      _photo = null;
      _photoBytes = null;
      _showPassword = false;
      _showConfirmPassword = false;
    });
  }

  @override
  void dispose() {
    AppRefreshNotifier.signal.removeListener(_handleRefresh);
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    _cpfCtrl.dispose();
    _objetivoOutroCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isValidCPF(String cpfMasked) {
    final numbers = cpfMasked.replaceAll(RegExp(r'[^0-9]'), '');
    if (numbers.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(numbers)) return false;

    int calcDigit(String base, int factor) {
      int sum = 0;
      for (int i = 0; i < base.length; i++) {
        sum += int.parse(base[i]) * (factor - i);
      }
      int mod = (sum * 10) % 11;
      return (mod == 10) ? 0 : mod;
    }

    final d1 = calcDigit(numbers.substring(0, 9), 10);
    final d2 = calcDigit(numbers.substring(0, 10), 11);

    return numbers.endsWith('$d1$d2');
  }

  Future<void> _pickPhoto() async {
    // ✅ Web: escolhe arquivo/galeria
    // ✅ Mobile: somente câmera
    final source = kIsWeb ? ImageSource.gallery : ImageSource.camera;

    final XFile? picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.front,
    );

    if (picked == null) return;

    Uint8List? bytes;
    if (kIsWeb) {
      bytes = await picked.readAsBytes();
    }

    setState(() {
      _photo = picked;
      _photoBytes = bytes;
    });
  }

  String _objetivoFinal() {
    if ((_objetivoSelecionado ?? '').trim() == 'Outro') {
      return _objetivoOutroCtrl.text.trim();
    }
    return (_objetivoSelecionado ?? '').trim();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_photo == null) {
      _showSnack('Tire/Selecione uma foto para continuar');
      return;
    }

    final cpfMasked = _cpfMask.getMaskedText().trim();
    if (!_isValidCPF(cpfMasked)) {
      _showSnack('CPF inválido');
      return;
    }

    final objetivo = _objetivoFinal();
    if (objetivo.isEmpty) {
      _showSnack('Selecione seu objetivo');
      return;
    }

    setState(() => loading = true);

    try {
      await AuthService.registerStudent(
        name: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        password: _passCtrl.text.trim(),
        cpf: cpfMasked,
        photo: _photo!, // XFile
        objetivos: objetivo,
        nivel: (nivelSelecionado ?? '').trim(),
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const RegisterSuccessView(userType: UserType.aluno),
        ),
      );
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _showSnack(msg);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 1020,
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
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        '← Voltar',
                        style: TextStyle(color: Colors.black),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const FitMatchLogo(height: 48),
                  const SizedBox(height: 20),
                  const Text(
                    'Criar Conta',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Escolha o tipo de conta e preencha seus dados',
                    style: TextStyle(color: Color.fromARGB(255, 56, 54, 54)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),

                  // Toggle
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.05),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Text(
                                'Aluno',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  settings: const RouteSettings(
                                    name: AppRoutes.registerTrainer,
                                  ),
                                  builder: (_) => const RegisterTrainerView(),
                                ),
                              );
                            },
                            child: Container(
                              height: 44,
                              alignment: Alignment.center,
                              child: const Text(
                                'Personal Trainer',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  _input(
                    'Nome Completo *',
                    'Seu nome',
                    controller: _nameCtrl,
                  ),
                  _input(
                    'Email *',
                    'seu@email.com',
                    controller: _emailCtrl,
                    isEmail: true,
                  ),
                  _input(
                    'Senha *',
                    'Mínimo 6 caracteres',
                    controller: _passCtrl,
                    obscure: !_showPassword,
                    isPassword: true,
                    suffixIcon: IconButton(
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  _input(
                    'Confirmar Senha *',
                    'Repita a senha',
                    controller: _confirmPassCtrl,
                    obscure: !_showConfirmPassword,
                    customValidator: (value) {
                      final v = (value ?? '').trim();
                      if (v.isEmpty) return 'Campo obrigatório';
                      if (v != _passCtrl.text.trim()) {
                        return 'As senhas não coincidem';
                      }
                      return null;
                    },
                    suffixIcon: IconButton(
                      onPressed: () => setState(
                        () => _showConfirmPassword = !_showConfirmPassword,
                      ),
                      icon: Icon(
                        _showConfirmPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                    ),
                  ),

                  // CPF
                  _cpfField(),

                  // Foto
                  _photoField(),

                  // ✅ Objetivos (dropdown + "Outro")
                  _objetivosDropdown(),

                  _dropdownNivel(),

                  const SizedBox(height: 24),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0B4DBA),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: loading ? null : _submit,
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
                            'Criar Conta de Aluno',
                            style: TextStyle(color: Colors.white),
                          ),
                  ),

                  const SizedBox(height: 16),

                  TextButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(
                          builder: (_) => LoginView(userType: UserType.aluno),
                        ),
                      );
                    },
                    child: const Text(
                      'Já tem uma conta? Entrar',
                      style: TextStyle(color: Colors.black),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cpfField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text(
          'CPF *',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _cpfCtrl,
          inputFormatters: [_cpfMask],
          keyboardType: TextInputType.number,
          validator: (value) {
            final v = (value ?? '').trim();
            if (v.isEmpty) return 'Campo obrigatório';
            if (!_isValidCPF(v)) return 'CPF inválido';
            return null;
          },
          decoration: _decoration('000.000.000-00'),
        ),
      ]),
    );
  }

  Widget _photoField() {
    final label = kIsWeb
        ? 'Foto * (Web: escolher arquivo)'
        : 'Foto * (Mobile: usar câmera)';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _pickPhoto,
              icon: Icon(kIsWeb ? Icons.upload_file : Icons.camera_alt),
              label: Text(kIsWeb ? 'Selecionar' : 'Tirar foto'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0B4DBA),
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _photo == null ? 'Nenhuma foto escolhida' : _photo!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // Preview (Web: memory / Mobile: file)
        if (_photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: kIsWeb
                ? Image.memory(
                    _photoBytes!,
                    height: 130,
                    fit: BoxFit.cover,
                  )
                : Image.file(
                    File(_photo!.path),
                    height: 130,
                    fit: BoxFit.cover,
                  ),
          ),
      ]),
    );
  }

  // ✅ Objetivo com dropdown + campo quando selecionar "Outro"
  Widget _objetivosDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Objetivo *',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: _objetivoSelecionado,
            items: _objetivos
                .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                .toList(),
            onChanged: (value) {
              setState(() => _objetivoSelecionado = value);
              if (value != 'Outro') _objetivoOutroCtrl.clear();
            },
            validator: (value) {
              if (value == null || value.isEmpty) return 'Selecione uma opção';
              if (value == 'Outro' && _objetivoOutroCtrl.text.trim().isEmpty) {
                return 'Escreva seu objetivo';
              }
              return null;
            },
            decoration: _decoration('Selecione seu objetivo'),
          ),
          if (_objetivoSelecionado == 'Outro') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _objetivoOutroCtrl,
              validator: (value) {
                if (_objetivoSelecionado == 'Outro' &&
                    (value == null || value.trim().isEmpty)) {
                  return 'Campo obrigatório';
                }
                return null;
              },
              decoration: _decoration('Descreva seu objetivo'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dropdownNivel() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nível de Condicionamento *',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            initialValue: nivelSelecionado,
            items: const [
              DropdownMenuItem(value: 'Iniciante', child: Text('Iniciante')),
              DropdownMenuItem(value: 'Intermediário', child: Text('Intermediário')),
              DropdownMenuItem(value: 'Avançado', child: Text('Avançado')),
            ],
            onChanged: (value) => setState(() => nivelSelecionado = value),
            validator: (value) {
              if (value == null || value.isEmpty) return 'Selecione uma opção';
              return null;
            },
            decoration: _decoration('Selecione seu nível'),
          ),
        ],
      ),
    );
  }

  Widget _input(
    String label,
    String hint, {
    bool obscure = false,
    bool isEmail = false,
    bool isPassword = false,
    String? Function(String?)? customValidator,
    Widget? suffixIcon,
    required TextEditingController controller,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            obscureText: obscure,
            validator: (value) {
              if (customValidator != null) return customValidator(value);
              final v = (value ?? '').trim();
              if (v.isEmpty) return 'Campo obrigatório';
              if (isEmail && !v.contains('@')) return 'Email inválido';
              if (isPassword && v.length < 6) return 'Mínimo 6 caracteres';
              return null;
            },
            decoration: _decoration(hint).copyWith(suffixIcon: suffixIcon),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF0B4DBA), width: 1.4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF0B4DBA), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }
}