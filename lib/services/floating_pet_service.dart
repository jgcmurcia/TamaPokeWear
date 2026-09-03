import 'package:flutter/services.dart';

import '../models/pet_state.dart';

/// Flutter facade for the Android floating companion.
///
/// The native service persists its own enabled state and screen position so the
/// companion can survive activity recreation and Android process restarts.
class FloatingPetService {
  FloatingPetService._();

  static const MethodChannel _channel = MethodChannel('tamapokewear/floating_pet');

  static Future<bool> canDrawOverlays() async {
    try {
      return await _channel.invokeMethod<bool>('canDrawOverlays') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> isRunning() async {
    try {
      return await _channel.invokeMethod<bool>('isFloatingPetRunning') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod<void>('requestOverlayPermission');
    } on MissingPluginException {
      // Unsupported platform/flavor.
    }
  }

  static Map<String, Object> _payload(
    PetState pet, {
    required int mischiefLevel,
    required int sizeDp,
  }) {
    return <String, Object>{
      'speciesId': pet.speciesId,
      'shiny': pet.shiny,
      'fullness': pet.fullness,
      'joy': pet.joy,
      'energy': pet.energy,
      'hygiene': pet.hygiene,
      'sleeping': pet.sleeping,
      'poops': pet.poops,
      'mischiefLevel': mischiefLevel.clamp(0, 5),
      'sizeDp': sizeDp.clamp(88, 240),
    };
  }

  static Future<bool> start(
    PetState pet, {
    int mischiefLevel = 2,
    int sizeDp = 150,
  }) async {
    if (pet.speciesId <= 0 || pet.isEgg) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'startFloatingPet',
            _payload(
              pet,
              mischiefLevel: mischiefLevel,
              sizeDp: sizeDp,
            ),
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<bool> update(
    PetState pet, {
    int mischiefLevel = 2,
    int sizeDp = 150,
  }) async {
    if (pet.speciesId <= 0 || pet.isEgg) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'updateFloatingPet',
            _payload(
              pet,
              mischiefLevel: mischiefLevel,
              sizeDp: sizeDp,
            ),
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> stop() async {
    try {
      await _channel.invokeMethod<void>('stopFloatingPet');
    } on MissingPluginException {
      // Unsupported platform/flavor.
    }
  }
}
