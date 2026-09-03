import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app.dart';
import 'services/game_engine.dart';
import 'services/notification_service.dart';
import 'services/storage_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final storage = StorageService();
  await storage.init();

  final notificationService = NotificationService();
  await notificationService.init();

  final engine = GameEngine(storage: storage);
  await engine.init();

  // Flutter exposes the actual Android product flavor through appFlavor.
  // The previous String.fromEnvironment approach defaulted mobile builds to
  // "wear", which could launch the watch UI even from --flavor mobile.
  final flavor = appFlavor ?? 'wear';

  runApp(TamaPokeApp(engine: engine, flavor: flavor));
}
