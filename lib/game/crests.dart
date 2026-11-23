// Brasões das Quintas Históricas: recompensas cosméticas permanentes da conta.
//
// Cada crônica dá um brasão com o metal da melhor campanha (1★ bronze, 2★ prata, 3★ ouro) e três insígnias
// marcam a coleção. A conta escolhe um para aparecer ao lado do nome. As regras são as mesmas do servidor
// (internal/server/crest.go), que confere antes de aceitar.
//
//   brasão de crônica: "<id da crônica>:<1..3>"   ex.: "hist_dday_1944:3"
//   insígnia:          "ins_<nome>"               ex.: "ins_veterano"

import 'daily_challenge.dart';

class InsigniaMeta {
  const InsigniaMeta(this.id, this.title, this.rule, this.count, this.stars);

  final String id;
  final String title;
  final String rule; // como conquistar
  final int count; // quantas crônicas…
  final int stars; // …com pelo menos tantas estrelas
}

const List<InsigniaMeta> insigniaCatalog = [
  InsigniaMeta('ins_veterano', 'Veterano', 'Concluir 3 crônicas', 3, 1),
  InsigniaMeta('ins_estrategista', 'Estrategista', 'Fechar 5 crônicas com três estrelas', 5, 3),
  InsigniaMeta('ins_historiador', 'Historiador', 'Concluir todas as 10 crônicas', 10, 1),
];

const List<String> tierNames = ['', 'Bronze', 'Prata', 'Ouro'];

/// Melhor campanha (estrelas) de uma crônica no Códice; 0 se ainda não jogou.
int codexStars(Map<String, dynamic> codex, String id) {
  final r = codex[id];
  if (r is! Map) return 0;
  return ((r['bestStars'] as num?)?.toInt() ?? 0).clamp(0, 3);
}

/// Quantas crônicas da rotação foram concluídas com pelo menos [stars] estrelas.
int chroniclesWith(Map<String, dynamic> codex, int stars) =>
    historicalCodexCatalog.where((m) => codexStars(codex, m.id) >= stars).length;

/// Brasão parseado: crônica (com metal) ou insígnia. null se o texto não é um brasão conhecido.
({HistoricalCodexMeta? chronicle, InsigniaMeta? insignia, int tier})? parseCrest(String crest) {
  for (final i in insigniaCatalog) {
    if (i.id == crest) return (chronicle: null, insignia: i, tier: 3);
  }
  final cut = crest.lastIndexOf(':');
  if (cut <= 0) return null;
  final tier = int.tryParse(crest.substring(cut + 1));
  if (tier == null || tier < 1 || tier > 3) return null;
  final id = crest.substring(0, cut);
  for (final m in historicalCodexCatalog) {
    if (m.id == id) return (chronicle: m, insignia: null, tier: tier);
  }
  return null;
}

/// Nome do brasão para mostrar ("Dia D: Muro do Atlântico · Ouro", "Veterano").
String crestTitle(String crest) {
  final p = parseCrest(crest);
  if (p == null) return '';
  if (p.insignia != null) return 'Insígnia ${p.insignia!.title}';
  return '${p.chronicle!.title} · ${tierNames[p.tier]}';
}

/// O progresso já conquistou o brasão? (o servidor confere de novo)
bool crestEarned(Map<String, dynamic> codex, String crest) {
  final p = parseCrest(crest);
  if (p == null) return false;
  if (p.insignia != null) return chroniclesWith(codex, p.insignia!.stars) >= p.insignia!.count;
  return codexStars(codex, p.chronicle!.id) >= p.tier;
}

/// Brasão de crônica no melhor metal conquistado (vazio se ainda não jogou).
String bestChronicleCrest(Map<String, dynamic> codex, String id) {
  final s = codexStars(codex, id);
  return s == 0 ? '' : '$id:$s';
}

/// Todos os brasões que dá para exibir agora (cada crônica no melhor metal, mais as insígnias).
List<String> earnedCrests(Map<String, dynamic> codex) => [
      for (final m in historicalCodexCatalog)
        if (codexStars(codex, m.id) > 0) bestChronicleCrest(codex, m.id),
      for (final i in insigniaCatalog)
        if (crestEarned(codex, i.id)) i.id,
    ];
