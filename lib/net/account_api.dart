// Conversa com o servidor sobre contas: cadastro, entrada, sessão e nome no jogo.
// O token vai no cabeçalho Authorization; nunca em URL (endereços acabam em logs).
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

class AccountUser {
  const AccountUser({required this.id, required this.username, required this.displayName});

  final int id;
  final String username;
  final String displayName;

  factory AccountUser.fromJson(Map<String, dynamic> j) => AccountUser(
        id: (j['id'] as num?)?.toInt() ?? 0,
        username: j['username'] as String? ?? '',
        displayName: j['displayName'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'id': id, 'username': username, 'displayName': displayName};
}

class AccountSession {
  const AccountSession(this.token, this.user);
  final String token;
  final AccountUser user;
}

/// Erro com a mensagem pronta para o jogador. [unauthorized] = o token não vale mais; [network] = sem resposta.
class AccountError implements Exception {
  const AccountError(this.message, {this.unauthorized = false, this.network = false});
  final String message;
  final bool unauthorized;
  final bool network;
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
  final msg = j['error'] as String? ?? 'Erro ${r.statusCode} no servidor.';
  throw AccountError(msg, unauthorized: r.statusCode == 401 && token != null && path != '/account/login');
}

AccountSession _session(Map<String, dynamic> j) =>
    AccountSession(j['token'] as String? ?? '', AccountUser.fromJson(j['user'] as Map<String, dynamic>? ?? const {}));

Future<AccountSession> accountRegister(String server, String username, String password, String displayName) async =>
    _session(await _call(server, 'POST', '/account/register',
        body: {'username': username, 'password': password, 'displayName': displayName}));

Future<AccountSession> accountLogin(String server, String username, String password) async =>
    _session(await _call(server, 'POST', '/account/login', body: {'username': username, 'password': password}));

Future<AccountUser> accountMe(String server, String token) async =>
    AccountUser.fromJson((await _call(server, 'GET', '/account/me', token: token))['user'] as Map<String, dynamic>);

Future<AccountUser> accountRename(String server, String token, String displayName) async => AccountUser.fromJson(
    (await _call(server, 'POST', '/account/name', token: token, body: {'displayName': displayName}))['user']
        as Map<String, dynamic>);

Future<void> accountLogout(String server, String token) async {
  await _call(server, 'POST', '/account/logout', token: token);
}
