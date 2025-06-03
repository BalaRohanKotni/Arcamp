// ignore_for_file: avoid_print

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class ArcampAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();

  ArcampAudioHandler() {
    _init();
  }

  Future<void> _init() async {
    // Listen to player state changes and update playback state
    _player.playerStateStream.listen((playerState) {
      final isPlaying = playerState.playing;
      final processingState = playerState.processingState;

      PlaybackState state;
      switch (processingState) {
        case ProcessingState.idle:
          state = PlaybackState(
            controls: [MediaControl.play],
            systemActions: const {MediaAction.seek},
            playing: false,
            processingState: AudioProcessingState.idle,
          );
          break;
        case ProcessingState.loading:
          state = PlaybackState(
            controls: [MediaControl.pause],
            systemActions: const {MediaAction.seek},
            playing: isPlaying,
            processingState: AudioProcessingState.loading,
          );
          break;
        case ProcessingState.buffering:
          state = PlaybackState(
            controls: [MediaControl.pause],
            systemActions: const {MediaAction.seek},
            playing: isPlaying,
            processingState: AudioProcessingState.buffering,
          );
          break;
        case ProcessingState.ready:
          state = PlaybackState(
            controls: [
              if (isPlaying) MediaControl.pause else MediaControl.play,
              MediaControl.skipToPrevious,
              MediaControl.skipToNext,
            ],
            systemActions: const {
              MediaAction.seek,
              MediaAction.seekForward,
              MediaAction.seekBackward,
            },
            playing: isPlaying,
            processingState: AudioProcessingState.ready,
            updatePosition: _player.position,
          );
          break;
        case ProcessingState.completed:
          state = PlaybackState(
            controls: [MediaControl.play],
            systemActions: const {MediaAction.seek},
            playing: false,
            processingState: AudioProcessingState.completed,
          );
          break;
      }

      playbackState.add(state);
    });
  }

  Future<void> loadNewAudio(String filePath) async {
    try {
      // Stop current playback
      await _player.stop();

      // Load new audio file
      await _player.setFilePath(filePath);

      // Extract file name and metadata
      final fileName = filePath.split('/').last;
      final titleWithoutExt = fileName.split('.').first;

      // Set new media item
      mediaItem.add(
        MediaItem(
          id: filePath,
          title: titleWithoutExt,
          artist: 'Unknown Artist',
          album: 'Unknown Album',
          duration: _player.duration ?? Duration.zero,
          // artUri: Uri.parse('https://example.com/album-art.jpg'),
          playable: true,
        ),
      );

      print('New audio loaded successfully: $fileName');
    } catch (e) {
      print('Error loading new audio: $e');
    }
  }

  @override
  Future<void> play() async {
    try {
      await _player.play();
    } catch (e) {
      print('Error playing audio: $e');
    }
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (e) {
      print('Error pausing audio: $e');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
      await _player.dispose();
    } catch (e) {
      print('Error stopping audio: $e');
    }
  }

  @override
  Future<void> seek(Duration position) async {
    try {
      await _player.seek(position);
    } catch (e) {
      print('Error seeking: $e');
    }
  }

  @override
  Future<void> skipToNext() async {
    // Implement next track logic here
    // TODO
    print('Skip to next');
  }

  @override
  Future<void> skipToPrevious() async {
    // Implement previous track logic here
    // TODO
    print('Skip to previous');
  }
}
