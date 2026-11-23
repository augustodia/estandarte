// Conversa com o servidor sobre contas: cadastro, entrada, confirmação de e-mail, sessão.
// O token vai no cabeçalho Authorization; nunca em URL (endereços acabam em logs).
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../platform/storage.dart';

class AccountUser {
  const AccountUser({
    required this.id,
    required this.username,
    this.email = '',
    this.emailVerified = false,
    this.crest = '',
  });

  final int id;
  final String username; // também é o nome no jogo (único)
  final String email;
  final bool emailVerified;
  final String crest; // brasão em destaque ('' = nenhum)

  factory AccountUser.fromJson(Map<String, dynamic> j) => AccountUser(
        id: (j['id'] as num?)?.toInt() ?? 0,
        username: j['username'] as String? ?? '',
        email: j['email'] as String? ?? '',
        emailVerified: j['emailVerified'] == true,
        crest: j['crest'] as String? ?? '',
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'username': username, 'email': email, 'emailVerified': emailVerified, 'crest': crest};
}

class AccountSession {
  const AccountSession(this.token, this.user, {this.codeSent = false});
  final String token;
  final AccountUser user;
  final bool codeSent;
}

/// Situação da conta vinda do servidor: e-mail pendente de troca e segundos até poder pedir outro código.
class AccountState {
  const AccountState(this.user, {this.pendingEmail, this.resendIn = 0, this.codeSent = false});
  final AccountUser user;
  final String? pendingEmail;
  final int resendIn;
  final bool codeSent;
}

/// Erro com a mensagem pronta para o jogador. [field] diz qual campo está errado (email, username, password, code).
class AccountError implements Exception {
  const AccountError(this.message, {this.unauthorized = false, this.network = false, this.field});
  final String message;
  final bool unauthorized;
  final bool network;
  final String? field;
  @override
  String toString() => message;
}

String _httpBase(String server) => server.replaceFirst(RegExp(r'^ws'), 'http');

// O servidor grátis dorme depois de 15 min parado e leva até ~1 min para acordar.
const _timeout = Duration(seconds: 75);

Future<Map<String, dynamic>> _call(String server, String method, String path,
    {String? token, Map<String, dynamic>? body}) async {
  final uri = Uri.parse('${_httpBase(server)}$path');
  final headers = <String, String>{
    'Content-Type': 'application/json',
    if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
  };
  http.Response r;
  try {
    r = switch (method) {
      'GET' => await http.get(uri, headers: headers).timeout(_timeout),
      'DELETE' => await http.delete(uri, headers: headers).timeout(_timeout),
      _ => await http.post(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(_timeout),
    };
  } on TimeoutException {
    throw const AccountError('O servidor demorou para responder. Tente de novo.', network: true);
  } catch (_) {
    throw const AccountError('Sem conexão com o servidor.', network: true);
  }
  Map<String, dynamic> j = const {};
  try {
    j = jsonDecode(r.body) as Map<String, dynamic>;
  } catch (_) {}
  if (r.statusCode >= 200 && r.statusCode < 300) return j;
  // 404: servidor ainda sem contas (versão antiga publicada)
  final msg = j['error'] as String? ??
      (r.statusCode == 404 ? 'Contas ainda não estão disponíveis no servidor.' : 'Erro ${r.statusCode} no servidor.');
  throw AccountError(msg, unauthorized: r.statusCode == 401 && token != null, field: j['field'] as String?);
}

AccountUser _user(Map<String, dynamic> j) => AccountUser.fromJson(j['user'] as Map<String, dynamic>? ?? const {});

AccountSession _session(Map<String, dynamic> j) =>
    AccountSession(j['token'] as String? ?? '', _user(j), codeSent: j['codeSent'] == true);

AccountState _state(Map<String, dynamic> j) {
  final p = j['pendingEmail'] as String?;
  return AccountState(_user(j),
      pendingEmail: p == null || p.isEmpty ? null : p,
      resendIn: (j['resendIn'] as num?)?.toInt() ?? 0,
      codeSent: j['codeSent'] == true);
}

Future<AccountSession> accountRegister(String server, String email, String username, String password) async =>
    _session(await _call(server, 'POST', '/account/register',
        body: {'email': email, 'username': username, 'password': password}));

/// Entra com e-mail ou nome de usuário.
Future<AccountSession> accountLogin(String server, String login, String password) async =>
    _session(await _call(server, 'POST', '/account/login', body: {'login': login, 'password': password}));

/// null = nome livre; senão, a mensagem (ocupado ou inválido).
Future<String?> accountCheckUsername(String server, String username) async {
  try {
    final j = await _call(server, 'GET', '/account/check?username=${Uri.encodeQueryComponent(username)}');
    return j['available'] == true ? null : (j['error'] as String? ?? 'Esse nome já está em uso.');
  } on AccountError catch (e) {
    if (e.network) rethrow;
    return e.message;
  }
}

Future<AccountState> accountMe(String server, String token) async =>
    _state(await _call(server, 'GET', '/account/me', token: token));

Future<AccountUser> accountVerify(String server, String token, String code) async =>
    _user(await _call(server, 'POST', '/account/verify', token: token, body: {'code': code}));

/// Manda outro código; devolve em quantos segundos dá para pedir de novo.
Future<int> accountResendCode(String server, String token) async =>
    ((await _call(server, 'POST', '/account/verify/send', token: token))['resendIn'] as num?)?.toInt() ?? 60;

Future<AccountState> accountChangeEmail(String server, String token, String email) async =>
    _state(await _call(server, 'POST', '/account/email', token: token, body: {'email': email}));

/// Escolhe o brasão em destaque ('' tira). O servidor confere se a conta já o conquistou.
Future<AccountUser> accountSetCrest(String server, String token, String crest) async =>
    _user(await _call(server, 'POST', '/account/crest', token: token, body: {'crest': crest}));

Future<AccountUser> accountRename(String server, String token, String username) async =>
    _user(await _call(server, 'POST', '/account/name', token: token, body: {'username': username}));

/// Pede o código de troca de senha (o servidor responde igual exista ou não a conta).
Future<void> accountForgotPassword(String server, String login) async {
  await _call(server, 'POST', '/account/password/forgot', body: {'login': login});
}

/// Troca a senha com o código do e-mail e já entra (as outras sessões caem).
Future<AccountSession> accountResetPassword(String server, String login, String code, String password) async =>
    _session(await _call(server, 'POST', '/account/password/reset',
        body: {'login': login, 'code': code, 'password': password}));

/// Junta o progresso do aparelho com o da conta (fica o melhor de cada dia e crônica) e devolve o resultado.
Future<({Map<String, dynamic> daily, Map<String, dynamic> codex})> accountSyncProgress(
    String server, String token, Map<String, dynamic> daily, Map<String, dynamic> codex) async {
  final j = await _call(server, 'POST', '/account/progress', token: token, body: {'daily': daily, 'codex': codex});
  return (
    daily: Map<String, dynamic>.from(j['daily'] as Map? ?? const {}),
    codex: Map<String, dynamic>.from(j['codex'] as Map? ?? const {}),
  );
}

Future<void> accountLogout(String server, String token) async {
  await _call(server, 'POST', '/account/logout', token: token);
}

/// Validação local do e-mail (o servidor confere de novo): pega erro de digitação antes de enviar.
bool looksLikeEmail(String s) {
  s = s.trim();
  if (s.isEmpty || s.length > 254) return false;
  return RegExp(r'^[^@\s<>(),;:"\[\]\\]{1,64}@'
          r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
          r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*\.[A-Za-z]{2,}$')
      .hasMatch(s);
}

// ---------------- Partidas por correspondência (24 h por jogada) ----------------

class AsyncSeatInfo {
  const AsyncSeatInfo({required this.name, required this.color, this.bot = false, this.you = false});
  final String name;
  final int color;
  final bool bot;
  final bool you;

  factory AsyncSeatInfo.fromJson(Map<String, dynamic> j) => AsyncSeatInfo(
        name: j['name'] as String? ?? '',
        color: (j['color'] as num?)?.toInt() ?? 0,
        bot: j['ctrl'] == 'bot',
        you: j['you'] == true,
      );
}

/// Uma partida da lista: [status] é lobby (esperando gente), play ou over.
class AsyncGameInfo {
  const AsyncGameInfo({
    required this.id,
    required this.status,
    this.round = 0,
    this.seats = const [],
    this.yourTurn = false,
    this.turnName = '',
    this.deadlineMs = 0,
    this.winner = '',
    this.youWon = false,
    this.owner = false,
    this.updatedMs = 0,
    this.replay = '',
  });

  final String id;
  final String status;
  final int round;
  final List<AsyncSeatInfo> seats;
  final bool yourTurn;
  final String turnName;
  final int deadlineMs;
  final String winner;
  final bool youWon;
  final bool owner;
  final int updatedMs;

  /// Replay da partida encerrada ('' se não há).
  final String replay;

  bool get playing => status == 'play';
  bool get waiting => status == 'lobby';
  bool get over => status == 'over';

  factory AsyncGameInfo.fromJson(Map<String, dynamic> j) => AsyncGameInfo(
        id: j['id'] as String? ?? '',
        status: j['status'] as String? ?? 'lobby',
        round: (j['round'] as num?)?.toInt() ?? 0,
        seats: [
          for (final s in (j['seats'] as List<dynamic>? ?? const []))
            AsyncSeatInfo.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        yourTurn: j['yourTurn'] == true,
        turnName: j['turnName'] as String? ?? '',
        deadlineMs: (j['deadline'] as num?)?.toInt() ?? 0,
        winner: j['winner'] as String? ?? '',
        youWon: j['youWon'] == true,
        owner: j['owner'] == true,
        updatedMs: (j['updated'] as num?)?.toInt() ?? 0,
        replay: j['replay'] as String? ?? '',
      );
}

/// Cria a sala de espera de uma partida por correspondência (já chamando os amigos de [invite]); devolve o código.
Future<String> asyncCreate(String server, String token, {List<String> invite = const []}) async =>
    (await _call(server, 'POST', '/async/create', token: token, body: {if (invite.isNotEmpty) 'invite': invite}))['id']
        as String? ??
    '';

/// Convite de um amigo para a sala de espera de uma partida por correspondência.
class AsyncInviteInfo {
  const AsyncInviteInfo({required this.id, required this.from, this.seats = const [], this.atMs = 0});
  final String id;
  final String from;
  final List<AsyncSeatInfo> seats;
  final int atMs;

  factory AsyncInviteInfo.fromJson(Map<String, dynamic> j) => AsyncInviteInfo(
        id: j['id'] as String? ?? '',
        from: j['from'] as String? ?? '',
        seats: [
          for (final s in (j['seats'] as List<dynamic>? ?? const []))
            AsyncSeatInfo.fromJson(Map<String, dynamic>.from(s as Map)),
        ],
        atMs: (j['at'] as num?)?.toInt() ?? 0,
      );
}

/// As partidas por correspondência da conta (as que esperam por você primeiro) e os convites que ainda valem.
Future<({List<AsyncGameInfo> games, List<AsyncInviteInfo> invites})> asyncMine(String server, String token) async {
  final j = await _call(server, 'GET', '/async/mine', token: token);
  return (
    games: [
      for (final g in (j['games'] as List<dynamic>? ?? const []))
        AsyncGameInfo.fromJson(Map<String, dynamic>.from(g as Map)),
    ],
    invites: [
      for (final g in (j['invites'] as List<dynamic>? ?? const []))
        AsyncInviteInfo.fromJson(Map<String, dynamic>.from(g as Map)),
    ],
  );
}

Future<void> asyncInvite(String server, String token, String id, String name) async {
  await _call(server, 'POST', '/async/invite', token: token, body: {'id': id, 'name': name});
}

Future<void> asyncDeclineInvite(String server, String token, String id) async {
  await _call(server, 'POST', '/async/invite/decline', token: token, body: {'id': id});
}

// ---------------- Replays ----------------

/// Código de replay (8 letras) digitado ou colado como link (?replay=).
String? replayCode(String? raw) {
  final s = (raw ?? '').trim();
  final m1 = RegExp(r'[?&]replay=([A-Za-z0-9]{8})').firstMatch(s);
  if (m1 != null) return m1.group(1)!.toUpperCase();
  final m2 = RegExp(r'^#?([A-Za-z0-9]{8})$').firstMatch(s);
  return m2?.group(1)!.toUpperCase();
}

/// Busca o replay (com a semente revelada) e o cabeçalho dele.
Future<({Map<String, dynamic> meta, Map<String, dynamic> replay})> fetchReplay(String server, String code) async {
  final j = await _call(server, 'GET', '/replay?id=${Uri.encodeQueryComponent(code)}');
  return (
    meta: Map<String, dynamic>.from(j['meta'] as Map? ?? const {}),
    replay: Map<String, dynamic>.from(j['replay'] as Map? ?? const {}),
  );
}

// ---------------- Amigos ----------------

/// Amigo com presença: [status] é playing (numa partida agora), online (jogo aberto há pouco) ou vazio.
class FriendInfo {
  const FriendInfo(this.name, {this.status = '', this.crest = ''});
  final String name;
  final String status;
  final String crest;
  bool get playing => status == 'playing';
  bool get online => status == 'playing' || status == 'online';
}

class FriendLists {
  const FriendLists({this.friends = const [], this.incoming = const [], this.outgoing = const []});
  final List<FriendInfo> friends;
  final List<String> incoming;
  final List<String> outgoing;
}

Future<FriendLists> friendsList(String server, String token) async {
  final j = await _call(server, 'GET', '/friends', token: token);
  List<String> names(String k) => [
        for (final x in (j[k] as List<dynamic>? ?? const [])) (x as Map)['name'] as String? ?? '',
      ];
  return FriendLists(
    friends: [
      for (final x in (j['friends'] as List<dynamic>? ?? const []))
        FriendInfo((x as Map)['name'] as String? ?? '',
            status: x['status'] as String? ?? '', crest: x['crest'] as String? ?? ''),
    ],
    incoming: names('incoming'),
    outgoing: names('outgoing'),
  );
}

/// Pede amizade; devolve o nome como está na conta e se já virou amizade (a pessoa tinha pedido também).
Future<({String name, bool accepted})> friendRequest(String server, String token, String name) async {
  final j = await _call(server, 'POST', '/friends/request', token: token, body: {'name': name});
  return (name: j['name'] as String? ?? name, accepted: j['accepted'] == true);
}

Future<void> friendAccept(String server, String token, String name) async {
  await _call(server, 'POST', '/friends/accept', token: token, body: {'name': name});
}

/// Desfaz a amizade, recusa o pedido recebido ou cancela o enviado.
Future<void> friendRemove(String server, String token, String name) async {
  await _call(server, 'POST', '/friends/remove', token: token, body: {'name': name});
}

/// Código de partida por correspondência (6 letras) digitado ou colado como link (?partida=).
String? asyncCode(String? raw) {
  final s = (raw ?? '').trim();
  final m1 = RegExp(r'[?&]partida=([A-Za-z0-9]{6})').firstMatch(s);
  if (m1 != null) return m1.group(1)!.toUpperCase();
  final m2 = RegExp(r'^#?([A-Za-z0-9]{6})$').firstMatch(s);
  return m2?.group(1)!.toUpperCase();
}

// ---------------------------------------------------------------- fila ranqueada (Duelo)

/// Entra na fila do Duelo. Devolve {status: waiting|matched, ticket, room?, secs, queue}.
Future<Map<String, dynamic>> rankedJoin(String server, String token) =>
    _call(server, 'POST', '/ranked/queue', token: token, body: {'mode': 'duel', 'install': installId()});

/// Identificador desta instalação do app (aleatório, guardado no aparelho; sobrevive a sair da conta). O servidor
/// guarda só um resumo dele, para não deixar duas contas do mesmo aparelho se enfrentarem na ranqueada.
String installId() {
  const key = 'ultimato.install';
  final saved = AppStorage.instance.getString(key);
  if (saved != null && saved.length >= 16) return saved;
  final rng = Random.secure();
  final id = List.generate(32, (_) => '0123456789abcdef'[rng.nextInt(16)]).join();
  AppStorage.instance.setString(key, id);
  return id;
}

/// Como está o bilhete na fila (sem conta: o bilhete é o segredo). status: waiting|matched|gone.
Future<Map<String, dynamic>> rankedPoll(String server, String ticket) =>
    _call(server, 'GET', '/ranked/queue?t=${Uri.encodeQueryComponent(ticket)}');

/// Sai da fila.
Future<void> rankedLeave(String server, String ticket) async {
  await _call(server, 'DELETE', '/ranked/queue?t=${Uri.encodeQueryComponent(ticket)}');
}

/// A nota da conta na temporada, a posição, castigo e duelo em andamento.
Future<Map<String, dynamic>> rankedMe(String server, String token) => _call(server, 'GET', '/ranked/me', token: token);

/// As 100 maiores notas da temporada.
Future<Map<String, dynamic>> rankedTop(String server) => _call(server, 'GET', '/ranked/top?mode=duel');

// ---------------------------------------------------------------- loja (Comandante)

/// Item do catálogo. O preço vale para o Pix; nas lojas de app vale o preço da própria loja.
class StoreItem {
  const StoreItem({required this.sku, required this.name, required this.desc, required this.cents, required this.available});
  final String sku;
  final String name;
  final String desc;
  final int cents;
  final bool available;

  String get price => 'R\$ ${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';

  factory StoreItem.fromJson(Map<String, dynamic> j) => StoreItem(
        sku: j['sku'] as String? ?? '',
        name: j['name'] as String? ?? '',
        desc: j['desc'] as String? ?? '',
        cents: (j['cents'] as num?)?.toInt() ?? 0,
        available: j['available'] == true,
      );
}

class StoreCatalog {
  const StoreCatalog({this.items = const [], this.pix = false, this.play = false, this.fundadorUntilMs = 0});
  final List<StoreItem> items;
  final bool pix; // Pix pelo site ligado no servidor
  final bool play; // conferência da Google Play ligada no servidor
  final int fundadorUntilMs; // fim da venda do Fundador (0 = fora de venda)
}

Future<StoreCatalog> storeCatalog(String server) async {
  final j = await _call(server, 'GET', '/store/catalog');
  return StoreCatalog(
    items: [for (final e in (j['items'] as List<dynamic>? ?? const [])) StoreItem.fromJson(e as Map<String, dynamic>)],
    pix: j['pix'] == true,
    play: j['play'] == true,
    fundadorUntilMs: (j['fundadorUntil'] as num?)?.toInt() ?? 0,
  );
}

/// Direitos da conta. O token é assinado pelo servidor e vale 30 dias sem internet (offline e LAN).
class Entitlements {
  const Entitlements({this.comandante = false, this.fundador = 0, this.token = '', this.tag = '', this.expiresMs = 0});
  final bool comandante;
  final int fundador; // número do Comandante Fundador (0 = não é)
  final String token;
  final String tag; // etiqueta da conta para a loja de apps (a compra fica presa a esta conta)
  final int expiresMs;

  static const none = Entitlements();

  bool get valid => token.isNotEmpty && DateTime.now().millisecondsSinceEpoch < expiresMs;

  /// Lê a carga do token guardado ("ult1.<carga>.<assinatura>"). Quem manda de verdade é o servidor; aqui é só
  /// para o app lembrar o que a conta tem quando está sem internet.
  factory Entitlements.fromToken(String token, {String tag = ''}) {
    try {
      final parts = token.split('.');
      if (parts.length != 3 || parts[0] != 'ult1') return none;
      final body = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1])))) as Map<String, dynamic>;
      final skus = [for (final s in (body['s'] as List<dynamic>? ?? const [])) s as String];
      return Entitlements(
        comandante: skus.contains('comandante') || skus.contains('comandante_fundador'),
        fundador: (body['f'] as num?)?.toInt() ?? 0,
        token: token,
        tag: tag,
        expiresMs: ((body['e'] as num?)?.toInt() ?? 0) * 1000,
      );
    } catch (_) {
      return none;
    }
  }

  factory Entitlements.fromMe(Map<String, dynamic> j) =>
      Entitlements.fromToken(j['token'] as String? ?? '', tag: j['tag'] as String? ?? '');
}

Future<Entitlements> storeMe(String server, String token) async =>
    Entitlements.fromMe(await _call(server, 'GET', '/store/me', token: token));

/// Confere uma compra da Google Play no servidor. Devolve null enquanto a compra está pendente.
Future<Entitlements?> storePlayVerify(String server, String token, String product, String purchaseToken) async {
  final j = await _call(server, 'POST', '/store/play/verify', token: token, body: {'product': product, 'token': purchaseToken});
  if (j['status'] == 'pending') return null;
  return Entitlements.fromMe(j);
}

class PixOrder {
  const PixOrder({required this.id, required this.status, this.code = '', this.cents = 0, this.expiresMs = 0});
  final String id;
  final String status; // pending | paid | expired
  final String code; // Pix copia e cola
  final int cents;
  final int expiresMs;

  factory PixOrder.fromJson(Map<String, dynamic> j) {
    final o = j['order'] as Map<String, dynamic>? ?? const {};
    return PixOrder(
      id: o['id'] as String? ?? '',
      status: o['status'] as String? ?? 'pending',
      code: o['code'] as String? ?? '',
      cents: (o['cents'] as num?)?.toInt() ?? 0,
      expiresMs: DateTime.tryParse(o['expires'] as String? ?? '')?.millisecondsSinceEpoch ?? 0,
    );
  }
}

Future<PixOrder> storePixOrder(String server, String token, String sku) async =>
    PixOrder.fromJson(await _call(server, 'POST', '/store/pix/order', token: token, body: {'sku': sku}));

Future<({PixOrder order, Entitlements? ent})> storePixStatus(String server, String token, String id) async {
  final j = await _call(server, 'GET', '/store/pix/order?id=${Uri.encodeQueryComponent(id)}', token: token);
  return (order: PixOrder.fromJson(j), ent: j['token'] is String ? Entitlements.fromMe(j) : null);
}
