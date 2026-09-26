import 'dart:async';

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
  Timer? _debounce;
  List<String> _options = const [];
  int _requestVersion = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _searchCities(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      if (mounted) setState(() => _options = const []);
      return;
    }

    final requestVersion = ++_requestVersion;
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final result = await AuthService.buscarCidadesIbge(query);
      if (!mounted || requestVersion != _requestVersion) return;
      setState(() {
        _options = result
            .map((city) => '${city['nome']} - ${city['uf']}')
            .toSet()
            .toList();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: widget.initialValue),
      optionsBuilder: (value) {
        final query = value.text.trim().toLowerCase();
        if (query.length < 2) return const Iterable<String>.empty();
        return _options.where((option) => option.toLowerCase().contains(query));
      },
      onSelected: widget.onChanged,
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onChanged: (value) {
            _searchCities(value);
            widget.onChanged?.call(value);
          },
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
