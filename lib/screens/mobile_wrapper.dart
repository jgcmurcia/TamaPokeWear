import 'package:flutter/material.dart';

import '../services/floating_pet_service.dart';
import '../services/game_engine.dart';
import 'home_screen.dart';

class MobileWrapper extends StatefulWidget {
  final GameEngine engine;

  const MobileWrapper({Key? key, required this.engine}) : super(key: key);

  @override
  State<MobileWrapper> createState() => _MobileWrapperState();
}

class _MobileWrapperState extends State<MobileWrapper> {
  final GlobalKey<HomeScreenState> _homeKey = GlobalKey<HomeScreenState>();
  bool _floatingPetEnabled = false;
  bool _floatingPetBusy = false;

  Future<void> _toggleFloatingPet() async {
    if (_floatingPetBusy) return;
    setState(() => _floatingPetBusy = true);

    try {
      if (_floatingPetEnabled) {
        await FloatingPetService.stop();
        if (mounted) {
          setState(() => _floatingPetEnabled = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pokémon guardado.')),
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

      final started = await FloatingPetService.start(pet);
      if (mounted) {
        setState(() => _floatingPetEnabled = started);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              started
                  ? '¡Pokémon suelto! Arrástralo, tócalo o haz doble toque para volver al juego.'
                  : 'No se pudo iniciar la mascota flotante.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _floatingPetBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // fallback
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background
          Image.asset(
            'assets/sprites/ui/background.jpg',
            fit: BoxFit.cover,
          ),
          
          SafeArea(
            child: Column(
              children: [
                // Tamagotchi Shell Area
                Expanded(
                  flex: 6,
                  child: Center(
                    // O Transform.scale amplia a carcaça, o visor e os botões de forma simétrica.
                    // Isso "corta" as bordas transparentes do arquivo de imagem original e faz 
                    // o brinquedo preencher a tela do celular.
                    child: Transform.scale(
                      scale: 2.2, 
                      child: AspectRatio(
                        aspectRatio: 0.85, // Proporção da carcaça com a borda transparente original
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 1. A tela redonda (HomeScreen) renderizada ATRÁS da carcaça
                            Align(
                              // Movido um pouco mais para cima (-0.05) para não sobrepor o aro amarelo embaixo
                              alignment: const Alignment(0.0, -0.05), 
                              child: FractionallySizedBox(
                                widthFactor: 0.42, // Mantido 0.42 que encaixou certinho na largura
                                heightFactor: 0.42,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: SizedBox(
                                    width: 350, // Aumentado um pouco para dar mais fôlego aos cantos
                                    height: 350,
                                    child: MediaQuery(
                                      // Substituímos o MediaQuery para a tela achar que está num relógio
                                      data: MediaQuery.of(context).copyWith(size: const Size(350, 350)),
                                      child: ClipOval(
                                        child: HomeScreen(
                                          engine: widget.engine,
                                          homeKey: _homeKey,
                                          isMobileWrapper: true, // Avisa que está no mobile
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),

                          // 2. A imagem da carcaça (com o buraco transparente)
                          // Renderizada por cima da tela do jogo para esconder as bordas.
                          IgnorePointer(
                            child: Image.asset(
                              'assets/sprites/ui/tamagotchi_shell.png',
                              fit: BoxFit.contain,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),

                          // 3. Zonas de toque para A, B, C, D
                          // A posição é baseada no AspectRatio de 0.85.
                          _buildInvisibleButton(
                            alignment: const Alignment(-0.35, 0.45), // A
                            onTap: () => _homeKey.currentState?.actionA(),
                          ),
                          _buildInvisibleButton(
                            alignment: const Alignment(-0.12, 0.60), // B
                            onTap: () => _homeKey.currentState?.actionB(),
                          ),
                          _buildInvisibleButton(
                            alignment: const Alignment(0.12, 0.60), // C
                            onTap: () => _homeKey.currentState?.actionC(),
                          ),
                          _buildInvisibleButton(
                            alignment: const Alignment(0.35, 0.45), // D
                            onTap: () => _homeKey.currentState?.actionD(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
                
                // Bottom Buttons Area
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
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

          // Mobile-only control for the Android overlay pet.
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: FloatingActionButton.small(
                  heroTag: 'floatingPetToggle',
                  tooltip: _floatingPetEnabled
                      ? 'Guardar Pokémon flotante'
                      : 'Soltar Pokémon por la pantalla',
                  onPressed: _floatingPetBusy ? null : _toggleFloatingPet,
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
                              ? Icons.home_rounded
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

  Widget _buildInvisibleButton({required Alignment alignment, required VoidCallback onTap}) {
    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: 0.15,
        heightFactor: 0.15,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            // Cor transparente é OBRIGATÓRIA para o Container receber toques sem ter um child!
            color: Colors.transparent,
            // color: Colors.red.withValues(alpha: 0.5), // Descomente para debugar
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBtn(String asset, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90, // Aumentado
        height: 90, // Aumentado
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.asset(asset, fit: BoxFit.cover),
      ),
    );
  }
}
