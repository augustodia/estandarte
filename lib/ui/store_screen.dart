import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../game/app_controller.dart';
import '../net/account_api.dart' as acc;
import 'account_sheet.dart';
import 'crest_badge.dart';
import 'theme.dart';

/// Loja: o Comandante (compra única). Nada aqui ajuda a vencer; a ranqueada é igual para todos.
class StoreScreen extends StatelessWidget {
  const StoreScreen({super.key, required this.ctrl});

  final AppController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = ctrl;
    final layout = EstLayout.of(context);
    final short = layout.size.height <= 520;
    final pad = layout.big ? 36.0 : (short ? 16.0 : 20.0);
    final wide = layout.size.width >= 760;

    final left = _OfferPanel(ctrl: c);
    const right = _WhatYouGet();

    return Scaffold(
      backgroundColor: AppColors.deep,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
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
                        onPressed: () {
                          c.cancelPix();
                          c.goHome();
                        },
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Comandante', style: AppText.serif(size: layout.big ? 28 : (short ? 20 : 24))),
                            if (!short) ...[
                              const SizedBox(height: 2),
                              Text('COMPRA ÚNICA · NÃO MUDA NADA NA RANQUEADA', style: AppText.label(size: 11)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: short ? 12 : 22),
                  Expanded(
                    child: wide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(width: 380, child: SingleChildScrollView(child: left)),
                              const SizedBox(width: 28),
                              const Expanded(
                                child: SingleChildScrollView(padding: EdgeInsets.only(bottom: 24), child: right),
                              ),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.only(bottom: 24),
                            children: [left, const SizedBox(height: 24), right],
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
}

class _OfferPanel extends StatelessWidget {
  const _OfferPanel({required this.ctrl});

  final AppController ctrl;

  @override
  Widget build(BuildContext context) {
    final c = ctrl;
    final ent = c.ent;
    final cat = c.storeCatalog;
    final children = <Widget>[];

    if (c.isComandante) {
      children.add(_Box(
        child: Row(
          children: [
            CrestBadge(ent.fundador > 0 ? 'ins_fundador' : 'ins_comandante', size: 48),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ent.fundador > 0 ? 'Fundador nº ${ent.fundador}' : 'Você é Comandante',
                      style: AppText.title(size: 20)),
                  const SizedBox(height: 4),
                  const Text(
                    'Obrigado por apoiar o Ultimato. O que o Comandante libera vale para todos nas salas que você abre, '
                    'e cada novidade chega sem pagar de novo.',
                    style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.mute),
                  ),
                ],
              ),
            ),
          ],
        ),
      ));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
    }

    final items = cat?.items ?? const <acc.StoreItem>[];
    acc.StoreItem? offer;
    for (final it in items) {
      if (it.available) offer = it;
    }
    final fundador = offer?.sku == 'comandante_fundador';

    if (cat == null && c.storeLoading) {
      children.add(const _Box(
        child: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 1.6, color: AppColors.ink)),
          SizedBox(width: 12),
          Text('Abrindo a loja…', style: TextStyle(fontSize: 13.5, color: AppColors.mute)),
        ]),
      ));
    } else if (offer == null) {
      children.add(const _Box(
        child: Text(
          'A loja ainda não abriu. O Comandante chega junto com o lançamento na Google Play.',
          style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.mute),
        ),
      ));
    } else {
      final catalog = cat!;
      final until = catalog.fundadorUntilMs > 0 ? DateTime.fromMillisecondsSinceEpoch(catalog.fundadorUntilMs) : null;
      children.add(_Box(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CrestBadge(fundador ? 'ins_fundador' : 'ins_comandante', size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(offer.name, style: AppText.title(size: 20)),
                      if (fundador && until != null)
                        Text(
                          'Só no lançamento · até ${_ddmm(until.subtract(const Duration(days: 1)))}',
                          style: AppText.label(size: 11, color: AppColors.medal),
                        ),
                    ],
                  ),
                ),
                Text(offer.price, style: AppText.number(size: 20, color: AppColors.ink, weight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Text(offer.desc, style: const TextStyle(fontSize: 13, height: 1.4, color: AppColors.mute)),
            const SizedBox(height: 14),
            ..._buy(context, c, offer, catalog),
          ],
        ),
      ));
    }
    if (c.storeError != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(c.storeError!, style: const TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.bad)),
      ));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }

  List<Widget> _buy(BuildContext context, AppController c, acc.StoreItem offer, acc.StoreCatalog cat) {
    if (!c.signedIn) {
      return [
        EstButton(
          label: 'Entrar para comprar',
          variant: EstButtonVariant.primary,
          height: 46,
          onPressed: () => showAccountSheet(context, c),
        ),
        const SizedBox(height: 8),
        const Text(
          'A compra fica na sua conta e vale em todos os aparelhos.',
          style: TextStyle(fontSize: 12, color: AppColors.faint),
        ),
      ];
    }
    final pix = c.pixOrder;
    if (pix != null) return [_PixPanel(ctrl: c, order: pix)];
    if (cat.pix) {
      return [
        EstButton(
          label: 'Pagar com Pix',
          variant: EstButtonVariant.primary,
          height: 46,
          onPressed: c.pixBusy ? null : () => unawaited(c.buyWithPix(offer.sku)),
        ),
      ];
    }
    return const [
      Text(
        'A compra abre com o lançamento do app na Google Play, e o Pix pelo site logo depois.',
        style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.faint),
      ),
    ];
  }

  static String _ddmm(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Pix em andamento: QR, copia e cola e a confirmação, que chega sozinha.
class _PixPanel extends StatelessWidget {
  const _PixPanel({required this.ctrl, required this.order});

  final AppController ctrl;
  final acc.PixOrder order;

  @override
  Widget build(BuildContext context) {
    final c = ctrl;
    if (order.status == 'paid') {
      return const Text('Pagamento confirmado. Bem-vindo, Comandante!',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink));
    }
    if (order.status == 'expired') {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Esse Pix venceu sem pagamento.', style: TextStyle(fontSize: 13, color: AppColors.mute)),
        const SizedBox(height: 10),
        EstButton(label: 'Gerar outro', onPressed: c.cancelPix),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(8),
            color: Colors.white,
            child: QrImageView(data: order.code, size: 168, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 12),
        EstButton(
          label: 'Copiar Pix copia e cola',
          onPressed: () {
            Clipboard.setData(ClipboardData(text: order.code));
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Código Pix copiado.')));
          },
        ),
        const SizedBox(height: 10),
        const Row(
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 1.5, color: AppColors.mute)),
            SizedBox(width: 10),
            Expanded(
              child: Text('Esperando o pagamento. A confirmação chega sozinha em alguns segundos.',
                  style: TextStyle(fontSize: 12, height: 1.35, color: AppColors.mute)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        EstButton(label: 'Cancelar', variant: EstButtonVariant.ghost, small: true, onPressed: c.cancelPix),
      ],
    );
  }
}

/// O que o Comandante inclui hoje, o que vem depois e o que nunca se vende.
class _WhatYouGet extends StatelessWidget {
  const _WhatYouGet();

  @override
  Widget build(BuildContext context) {
    Widget item(String title, String sub) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: SizedBox(width: 5, height: 5, child: DecoratedBox(decoration: BoxDecoration(color: AppColors.mute))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: '$title  ', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                  TextSpan(text: sub, style: const TextStyle(color: AppColors.mute)),
                ]), style: const TextStyle(fontSize: 13, height: 1.4)),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const EstSectionTag('JÁ INCLUI'),
        const SizedBox(height: 10),
        item('Sala de Comandante.', 'O que você libera vale para todos na mesa que você abre; os convidados não pagam.'),
        item('Insígnia e moldura.', 'Comandante ao lado do seu nome; no lançamento, o brasão Fundador numerado.'),
        const SizedBox(height: 8),
        const EstSectionTag('CHEGA SEM PAGAR DE NOVO'),
        const SizedBox(height: 10),
        item('Mapas e modos novos.', 'Para abrir salas com eles; quem entra joga junto.'),
        item('Liga da Galera e torneios.', 'Classificação do seu grupo por temporada e chaves de até 16.'),
        item('Estatísticas e replays.', 'Histórico completo e o Índice de Sorte de cada partida.'),
        const SizedBox(height: 8),
        const EstSectionTag('NUNCA SE VENDE'),
        const SizedBox(height: 10),
        const Text(
          'Nada que ajude a vencer: nem tropas, nem cartas, nem dados, nem prioridade na fila. Jogar continua grátis e '
          'ilimitado, a ranqueada é igual para todos, e patentes e brasões de mérito só se ganham jogando.',
          style: TextStyle(fontSize: 13, height: 1.45, color: AppColors.mute),
        ),
      ],
    );
  }
}

class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: AppColors.line),
        ),
        child: child,
      );
}
