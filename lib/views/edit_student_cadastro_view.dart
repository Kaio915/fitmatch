import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/user_type.dart';
import '../services/auth_service.dart';
import 'register_success_view.dart';

class EditStudentCadastroView extends StatefulWidget {
  final Map<String, dynamic> user;

  const EditStudentCadastroView({super.key, required this.user});

  @override
  State<EditStudentCadastroView> createState() => _EditStudentCadastroViewState();
}

class _EditStudentCadastroViewState extends State<EditStudentCadastroView> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _cpfCtrl;
  late final TextEditingController _cidadeCtrl;
  final _passwordCtrl = TextEditingController();
  final _objetivoOutroCtrl = TextEditingController();

  List<Map<String, dynamic>> cidades = [];
  Timer? _cidadeDebounce;

  String? _nivel;
  String? _objetivoSelecionado;
  XFile? _photo;
  bool _loading = false;

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

  String get _statusTitle {
    final status = (widget.user['status'] ?? '').toString().toUpperCase();
    return status == 'TEMPORARILY_REJECTED'
        ? 'Mensagem do administrador'
        : 'Status do cadastro';
  }

  String get _statusMessage {
    final status = (widget.user['status'] ?? '').toString().toUpperCase();
    if (status == 'TEMPORARILY_REJECTED') {
      final r = (widget.user['rejectionReason'] ?? '').toString().trim();
      return r.isEmpty
          ? 'O administrador solicitou ajustes no seu cadastro.'
          : r;
    }
    return 'Seu cadastro está em análise. Você pode editar seus dados enquanto aguarda a análise.';
  }

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: (widget.user['name'] ?? '').toString());
    _emailCtrl = TextEditingController(text: (widget.user['email'] ?? '').toString());
    _cpfCtrl = TextEditingController(text: (widget.user['cpf'] ?? '').toString());
    final objetivoAtual = (widget.user['objetivos'] ?? '').toString().trim();
    if (objetivoAtual.isEmpty) {
      _objetivoSelecionado = null;
    } else if (_objetivos.contains(objetivoAtual)) {
      _objetivoSelecionado = objetivoAtual;
    } else {
      _objetivoSelecionado = 'Outro';
      _objetivoOutroCtrl.text = objetivoAtual;
    }
    _cidadeCtrl = TextEditingController(text: (widget.user['cidade'] ?? '').toString());

    final nivel = (widget.user['nivel'] ?? '').toString().trim();
    _nivel = nivel.isEmpty ? null : nivel;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _cpfCtrl.dispose();
    _objetivoOutroCtrl.dispose();
    _cidadeCtrl.dispose();
    _passwordCtrl.dispose();
    _cidadeDebounce?.cancel();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) setState(() => _photo = picked);
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);

    try {
      await AuthService.editStudentCadastro(
        name: _nameCtrl.text,
        email: _emailCtrl.text,
        cpf: _cpfCtrl.text,
        objetivos: _objetivoSelecionado == 'Outro'
            ? _objetivoOutroCtrl.text
            : (_objetivoSelecionado ?? ''),
        nivel: _nivel ?? '',
        cidade: _cidadeCtrl.text,
        password: _passwordCtrl.text,
        photo: _photo,
      );

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
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        title: const Text('Editar Cadastro'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Card(
              elevation: 0,
              color: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7E6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF5C842)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _statusTitle,
                              style: const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Text(_statusMessage),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _input('Nome *', _nameCtrl),
                      _input('Email *', _emailCtrl, isEmail: true),
                      _input('CPF *', _cpfCtrl),
                      _objetivoDropdown(),
                      _cidadeAutocomplete(required: false),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: _nivel,
                        decoration: const InputDecoration(
                          labelText: 'Nível de Condicionamento *',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Iniciante', child: Text('Iniciante')),
                          DropdownMenuItem(
                              value: 'Intermediário', child: Text('Intermediário')),
                          DropdownMenuItem(value: 'Avançado', child: Text('Avançado')),
                        ],
                        onChanged: (v) => setState(() => _nivel = v),
                        validator: (v) =>
                            (v == null || v.isEmpty) ? 'Selecione uma opção' : null,
                      ),
                      const SizedBox(height: 16),
                      _input('Nova senha (opcional)', _passwordCtrl,
                          required: false, obscure: true),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.photo_camera),
                        label: Text(
                          _photo == null ? 'Trocar foto (opcional)' : 'Foto selecionada',
                        ),
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
                              : const Text('Salvar e enviar para análise'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
            initialValue: _objetivoSelecionado,
            decoration: const InputDecoration(
              labelText: 'Objetivos *',
              border: OutlineInputBorder(),
            ),
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
              decoration: const InputDecoration(
                labelText: 'Descreva seu objetivo',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cidadeAutocomplete({bool required = true}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _cidadeCtrl,
            onChanged: (value) async {
              _cidadeDebounce?.cancel();
              final query = value.trim();
              if (query.length < 2) {
                if (mounted) setState(() => cidades = []);
                return;
              }
              _cidadeDebounce = Timer(const Duration(milliseconds: 300), () async {
                final typedAtRequest = _cidadeCtrl.text.trim();
                final resultado = await AuthService.buscarCidadesIbge(typedAtRequest);
                if (!mounted) return;
                if (typedAtRequest == _cidadeCtrl.text.trim()) {
                  setState(() => cidades = resultado);
                }
              });
            },
            validator: (value) {
              if (required && (value == null || value.trim().isEmpty)) {
                return 'Campo obrigatório';
              }
              return null;
            },
            decoration: InputDecoration(
              labelText: required ? 'Cidade *' : 'Cidade',
              border: const OutlineInputBorder(),
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
                      _cidadeCtrl.text = "${cidade['nome']} - ${cidade['uf']}";
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

  Widget _input(
    String label,
    TextEditingController ctrl, {
    bool required = true,
    bool obscure = false,
    bool isEmail = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: ctrl,
        obscureText: obscure,
        validator: (v) {
          final value = (v ?? '').trim();
          if (!required) return null;
          if (value.isEmpty) return 'Campo obrigatório';
          if (isEmail && !value.contains('@')) return 'Email inválido';
          return null;
        },
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
