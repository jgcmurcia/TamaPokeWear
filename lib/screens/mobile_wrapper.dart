import 'dart:async';

import 'package:flutter/material.dart';

import '../services/floating_pet_service.dart';
import '../services/game_engine.dart';
import 'home_screen.dart';

/// Phone-first shell for TamaPoke Pocket.
///
/// The original Tamagotchi shell is still available as Retro mode, but mobile
/// now defaults to a full-screen companion view so the phone display is actually
/// used. The floating companion controls also live here.
class MobileWrapper extends StatefulWidget {
  final GameEngine engine;

  const MobileWrapper({super.key, required this.engine});

  @override
  State<MobileWrapper> createState() => _MobileWrapperState();
}

class _MobileWrapperState extends State<MobileWrapper>
    with WidgetsBindingObserver {
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();

  bool _retroMode = false;
  bool _floatingPetEnabled = false;
  bool _floatingPetBusy = false;
  int _mischiefLevel = 2;
  double _petSizeDp = 150;

  VoidCallback? _originalEngineStateCallback;
  VoidCallback? _engineStateBridge;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bindEngineStateBridge();
      unawaited(_syncFloatingState());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_engineStateBridge != null &&
        identical(widget.engine.onStateChanged, _engineStateBridge)) {
      widget.engine.onStateChanged = _originalEngineStateCallback;
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncFloatingState(updateSnapshot: true));
    }
  }

  void _bindEngineStateBridge() {
    _originalEngineStateCallback = widget.engine.onStateChanged;
    _engineStateBridge = () {
      _originalEngineStateCallback?.call();
      _onPetStateChanged();
    };
    widget.engine.onStateChanged = _engineStateBridge;
  }

  void _onPetStateChanged() {
    if (!_floatingPetEnabled) return;
    final pet = widget.engine.pet;
    if (pet.isEgg || pet.speciesId <= 0) {
      unawaited(FloatingPetService.stop());
      if (mounted) setState(() => _floatingPetEnabled = false);
      return;
    }
    unawaited(
      FloatingPetService.update(
        pet,
        mischiefLevel: _mischiefLevel,
        sizeDp: _petSizeDp.round(),
      ),
    );
  }

  Future<void> _syncFloatingState({bool updateSnapshot = false}) async {
    final running = await FloatingPetService.isRunning();
    if (!mounted) return;
    setState(() => _floatingPetEnabled = running);
    if (running && updateSnapshot) _onPetStateChanged();
  }

  Future<void> _toggleFloatingPet() async {
    if (_floatingPetBusy) return;
    setState(() => _floatingPetBusy = true);

    try {
      if (_floatingPetEnabled) {
        await FloatingPetService.stop();
        if (mounted) {
          setState(() => _floatingPetEnabled = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pokémon guardado en su Poké Ball.')),
          );
        }
        return;
      }

      final pet = widget.engine.pet;
      if (pet.isEgg || pet.speciesId <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Primero tiene que nacer tu Pokémon.')),
          );
        }
        return;
      }

      final allowed = await FloatingPetService.canDrawOverlays();
      if (!allowed) {
        await FloatingPetService.requestOverlayPermission();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Activa “Mostrar sobre otras aplicaciones”, vuelve a TamaPoke y pulsa de nuevo.',
              ),
              duration: Duration(seconds: 5),
            ),
          );
        }
        return;
      }

      final started = await FloatingPetService.start(
        pet,
        mischiefLevel: _mischiefLevel,
        sizeDp: _petSizeDp.round(),
      );
      if (mounted) {
        setState(() => _floatingPetEnabled = started);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              started
                  ? '¡${pet.nick.isNotEmpty ? pet.nick : 'Tu Pokémon'} está suelto por la pantalla!'
                  : 'No se pudo iniciar el compañero flotante.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _floatingPetBusy = false);
    }
  }

  Future<void> _showPetControls() async {
    await _syncFloatingState();
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171725),
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final mischiefName = switch (_mischiefLevel) {
              0 => 'Quieto',
              1 => 'Tranquilo',
              2 => 'Normal',
              3 => 'Travieso',
              4 => 'Caos',
              _ => 'Team Rocket',
            };

            Future<void> pushSettings() async {
              if (!_floatingPetEnabled) return;
              await FloatingPetService.update(
                widget.engine.pet,
                mischiefLevel: _mischiefLevel,
                sizeDp: _petSizeDp.round(),
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _floatingPetEnabled
                              ? Icons.catching_pokemon
                              : Icons.pets_rounded,
                          color: _floatingPetEnabled
                              ? Colors.greenAccent
                              : Colors.white70,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _floatingPetEnabled
                                ? 'Compañero flotante activo'
                                : 'Compañero flotante',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Travesura: $mischiefName',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Slider(
                      value: _mischiefLevel.toDouble(),
                      min: 0,
                      max: 5,
                      divisions: 5,
                      label: mischiefName,
                      onChanged: (value) {
                        setState(() => _mischiefLevel = value.round());
                        setSheetState(() {});
                        unawaited(pushSettings());
                      },
                    ),
                    Text(
                      'Tamaño: ${_petSizeDp.round()} dp',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    Slider(
                      value: _petSizeDp,
                      min: 96,
                      max: 220,
                      divisions: 31,
                      label: '${_petSizeDp.round()} dp',
                      onChanged: (value) {
                        setState(() => _petSizeDp = value);
                        setSheetState(() {});
                        unawaited(pushSettings());
                      },
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _floatingPetBusy
                          ? null
                          : () async {
                              await _toggleFloatingPet();
                              if (context.mounted) setSheetState(() {});
                            },
                      icon: Icon(
                        _floatingPetEnabled
                            ? Icons.home_rounded
                            : Icons.catching_pokemon,
                      ),
                      label: Text(
                        _floatingPetEnabled
                            ? 'Guardar Pokémon'
                            : 'Soltar Pokémon',
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Toque: reacción · doble toque: abrir TamaPoke · mantén y arrastra: mover',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_retroMode) _buildRetroMode() else _buildPhoneMode(),

          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.58),
                  shape: const CircleBorder(),
                  child: IconButton(
                    tooltip: _retroMode ? 'Modo móvil' : 'Modo retro',
                    onPressed: () => setState(() => _retroMode = !_retroMode),
                    icon: Icon(
                      _retroMode ? Icons.smartphone_rounded : Icons.toys_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FloatingActionButton.small(
                  heroTag: 'floatingPetControls',
                  tooltip: 'Compañero flotante',
                  onPressed: _floatingPetBusy ? null : _showPetControls,
                  backgroundColor: _floatingPetEnabled
                      ? Colors.red.shade700
                      : Colors.black.withValues(alpha: 0.72),
                  foregroundColor: Colors.white,
                  child: _floatingPetBusy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _floatingPetEnabled
                              ? Icons.catching_pokemon
                              : Icons.pets_rounded,
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneMode() {
    return Stack(
      fit: StackFit.expand,
      children: [
        HomeScreen(
          engine: widget.engine,
          homeKey: _homeKey,
          isMobileWrapper: true,
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(left: 22, right: 22, bottom: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white12),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _phoneNavButton(
                        icon: Icons.catching_pokemon,
                        label: 'Pokédex',
                        onTap: () => _homeKey.currentState?.openDex(),
                      ),
                      _phoneNavButton(
                        icon: Icons.badge_outlined,
                        label: 'Ficha',
                        onTap: () => _homeKey.currentState?.openStatCard(),
                      ),
                      _phoneNavButton(
                        icon: Icons.settings_rounded,
                        label: 'Ajustes',
                        onTap: () => _homeKey.currentState?.openSettings(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _phoneNavButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 21),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRetroMode() {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset('assets/sprites/ui/background.jpg', fit: BoxFit.cover),
        SafeArea(
          child: Column(
            children: [
              Expanded(
                flex: 6,
                child: Center(
                  child: Transform.scale(
                    scale: 2.2,
                    child: AspectRatio(
                      aspectRatio: 0.85,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Align(
                            alignment: const Alignment(0.0, -0.05),
                            child: FractionallySizedBox(
                              widthFactor: 0.42,
                              heightFactor: 0.42,
                              child: FittedBox(
                                fit: BoxFit.contain,
                                child: SizedBox(
                                  width: 350,
                                  height: 350,
                                  child: MediaQuery(
                                    data: MediaQuery.of(context)
                                        .copyWith(size: const Size(350, 350)),
                                    child: ClipOval(
                                      child: HomeScreen(
                                        engine: widget.engine,
                                        homeKey: _homeKey,
                                        isMobileWrapper: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IgnorePointer(
                            child: Image.asset(
                              'assets/sprites/ui/tamagotchi_shell.png',
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),
                          _buildInvisibleButton(
                            alignment: const Alignment(-0.35, 0.45),
                            onTap: () => _homeKey.currentState?.actionA(),
                          ),
                          _buildInvisibleButton(
                            alignment: const Alignment(-0.12, 0.60),
                            onTap: () => _homeKey.currentState?.actionB(),
                          ),
                          _buildInvisibleButton(
                            alignment: const Alignment(0.12, 0.60),
                            onTap: () => _homeKey.currentState?.actionC(),
                          ),
                          _buildInvisibleButton(
                            alignment: const Alignment(0.35, 0.45),
                            onTap: () => _homeKey.currentState?.actionD(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildBottomBtn('assets/sprites/ui/btn_dex.jpg', () {
                          _homeKey.currentState?.openDex();
                        }),
                        _buildBottomBtn('assets/sprites/ui/btn_info.jpg', () {
                          _homeKey.currentState?.openStatCard();
                        }),
                        _buildBottomBtn('assets/sprites/ui/btn_settings.jpg', () {
                          _homeKey.currentState?.openSettings();
                        }),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInvisibleButton({
    required Alignment alignment,
    required VoidCallback onTap,
  }) {
    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: 0.15,
        heightFactor: 0.15,
        child: GestureDetector(
          onTap: onTap,
          child: Container(color: Colors.transparent),
        ),
      ),
    );
  }

  Widget _buildBottomBtn(String asset, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        height: 90,
        decoration: const BoxDecoration(shape: BoxShape.circle),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(asset, fit: BoxFit.cover),
      ),
    );
  }
}
