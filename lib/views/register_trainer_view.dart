import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import 'login_view.dart';
import '../core/user_type.dart';
import '../services/auth_service.dart';
import 'register_student_view.dart';
import 'register_success_view.dart';

class RegisterTrainerView extends StatefulWidget {
  const RegisterTrainerView({super.key});

  @override
  State<RegisterTrainerView> createState() => _RegisterTrainerViewState();
}

class _RegisterTrainerViewState extends State<RegisterTrainerView> {
  final _formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final cpfController = TextEditingController();
  final crefController = TextEditingController();
  final cidadeController = TextEditingController();
  final especialidadeController = TextEditingController();
  final valorController = TextEditingController();
  final bioController = TextEditingController();

  List<Map<String, dynamic>> cidades = [];

  final _cpfMask = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {"#": RegExp(r'[0-9]')},
  );

  final ImagePicker _picker = ImagePicker();
  XFile? _photo;
  Uint8List? _photoBytes;
  bool loading = false;

  // ✅ limites recomendados (pra não quebrar card/tela do admin)
  static const int _bioMinLen = 30;
  static const int _bioMaxLen = 150;

  Future<void> _pickPhoto() async {
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

  bool _isValidCPF(String cpf) {
    final numbers = cpf.replaceAll(RegExp(r'[^0-9]'), '');
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

  @override
  void dispose() {
    nameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    cpfController.dispose();
    crefController.dispose();
    cidadeController.dispose();
    especialidadeController.dispose();
    valorController.dispose();
    bioController.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _registerTrainer() async {
    setState(() => loading = true);

    try {
      await AuthService.registerTrainer(
        name: nameController.text.trim(),
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
        cpf: cpfController.text.trim(),
        photo: _photo!,
        cref: crefController.text.trim(),
        cidade: cidadeController.text.trim(),
        especialidade: especialidadeController.text.trim(),
        valorHora: valorController.text.trim(),
        bio: bioController.text.trim(),
      );

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const RegisterSuccessView(userType: UserType.personal),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
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
                color: Colors.black.withValues(alpha: 0.08),
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
                      child: const Text('← Voltar',
                          style: TextStyle(color: Colors.black)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Icon(Icons.fitness_center,
                      size: 36, color: Color(0xFF0B4DBA)),
                  const SizedBox(height: 16),
                  const Text(
                    'Criar Conta',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.black),
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
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () {
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const RegisterStudentView(),
                                ),
                              );
                            },
                            child: const SizedBox(
                              height: 44,
                              child: Center(
                                child: Text(
                                  'Aluno',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color.fromARGB(137, 0, 0, 0),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Container(
                            height: 44,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                'Personal Trainer',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  _input('Nome Completo *', 'Seu nome completo', nameController),
                  _input('Email *', 'seuemail@email.com', emailController,
                      isEmail: true),
                  _input('Senha *', 'Mínimo 6 caracteres', passwordController,
                      obscure: true, isPassword: true),

                  _cpfField(),
                  _photoField(),

                  _input('CREF *', 'Seu número de registro', crefController),

                  _cidadeAutocomplete(),

                    _input('Especialidade', 'Ex: Musculação, Funcional...',
                      especialidadeController, required: false),
                    _input('Valor por Hora', 'Ex: 120', valorController,
                      required: false),

                  // ✅ BIO COM LIMITE REAL
                  _textarea(
                    'Biografia *',
                    'Fale um pouco sobre você, quantos anos de profissão, onde já trabalhou, etc.',
                    bioController,
                    minLen: _bioMinLen,
                    maxLen: _bioMaxLen,
                  ),

                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B4DBA),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: loading
                          ? null
                          : () {
                              if (_photo == null) {
                                _showSnack(kIsWeb
                                    ? 'Selecione uma foto do seu computador'
                                    : 'Tire uma foto pela câmera');
                                return;
                              }

                              if (_formKey.currentState!.validate()) {
                                _registerTrainer();
                              }
                            },
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
                              'Criar Conta de Personal Trainer',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 16),
                            ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                LoginView(userType: UserType.personal),
                          ),
                        );
                      },
                      child: const Text('Já tem uma conta? Entrar',
                          style: TextStyle(color: Colors.black)),
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

  Widget _cidadeAutocomplete() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Cidade *',
              style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black)),
          const SizedBox(height: 6),
          TextFormField(
            controller: cidadeController,
            onChanged: (value) async {
              if (value.length >= 2) {
                final resultado = await AuthService.buscarCidades(value);
                setState(() => cidades = resultado);
              } else {
                setState(() => cidades = []);
              }
            },
            validator: (value) {
              if (value == null || value.isEmpty) return 'Campo obrigatório';
              return null;
            },
            decoration: InputDecoration(
              hintText: 'Digite sua cidade',
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFF0B4DBA)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: Color(0xFF0B4DBA), width: 2),
              ),
            ),
          ),
          if (cidades.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
                color: Colors.white,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: cidades.length,
                itemBuilder: (context, index) {
                  final cidade = cidades[index];
                  return ListTile(
                    title: Text("${cidade['nome']} - ${cidade['uf']}"),
                    onTap: () {
                      cidadeController.text = "${cidade['nome']} - ${cidade['uf']}";
                      setState(() => cidades = []);
                    },
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _cpfField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('CPF *',
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black)),
        const SizedBox(height: 6),
        TextFormField(
          controller: cpfController,
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
    final label =
        kIsWeb ? 'Foto * (Web: escolher arquivo)' : 'Foto * (Mobile: usar câmera)';

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black)),
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
                _photo == null ? 'Nenhuma foto' : _photo!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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

  Widget _input(
    String label,
    String hint,
    TextEditingController controller, {
    bool obscure = false,
    bool isEmail = false,
    bool isPassword = false,
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: (value) {
            final v = (value ?? '').trim();
            if (required && v.isEmpty) return 'Campo obrigatório';
            if (isEmail && !v.contains('@')) return 'Email inválido';
            if (isPassword && v.length < 6) return 'Mínimo 6 caracteres';
            return null;
          },
          decoration: _decoration(hint),
        ),
      ]),
    );
  }

  Widget _textarea(
    String label,
    String hint,
    TextEditingController controller, {
    bool required = true,
    int maxLines = 3,
    int? minLen,
    int? maxLen,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.black)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLen, // ✅ impede passar do limite
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          inputFormatters: [
            // evita quebras esquisitas
            FilteringTextInputFormatter.deny(RegExp(r'[\r\n]')),
          ],
          validator: (value) {
            final v = (value ?? '').trim();
            if (required && v.isEmpty) return 'Campo obrigatório';
            if (minLen != null && v.length < minLen) {
              return 'Escreva pelo menos $minLen caracteres';
            }
            if (maxLen != null && v.length > maxLen) {
              return 'Máximo de $maxLen caracteres';
            }
            return null;
          },
          decoration: _decoration(hint),
        ),
      ]),
    );
  }

  InputDecoration _decoration(String hint) {
    return InputDecoration(
      hintText: hint,
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF0B4DBA)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF0B4DBA), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }
}