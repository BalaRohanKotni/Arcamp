// Enhanced ArcampAudioHandler with better session management
import 'dart:typed_data';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

class ArcampAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();
  File? _currentAlbumArtFile;
  bool _isLoadingNewTrack = false;

  // Queue management callbacks
  Function()? onSkipToNext;
  Function()? onSkipToPrevious;

  ArcampAudioHandler() {
    _init();
  }

  void setQueueCallbacks({Function()? skipToNext, Function()? skipToPrevious}) {
    onSkipToNext = skipToNext;
    onSkipToPrevious = skipToPrevious;
  }

  Future<void> _init() async {
    // Listen to player state changes and update playback state
    _player.playerStateStream.listen((playerState) {
      // Skip state updates while loading new track to prevent conflicts
      if (_isLoadingNewTrack) return;

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

    // Listen for when tracks complete to handle auto-next
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        // Auto-skip to next track when current track completes
        skipToNext();
      }
    });
  }

  Future<void> loadNewAudio(String filePath, Metadata metadata) async {
    try {
      print('Loading new audio: ${filePath.split('/').last}');
      _isLoadingNewTrack = true;

      // Stop current playback but don't dispose
      await _player.stop();
      await _cleanupPreviousAlbumArt();

      // Load new audio file
      await _player.setFilePath(filePath);

      // Wait for the player to be ready
      await _player.load();

      final fileName = filePath.split('/').last;
      Uri? artUri;

      if (metadata.albumArt != null) {
        artUri = await _saveAlbumArtAsFile(metadata.albumArt!);
        if (artUri == null) {
          final mimeType = _getMimeType(metadata.albumArt!);
          artUri = Uri.dataFromBytes(metadata.albumArt!, mimeType: mimeType);
        }
      }

      // Get duration - wait for it to be available
      Duration? duration = _player.duration;
      if (duration == null) {
        // Wait for duration to load
        int attempts = 0;
        while (duration == null && attempts < 10) {
          await Future.delayed(const Duration(milliseconds: 50));
          duration = _player.duration;
          attempts++;
        }
        duration ??= Duration.zero;
      }

      // Create and set new media item
      final mediaItemToAdd = MediaItem(
        id: filePath,
        title: metadata.trackName ?? fileName.split('.').first,
        artist: metadata.trackArtistNames?.join(', ') ?? 'Unknown Artist',
        album: metadata.albumName ?? 'Unknown Album',
        duration: duration,
        artUri: artUri,
        playable: true,
        extras: {'albumArtBytes': metadata.albumArt, 'filePath': filePath},
      );

      mediaItem.add(mediaItemToAdd);

      // Force update playback state to ready
      playbackState.add(
        PlaybackState(
          controls: [
            MediaControl.play,
            MediaControl.skipToPrevious,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          playing: false,
          processingState: AudioProcessingState.ready,
          updatePosition: Duration.zero,
        ),
      );

      _isLoadingNewTrack = false;
      print('Successfully loaded new audio: ${mediaItemToAdd.title}');
    } catch (e) {
      _isLoadingNewTrack = false;
      print('Error loading new audio: $e');
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    try {
      print('Play requested - current state: ${_player.processingState}');

      // Ensure we have a loaded audio file
      if (_player.processingState == ProcessingState.idle) {
        print('Player is idle, cannot play');
        return;
      }

      await _player.play();
      print('Play command executed');
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
    print('Skip to next track requested');
    if (onSkipToNext != null) {
      await onSkipToNext!();
    } else {
      print('No skip to next callback set');
    }
  }

  @override
  Future<void> skipToPrevious() async {
    print('Skip to previous track requested');

    final currentPosition = _player.position;
    const thresholdDuration = Duration(seconds: 4);

    if (currentPosition < thresholdDuration) {
      if (onSkipToPrevious != null) {
        await onSkipToPrevious!();
      } else {
        print('No skip to previous callback set');
      }
    } else {
      print('Restarting current track');
      await seek(Duration.zero);
    }
  }

  Future<void> _cleanupPreviousAlbumArt() async {
    if (_currentAlbumArtFile != null && await _currentAlbumArtFile!.exists()) {
      try {
        await _currentAlbumArtFile!.delete();
        print('Deleted previous album art file: ${_currentAlbumArtFile!.path}');
      } catch (e) {
        print('Error deleting previous album art file: $e');
      }
      _currentAlbumArtFile = null;
    }
  }

  Future<Uri?> _saveAlbumArtAsFile(Uint8List albumArtBytes) async {
    try {
      await _cleanupPreviousAlbumArt();

      final tempDir = await getTemporaryDirectory();
      final fileName = 'album_art_${DateTime.now().millisecondsSinceEpoch}';

      String extension = '.jpg';
      String mimeType = 'image/jpeg';

      if (albumArtBytes.length >= 8) {
        if (albumArtBytes[0] == 0x89 &&
            albumArtBytes[1] == 0x50 &&
            albumArtBytes[2] == 0x4E &&
            albumArtBytes[3] == 0x47) {
          extension = '.png';
          mimeType = 'image/png';
        }
      }

      final file = File('${tempDir.path}/$fileName$extension');
      await file.writeAsBytes(albumArtBytes);
      _currentAlbumArtFile = file;

      print('Album art saved to: ${file.path} (MIME: $mimeType)');
      return file.uri;
    } catch (e) {
      print('Error saving album art: $e');
      return null;
    }
  }

  String _getMimeType(Uint8List bytes) {
    if (bytes.length >= 8) {
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'image/png';
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return 'image/jpeg';
      }
    }
    return 'image/jpeg';
  }

  @override
  Future<void> onTaskRemoved() async {
    await _cleanupPreviousAlbumArt();
    await _player.dispose();
    await super.onTaskRemoved();
  }
}
