import 'package:flutter/material.dart';

import '../data/pokedex.dart';
import '../i18n/strings.dart';
import '../services/audio_service.dart';
import '../services/game_engine.dart';
import '../theme/wear_theme.dart';

enum _DexFilter { all, owned, missing, shiny, pc }

class PokedexScreen extends StatefulWidget {
  final GameEngine engine;
  final VoidCallback? onReturnHome;
  final bool isMobileWrapper;

  const PokedexScreen({
    super.key,
    required this.engine,
    this.onReturnHome,
    this.isMobileWrapper = false,
  });

  @override
  State<PokedexScreen> createState() => _PokedexScreenState();
}

class _PokedexScreenState extends State<PokedexScreen> {
  _DexFilter _filter = _DexFilter.all;

  void _attemptSwap(int targetId, bool targetShiny) {
    if (targetId == widget.engine.pet.speciesId &&
        targetShiny == widget.engine.pet.shiny) {
      return;
    }

    final isVeteran = widget.engine.isCurrentPetVeteran();

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isVeteran ? Icons.star_rounded : Icons.warning_rounded,
                  color: isVeteran ? Colors.amber : Colors.redAccent,
                  size: 28,
                ),
                const SizedBox(height: 6),
                Text(
                  isVeteran ? tr('pcVeteranTitle') : tr('pcNewbieTitle'),
                  style: TextStyle(
                    fontSize: 15,
                    color: isVeteran ? Colors.amber : Colors.redAccent,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  isVeteran ? tr('pcVeteranMsg') : tr('pcNewbieMsg'),
                  style: const TextStyle(fontSize: 12, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        isVeteran ? Colors.blueAccent : Colors.redAccent,
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.engine.swapWithArchived(targetId, targetShiny);
                    widget.onReturnHome?.call();
                  },
                  child: Text(
                    isVeteran ? tr('pcVeteranSave') : tr('pcNewbieRelease'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<int> _visibleIds() {
    final pet = widget.engine.pet;
    return List<int>.generate(151, (index) => index + 1).where((id) {
      return switch (_filter) {
        _DexFilter.all => true,
        _DexFilter.owned => pet.isRegistered(id),
        _DexFilter.missing => !pet.isRegistered(id),
        _DexFilter.shiny => pet.isShinyRegistered(id),
        _DexFilter.pc => widget.engine.hasArchivedPet(id, false) ||
            widget.engine.hasArchivedPet(id, true),
      };
    }).toList(growable: false);
  }

  String _filterLabel(_DexFilter value) {
    return switch (value) {
      _DexFilter.all => '151',
      _DexFilter.owned => 'Míos',
      _DexFilter.missing => 'Faltan',
      _DexFilter.shiny => 'Shiny',
      _DexFilter.pc => 'PC',
    };
  }

  void _openEntry(int id) {
    final pet = widget.engine.pet;
    if (!pet.isRegistered(id)) {
      AudioService().playDeny();
      return;
    }

    AudioService().playPlay();
    bool showShiny = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF171725),
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final entry = dex[id];
            final shinyAvailable = pet.isShinyRegistered(id);
            if (!shinyAvailable) showShiny = false;
            final folder = showShiny ? 'shiny' : 'normal';
            final archived = widget.engine.hasArchivedPet(id, showShiny);
            final isCurrent = pet.speciesId == id && pet.shiny == showShiny;
            final next = entry.evolvesTo > 0 ? dex[entry.evolvesTo] : null;

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 26),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: WearTheme.typeColor(entry.type)
                                .withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '#${id.toString().padLeft(3, '0')}',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            entry.displayName.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                        if (archived)
                          const Icon(
                            Icons.inventory_2_rounded,
                            color: Colors.amber,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 180,
                      child: Image.asset(
                        'assets/sprites/$folder/${id.toString().padLeft(3, '0')}_idle.gif',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Image.asset(
                          'assets/sprites/thumbs/$id.png',
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    if (shinyAvailable)
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(value: false, label: Text('Normal')),
                          ButtonSegment(
                            value: true,
                            label: Text('Shiny ✨'),
                          ),
                        ],
                        selected: {showShiny},
                        onSelectionChanged: (selection) {
                          setSheetState(() => showShiny = selection.first);
                        },
                      ),
                    const SizedBox(height: 14),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _infoPill(
                          Icons.category_rounded,
                          entry.type.toUpperCase(),
                          WearTheme.typeColor(entry.type),
                        ),
                        if (isCurrent)
                          _infoPill(
                            Icons.favorite_rounded,
                            'Compañero Lv.${pet.level}',
                            Colors.pinkAccent,
                          ),
                        if (archived)
                          _infoPill(
                            Icons.inventory_2_rounded,
                            'PC BOX',
                            Colors.amber,
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            next == null
                                ? 'Forma final de su línea evolutiva.'
                                : 'Evoluciona a ${next.displayName} en Nv.${entry.evolveLevel}.',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          if (isCurrent) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Vínculo ${pet.bond}/100 · Peso ${pet.weight}/100 · Medallas ${pet.totalMedals}',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (archived && !isCurrent) ...[
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _attemptSwap(id, showShiny);
                        },
                        icon: const Icon(Icons.swap_horiz_rounded),
                        label: const Text('Hacer compañero desde PC'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _infoPill(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.17),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pet = widget.engine.pet;
    final ids = _visibleIds();

    return Scaffold(
      backgroundColor: const Color(0xFF111528),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(height: widget.isMobileWrapper ? 66 : 16),
            Text(
              'POKÉDEX  ${pet.registeredCount}/151',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 38,
              child: ListView.separated(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.isMobileWrapper ? 18 : 28,
                ),
                scrollDirection: Axis.horizontal,
                itemCount: _DexFilter.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final value = _DexFilter.values[index];
                  return ChoiceChip(
                    label: Text(_filterLabel(value)),
                    selected: _filter == value,
                    onSelected: (_) => setState(() => _filter = value),
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ids.isEmpty
                  ? const Center(
                      child: Text(
                        'Todavía no hay Pokémon aquí.',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : GridView.builder(
                      padding: EdgeInsets.only(
                        left: widget.isMobileWrapper ? 18 : 30,
                        right: widget.isMobileWrapper ? 18 : 30,
                        bottom: widget.isMobileWrapper ? 100 : 60,
                      ),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 0.9,
                      ),
                      itemCount: ids.length,
                      itemBuilder: (context, index) {
                        final id = ids[index];
                        final registered = pet.isRegistered(id);
                        final shinyReg = pet.isShinyRegistered(id);
                        final hasPc = widget.engine.hasArchivedPet(id, false) ||
                            widget.engine.hasArchivedPet(id, true);
                        final path =
                            'assets/sprites/normal/${id.toString().padLeft(3, '0')}_idle.gif';

                        Widget sprite = Image.asset(
                          path,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Image.asset(
                            'assets/sprites/thumbs/$id.png',
                            fit: BoxFit.contain,
                          ),
                        );

                        if (!registered) {
                          sprite = ColorFiltered(
                            colorFilter: const ColorFilter.mode(
                              Color(0xFF0B0C13),
                              BlendMode.srcATop,
                            ),
                            child: sprite,
                          );
                        }

                        return GestureDetector(
                          onTap: () => _openEntry(id),
                          onLongPress: () {
                            if (hasPc) {
                              final useShiny = widget.engine.hasArchivedPet(id, true) &&
                                  !widget.engine.hasArchivedPet(id, false);
                              AudioService().playEvolve();
                              _attemptSwap(id, useShiny);
                            }
                          },
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: registered
                                  ? Colors.white.withValues(alpha: 0.08)
                                  : Colors.black.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: hasPc
                                    ? Colors.amber.withValues(alpha: 0.72)
                                    : Colors.white10,
                              ),
                            ),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(5, 9, 5, 14),
                                    child: sprite,
                                  ),
                                ),
                                Positioned(
                                  left: 6,
                                  bottom: 4,
                                  child: Text(
                                    '#${id.toString().padLeft(3, '0')}',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (shinyReg)
                                  const Positioned(
                                    top: 4,
                                    right: 5,
                                    child: Text('✨', style: TextStyle(fontSize: 12)),
                                  ),
                                if (hasPc)
                                  const Positioned(
                                    right: 5,
                                    bottom: 3,
                                    child: Icon(
                                      Icons.inventory_2_rounded,
                                      color: Colors.amber,
                                      size: 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
