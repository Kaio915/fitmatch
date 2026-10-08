import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/user_type.dart';
import '../core/objective_options.dart';
import '../services/auth_service.dart';
import '../widgets/city_autocomplete_field.dart';
import 'register_success_view.dart';

class EditStudentCadastroView extends StatefulWidget {
  final Map<String, dynamic> user;
  final bool showAsDialog;

  const EditStudentCadastroView({
    super.key,
    required this.user,
    this.showAsDialog = false,
  });

  @override
  State<EditStudentCadastroView> createState() =>
      _EditStudentCadastroViewState();
}

class _EditStudentCadastroViewState extends State<EditStudentCadastroView> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _cpfCtrl;
  late final TextEditingController _cidadeCtrl;
  final _senhaCtrl = TextEditingController();
  final _confirmarSenhaCtrl = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  XFile? _photo;
  Uint8List? _photoBytes;
  bool _showPassword = false;
  bool _showConfirmPassword = false;

  String? _nivel;
  String? _objetivoSelecionado;
  bool _loading = false;

  final List<String> _objetivos = kObjectiveOptions;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: (widget.user['name'] ?? '').toString(),
    );
    _emailCtrl = TextEditingController(
      text: (widget.user['email'] ?? '').toString(),
    );
    _cpfCtrl = TextEditingController(
      text: (widget.user['cpf'] ?? '').toString(),
    );
    final objetivoAtual = (widget.user['objetivos'] ?? '').toString().trim();
    if (objetivoAtual.isEmpty) {
      _objetivoSelecionado = null;
    } else if (_objetivos.contains(objetivoAtual)) {
      _objetivoSelecionado = objetivoAtual;
    }
    _cidadeCtrl = TextEditingController(
      text: (widget.user['cidade'] ?? '').toString(),
    );

    final nivel = (widget.user['nivel'] ?? '').toString().trim();
    _nivel = nivel.isEmpty ? null : nivel;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _cpfCtrl.dispose();
    _cidadeCtrl.dispose();
    _senhaCtrl.dispose();
    _confirmarSenhaCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _pickPhoto() async {
    // Web: escolher arquivo/galeria. Mobile: somente câmera.
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

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    try {
      await AuthService.editStudentCadastro(
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        cpf: _cpfCtrl.text,
        objetivos: _objetivoSelecionado ?? '',
        nivel: _nivel ?? '',
        cidade: _cidadeCtrl.text,
        password: _senhaCtrl.text,
        photo: _photo,
      );

      final wasApproved =
          (widget.user['status'] ?? '').toString().toUpperCase() == 'APPROVED';
      if (wasApproved) {
        final updatedUser = await AuthService.getCurrentUser();
        await AuthService.saveSession(updatedUser);
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

      await AuthService.clearSession();

      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => const RegisterSuccessView(userType: UserType.aluno),
        ),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.showAsDialog) {
      final isNarrow = MediaQuery.of(context).size.width < 600;
      return Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: isNarrow ? MediaQuery.of(context).size.width * 0.05 : 24,
          vertical: 24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isNarrow ? MediaQuery.of(context).size.width * 0.9 : 560,
          ),
          child: _buildInternalFormCard(),
        ),
      );
    }

    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Editar Cadastro'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isNarrow ? 16 : 24,
          vertical: 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _buildFormCard(),
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    final isNarrow = MediaQuery.of(context).size.width < 600;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isNarrow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 16,
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.all(isNarrow ? 16 : 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFF5C842)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Status do cadastro',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Seu cadastro está em análise. Você pode editar seus dados enquanto aguarda a análise.',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              _textField(
                'Nome Completo *',
                'Seu nome completo',
                controller: _nameCtrl,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Informe o nome completo'
                    : null,
              ),
              const SizedBox(height: 16),
              _textField(
                'Email *',
                'seu@email.com',
                controller: _emailCtrl,
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return 'Informe o email';
                  if (!value.contains('@') || !value.contains('.')) {
                    return 'Email inválido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _textField(
                'Senha',
                'Mínimo 6 caracteres',
                controller: _senhaCtrl,
                obscure: !_showPassword,
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
                validator: (v) {
                  final value = (v ?? '').trim();
                  if (value.isEmpty) return null; // opcional na edição
                  if (value.length < 6) return 'Mínimo 6 caracteres';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _textField(
                'Confirmar Senha',
                'Repita a senha',
                controller: _confirmarSenhaCtrl,
                obscure: !_showConfirmPassword,
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
                validator: (v) {
                  final value = (v ?? '').trim();
                  final senha = _senhaCtrl.text.trim();
                  if (senha.isEmpty && value.isEmpty) return null;
                  if (value.isEmpty) return 'Confirme a senha';
                  if (value != senha) return 'As senhas não coincidem';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _textField(
                'CPF *',
                'Somente números',
                controller: _cpfCtrl,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Informe o CPF'
                    : null,
              ),
              const SizedBox(height: 16),
              _photoField(),
              const SizedBox(height: 16),
              _objetivoDropdown(),
              const SizedBox(height: 16),
              CityAutocompleteField(
                initialValue: _cidadeCtrl.text,
                onChanged: (value) => _cidadeCtrl.text = value,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _nivel,
                decoration: const InputDecoration(
                  labelText: 'Nível de Condicionamento *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Iniciante',
                    child: Text('Iniciante'),
                  ),
                  DropdownMenuItem(
                    value: 'Intermediário',
                    child: Text('Intermediário'),
                  ),
                  DropdownMenuItem(value: 'Avançado', child: Text('Avançado')),
                ],
                onChanged: (v) => setState(() => _nivel = v),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Selecione uma opção' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B4DBA),
                    foregroundColor: Colors.white,
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Salvar alterações'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInternalFormCard() {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Editar Perfil',
                    style: Theme.of(context).textTheme.headlineSmall!.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _objetivoDropdown(),
              const SizedBox(height: 16),
              CityAutocompleteField(
                initialValue: _cidadeCtrl.text,
                onChanged: (value) => _cidadeCtrl.text = value,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _nivel,
                decoration: const InputDecoration(
                  labelText: 'Nível de Condicionamento *',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'Iniciante',
                    child: Text('Iniciante'),
                  ),
                  DropdownMenuItem(
                    value: 'Intermediário',
                    child: Text('Intermediário'),
                  ),
                  DropdownMenuItem(value: 'Avançado', child: Text('Avançado')),
                ],
                onChanged: (v) => setState(() => _nivel = v),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Selecione uma opção' : null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0B4DBA),
                    foregroundColor: Colors.white,
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Salvar alterações'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _objetivoDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            isExpanded: MediaQuery.of(context).size.width < 600,
            menuMaxHeight: MediaQuery.of(context).size.height * 0.42,
            initialValue: _objetivoSelecionado,
            decoration: const InputDecoration(
              labelText: 'Objetivos *',
              border: OutlineInputBorder(),
            ),
            items: _objetivos
                .map(
                  (o) => DropdownMenuItem(
                    value: o,
                    child: Text(o, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (value) {
              setState(() => _objetivoSelecionado = value);
            },
            validator: (value) {
              if (value == null || value.isEmpty) return 'Selecione uma opção';
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _textField(
    String label,
    String hint, {
    required TextEditingController controller,
    String? Function(String?)? validator,
    bool obscure = false,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _photoField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _pickPhoto,
          icon: const Icon(Icons.camera_alt),
          label: Text(_photo == null ? 'Foto/Upload' : 'Foto selecionada'),
          style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
          ),
        ),
        const SizedBox(height: 10),
        if (_photo != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: kIsWeb
                ? Image.memory(_photoBytes!, height: 130, fit: BoxFit.cover)
                : Image.file(
                    File(_photo!.path),
                    height: 130,
                    fit: BoxFit.cover,
                  ),
          ),
      ],
    );
  }
}
