// Conversa com o servidor sobre contas: cadastro, entrada, confirmação de e-mail, sessão.
// O token vai no cabeçalho Authorization; nunca em URL (endereços acabam em logs).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AccountUser {
  const AccountUser({required this.id, required this.username, this.email = '', this.emailVerified = false});

  final int id;
  final String username; // também é o nome no jogo (único)
  final String email;
  final bool emailVerified;

  factory AccountUser.fromJson(Map<String, dynamic> j) => AccountUser(
        id: (j['id'] as num?)?.toInt() ?? 0,
        username: j['username'] as String? ?? '',
        email: j['email'] as String? ?? '',
        emailVerified: j['emailVerified'] == true,
      );

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'email': email, 'emailVerified': emailVerified};
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
    r = method == 'GET'
        ? await http.get(uri, headers: headers).timeout(_timeout)
        : await http.post(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(_timeout);
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

Future<AccountUser> accountRename(String server, String token, String username) async =>
    _user(await _call(server, 'POST', '/account/name', token: token, body: {'username': username}));

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
