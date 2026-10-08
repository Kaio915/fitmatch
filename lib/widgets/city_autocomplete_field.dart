import 'package:flutter/material.dart';

import '../services/auth_service.dart';

class CityAutocompleteField extends StatefulWidget {
  final String initialValue;
  final ValueChanged<String>? onChanged;

  const CityAutocompleteField({
    super.key,
    this.initialValue = '',
    this.onChanged,
  });

  @override
  State<CityAutocompleteField> createState() => _CityAutocompleteFieldState();
}

class _CityAutocompleteFieldState extends State<CityAutocompleteField> {
  int _requestVersion = 0;

  // Dispara a partir da 2ª letra digitada. Devolve um Future para que o
  // Autocomplete nativo atualize a lista de sugestões assim que a busca termina
  // (sem depender de mais uma tecla digitada).
  Future<Iterable<String>> _searchCities(TextEditingValue value) async {
    final query = value.text.trim();
    if (query.length < 2) {
      return const Iterable<String>.empty();
    }

    final requestVersion = ++_requestVersion;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted || requestVersion != _requestVersion) {
      return const Iterable<String>.empty();
    }

    try {
      final result = await AuthService.buscarCidadesIbge(query);
      return result
          .map((city) => '${city['nome']} - ${city['uf']}')
          .toSet()
          .toList();
    } catch (_) {
      return const Iterable<String>.empty();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: widget.initialValue),
      optionsBuilder: _searchCities,
      onSelected: widget.onChanged,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: widget.onChanged,
          decoration: const InputDecoration(
            labelText: 'Cidade',
            prefixIcon: Icon(Icons.location_on_rounded),
            border: OutlineInputBorder(),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
