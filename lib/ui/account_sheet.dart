// Janela da conta: entrar, criar conta, trocar o nome no jogo e sair.
// Conta é opcional: o jogo continua aberto para convidados e funciona sem internet.
import 'package:flutter/material.dart';

import '../game/app_controller.dart';
import 'theme.dart';

Future<void> showAccountSheet(BuildContext context, AppController ctrl, {bool startOnSignUp = false}) {
  return showEstSheet<void>(
    context,
    maxWidth: 440,
    builder: (ctx) => _AccountSheet(ctrl: ctrl, startOnSignUp: startOnSignUp),
  );
}

class _AccountSheet extends StatefulWidget {
  const _AccountSheet({required this.ctrl, required this.startOnSignUp});
  final AppController ctrl;
  final bool startOnSignUp;

  @override
  State<_AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends State<_AccountSheet> {
  late bool _signUp = widget.startOnSignUp;
  final _user = TextEditingController();
  final _pass = TextEditingController();
  late final _name = TextEditingController(text: widget.ctrl.account?.displayName ?? widget.ctrl.savedName);
  bool _showPass = false;
  String? _error;
  String? _info;

  AppController get c => widget.ctrl;

  @override
  void dispose() {
    _user.dispose();
    _pass.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _info = null;
    });
    final u = _user.text.trim();
    final p = _pass.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Preencha usuário e senha.');
      return;
    }
    final err = _signUp ? await c.accountSignUp(u, p, _name.text) : await c.accountSignIn(u, p);
    if (!mounted) return;
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    _pass.clear();
    _name.text = c.account?.displayName ?? _name.text;
    c.showToast(_signUp ? 'Conta criada. Bem-vindo, ${c.account?.displayName}.' : 'Bem-vindo, ${c.account?.displayName}.');
    Navigator.of(context).maybePop();
  }

  Future<void> _rename() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _info = null;
    });
    final err = await c.accountRename(_name.text);
    if (!mounted) return;
    setState(() {
      if (err != null) {
        _error = err;
      } else {
        _info = 'Nome salvo.';
        _name.text = c.account?.displayName ?? _name.text;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => EstSheetBody(
        title: c.signedIn ? 'Sua conta' : (_signUp ? 'Criar conta' : 'Entrar'),
        children: c.signedIn ? _signedIn() : _signedOut(),
      ),
    );
  }

  List<Widget> _signedOut() {
    final busy = c.accountBusy;
    return [
      _Tabs(
        signUp: _signUp,
        onChanged: busy
            ? null
            : (v) => setState(() {
                  _signUp = v;
                  _error = null;
                }),
      ),
      const SizedBox(height: Space.x4),
      if (!c.netOnline) ...[
        const _Notice('Sem internet. Dá para jogar na mesa local e na rede de casa; a conta precisa de conexão.'),
        const SizedBox(height: Space.x3),
      ],
      AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Field(
              label: 'USUÁRIO',
              child: TextField(
                controller: _user,
                enabled: !busy,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 20,
                textInputAction: TextInputAction.next,
                autofillHints: [_signUp ? AutofillHints.newUsername : AutofillHints.username],
                decoration: const InputDecoration(hintText: 'ex.: luiz_97', counterText: ''),
              ),
            ),
            if (_signUp)
              const _Hint('3 a 20 caracteres: letras sem acento, números, ponto e _. É com ele que você entra.'),
            const SizedBox(height: Space.x3),
            _Field(
              label: 'SENHA',
              child: TextField(
                controller: _pass,
                enabled: !busy,
                obscureText: !_showPass,
                autocorrect: false,
                enableSuggestions: false,
                maxLength: 128,
                textInputAction: _signUp ? TextInputAction.next : TextInputAction.done,
                autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
                onSubmitted: _signUp ? null : (_) => _submit(),
                decoration: InputDecoration(
                  hintText: _signUp ? 'Pelo menos 8 caracteres' : null,
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
            if (_signUp) ...[
              const SizedBox(height: Space.x3),
              _Field(
                label: 'NOME NO JOGO',
                child: TextField(
                  controller: _name,
                  enabled: !busy,
                  maxLength: 14,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(hintText: 'Como os outros vão te ver', counterText: ''),
                ),
              ),
              const _Hint('Dá para trocar depois. A conta não pede e-mail: guarde bem a senha.'),
            ],
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
        label: busy ? (_signUp ? 'Criando…' : 'Entrando…') : (_signUp ? 'Criar conta' : 'Entrar'),
        onPressed: busy || !c.netOnline ? null : _submit,
      ),
      if (busy) const _Hint('Se o servidor estava dormindo, pode levar até um minuto.', center: true),
      const SizedBox(height: Space.x3),
      Text(
        'Sem conta você continua jogando como convidado. Com conta, seu nome e o desafio do dia valem em qualquer aparelho.',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12.5, color: AppColors.faint, height: 1.35),
      ),
    ];
  }

  List<Widget> _signedIn() {
    final u = c.account!;
    final busy = c.accountBusy;
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
            child: Text(
              u.displayName.isNotEmpty ? u.displayName.characters.first.toUpperCase() : '?',
              style: AppText.number(size: 20),
            ),
          ),
          const SizedBox(width: Space.x3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.displayName, style: AppText.title(size: 18), overflow: TextOverflow.ellipsis),
                Text('@${u.username}', style: const TextStyle(fontSize: 13, color: AppColors.mute)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: Space.x4),
      _Field(
        label: 'NOME NO JOGO',
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _name,
                enabled: !busy,
                maxLength: 14,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _rename(),
                decoration: const InputDecoration(counterText: ''),
              ),
            ),
            const SizedBox(width: Space.x2),
            EstButton(
              label: busy ? '…' : 'Salvar',
              onPressed: busy || !c.netOnline ? null : _rename,
            ),
          ],
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
      const SizedBox(height: Space.x6),
      EstButton(
        variant: EstButtonVariant.ghost,
        label: 'Sair da conta',
        onPressed: busy
            ? null
            : () async {
                await c.accountSignOut();
                if (!mounted) return;
                c.showToast('Você saiu da conta. Seu nome continua neste aparelho.');
                Navigator.of(context).maybePop();
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
  const _Field({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: AppText.label(size: 11.5)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.center = false});
  final String text;
  final bool center;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        textAlign: center ? TextAlign.center : TextAlign.start,
        style: const TextStyle(fontSize: 12, color: AppColors.faint, height: 1.35),
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
