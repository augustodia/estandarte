import 'package:flutter/material.dart';

import 'core/map_data.dart';
import 'engine/game_engine.dart';
import 'game/app_controller.dart';
import 'game/fx_models.dart';
import 'platform/storage.dart';
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
      title: 'Estandarte',
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
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: AppColors.gold),
            SizedBox(height: 14),
            Text('Carregando Estandarte…', style: TextStyle(color: AppColors.muted)),
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handledPendingUrl) return;
    _handledPendingUrl = true;
    final c = widget.ctrl;
    if (c.pendingJoinSalaCode != null) {
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
    final nameCtrl = TextEditingController(text: widget.ctrl.savedName);
    showEstSheet<void>(
      context,
      maxWidth: 420,
      builder: (ctx) => EstSheetBody(
        title: 'Entrar na sala $code',
        onClose: () => Navigator.pop(ctx),
        children: [
          const Text('Seu nome', style: TextStyle(fontSize: 13, color: AppColors.mute)),
          const SizedBox(height: 6),
          TextField(
            controller: nameCtrl,
            maxLength: 14,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Como quer ser chamado',
              counterText: '',
            ),
            onSubmitted: (_) {
              Navigator.pop(ctx);
              widget.ctrl.joinOnlineRoom(code, nameCtrl.text);
            },
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
                    widget.ctrl.joinOnlineRoom(code, nameCtrl.text);
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
        final Widget screen;
        switch (widget.ctrl.screen) {
          case AppScreen.home:
            screen = HomeScreen(ctrl: widget.ctrl);
          case AppScreen.rooms:
            screen = RoomsScreen(ctrl: widget.ctrl);
          case AppScreen.lobby:
            screen = LobbyScreen(ctrl: widget.ctrl);
          case AppScreen.game:
            screen = GameScreen(ctrl: widget.ctrl);
        }

        final showGlobalToast =
            widget.ctrl.screen != AppScreen.game && widget.ctrl.toastMessage != null;
        if (!showGlobalToast) return screen;

        final layout = EstLayout.of(context);
        return Stack(
          children: [
            screen,
            Positioned(
              top: layout.big ? 18 : 62,
              left: 20,
              right: 20,
              child: IgnorePointer(
                child: Material(
                  color: Colors.transparent,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xF00A1422),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.glassBorder),
                        boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 24)],
                      ),
                      child: Text(
                        widget.ctrl.toastMessage!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
