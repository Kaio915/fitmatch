import 'package:flutter/material.dart';

import '../core/user_type.dart';
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
  final _objetivoOutroCtrl = TextEditingController();

  String? _nivel;
  String? _objetivoSelecionado;
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
    } else {
      _objetivoSelecionado = 'Outro';
      _objetivoOutroCtrl.text = objetivoAtual;
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
    _objetivoOutroCtrl.dispose();
    _cidadeCtrl.dispose();
    super.dispose();
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
        password: null,
        photo: null,
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
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: _buildFormCard(),
        ),
      );
    }

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
            child: _buildFormCard(),
          ),
        ),
      ),
    );
  }

  Widget _buildFormCard() {
    return Card(
      margin: EdgeInsets.zero,
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
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  DropdownMenuItem(
                    value: 'Avançado',
                    child: Text('Avançado'),
                  ),
                ],
                onChanged: (v) => setState(() => _nivel = v),
                validator: (v) => (v == null || v.isEmpty)
                    ? 'Selecione uma opção'
                    : null,
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
}
