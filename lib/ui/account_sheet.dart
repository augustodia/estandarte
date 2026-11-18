// Janela da conta: entrar, criar conta (e-mail + nome de usuário único), confirmar o e-mail com o código,
// trocar nome ou e-mail e sair. Conta é opcional: o jogo continua aberto para convidados e funciona sem internet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../game/app_controller.dart';
import '../net/account_api.dart' show AccountError, looksLikeEmail;
import 'theme.dart';

Future<void> showAccountSheet(BuildContext context, AppController ctrl, {bool startOnSignUp = false, String? reason}) {
  return showEstSheet<void>(
    context,
    maxWidth: 440,
    // não fecha com toque fora nem com Esc: o menu do gerenciador de senhas (1Password e outros) fica por cima da
    // página, e o clique nele chegava ao fundo da janela e a fechava antes de preencher. Fecha no × e nos botões.
    dismissible: false,
    builder: (ctx) => _AccountSheet(ctrl: ctrl, startOnSignUp: startOnSignUp, reason: reason),
  );
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet({required this.ctrl, required this.startOnSignUp, this.reason});
  final AppController ctrl;
  final bool startOnSignUp;
  final String? reason; // por que a janela abriu (ex.: tentou jogar online sem conta)

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late bool _signUp = widget.startOnSignUp;
  final _login = TextEditingController();
  final _email = TextEditingController();
  late final _user = TextEditingController(text: widget.ctrl.account?.username ?? widget.ctrl.savedName);
  final _pass = TextEditingController();
  final _code = TextEditingController();
  late final _newEmail = TextEditingController(text: widget.ctrl.account?.email ?? '');
  bool _showPass = false;
  bool _editEmail = false;
  bool _closing = false;

  // esqueci a senha: 0 = fora, 1 = pedir o código, 2 = código + senha nova
  int _resetStep = 0;
  final _resetLogin = TextEditingController();
  final _resetCode = TextEditingController();
  final _newPass = TextEditingController();
  DateTime? _resetSentAt;

  // erros por campo e geral
  final Map<String, String> _fieldErr = {};
  String? _error;
  String? _info;

  // nome livre? (aviso enquanto digita)
  Timer? _checkTimer;
  String? _checkedName;
  String? _nameIssue; // null = livre (ou ainda não conferido)
  bool _checking = false;

  Timer? _tick; // contagem do reenvio

  AppController get c => widget.ctrl;

  @override
  void initState() {
    super.initState();
    _user.addListener(_onUserChanged);
    if (_signUp && !c.signedIn) WidgetsBinding.instance.addPostFrameCallback((_) => _onUserChanged());
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (c.accountResendAt != null || _resetSentAt != null)) setState(() {});
    });
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _tick?.cancel();
    for (final t in [_login, _email, _user, _pass, _code, _newEmail, _resetLogin, _resetCode, _newPass]) {
      t.dispose();
    }
    super.dispose();
  }

  void _onUserChanged() {
    final v = _user.text.trim();
    final current = c.account?.username;
    if (v == _checkedName || (current != null && v == current)) return;
    _checkTimer?.cancel();
    setState(() {
      _fieldErr.remove('username');
      _nameIssue = null;
      _checking = false;
    });
    final local = _localNameIssue(v);
    if (local != null || v.isEmpty || !c.netOnline) {
      if (local != null) setState(() => _nameIssue = local);
      return;
    }
    _checkTimer = Timer(const Duration(milliseconds: 450), () async {
      if (!mounted) return;
      setState(() => _checking = true);
      final issue = await c.accountCheckUsername(v);
      if (!mounted || _user.text.trim() != v) return;
      setState(() {
        _checking = false;
        _checkedName = v;
        _nameIssue = issue;
      });
    });
  }

  String? _localNameIssue(String v) {
    final n = v.characters.length;
    if (n == 0) return null;
    if (n < 3) return 'Pelo menos 3 caracteres.';
    if (n > 14) return 'No máximo 14 caracteres.';
    if (v.contains('@')) return 'Sem @: esse é o nome que aparece no jogo.';
    return null;
  }

  void _clearMsgs() {
    _fieldErr.clear();
    _error = null;
    _info = null;
  }

  void _show(AccountError? e, {String? ok}) {
    setState(() {
      if (e == null) {
        _info = ok;
      } else if (e.field != null) {
        _fieldErr[e.field!] = e.message;
      } else {
        _error = e.message;
      }
    });
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(_clearMsgs);
    if (_signUp) {
      final em = _email.text.trim();
      final un = _user.text.trim();
      if (!looksLikeEmail(em)) _fieldErr['email'] = 'Confira o e-mail: ele recebe o código de confirmação.';
      final ni = _localNameIssue(un) ?? (un.isEmpty ? 'Escolha um nome de usuário.' : null);
      if (ni != null) _fieldErr['username'] = ni;
      if (_nameIssue != null && _checkedName == un) _fieldErr['username'] = _nameIssue!;
      if (_pass.text.characters.length < 8) _fieldErr['password'] = 'Pelo menos 8 caracteres.';
      if (_fieldErr.isNotEmpty) {
        setState(() {});
        return;
      }
      final e = await c.accountSignUp(em, un, _pass.text);
      if (!mounted) return;
      if (e != null) return _show(e);
      TextInput.finishAutofillContext();
      _pass.clear();
      // a janela passa para a confirmação do e-mail
      setState(() => _info = c.accountResendAt == null ? 'O e-mail não saiu agora. Toque em reenviar código.' : null);
      return;
    }
    if (_login.text.trim().isEmpty || _pass.text.isEmpty) {
      setState(() => _error = 'Preencha e-mail (ou nome de usuário) e senha.');
      return;
    }
    final e = await c.accountSignIn(_login.text, _pass.text);
    if (!mounted) return;
    if (e != null) return _show(e);
    TextInput.finishAutofillContext(); // o gerenciador de senhas guarda (ou atualiza) o login que deu certo
    _pass.clear();
    if (!c.accountNeedsConfirm) {
      c.showToast('Bem-vindo, ${c.account?.username}.');
      _close();
    }
  }

  Future<void> _verify() async {
    FocusScope.of(context).unfocus();
    setState(_clearMsgs);
    final code = _code.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) {
      setState(() => _fieldErr['code'] = 'O código tem 6 dígitos.');
      return;
    }
    final e = await c.accountVerify(code);
    if (!mounted) return;
    if (e != null) return _show(e);
    _code.clear();
    c.showToast('E-mail confirmado.');
    setState(() {
      _editEmail = false;
      _newEmail.text = c.account?.email ?? '';
    });
  }

  Future<void> _resend() async {
    setState(_clearMsgs);
    final e = await c.accountResendCode();
    if (!mounted) return;
    _show(e, ok: 'Código reenviado para ${c.accountCodeEmail}.');
  }

  Future<void> _changeEmail() async {
    FocusScope.of(context).unfocus();
    setState(_clearMsgs);
    final em = _newEmail.text.trim();
    if (!looksLikeEmail(em)) {
      setState(() => _fieldErr['email'] = 'Confira o e-mail.');
      return;
    }
    final e = await c.accountChangeEmail(em);
    if (!mounted) return;
    if (e != null) return _show(e);
    setState(() {
      _editEmail = false;
      _code.clear();
      _info = c.accountNeedsConfirm ? 'Código enviado para ${c.accountCodeEmail}.' : null;
    });
  }

  int get _resetWait {
    final at = _resetSentAt;
    if (at == null) return 0;
    final left = 60 - DateTime.now().difference(at).inSeconds;
    return left > 0 ? left : 0;
  }

  Future<void> _sendReset() async {
    FocusScope.of(context).unfocus();
    setState(_clearMsgs);
    final login = _resetLogin.text.trim();
    if (login.isEmpty) {
      setState(() => _fieldErr['login'] = 'Digite o e-mail ou o nome de usuário da conta.');
      return;
    }
    final e = await c.accountForgotPassword(login);
    if (!mounted) return;
    if (e != null) return _show(e);
    setState(() {
      _resetSentAt = DateTime.now();
      _resetStep = 2;
      _resetCode.clear();
    });
  }

  Future<void> _doReset() async {
    FocusScope.of(context).unfocus();
    setState(_clearMsgs);
    final code = _resetCode.text.replaceAll(RegExp(r'\D'), '');
    if (code.length != 6) _fieldErr['code'] = 'O código tem 6 dígitos.';
    if (_newPass.text.characters.length < 8) _fieldErr['password'] = 'Pelo menos 8 caracteres.';
    if (_fieldErr.isNotEmpty) {
      setState(() {});
      return;
    }
    final e = await c.accountResetPassword(_resetLogin.text, code, _newPass.text);
    if (!mounted) return;
    if (e != null) return _show(e);
    _newPass.clear();
    _resetCode.clear();
    c.showToast('Senha trocada. Os outros aparelhos saíram da conta.');
    setState(() => _resetStep = 0);
    if (!c.accountNeedsConfirm) _close();
  }

  Future<void> _rename() async {
    FocusScope.of(context).unfocus();
    setState(_clearMsgs);
    final un = _user.text.trim();
    final ni = _localNameIssue(un) ?? (un.isEmpty ? 'Escolha um nome de usuário.' : null);
    if (ni != null) {
      setState(() => _fieldErr['username'] = ni);
      return;
    }
    final e = await c.accountRename(un);
    if (!mounted) return;
    _show(e, ok: 'Nome salvo.');
    if (e == null) _checkedName = c.account?.username;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final String title;
        final List<Widget> body;
        if (_resetStep > 0) {
          title = 'Trocar senha';
          body = _resetBody();
        } else if (!c.signedIn) {
          title = _signUp ? 'Criar conta' : 'Entrar';
          body = _signedOut();
        } else if (c.accountNeedsConfirm && !_editEmail) {
          title = 'Confirme seu e-mail';
          body = _confirm();
        } else {
          title = 'Sua conta';
          body = _signedIn();
        }
        // Com o formulário preenchido, um toque fora da janela ou um Esc não fecham: gerenciadores de senha (1Password
        // e outros) mexem na página ao preencher e não podem derrubar o login no meio. O × e os botões fecham sempre.
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (didPop) return;
            if (_closing || !_dirty) {
              _closing = true;
              Navigator.of(context).pop();
            }
          },
          child: EstSheetBody(title: title, onClose: _close, children: body),
        );
      },
    );
  }

  /// Algo digitado (ou preenchido pelo gerenciador de senhas) que se perderia ao fechar.
  bool get _dirty => [_login, _pass, _email, _code, _resetCode, _newPass].any((t) => t.text.isNotEmpty);

  void _close() {
    _closing = true;
    Navigator.of(context).maybePop();
  }

  // ── sem conta ────────────────────────────────────────────────────────────────

  List<Widget> _signedOut() {
    final busy = c.accountBusy;
    return [
      _Tabs(
        signUp: _signUp,
        onChanged: busy
            ? null
            : (v) {
                setState(() {
                  _signUp = v;
                  _clearMsgs();
                });
                if (v) _onUserChanged(); // confere o nome que já veio preenchido
              },
      ),
      const SizedBox(height: Space.x4),
      if (widget.reason != null) ...[
        _Notice(widget.reason!),
        const SizedBox(height: Space.x3),
      ],
      if (!c.netOnline) ...[
        const _Notice('Sem internet. Dá para jogar na mesa local e na rede de casa; a conta precisa de conexão.'),
        const SizedBox(height: Space.x3),
      ],
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _signUp ? _signUpFields(busy) : _signInFields(busy),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: Space.x3),
        _Notice(_error!, bad: true),
      ],
      const SizedBox(height: Space.x4),
      EstButton(
        variant: EstButtonVariant.primary,
        label: busy ? (_signUp ? 'Criando…' : 'Entrando…') : (_signUp ? 'Criar conta' : 'Entrar'),
        onPressed: busy || !c.netOnline ? null : _submit,
      ),
      if (busy) const _Hint('Se o servidor estava dormindo, pode levar até um minuto.', center: true),
      const SizedBox(height: Space.x3),
      const Text(
        'Sem conta dá para jogar na mesa local e na rede de casa. Online, o seu nome de usuário é o seu nome em todas as salas.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: AppColors.faint, height: 1.35),
      ),
    ];
  }

  List<Widget> _signInFields(bool busy) => [
        _Field(
          label: 'E-MAIL OU NOME DE USUÁRIO',
          child: TextField(
            controller: _login,
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            // o gerenciador de senhas às vezes manda o Enter daqui, já com a senha preenchida
            onSubmitted: (_) => _pass.text.isNotEmpty ? _submit() : FocusScope.of(context).nextFocus(),
            decoration: const InputDecoration(hintText: 'voce@email.com'),
          ),
        ),
        const SizedBox(height: Space.x3),
        _passwordField(busy, newPassword: false),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy
                ? null
                : () => setState(() {
                      _clearMsgs();
                      _resetLogin.text = _login.text.trim();
                      _resetStep = 1;
                    }),
            child: Text('ESQUECI A SENHA', style: AppText.label(size: 11.5, color: AppColors.mute)),
          ),
        ),
      ];

  List<Widget> _signUpFields(bool busy) {
    final un = _user.text.trim();
    final nameOk = un.isNotEmpty && _checkedName == un && _nameIssue == null && !_checking;
    final nameMsg = _fieldErr['username'] ?? _nameIssue;
    return [
      _Field(
        label: 'E-MAIL',
        error: _fieldErr['email'],
        child: TextField(
          controller: _email,
          enabled: !busy,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.email],
          onChanged: (_) {
            if (_fieldErr.containsKey('email')) setState(() => _fieldErr.remove('email'));
          },
          decoration: const InputDecoration(hintText: 'voce@email.com'),
        ),
      ),
      if (_fieldErr['email'] == null) const _Hint('Mandamos um código para confirmar. Não aparece para ninguém.'),
      const SizedBox(height: Space.x3),
      _Field(
        label: 'NOME DE USUÁRIO',
        error: nameMsg,
        child: TextField(
          controller: _user,
          enabled: !busy,
          autocorrect: false,
          maxLength: 14,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.newUsername],
          decoration: InputDecoration(
            hintText: 'Como os outros vão te ver',
            counterText: '',
            suffixIcon: _nameStatusIcon(_checking, nameOk, nameMsg != null),
          ),
        ),
      ),
      if (nameMsg == null)
        _Hint(nameOk ? '$un está livre.' : 'É o nome no jogo e é só seu. 3 a 14 letras, números, espaço, . - _',
            good: nameOk),
      const SizedBox(height: Space.x3),
      _passwordField(busy, newPassword: true),
    ];
  }

  Widget? _nameStatusIcon(bool checking, bool ok, bool bad) {
    if (checking) {
      return const Padding(
        padding: EdgeInsets.all(14),
        child: SizedBox(
            width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.faint)),
      );
    }
    if (ok) return const Icon(Icons.check, size: 18, color: AppColors.ink);
    if (bad) return const Icon(Icons.close, size: 18, color: AppColors.bad);
    return null;
  }

  Widget _passwordField(bool busy, {required bool newPassword}) => _Field(
        label: 'SENHA',
        error: _fieldErr['password'],
        child: TextField(
          controller: _pass,
          enabled: !busy,
          obscureText: !_showPass,
          autocorrect: false,
          enableSuggestions: false,
          maxLength: 128,
          textInputAction: TextInputAction.done,
          autofillHints: [newPassword ? AutofillHints.newPassword : AutofillHints.password],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            hintText: newPassword ? 'Pelo menos 8 caracteres' : null,
            counterText: '',
            suffixIcon: IconButton(
              tooltip: _showPass ? 'Esconder senha' : 'Mostrar senha',
              icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
              color: AppColors.faint,
              onPressed: () => setState(() => _showPass = !_showPass),
            ),
          ),
        ),
      );

  // ── esqueci a senha ──────────────────────────────────────────────────────────

  List<Widget> _resetBody() {
    final busy = c.accountBusy;
    final back = EstButton(
      variant: EstButtonVariant.ghost,
      small: true,
      label: 'Voltar',
      onPressed: busy
          ? null
          : () => setState(() {
                _clearMsgs();
                _resetStep = 0;
              }),
    );
    if (_resetStep == 1) {
      return [
        const Text(
          'Mandamos um código para o e-mail da conta. Com ele você escolhe uma senha nova.',
          style: TextStyle(fontSize: 14, color: AppColors.mute, height: 1.4),
        ),
        const SizedBox(height: Space.x4),
        _Field(
          label: 'E-MAIL OU NOME DE USUÁRIO',
          error: _fieldErr['login'],
          child: TextField(
            controller: _resetLogin,
            enabled: !busy,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.send,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            onSubmitted: (_) => _sendReset(),
            decoration: const InputDecoration(hintText: 'voce@email.com'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.x3),
          _Notice(_error!, bad: true),
        ],
        const SizedBox(height: Space.x4),
        EstButton(
          variant: EstButtonVariant.primary,
          label: busy ? 'Enviando…' : 'Enviar código',
          onPressed: busy || !c.netOnline ? null : _sendReset,
        ),
        const SizedBox(height: Space.x2),
        back,
      ];
    }
    final wait = _resetWait;
    return [
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Se existe uma conta com '),
          TextSpan(text: _resetLogin.text.trim(), style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
          const TextSpan(text: ', o código chegou no e-mail dela. Vale por 30 minutos.'),
        ]),
        style: const TextStyle(fontSize: 14, color: AppColors.mute, height: 1.4),
      ),
      const SizedBox(height: Space.x4),
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              label: 'CÓDIGO',
              error: _fieldErr['code'],
              child: TextField(
                controller: _resetCode,
                enabled: !busy,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                autofillHints: const [AutofillHints.oneTimeCode],
                textAlign: TextAlign.center,
                textInputAction: TextInputAction.next,
                style: AppText.number(size: 26).copyWith(letterSpacing: 10),
                decoration: const InputDecoration(hintText: '000000', counterText: ''),
              ),
            ),
            const SizedBox(height: Space.x3),
            _Field(
              label: 'SENHA NOVA',
              error: _fieldErr['password'],
              child: TextField(
                controller: _newPass,
                enabled: !busy,
                obscureText: !_showPass,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 128,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newPassword],
                onSubmitted: (_) => _doReset(),
                decoration: InputDecoration(
                  hintText: 'Pelo menos 8 caracteres',
                  counterText: '',
                  suffixIcon: IconButton(
                    tooltip: _showPass ? 'Esconder senha' : 'Mostrar senha',
                    icon: Icon(_showPass ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18),
                    color: AppColors.faint,
                    onPressed: () => setState(() => _showPass = !_showPass),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: Space.x3),
        _Notice(_error!, bad: true),
      ],
      const SizedBox(height: Space.x4),
      EstButton(
        variant: EstButtonVariant.primary,
        label: busy ? 'Trocando…' : 'Trocar senha',
        onPressed: busy || !c.netOnline ? null : _doReset,
      ),
      const SizedBox(height: Space.x2),
      Row(
        children: [
          Expanded(
            child: EstButton(
              small: true,
              label: wait > 0 ? 'Reenviar em ${wait}s' : 'Reenviar código',
              onPressed: busy || wait > 0 || !c.netOnline ? null : _sendReset,
            ),
          ),
          const SizedBox(width: Space.x2),
          Expanded(child: back),
        ],
      ),
      const SizedBox(height: Space.x3),
      const _Hint('Não chegou? Olhe o spam. Ao trocar, os outros aparelhos saem da conta.', center: true),
    ];
  }

  // ── confirmar o e-mail ───────────────────────────────────────────────────────

  List<Widget> _confirm() {
    final busy = c.accountBusy;
    final wait = c.accountResendIn;
    final pendingChange = c.accountPendingEmail != null;
    return [
      Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Mandamos um código de 6 dígitos para '),
          TextSpan(text: c.accountCodeEmail, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
          const TextSpan(text: '. Ele vale por 30 minutos.'),
        ]),
        style: const TextStyle(fontSize: 14, color: AppColors.mute, height: 1.4),
      ),
      const SizedBox(height: Space.x4),
      _Field(
        label: 'CÓDIGO',
        error: _fieldErr['code'],
        child: TextField(
          controller: _code,
          enabled: !busy,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
          autofillHints: const [AutofillHints.oneTimeCode],
          textAlign: TextAlign.center,
          textInputAction: TextInputAction.done,
          onChanged: (v) {
            if (_fieldErr.containsKey('code')) setState(() => _fieldErr.remove('code'));
            if (v.length == 6 && !c.accountBusy) _verify();
          },
          onSubmitted: (_) => _verify(),
          style: AppText.number(size: 26).copyWith(letterSpacing: 10),
          decoration: const InputDecoration(hintText: '000000', counterText: ''),
        ),
      ),
      if (_error != null) ...[
        const SizedBox(height: Space.x3),
        _Notice(_error!, bad: true),
      ],
      if (_info != null) ...[
        const SizedBox(height: Space.x3),
        _Notice(_info!),
      ],
      const SizedBox(height: Space.x4),
      EstButton(
        variant: EstButtonVariant.primary,
        label: busy ? 'Conferindo…' : 'Confirmar e-mail',
        onPressed: busy || !c.netOnline ? null : _verify,
      ),
      const SizedBox(height: Space.x2),
      Row(
        children: [
          Expanded(
            child: EstButton(
              small: true,
              label: wait > 0 ? 'Reenviar em ${wait}s' : 'Reenviar código',
              onPressed: busy || wait > 0 || !c.netOnline ? null : _resend,
            ),
          ),
          const SizedBox(width: Space.x2),
          Expanded(
            child: EstButton(
              small: true,
              label: 'Trocar e-mail',
              onPressed: busy
                  ? null
                  : () => setState(() {
                        _clearMsgs();
                        _newEmail.text = c.accountCodeEmail;
                        _editEmail = true;
                      }),
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.x3),
      _Hint(
        pendingChange
            ? 'Até confirmar, sua conta continua com ${c.account!.email}. Não chegou? Olhe o spam.'
            : 'Não chegou? Olhe o spam. Contas sem e-mail confirmado são apagadas em 3 dias.',
        center: true,
      ),
      const SizedBox(height: Space.x2),
      EstButton(
        variant: EstButtonVariant.ghost,
        small: true,
        label: 'Fazer depois',
        onPressed: _close,
      ),
    ];
  }

  // ── com conta ────────────────────────────────────────────────────────────────

  List<Widget> _signedIn() {
    final u = c.account!;
    final busy = c.accountBusy;
    final un = _user.text.trim();
    final nameChanged = un.isNotEmpty && un != u.username;
    final nameMsg = _fieldErr['username'] ?? (nameChanged ? _nameIssue : null);
    final emailSame = _newEmail.text.trim().toLowerCase() == c.accountCodeEmail.toLowerCase();
    return [
      Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.panel2,
              borderRadius: BorderRadius.circular(Radii.sm),
              border: Border.all(color: AppColors.line),
            ),
            child: Text(u.username.isNotEmpty ? u.username.characters.first.toUpperCase() : '?',
                style: AppText.number(size: 20)),
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.username, style: AppText.title(size: 18), overflow: TextOverflow.ellipsis),
                Row(
                  children: [
                    Flexible(
                      child: Text(u.email,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppColors.mute)),
                    ),
                    const SizedBox(width: 6),
                    Text(u.emailVerified ? 'CONFIRMADO' : 'PENDENTE',
                        style: AppText.label(size: 10.5, color: u.emailVerified ? AppColors.mute : AppColors.medal)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.x4),
      _Field(
        label: 'NOME DE USUÁRIO',
        error: nameMsg,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _user,
                enabled: !busy,
                autocorrect: false,
                maxLength: 14,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _rename(),
                decoration: InputDecoration(
                  counterText: '',
                  suffixIcon: nameChanged
                      ? _nameStatusIcon(_checking, _checkedName == un && _nameIssue == null, nameMsg != null)
                      : null,
                ),
              ),
            ),
            const SizedBox(width: Space.x2),
            EstButton(
              label: 'Salvar',
              onPressed: busy || !c.netOnline || !nameChanged || nameMsg != null ? null : _rename,
            ),
          ],
        ),
      ),
      if (nameMsg == null) const _Hint('É o nome que aparece no jogo e no ranking. Só você pode usar.'),
      const SizedBox(height: Space.x3),
      _Field(
        label: 'E-MAIL',
        error: _fieldErr['email'],
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newEmail,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() => _fieldErr.remove('email')),
                onSubmitted: (_) => _changeEmail(),
              ),
            ),
            const SizedBox(width: Space.x2),
            EstButton(
              label: 'Trocar',
              onPressed: busy || !c.netOnline || emailSame ? null : _changeEmail,
            ),
          ],
        ),
      ),
      if (_fieldErr['email'] == null)
        const _Hint('Para trocar, mandamos um código para o e-mail novo; até confirmar, vale o atual.'),
      if (_error != null) ...[
        const SizedBox(height: Space.x3),
        _Notice(_error!, bad: true),
      ],
      if (_info != null) ...[
        const SizedBox(height: Space.x3),
        _Notice(_info!),
      ],
      if (_editEmail && c.accountNeedsConfirm) ...[
        const SizedBox(height: Space.x3),
        EstButton(
          small: true,
          label: 'Voltar ao código',
          onPressed: () => setState(() => _editEmail = false),
        ),
      ],
      const SizedBox(height: Space.x6),
      EstButton(
        label: 'Trocar senha',
        onPressed: busy || !c.netOnline
            ? null
            : () async {
                setState(_clearMsgs);
                _resetLogin.text = u.email;
                await _sendReset();
              },
      ),
      const SizedBox(height: Space.x2),
      EstButton(
        variant: EstButtonVariant.ghost,
        label: 'Sair da conta',
        onPressed: busy
            ? null
            : () async {
                await c.accountSignOut();
                if (!mounted) return;
                c.showToast('Você saiu da conta. Seu nome continua neste aparelho.');
                _close();
              },
      ),
    ];
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.signUp, required this.onChanged});
  final bool signUp;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    Widget tab(String label, bool value) {
      final on = signUp == value;
      return Expanded(
        child: InkWell(
          onTap: onChanged == null || on ? null : () => onChanged!(value),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: on ? AppColors.ink : AppColors.line, width: on ? 2 : 1)),
            ),
            child: Text(label, style: AppText.label(size: 13, color: on ? AppColors.ink : AppColors.faint)),
          ),
        ),
      );
    }

    return Row(children: [tab('ENTRAR', false), tab('CRIAR CONTA', true)]);
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child, this.error});
  final String label;
  final Widget child;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppText.label(size: 11.5, color: error != null ? AppColors.bad : AppColors.faint)),
        const SizedBox(height: 6),
        child,
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(error!, style: const TextStyle(fontSize: 12.5, color: AppColors.bad, height: 1.35)),
          ),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.center = false, this.good = false});
  final String text;
  final bool center;
  final bool good;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: TextStyle(fontSize: 12, color: good ? AppColors.ink : AppColors.faint, height: 1.35),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.bad = false});
  final String text;
  final bool bad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.x3, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border(left: BorderSide(color: bad ? AppColors.bad : AppColors.mute, width: 3)),
      ),
      child: Text(text, style: TextStyle(fontSize: 13, color: bad ? AppColors.ink : AppColors.mute, height: 1.35)),
    );
  }
}
