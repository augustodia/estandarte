import 'package:flutter/material.dart';

import '../core/map_data.dart';
import '../game/app_controller.dart';
import '../net/online_client.dart';
import 'theme.dart';

class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _codeCtrl;
  late final TextEditingController _searchCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.ctrl.savedName);
    _codeCtrl = TextEditingController();
    _searchCtrl = TextEditingController(text: widget.ctrl.roomsQuery);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _syncName() {
    widget.ctrl.savePlayerName(_nameCtrl.text);
  }

  void _enterCode() {
    final c = roomCode(_codeCtrl.text);
    if (c == null) {
      widget.ctrl.showToast('Digite o código de 5 letras ou cole o link da sala.');
      return;
    }
    _syncName();
    widget.ctrl.joinOnlineRoom(c, _nameCtrl.text, fromRooms: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.ctrl;
    final layout = EstLayout.of(context);
    final compactLand = !layout.big && layout.size.width > layout.size.height && layout.size.height <= 520;
    final horizBar = layout.big || compactLand;

    final wait = c.roomsTab == 'lobby';
    final all = wait ? c.publicLobbyRooms : c.publicPlayRooms;
    final q = c.roomsQuery.trim().toLowerCase();
    final filtered = all.where((r) {
      if (c.roomsOnlyOpen && r['full'] == true) return false;
      if (q.isEmpty) return true;
      final code = (r['code'] as String? ?? '').toLowerCase();
      final host = (r['host'] as String? ?? '').toLowerCase();
      if (code.contains(q) || host.contains(q)) return true;
      final players = (r['players'] as List<dynamic>? ?? const []);
      return players.any((p) => (p['name'] as String? ?? '').toLowerCase().contains(q));
    }).toList();

    final hasData = !c.roomsLoading || c.publicLobbyRooms.isNotEmpty || c.publicPlayRooms.isNotEmpty;
    final statusMsg = !c.netOnline
        ? 'Sem internet: o jogo online precisa de conexão.'
        : (c.roomsError ?? '');

    Widget topHeader() => Row(
          children: [
            SizedBox(
              width: 44,
              child: EstButton(
                label: '←',
                variant: EstButtonVariant.ghost,
                fontSize: 22,
                padding: EdgeInsets.zero,
                onPressed: c.goHome,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              'Jogar online',
              style: AppText.serif(
                size: layout.big ? 32 : (compactLand ? 20 : 24),
              ),
            ),
            const SizedBox(width: 8),
            const EstBadge(text: 'pela internet', net: true),
          ],
        );

    Widget rBar() {
      Widget nameField() => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Seu nome', style: TextStyle(fontSize: 13, color: AppColors.mute)),
              const SizedBox(height: 6),
              TextField(
                controller: _nameCtrl,
                maxLength: 14,
                onChanged: c.savePlayerName,
                decoration: const InputDecoration(
                  hintText: 'Como quer ser chamado',
                  counterText: '',
                ),
              ),
            ],
          );

      Widget createBtn() => EstButton(
            label: 'Criar sala',
            variant: EstButtonVariant.primary,
            onPressed: () {
              _syncName();
              c.createOnlineRoom(_nameCtrl.text, isPublic: true);
            },
          );

      Widget codeField() => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Tem um código ou link?',
                style: TextStyle(fontSize: 13, color: AppColors.mute),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _codeCtrl,
                      maxLength: 80,
                      textCapitalization: TextCapitalization.characters,
                      onSubmitted: (_) => _enterCode(),
                      decoration: const InputDecoration(
                        hintText: 'Ex.: K7M2Q',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  EstButton(label: 'Entrar', onPressed: _enterCode),
                ],
              ),
            ],
          );

      return EstGlassCard(
        borderRadius: 16,
        padding: EdgeInsets.all(layout.big ? 16 : (compactLand ? 8 : 12)),
        child: horizBar
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(width: layout.big ? 240 : 180, child: nameField()),
                  const SizedBox(width: 10),
                  createBtn(),
                  const SizedBox(width: 10),
                  Expanded(child: codeField()),
                ],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(child: nameField()),
                      const SizedBox(width: 10),
                      createBtn(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  codeField(),
                ],
              ),
      );
    }

    Widget toolsRow() {
      final tabs = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.deep,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF233C5E)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _RoomTabButton(
                label: 'Aguardando',
                count: hasData ? '${c.publicLobbyRooms.length}' : '–',
                active: c.roomsTab == 'lobby',
                onTap: () => c.setRoomsTab('lobby'),
              ),
            ),
            Expanded(
              child: _RoomTabButton(
                label: 'Em andamento',
                count: hasData ? '${c.publicPlayRooms.length}' : '–',
                active: c.roomsTab == 'play',
                onTap: () => c.setRoomsTab('play'),
              ),
            ),
          ],
        ),
      );

      final search = SizedBox(
        height: 40,
        child: TextField(
          controller: _searchCtrl,
          onChanged: c.setRoomsQuery,
          decoration: const InputDecoration(
            hintText: 'Buscar sala ou jogador',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          ),
        ),
      );

      final filterChip = EstChip(
        label: wait ? 'Com vaga' : 'Dá para assistir',
        selected: c.roomsOnlyOpen,
        onTap: c.toggleRoomsOnlyOpen,
      );

      if (layout.wide) {
        return Row(
          children: [
            SizedBox(width: 380, child: tabs),
            const SizedBox(width: 8),
            Expanded(child: search),
            const SizedBox(width: 8),
            filterChip,
          ],
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tabs,
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 8),
              filterChip,
            ],
          ),
        ],
      );
    }

    Widget roomCard(Map<String, dynamic> r) {
      final code = r['code'] as String? ?? '';
      final host = r['host'] as String? ?? '';
      final full = r['full'] == true;
      final secs = (r['secs'] as num?)?.toInt() ?? 0;
      final round = (r['round'] as num?)?.toInt() ?? 1;
      final watchers = (r['watchers'] as num?)?.toInt() ?? 0;
      final players = (r['players'] as List<dynamic>? ?? const []);
      final humans = players.where((p) => p['ctrl'] != 'bot').length;
      final bots = players.length - humans;

      final extras = <String>[
        secs > 0 ? '${secs ~/ 60} min/turno' : 'tempo livre',
        if (r['events'] == true) 'eventos de rodada',
        if (r['pacts'] == true) 'pactos',
        if (r['nukes'] == true) 'ogiva nuclear',
        if (r['hq'] == true) 'quartel',
      ].join(' · ');

      final meta = wait
          ? '${players.length} de 6 jogadores · $extras'
          : 'rodada $round · $humans ${humans == 1 ? 'pessoa' : 'pessoas'}'
              '${bots > 0 ? ' e $bots bot${bots == 1 ? '' : 's'}' : ''}'
              ' · 👁 $watchers/${c.maxWatchers} · $extras';

      final colors = c.engine.constants.colors;

      return Opacity(
        opacity: full ? 0.6 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0x8C0B1626),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF233C5E)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Sala de $host',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          code,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                            color: AppColors.gold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      children: [
                        for (final p in players)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: parseHexColor(
                                    colors[((p['color'] as num?)?.toInt() ?? 0) % colors.length].hex,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(color: const Color(0x88000000), width: 1.5),
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${p['name'] ?? ''}',
                                style: const TextStyle(fontSize: 12.5, color: AppColors.ink),
                              ),
                              if (p['ctrl'] == 'bot') ...[
                                const SizedBox(width: 4),
                                const Text(
                                  'BOT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.mute,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      meta,
                      style: const TextStyle(fontSize: 12, color: AppColors.mute),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 88),
                child: EstButton(
                  small: true,
                  variant: wait ? EstButtonVariant.primary : EstButtonVariant.normal,
                  label: wait
                      ? (full ? 'Cheia' : 'Entrar')
                      : (full ? 'Lotada (${c.maxWatchers} assistindo)' : 'Assistir'),
                  onPressed: full
                      ? null
                      : () {
                          _syncName();
                          c.joinOnlineRoom(
                            code,
                            _nameCtrl.text,
                            watchOnly: !wait,
                            fromRooms: true,
                          );
                        },
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget listBody() {
      if (!hasData && c.roomsLoading) {
        return const _EmptyRoomsBox('Procurando salas…');
      }
      if (!hasData && c.roomsError != null) {
        return const _EmptyRoomsBox('Nenhuma sala disponível.');
      }
      if (filtered.isEmpty) {
        final empty = all.isEmpty
            ? (wait
                ? 'Nenhuma sala esperando jogadores agora. Crie uma e chame a turma!'
                : 'Nenhuma partida em andamento agora.')
            : 'Nenhuma sala com esse filtro.';
        return _EmptyRoomsBox(empty);
      }

      return LayoutBuilder(
        builder: (context, constraints) {
          final cols = constraints.maxWidth >= 620
              ? (constraints.maxWidth / 316).floor().clamp(2, 4)
              : 1;
          if (cols == 1) {
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 18),
              itemCount: filtered.length + (filtered.length < all.length ? 1 : 0),
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, idx) {
                if (idx >= filtered.length) {
                  final hidden = all.length - filtered.length;
                  return Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      '$hidden sala${hidden == 1 ? '' : 's'} fora do filtro.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.mute),
                    ),
                  );
                }
                return roomCard(filtered[idx]);
              },
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.only(bottom: 18),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              mainAxisExtent: 124,
            ),
            itemCount: filtered.length,
            itemBuilder: (_, idx) => roomCard(filtered[idx]),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                layout.big ? 28 : 16,
                layout.big ? 24 : 16,
                layout.big ? 28 : 16,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  topHeader(),
                  SizedBox(height: layout.big ? 14 : 10),
                  rBar(),
                  SizedBox(height: layout.big ? 14 : 10),
                  toolsRow(),
                  if (statusMsg.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      statusMsg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12.5, color: AppColors.mute),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Expanded(child: listBody()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoomTabButton extends StatelessWidget {
  const _RoomTabButton({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String label;
  final String count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        height: 38,
        decoration: BoxDecoration(
          color: active ? AppColors.panel2 : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          boxShadow: active
              ? const [BoxShadow(color: Color(0x88000000), blurRadius: 3, offset: Offset(0, 1))]
              : null,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: active ? AppColors.ink : AppColors.mute,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
              decoration: BoxDecoration(
                color: const Color(0x12FFFFFF),
                borderRadius: BorderRadius.circular(999),
              ),
              alignment: Alignment.center,
              child: Text(
                count,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRoomsBox extends StatelessWidget {
  const _EmptyRoomsBox(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF2D4A72)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 13, color: AppColors.mute),
        ),
      ),
    );
  }
}
