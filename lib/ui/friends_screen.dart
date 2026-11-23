import 'package:flutter/material.dart';

import '../game/app_controller.dart';
import '../net/account_api.dart';
import 'modals.dart';
import 'crest_badge.dart';
import 'theme.dart';

/// Amigos: pedir amizade pelo nome de usuário, ver quem está com o jogo aberto e desafiar por correspondência.
///
/// Uma lista só: pedidos recebidos no topo (pedem resposta), depois os amigos (quem está jogando e quem está online
/// primeiro) e por fim os pedidos enviados.
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _nameCtrl = TextEditingController();
  String? _err;
  bool _busy = false;

  AppController get c => widget.ctrl;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _err = null;
    });
    final err = await c.addFriend(_nameCtrl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _err = err;
      if (err == null) _nameCtrl.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final layout = EstLayout.of(context);
    final short = layout.size.height <= 520;
    final pad = layout.big ? 36.0 : (short ? 16.0 : 20.0);
    final l = c.friends;
    final online = c.friendsOnline;

    final body = <Widget>[];
    void section(String label, int n, List<Widget> rows, {bool lit = false}) {
      if (rows.isEmpty) return;
      if (body.isNotEmpty) body.add(SizedBox(height: short ? 18 : 26));
      body.add(_SectionHead(label: label, n: n, lit: lit));
      body.add(const SizedBox(height: 10));
      for (var i = 0; i < rows.length; i++) {
        if (i > 0) body.add(const SizedBox(height: 6));
        body.add(rows[i]);
      }
    }

    if (!c.friendsLoaded && c.friendsLoading) {
      body.add(const _Note('Buscando seus amigos…'));
    } else if (c.friendsError != null && !c.friendsLoaded) {
      body.add(_Note(c.friendsError!, bad: true));
    } else if (l.friends.isEmpty && l.incoming.isEmpty && l.outgoing.isEmpty) {
      body.add(const _Empty());
    } else {
      section('PEDIDOS', l.incoming.length, [
        for (final n in l.incoming)
          _Row(
            name: n,
            sub: 'quer ser seu amigo',
            actions: [
              EstButton(small: true, label: 'Aceitar', onPressed: () => c.acceptFriend(n)),
              const SizedBox(width: 6),
              EstIconButton(
                icon: EstIconKind.close,
                size: 32,
                iconSize: 12,
                tooltip: 'Recusar',
                onPressed: () => c.removeFriend(n),
              ),
            ],
          ),
      ], lit: true);
      section('AMIGOS', l.friends.length, [
        for (final f in l.friends)
          _Row(
            name: f.name,
            crest: f.crest,
            sub: f.playing ? 'jogando agora' : (f.online ? 'online' : ''),
            dot: f.playing ? _Dot.playing : (f.online ? _Dot.online : _Dot.off),
            actions: [
              EstButton(
                small: true,
                icon: EstIconKind.compass,
                label: 'Desafiar',
                onPressed: c.corrCreating ? null : () => c.challengeFriend(f.name),
              ),
              const SizedBox(width: 6),
              EstIconButton(
                icon: EstIconKind.close,
                size: 32,
                iconSize: 12,
                tooltip: 'Desfazer amizade',
                onPressed: () => _confirmRemove(f.name),
              ),
            ],
          ),
      ]);
      section('ENVIADOS', l.outgoing.length, [
        for (final n in l.outgoing)
          _Row(
            name: n,
            sub: 'esperando resposta',
            muted: true,
            actions: [
              EstButton(small: true, variant: EstButtonVariant.ghost, label: 'Cancelar', onPressed: () => c.removeFriend(n)),
            ],
          ),
      ]);
    }

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Padding(
              padding: EdgeInsets.fromLTRB(pad, short ? 12 : 24, pad, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      EstIconButton(
                        icon: EstIconKind.back,
                        size: 36,
                        iconSize: 16,
                        color: AppColors.ink,
                        tooltip: 'Voltar',
                        onPressed: c.goHome,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Amigos', style: AppText.serif(size: layout.big ? 28 : (short ? 20 : 24))),
                            if (!short) ...[
                              const SizedBox(height: 2),
                              Text(
                                online > 0 ? '$online COM O JOGO ABERTO AGORA' : 'DESAFIE POR CORRESPONDÊNCIA',
                                style: AppText.label(size: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: short ? 12 : 22),
                  Row(
                    children: [
                      Expanded(
                        child: EstTextField(
                          controller: _nameCtrl,
                          height: 42,
                          maxLength: 14,
                          hintText: 'Nome de usuário do amigo',
                          onSubmitted: (_) => _add(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      EstButton(label: _busy ? 'Enviando…' : 'Adicionar', height: 42, onPressed: _busy ? null : _add),
                    ],
                  ),
                  if (_err != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_err!, style: const TextStyle(fontSize: 12.5, color: AppColors.bad)),
                    ),
                  SizedBox(height: short ? 14 : 26),
                  Expanded(
                    child: RefreshIndicator(
                      color: AppColors.ink,
                      backgroundColor: AppColors.panel,
                      onRefresh: c.refreshFriends,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 24),
                        children: body,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmRemove(String name) {
    showEstSheet<void>(
      context,
      maxWidth: 420,
      builder: (ctx) => EstSheetBody(
        title: 'Desfazer amizade com $name?',
        onClose: () => Navigator.pop(ctx),
        children: [
          const Text(
            'As partidas que vocês já jogam continuam. Para voltar a ser amigos, alguém pede de novo.',
            style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.mute),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: EstButton(
                  label: 'Desfazer',
                  variant: EstButtonVariant.warn,
                  onPressed: () {
                    Navigator.pop(ctx);
                    c.removeFriend(name);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: EstButton(label: 'Manter', onPressed: () => Navigator.pop(ctx))),
            ],
          ),
        ],
      ),
    );
  }
}

enum _Dot { none, playing, online, off }

class _SectionHead extends StatelessWidget {
  const _SectionHead({required this.label, required this.n, this.lit = false});
  final String label;
  final int n;
  final bool lit;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Text(label, style: AppText.label(size: 11.5, color: lit ? AppColors.ink : AppColors.faint)),
          const SizedBox(width: 8),
          Text('$n', style: AppText.number(size: 12, color: AppColors.faint)),
          const SizedBox(width: 12),
          const Expanded(child: Divider(height: 1, thickness: 1, color: AppColors.line)),
        ],
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.name,
    required this.sub,
    required this.actions,
    this.dot = _Dot.none,
    this.muted = false,
    this.crest = '',
  });

  final String name;
  final String crest;
  final String sub;
  final List<Widget> actions;
  final _Dot dot;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    Widget? mark;
    switch (dot) {
      case _Dot.playing:
        mark = Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.ink, shape: BoxShape.circle));
      case _Dot.online:
        mark = Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.ink, width: 1.6)),
        );
      case _Dot.off:
        mark = Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.glassBorder, width: 1.2)),
        );
      case _Dot.none:
        mark = null;
    }
    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          if (mark != null) ...[mark, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                NameWithCrest(
                  name,
                  crest: crest,
                  size: 16,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: muted ? AppColors.mute : AppColors.ink,
                  ),
                ),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(sub, style: const TextStyle(fontSize: 12, color: AppColors.mute)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          ...actions,
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: AppColors.line),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ninguém por aqui ainda', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.ink)),
            SizedBox(height: 6),
            Text(
              'Peça amizade pelo nome de usuário. Quando aceitarem, você vê quem está com o jogo aberto e desafia '
              'para uma partida por correspondência com um toque.',
              style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.mute),
            ),
          ],
        ),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.bad = false});
  final String text;
  final bool bad;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: bad ? AppColors.bad : AppColors.mute),
        ),
      );
}

/// Convidar para a sala de espera da correspondência: os amigos que ainda não estão nela, e o link/QR para quem
/// não é amigo.
void showCorrInviteSheet(BuildContext context, AppController c) {
  if (!c.friendsLoaded) c.refreshFriends(silent: true);
  showEstSheet<void>(
    context,
    maxWidth: 460,
    builder: (ctx) => ListenableBuilder(
      listenable: c,
      builder: (ctx, _) {
        final seated = {for (final s in c.seats) s.name.toLowerCase()};
        final list = c.friends.friends.where((f) => !seated.contains(f.name.toLowerCase())).toList();
        return EstSheetBody(
          title: 'Convidar',
          onClose: () => Navigator.pop(ctx),
          children: [
            Text(
              list.isEmpty
                  ? 'Mande o link ou o código para quem você quer chamar. Amigos aparecem aqui para convidar com um toque.'
                  : 'O amigo recebe o convite na Correspondência e por e-mail.',
              style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.mute),
            ),
            const SizedBox(height: 12),
            for (final f in list) ...[
              _InviteRow(friend: f, onInvite: () => c.inviteToCorr(f.name)),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 6),
            EstButton(
              icon: EstIconKind.qr,
              label: 'Link ou QR',
              onPressed: () {
                Navigator.pop(ctx);
                showOnlineInviteModal(context, c);
              },
            ),
          ],
        );
      },
    ),
  );
}

class _InviteRow extends StatefulWidget {
  const _InviteRow({required this.friend, required this.onInvite});
  final FriendInfo friend;
  final Future<bool> Function() onInvite;

  @override
  State<_InviteRow> createState() => _InviteRowState();
}

class _InviteRowState extends State<_InviteRow> {
  bool _sent = false;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final f = widget.friend;
    return _Row(
      name: f.name,
      sub: f.playing ? 'jogando agora' : (f.online ? 'online' : ''),
      dot: f.playing ? _Dot.playing : (f.online ? _Dot.online : _Dot.off),
      actions: [
        EstButton(
          small: true,
          label: _sent ? 'Convidado' : 'Chamar',
          onPressed: _sent || _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final ok = await widget.onInvite();
                  if (mounted) {
                    setState(() {
                      _busy = false;
                      _sent = ok;
                    });
                  }
                },
        ),
      ],
    );
  }
}
