import 'package:flutter/material.dart';

import 'core/map_data.dart';
import 'engine/game_engine.dart';
import 'game/app_controller.dart';
import 'game/fx_models.dart';
import 'platform/storage.dart';
import 'ui/account_sheet.dart';
import 'ui/corr_screen.dart';
import 'ui/daily_screen.dart';
import 'ui/friends_screen.dart';
import 'ui/game_screen.dart';
import 'ui/home_screen.dart';
import 'ui/lobby_screen.dart';
import 'ui/modals.dart';
import 'ui/rooms_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EstandarteBootstrap());
}

class EstandarteBootstrap extends StatefulWidget {
  const EstandarteBootstrap({super.key});

  @override
  State<EstandarteBootstrap> createState() => _EstandarteBootstrapState();
}

class _EstandarteBootstrapState extends State<EstandarteBootstrap> {
  AppController? _ctrl;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await AppStorage.init();
      final engine = await GameEngine.init();
      final mapData = await MapData.load();
      final ctrl = AppController(mapData: mapData, engine: engine);
      await ctrl.init();
      if (!mounted) {
        ctrl.dispose();
        return;
      }
      setState(() => _ctrl = ctrl);
    } catch (e) {
      if (!mounted) return;
      setState(() => _initError = e);
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ultimato',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: _initError != null
          ? _BootErrorScreen(error: _initError!)
          : _ctrl == null
              ? const _BootLoadingScreen()
              : _EstandarteRoot(ctrl: _ctrl!),
    );
  }
}

class _BootLoadingScreen extends StatelessWidget {
  const _BootLoadingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.deep,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const EstIcon(EstIconKind.crest, size: 54),
            const SizedBox(height: 14),
            Text(
              'ULTIMATO',
              style: AppText.serif(size: 22, letterSpacing: 0.14),
            ),
            const SizedBox(height: 14),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                color: AppColors.brass,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BootErrorScreen extends StatelessWidget {
  const _BootErrorScreen({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 42),
              const SizedBox(height: 12),
              const Text(
                'Não foi possível iniciar o motor de regras.',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                style: const TextStyle(color: AppColors.muted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EstandarteRoot extends StatefulWidget {
  const _EstandarteRoot({required this.ctrl});

  final AppController ctrl;

  @override
  State<_EstandarteRoot> createState() => _EstandarteRootState();
}

class _EstandarteRootState extends State<_EstandarteRoot> {
  bool _handledPendingUrl = false;
  bool _accountOpen = false;

  @override
  void initState() {
    super.initState();
    widget.ctrl.addListener(_onAccountPrompt);
  }

  @override
  void dispose() {
    widget.ctrl.removeListener(_onAccountPrompt);
    super.dispose();
  }

  // Online pediu conta: abre a janela de entrar/criar com o motivo.
  void _onAccountPrompt() {
    final reason = widget.ctrl.accountPrompt;
    if (reason == null || _accountOpen) return;
    widget.ctrl.accountPrompt = null;
    _accountOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showAccountSheet(context, widget.ctrl, reason: reason);
      _accountOpen = false;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledPendingUrl) return;
    _handledPendingUrl = true;
    final c = widget.ctrl;
    if (c.pendingReplayCode != null) {
      final code = c.pendingReplayCode!;
      c.pendingReplayCode = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) c.openReplay(code);
      });
    } else if (c.pendingJoinCorrCode != null) {
      // link de convite da correspondência: abre a lista com a partida (pede a conta antes, se faltar)
      final code = c.pendingJoinCorrCode!;
      c.pendingJoinCorrCode = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        c.corrPrefill = code;
        if (c.signedIn) {
          c.openCorrGame(code);
        } else {
          c.openCorrScreen();
        }
      });
    } else if (c.pendingJoinSalaCode != null) {
      final code = c.pendingJoinSalaCode!;
      c.pendingJoinSalaCode = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _promptSalaJoin(code);
      });
    } else if (c.pendingJoinQrCode != null) {
      final offer = c.pendingJoinQrCode!;
      c.pendingJoinQrCode = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showP2pJoinModal(context, c, initialOffer: offer);
      });
    }
  }

  void _promptSalaJoin(String code) {
    final c = widget.ctrl;
    if (!c.signedIn) {
      c.joinOnlineRoom(code, ''); // pede a conta antes
      return;
    }
    showEstSheet<void>(
      context,
      maxWidth: 420,
      builder: (ctx) => EstSheetBody(
        title: 'Entrar na sala $code',
        onClose: () => Navigator.pop(ctx),
        children: [
          Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Você entra como '),
              TextSpan(text: c.onlineName, style: const TextStyle(color: AppColors.ink, fontWeight: FontWeight.w600)),
              const TextSpan(text: '.'),
            ]),
            style: const TextStyle(fontSize: 14, color: AppColors.mute),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: EstButton(
                  label: 'Entrar',
                  variant: EstButtonVariant.primary,
                  onPressed: () {
                    Navigator.pop(ctx);
                    c.joinOnlineRoom(code, '');
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: EstButton(label: 'Cancelar', onPressed: () => Navigator.pop(ctx)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.ctrl,
      builder: (context, _) {
        final Widget screen = KeyedSubtree(
          key: ValueKey(widget.ctrl.screen),
          child: switch (widget.ctrl.screen) {
            AppScreen.home => HomeScreen(ctrl: widget.ctrl),
            AppScreen.rooms => RoomsScreen(ctrl: widget.ctrl),
            AppScreen.corr => CorrScreen(ctrl: widget.ctrl),
            AppScreen.friends => FriendsScreen(ctrl: widget.ctrl),
            AppScreen.lobby => LobbyScreen(ctrl: widget.ctrl),
            AppScreen.daily => DailyScreen(ctrl: widget.ctrl),
            AppScreen.game => GameScreen(ctrl: widget.ctrl),
          },
        );

        final pageStage = AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(
              scale: Tween(begin: 0.985, end: 1.0).animate(anim),
              child: child,
            ),
          ),
          child: screen,
        );

        final showGlobalToast =
            widget.ctrl.screen != AppScreen.game && widget.ctrl.toastMessage != null;
        final passPrompt = widget.ctrl.passPrompt;
        if (!showGlobalToast && passPrompt == null) return pageStage;

        final layout = EstLayout.of(context);
        return Stack(
          children: [
            pageStage,
            if (showGlobalToast)
              Positioned(
                top: layout.big ? 18 : 62,
                left: 20,
                right: 20,
                child: IgnorePointer(
                  child: Material(
                    color: Colors.transparent,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: AppColors.obsidian.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.brass),
                          boxShadow: AppColors.edgeShadows,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const EstIcon(EstIconKind.compass, size: 14, color: AppColors.gold),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                widget.ctrl.toastMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            if (passPrompt != null)
              _RoomPasswordOverlay(
                key: ValueKey('${passPrompt.code}:${passPrompt.wrong}'),
                ctrl: widget.ctrl,
                prompt: passPrompt,
              ),
          ],
        );
      },
    );
  }
}

class _RoomPasswordOverlay extends StatefulWidget {
  const _RoomPasswordOverlay({
    super.key,
    required this.ctrl,
    required this.prompt,
  });

  final AppController ctrl;
  final ({String code, bool wrong, bool isLan}) prompt;

  @override
  State<_RoomPasswordOverlay> createState() => _RoomPasswordOverlayState();
}

class _RoomPasswordOverlayState extends State<_RoomPasswordOverlay> {
  final _passCtrl = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _passCtrl.text.trim();
    if (p.isEmpty) return;
    widget.ctrl.submitRoomPassword(p);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xD80B0F14),
      child: Padding(
        // acima do teclado
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: EstGlassCard(
              highlight: true,
              ornate: true,
              borderRadius: 6,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const EstIcon(EstIconKind.lock, size: 19, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Sala Protegida',
                          style: AppText.serif(size: 20, color: const Color(0xFFE8ECF1)),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.obsidian,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Text(
                          widget.prompt.isLan ? widget.prompt.code : '#${widget.prompt.code}',
                          style: const TextStyle(
                            fontFamily: AppText.cond, fontFeatures: AppText.tabular,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.gold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const EstRuleDivider(diamond: false),
                  const SizedBox(height: 10),
                  Text(
                    widget.prompt.wrong
                        ? 'Senha incorreta. Confira com o anfitrião e tente novamente.'
                        : 'Digite a senha definida pelo anfitrião para entrar na mesa.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: widget.prompt.wrong ? AppColors.bad : AppColors.mute,
                      fontWeight: widget.prompt.wrong ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 12),
                  EstTextField(
                    controller: _passCtrl,
                    height: 42,
                    obscureText: _obscure,
                    autofocus: true,
                    maxLength: 24,
                    hintText: 'Senha da sala',
                    onSubmitted: (_) => _submit(),
                    suffix: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                      icon: Icon(
                        _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                        size: 18,
                        color: AppColors.mute,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: EstButton(
                          label: 'Entrar',
                          variant: EstButtonVariant.primary,
                          onPressed: _submit,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: EstButton(
                          label: 'Cancelar',
                          variant: EstButtonVariant.ghost,
                          onPressed: widget.ctrl.cancelPasswordPrompt,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
