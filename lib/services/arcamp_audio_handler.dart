// ignore_for_file: avoid_print
import 'dart:typed_data';
import 'dart:io';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:just_audio/just_audio.dart';
// ignore: depend_on_referenced_packages
import 'package:path_provider/path_provider.dart';

class ArcampAudioHandler extends BaseAudioHandler {
  final _player = AudioPlayer();
  File? _currentAlbumArtFile;

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

      // Detect image format and set appropriate extension
      String extension = '.jpg'; // Default to jpg
      String mimeType = 'image/jpeg';

      // Simple format detection based on file signature
      if (albumArtBytes.length >= 8) {
        // PNG signature: 89 50 4E 47 0D 0A 1A 0A
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

      // Store reference to current album art file
      _currentAlbumArtFile = file;

      print('Album art saved to: ${file.path} (MIME: $mimeType)');
      return file.uri;
    } catch (e) {
      print('Error saving album art: $e');
      return null;
    }
  }

  // Helper method to determine correct MIME type
  String _getMimeType(Uint8List bytes) {
    if (bytes.length >= 8) {
      // PNG signature
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'image/png';
      }
      // JPEG signature
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return 'image/jpeg';
      }
    }
    return 'image/jpeg'; // Default fallback
  }

  Future<void> loadNewAudio(String filePath, Metadata metadata) async {
    try {
      // Stop current playback
      await _player.stop();

      // Load new audio file
      await _player.setFilePath(filePath);

      // Extract file name
      final fileName = filePath.split('/').last;

      Uri? artUri;

      if (metadata.albumArt != null) {
        // Try multiple approaches for album art

        // Approach 1: Save as temporary file (often more reliable on macOS)
        artUri = await _saveAlbumArtAsFile(metadata.albumArt!);

        // Approach 2: If file approach fails, try data URI with correct MIME type
        if (artUri == null) {
          final mimeType = _getMimeType(metadata.albumArt!);
          artUri = Uri.dataFromBytes(metadata.albumArt!, mimeType: mimeType);
          print('Using data URI with MIME type: $mimeType');
        }
      }

      // Wait for duration to be available
      Duration? duration = _player.duration;
      if (duration == null) {
        // Wait a bit for duration to load
        await Future.delayed(const Duration(milliseconds: 100));
        duration = _player.duration ?? Duration.zero;
      }

      // Set new media item
      final mediaItemToAdd = MediaItem(
        id: filePath,
        title: metadata.trackName ?? fileName.split('.').first,
        artist: metadata.trackArtistNames?.join(', ') ?? 'Unknown Artist',
        album: metadata.albumName ?? 'Unknown Album',
        duration: duration,
        artUri: artUri,
        playable: true,
        extras: {
          'albumArtBytes': metadata.albumArt, // Keep original bytes as backup
        },
      );

      mediaItem.add(mediaItemToAdd);
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
      // Don't dispose here, just stop
    } catch (e) {
      print('Error stopping audio: $e');
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    // Clean up album art file and dispose player
    await _cleanupPreviousAlbumArt();
    await _player.dispose();
    await super.onTaskRemoved();
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
