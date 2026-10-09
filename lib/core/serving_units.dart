/// Tradução e limpeza das descrições de porção vindas das APIs de alimentos.
///
/// As APIs (FatSecret, OpenFoodFacts, Edamam) podem devolver a descrição da
/// porção em inglês (ex.: "1 cup", "1 slice", "1 can"). Este helper garante que
/// o dropdown de unidades da tela "Controle de Dieta" exiba sempre termos
/// naturais em português ("1 copo", "1 fatia", "1 lata"), mantendo o valor
/// consistente com o que é persistido no backend (que usa o mesmo dicionário).
library;

const Map<String, String> _servingTermTranslations = {
  'extra large': 'extra grande',
  'tablespoon': 'colher de sopa',
  'tablespoons': 'colheres de sopa',
  'teaspoon': 'colher de chá',
  'teaspoons': 'colheres de chá',
  'tbsp': 'colher de sopa',
  'tsp': 'colher de chá',
  'cup': 'copo',
  'cups': 'copos',
  'glass': 'copo',
  'glasses': 'copos',
  'serving': 'porção',
  'servings': 'porções',
  'slice': 'fatia',
  'slices': 'fatias',
  'piece': 'pedaço',
  'pieces': 'pedaços',
  'bottle': 'garrafa',
  'bottles': 'garrafas',
  'can': 'lata',
  'cans': 'latas',
  'jar': 'pote',
  'jars': 'potes',
  'pack': 'embalagem',
  'packs': 'embalagens',
  'bag': 'pacote',
  'bags': 'pacotes',
  'bar': 'barra',
  'bars': 'barras',
  'container': 'recipiente',
  'containers': 'recipientes',
  'ounce': 'onça',
  'ounces': 'onças',
  'large': 'grande',
  'medium': 'médio',
  'small': 'pequeno',
  'unit': 'unidade',
  'units': 'unidades',
};

/// Substitui termos comuns em inglês por suas traduções em português.
///
/// A substituição é feita por palavra inteira (word boundary), de forma
/// case-insensitive, e os termos são ordenados do maior para o menor para que
/// expressões compostas (ex.: "extra large") sejam tratadas antes das simples
/// (ex.: "large").
String translateServingDescription(String raw) {
  if (raw.isEmpty) return raw;

  final entries = _servingTermTranslations.entries.toList()
    ..sort((a, b) => b.key.length.compareTo(a.key.length));

  var result = raw;
  for (final entry in entries) {
    result = result.replaceAll(
      RegExp('\\b${RegExp.escape(entry.key)}\\b', caseSensitive: false),
      entry.value,
    );
  }
  return result;
}

/// Traduz e limpa uma descrição de porção para exibição/persistência.
///
/// Remove espaços repetidos e quebras de linha, devolvendo um texto curto e
/// legível para o dropdown de unidades.
String normalizeServingDescription(String? raw) {
  final trimmed = (raw ?? '').trim();
  if (trimmed.isEmpty) return '';
  return translateServingDescription(trimmed)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
