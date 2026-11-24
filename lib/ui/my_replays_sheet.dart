import 'dart:async';

import 'package:flutter/material.dart';

import '../game/app_controller.dart';
import '../net/account_api.dart' as acc;
import 'crest_badge.dart';
import 'theme.dart';

/// Minhas partidas: as últimas 10 de graça; o arquivo inteiro (e replays que não expiram) para o Comandante.
void showMyReplaysSheet(BuildContext context, AppController c) {
  showEstSheet<void>(
    context,
    maxWidth: 560,
    builder: (ctx) => EstSheetBody(
      title: 'Minhas partidas',
      onClose: () => Navigator.pop(ctx),
      children: [
        _MyReplays(
          ctrl: c,
          onOpen: (id) {
            Navigator.pop(ctx);
            unawaited(c.openReplay(id));
          },
          onStore: () {
            Navigator.pop(ctx);
            c.openStoreScreen();
          },
        ),
      ],
    ),
  );
}

class _MyReplays extends StatefulWidget {
  const _MyReplays({required this.ctrl, required this.onOpen, required this.onStore});

  final AppController ctrl;
  final void Function(String id) onOpen;
  final VoidCallback onStore;

  @override
  State<_MyReplays> createState() => _MyReplaysState();
}

class _MyReplaysState extends State<_MyReplays> {
  ({List<acc.MyReplay> list, bool archive, bool more, int keepDays})? _data;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await widget.ctrl.loadMyReplays();
      if (mounted) setState(() => _data = d);
    } on acc.AccountError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'O servidor não respondeu. Tente de novo.');
    }
  }

  static String _mode(String m) => switch (m) {
        'quick' => 'Partida rápida',
        'corr' => 'Correspondência',
        'daily' => 'Desafio do dia',
        _ => 'Sala online',
      };

  static String _date(int ms) {
    if (ms == 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    if (_error != null) {
      return Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.bad));
    }
    if (d == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.ink)),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (d.list.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Nenhuma partida online guardada ainda.', style: TextStyle(fontSize: 13, color: AppColors.mute)),
          ),
        for (final r in d.list)
          InkWell(
            onTap: () => widget.onOpen(r.id),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text(_date(r.createdMs), style: AppText.number(size: 13, color: AppColors.mute)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.players.join(' × '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.ink)),
                        Text(
                          [_mode(r.mode), if (r.winner.isNotEmpty) 'venceu ${r.winner}', '${r.rounds} rodadas'].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: AppColors.mute),
                        ),
                      ],
                    ),
                  ),
                  if (r.kept) ...[
                    const SizedBox(width: 8),
                    const Tooltip(message: 'No arquivo: não expira', child: CrestBadge('ins_comandante', size: 18)),
                  ],
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.mute),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        if (!d.archive)
          InkWell(
            onTap: widget.onStore,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text(
                'Aqui aparecem suas 10 últimas partidas, guardadas por ${d.keepDays} dias. Com o Comandante você vê '
                'todas, e as jogadas com um Comandante na mesa não expiram.',
                style: const TextStyle(fontSize: 12, height: 1.4, color: AppColors.faint),
              ),
            ),
          )
        else
          const Text(
            'Partidas com um Comandante na mesa ficam no arquivo e não expiram.',
            style: TextStyle(fontSize: 12, height: 1.4, color: AppColors.faint),
          ),
      ],
    );
  }
}
