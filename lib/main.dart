import 'package:arcamp/screens/now_playing_screen.dart';
import 'package:arcamp/services/arcamp_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final audioHandler = await AudioService.init(
    builder: () => ArcampAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.example.channel.audio',
      androidNotificationChannelName: 'Audio playback',
      androidNotificationOngoing: true,
      // Enable media controls for desktop platforms
      preloadArtwork: true,
    ),
  );
  runApp(App(audioHandler: audioHandler));
}
