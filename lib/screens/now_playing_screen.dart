// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:ui';
import 'package:arcamp/services/arcamp_audio_handler.dart';
import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'dart:io';

import 'package:palette_generator/palette_generator.dart';

class App extends StatefulWidget {
  final AudioHandler audioHandler;
  const App({super.key, required this.audioHandler});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  String? selectedFilePath;
  Metadata? audioMetadata;
  PaletteGenerator? _palette;
  Color _dominantColor = Colors.black;
  Color _accentColor = Colors.white;
  // ignore: unused_field
  Color _previousDominantColor = Colors.black;
  Timer? _positionTimer;
  Duration _currentPosition = Duration.zero;

  @override
  void initState() {
    super.initState();
    _startPositionTimer();
    _accentColor = getComplementaryColor(_dominantColor);
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  Color getComplementaryColor(Color color) {
    HSLColor hsl = HSLColor.fromColor(color);
    if (hsl.lightness < 0.5) {
      // If dominant color is dark, use a much lighter version
      return hsl.withLightness((hsl.lightness + 0.6).clamp(0.0, 1.0)).toColor();
    } else {
      // If dominant color is light, use a much darker version
      return hsl.withLightness((hsl.lightness - 0.6).clamp(0.0, 1.0)).toColor();
    }
  }

  Future<void> showChangeSourceDialog() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      // type: FileType.audio,
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        selectedFilePath = result.files.single.path!;
      });

      // Extract metadata and technical info
      await _extractAudioMetadata(selectedFilePath!);

      // Load the new audio file into the handler
      if (widget.audioHandler is ArcampAudioHandler) {
        await (widget.audioHandler as ArcampAudioHandler).loadNewAudio(
          selectedFilePath!,
        );
      }
    }
  }

  void _startPositionTimer() {
    _positionTimer = Timer.periodic(const Duration(milliseconds: 200), (
      timer,
    ) async {
      if (mounted) {
        final playbackState = widget.audioHandler.playbackState.value;
        if (playbackState.playing) {
          // Update position only when playing
          setState(() {
            _currentPosition = playbackState.position;
          });
        }
      }
    });
  }

  Future<void> _extractAudioMetadata(String filePath) async {
    try {
      // Extract metadata using flutter_media_metadata
      final metadata = await MetadataRetriever.fromFile(File(filePath));
      if (metadata.albumArt != null) {
        _palette = await PaletteGenerator.fromImageProvider(
          MemoryImage(metadata.albumArt!),
        );

        final newColor =
            _palette?.darkMutedColor?.color ??
            _palette?.dominantColor?.color ??
            Colors.black;

        if (newColor != _dominantColor) {
          setState(() {
            _previousDominantColor = _dominantColor;
            _dominantColor = newColor;
            _accentColor = getComplementaryColor(_dominantColor);
          });
        }
      }

      if (metadata.albumArt != null) {
        _palette = await PaletteGenerator.fromImageProvider(
          MemoryImage(metadata.albumArt!),
        );

        final newColor =
            _palette?.darkMutedColor?.color ??
            _palette?.dominantColor?.color ??
            Colors.black;

        if (newColor != _dominantColor) {
          setState(() {
            _previousDominantColor = _dominantColor;
            _dominantColor = newColor;
            _accentColor = getComplementaryColor(_dominantColor);
          });
        }
      }

      setState(() {
        audioMetadata = metadata;
      });
    } catch (e) {
      print('Error extracting audio metadata: $e');
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '0:00';
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '$minutes:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return MaterialApp(
      themeMode: ThemeMode.system,
      theme: ThemeData(
        brightness: Brightness.light,
        primarySwatch: Colors.blue,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[900],
      ),
      home: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        body: Stack(
          children: [
            // Main content
            selectedFilePath == null
                ? _buildWelcomeScreen()
                : _buildNowPlayingScreen(isDark),

            // Floating change source button
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: Container(
                decoration: BoxDecoration(
                  color: selectedFilePath != null
                      ? _accentColor.withAlpha(230)
                      : Colors.blue.withAlpha(230),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withAlpha(77),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: IconButton(
                  icon: Icon(
                    Icons.folder_open,
                    color: selectedFilePath != null
                        ? _dominantColor
                        : Colors.white,
                  ),
                  onPressed: showChangeSourceDialog,
                  tooltip: 'Select Audio File',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_note, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 24),
          Text(
            'No audio file selected',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: showChangeSourceDialog,
            icon: const Icon(Icons.folder_open),
            label: const Text('Select Audio File'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNowPlayingScreen(bool isDark) {
    return Stack(
      children: [
        // Blurred album art background
        if (audioMetadata?.albumArt != null)
          SizedBox.expand(
            child: Image.memory(audioMetadata!.albumArt!, fit: BoxFit.cover),
          ),
        if (audioMetadata?.albumArt != null)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(color: _dominantColor.withAlpha(153)),
          )
        else
          Container(color: isDark ? Colors.black : Colors.white),

        // Foreground UI
        SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20.0,
              right: 20.0,
              top:
                  MediaQuery.of(context).padding.top +
                  80, // Account for status bar and floating button
              bottom: 20.0,
            ),
            child: Column(
              children: [
                // Artwork
                Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(51),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: audioMetadata?.albumArt != null
                        ? ClipRRect(
                            key: ValueKey(
                              audioMetadata!.albumArt,
                            ), // ensure it switches
                            borderRadius: BorderRadius.circular(20),
                            child: Image.memory(
                              audioMetadata!.albumArt!,
                              fit: BoxFit.cover,
                              width: 280,
                              height: 280,
                            ),
                          )
                        : Icon(
                            Icons.music_note,
                            size: 100,
                            color: Colors.grey[400],
                          ),
                  ),
                ),
                const SizedBox(height: 30),

                // Song Info
                StreamBuilder<MediaItem?>(
                  stream: widget.audioHandler.mediaItem,
                  builder: (context, snapshot) {
                    final mediaItem = snapshot.data;
                    final title =
                        audioMetadata?.trackName ??
                        mediaItem?.title ??
                        'Unknown Title';
                    final artist =
                        audioMetadata?.trackArtistNames?.join(', ') ??
                        mediaItem?.artist ??
                        'Unknown Artist';
                    final album =
                        audioMetadata?.albumName ??
                        mediaItem?.album ??
                        'Unknown Album';

                    return Column(
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          artist,
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white70,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          album,
                          style: TextStyle(fontSize: 16, color: Colors.white54),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 30),

                // Seek bar and playback controls
                _buildSeekBar(),
                const SizedBox(height: 30),
                _buildControlButtons(),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSeekBar() {
    return StreamBuilder<MediaItem?>(
      stream: widget.audioHandler.mediaItem,
      builder: (context, mediaSnapshot) {
        final duration = mediaSnapshot.data?.duration ?? Duration.zero;

        // Use the timer-updated position instead of stream
        final position = _currentPosition;
        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbColor: _accentColor,
                activeTrackColor: _accentColor.withAlpha(255),
                inactiveTrackColor: _accentColor.withAlpha(76),
                overlayColor: _accentColor.withAlpha(51),
              ),
              child: Slider(
                value: progress.clamp(0.0, 1.0),
                onChanged: (value) {
                  final newPosition = Duration(
                    milliseconds: (value * duration.inMilliseconds).round(),
                  );
                  widget.audioHandler.seek(newPosition);
                  // Update local position immediately for responsive UI
                  setState(() {
                    _currentPosition = newPosition;
                  });
                },
                min: 0.0,
                max: 1.0,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _formatDuration(position),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                  Text(
                    _formatDuration(duration),
                    style: const TextStyle(color: Colors.white70, fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControlButtons() {
    return StreamBuilder<PlaybackState>(
      stream: widget.audioHandler.playbackState,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.skip_previous),
              iconSize: 40,
              color: _accentColor,
            ),
            Container(
              decoration: BoxDecoration(
                color: _accentColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _accentColor.withAlpha(76),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: IconButton(
                onPressed: isPlaying
                    ? widget.audioHandler.pause
                    : widget.audioHandler.play,
                icon: Icon(
                  isPlaying ? Icons.pause : Icons.play_arrow,
                  color: _dominantColor,
                ),
                iconSize: 50,
                padding: const EdgeInsets.all(20),
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.skip_next),
              iconSize: 40,
              color: _accentColor,
            ),
          ],
        );
      },
    );
  }
}
