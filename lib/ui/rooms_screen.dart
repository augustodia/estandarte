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

    Widget commanderPlaque({double? width}) => Container(
          width: width,
          padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
          decoration: BoxDecoration(
            color: AppColors.obsidian.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              const EstIcon(EstIconKind.crest, size: 15),
              const SizedBox(width: 7),
              const Text(
                'COMANDANTE',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.3,
                  color: AppColors.mute,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  maxLength: 14,
                  onChanged: c.savePlayerName,
                  textAlign: TextAlign.right,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  decoration: const InputDecoration(
                    hintText: 'Seu apelido',
                    counterText: '',
                    filled: false,
                    isDense: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 6),
                  ),
                ),
              ),
            ],
          ),
        );

    Widget topHeader() => Row(
          children: [
            EstIconButton(
              icon: EstIconKind.back,
              size: 36,
              iconSize: 16,
              color: AppColors.ink,
              tooltip: 'Voltar',
              onPressed: c.goHome,
            ),
            const SizedBox(width: 12),
            EstIcon(EstIconKind.globe, size: layout.big ? 22 : 18, color: AppColors.gold),
            const SizedBox(width: 8),
            Text(
              'Salas Online',
              style: AppText.serif(
                size: layout.big ? 28 : (compactLand ? 20 : 22),
              ),
            ),
            if (horizBar) ...[
              const Spacer(),
              commanderPlaque(width: layout.big ? 270 : 220),
            ],
          ],
        );

    Widget commandStrip() {
      final quickCard = EstGlassCard(
        highlight: true,
        borderRadius: 6,
        padding: EdgeInsets.symmetric(horizontal: layout.big ? 16 : 12, vertical: layout.big ? 12 : 10),
        child: Row(
          children: [
            const EstIcon(EstIconKind.bolt, size: 22, color: AppColors.gold),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Text(
                    'PARTIDA RÁPIDA',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.0,
                      color: AppColors.gold,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    '4 comandantes · Quartel · entra em até 45s',
                    style: TextStyle(fontSize: 12, color: AppColors.mute),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            EstButton(
              icon: EstIconKind.sword,
              label: 'Entrar na Fila',
              variant: EstButtonVariant.primary,
              height: 40,
              fontSize: 13,
              onPressed: () {
                _syncName();
                c.startQuickMatch(_nameCtrl.text);
              },
            ),
          ],
        ),
      );

      final customBar = EstGlassCard(
        ornate: false,
        borderRadius: 6,
        padding: EdgeInsets.symmetric(horizontal: layout.big ? 14 : 10, vertical: layout.big ? 10 : 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!horizBar) ...[
              commanderPlaque(),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                EstButton(
                  label: '+ Criar Mesa',
                  height: 40,
                  fontSize: 13,
                  onPressed: () {
                    _syncName();
                    c.createOnlineRoom(_nameCtrl.text, isPublic: true);
                  },
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: EstTextField(
                    controller: _codeCtrl,
                    height: 40,
                    maxLength: 80,
                    hintText: 'Código (ex.: K7M2Q)',
                    textCapitalization: TextCapitalization.characters,
                    onSubmitted: (_) => _enterCode(),
                    style: const TextStyle(
                      fontFamily: AppText.cond, fontFeatures: AppText.tabular,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      fontSize: 13,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                EstButton(
                  label: 'Entrar',
                  height: 40,
                  fontSize: 13,
                  onPressed: _enterCode,
                ),
              ],
            ),
          ],
        ),
      );

      if (layout.wide) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(flex: 11, child: quickCard),
            const SizedBox(width: 10),
            Expanded(flex: 10, child: customBar),
          ],
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          quickCard,
          const SizedBox(height: 8),
          customBar,
        ],
      );
    }

    Widget toolsRow() {
      final tabs = Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.line),
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

      final search = EstTextField(
        controller: _searchCtrl,
        height: 40,
        hintText: 'Buscar sala ou jogador',
        prefix: const Icon(Icons.search_rounded, size: 16, color: AppColors.mute),
        onChanged: (q) {
          c.setRoomsQuery(q);
          setState(() {});
        },
        suffix: _searchCtrl.text.isNotEmpty
            ? IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                icon: const EstIcon(EstIconKind.close, size: 12, color: AppColors.mute),
                onPressed: () {
                  _searchCtrl.clear();
                  c.setRoomsQuery('');
                  setState(() {});
                },
              )
            : null,
      );

      final filterChip = EstChip(
        label: wait ? 'Com vaga' : 'Dá para assistir',
        height: 40,
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
      final isQuick = r['quick'] == true;
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
        if (r['hq'] == true && r['spy'] == true) 'espionagem',
        if (r['hq'] != true) 'cartas',
      ].join(' · ');

      final maxSeats = isQuick ? 4 : 6;
      final openSlots = wait ? (maxSeats - players.length).clamp(0, maxSeats) : 0;
      final meta = wait
          ? '${players.length}/$maxSeats lugares · $extras'
          : 'Rodada $round · $humans ${humans == 1 ? 'humano' : 'humanos'}'
              '${bots > 0 ? ' + $bots bot${bots == 1 ? '' : 's'}' : ''}'
              ' · $watchers/${c.maxWatchers} assistindo · $extras';

      final colors = c.engine.constants.colors;

      return Opacity(
        opacity: full ? 0.58 : 1.0,
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            gradient: AppColors.glassGradient,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isQuick ? const Color(0xFF9AA4B2) : AppColors.line,
            ),
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
                            'Mesa de $host',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (isQuick) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0x28F2EEE6),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.brassDim),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                EstIcon(EstIconKind.bolt, size: 10, color: AppColors.gold),
                                SizedBox(width: 3),
                                Text(
                                  'RÁPIDA',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: AppColors.gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        if (r['hasPass'] == true) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.obsidian,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF9AA4B2)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                EstIcon(EstIconKind.lock, size: 10, color: AppColors.gold),
                                SizedBox(width: 3),
                                Text(
                                  'SENHA',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                    color: AppColors.gold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.obsidian,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.line),
                          ),
                          child: Text(
                            '#$code',
                            style: const TextStyle(
                              fontFamily: AppText.cond, fontFeatures: AppText.tabular,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.7,
                              color: AppColors.gold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        for (final p in players)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              EstFactionSeal(
                                color: parseHexColor(
                                  colors[((p['color'] as num?)?.toInt() ?? 0) % colors.length].hex,
                                ),
                                size: 9,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${p['name'] ?? ''}',
                                style: const TextStyle(fontSize: 12, color: AppColors.ink),
                              ),
                              if (p['ctrl'] == 'bot') ...[
                                const SizedBox(width: 3),
                                const Text(
                                  'BOT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.mute,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        for (var k = 0; k < openSlots; k++)
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.mute.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.mute),
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
                      : (full ? 'Lotada (${c.maxWatchers})' : 'Assistir'),
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
              mainAxisExtent: 132,
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
              child: LayoutBuilder(builder: (context, box) {
                final head = <Widget>[
                  topHeader(),
                  SizedBox(height: layout.big ? 12 : 8),
                  commandStrip(),
                  SizedBox(height: layout.big ? 12 : 8),
                  toolsRow(),
                  if (statusMsg.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      statusMsg,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: AppColors.mute),
                    ),
                  ],
                  const SizedBox(height: 10),
                ];
                // Teclado aberto deixa pouca altura: a tela rola inteira e o campo segue visível.
                if (box.maxHeight < 360) {
                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [...head, SizedBox(height: 280, child: listBody())],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [...head, Expanded(child: listBody())],
                );
              }),
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
        duration: const Duration(milliseconds: 140),
        height: 32,
        decoration: BoxDecoration(
          color: active ? AppColors.panel2 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: active ? Border.all(color: const Color(0xFF7D8796)) : null,
          
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                color: active ? AppColors.ink : AppColors.mute,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              constraints: const BoxConstraints(minWidth: 22),
              height: 20,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(
                color: active
                    ? AppColors.gold.withValues(alpha: 0.16)
                    : AppColors.ink.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: active
                    ? Border.all(color: AppColors.brass.withValues(alpha: 0.40), width: 0.8)
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                count,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  color: active ? AppColors.gold : AppColors.mute,
                  fontFeatures: const [FontFeature.tabularFigures()],
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
        decoration: BoxDecoration(
          color: AppColors.obsidian.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.line),
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
