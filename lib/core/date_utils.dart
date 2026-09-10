/// Converte uma data em ISO (ex.: "2026-08-05" ou "2026-08-05T12:34:56")
/// para o formato brasileiro "dd-MM-yyyy" (ex.: "05-08-2026").
///
/// Retorna "-" quando a data é nula/vazia e o texto original quando não
/// consegue identificar um padrão "yyyy-MM-dd".
String formatIsoDateToPtBr(String? iso) {
  if (iso == null || iso.isEmpty) return '-';

  // Remove o horário (caso venha "yyyy-MM-ddTHH:mm:ss").
  final datePart = iso.length >= 10 ? iso.substring(0, 10) : iso;
  final parts = datePart.split('-');
  if (parts.length == 3 && parts[0].length == 4) {
    return '${parts[2]}-${parts[1]}-${parts[0]}';
  }

  return iso;
}
