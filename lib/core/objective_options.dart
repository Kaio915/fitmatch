/// Opções de objetivo usadas no cadastro do aluno e no cálculo de TMB.
///
/// Mantidas num único lugar para garantir que o dropdown do modal "Calcular TMB"
/// use exatamente as mesmas opções do cadastro.
const List<String> kObjectiveOptions = [
  'Perder peso',
  'Ganhar massa muscular',
  'Definir / Hipertrofia',
  'Aumentar força',
  'Melhorar condicionamento',
  'Melhorar saúde e disposição',
  'Melhorar postura',
  'Reabilitação / Fortalecimento',
  'Preparação para prova (corrida, TAF, etc.)',
];

/// Ajuste calórico (kcal) a aplicar sobre o Gasto Energético Total (GET).
///
/// - Perder peso: défice de 500 kcal
/// - Ganhar massa muscular / Aumentar força: superávite de 500 kcal
/// - Definir / Hipertrofia: superávite leve de 250 kcal
/// - Demais objetivos: manutenção (0 kcal)
int kcalAdjustmentForObjective(String objective) {
  switch (objective.trim()) {
    case 'Perder peso':
      return -500;
    case 'Ganhar massa muscular':
    case 'Aumentar força':
      return 500;
    case 'Definir / Hipertrofia':
      return 250;
    default:
      return 0;
  }
}
