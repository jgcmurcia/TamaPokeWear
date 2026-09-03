import 'package:flutter/services.dart';

import '../models/pet_state.dart';

/// Small Flutter facade over the Android overlay service.
///
/// The overlay is intentionally Android-only. Calls gracefully no-op on
/// platforms where the native channel is not registered (for example WearOS
/// previews or desktop development).
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

  static Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod<void>('requestOverlayPermission');
    } on MissingPluginException {
      // Unsupported platform/flavor.
    }
  }

  static Future<bool> start(PetState pet) async {
    if (pet.speciesId <= 0 || pet.isEgg) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'startFloatingPet',
            <String, Object>{
              'speciesId': pet.speciesId,
              'shiny': pet.shiny,
            },
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
