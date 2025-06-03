// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:ui';
import 'package:arcamp/services/arcamp_audio_handler.dart';
import 'package:arcamp/services/metadata_extractor.dart';
import 'package:arcamp/services/waveform_extractor.dart';
import 'package:arcamp/widgets/audio_control_buttons.dart';
import 'package:arcamp/widgets/audio_info_row.dart';
import 'package:arcamp/widgets/seek_bar.dart';
import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
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

  List<double> _waveformData = [];
  bool _isLoadingWaveform = false;

  @override
  void initState() {
    super.initState();
    _startPositionTimer();
    _accentColor = AudioMetadataExtractor.getComplementaryColor(_dominantColor);
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    super.dispose();
  }

  Color _getTextColor(bool isDark, {double opacity = 1.0}) {
    if (audioMetadata?.albumArt != null) {
      // When album art is present, always use white text (as before)
      return Colors.white.withAlpha((opacity * 255).round());
    } else {
      // When no album art, use appropriate color for the theme
      return isDark
          ? Colors.white.withAlpha((opacity * 255).round())
          : Colors.black.withAlpha((opacity * 255).round());
    }
  }

  Future<void> _extractWaveformData(String audioPath) async {
    setState(() {
      _isLoadingWaveform = true;
    });

    try {
      final waveformData = await WaveformExtractor.extractWaveformData(
        audioPath,
      );

      setState(() {
        _waveformData = waveformData;
        _isLoadingWaveform = false;
      });
    } catch (e) {
      print('Error extracting waveform in App: $e');
      setState(() {
        _isLoadingWaveform = false;
        _waveformData = []; // Set empty data on error
      });
    }
  }

  Future<void> showChangeSourceDialog() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final newFilePath = result.files.single.path!;

      setState(() {
        selectedFilePath = newFilePath;
        _isLoadingWaveform = false;
      });

      print('Selected new file: ${newFilePath.split('/').last}');

      // Extract metadata first
      await _extractAudioMetadata(newFilePath);

      // Then extract waveform data
      await _extractWaveformData(newFilePath);

      // Load the new audio file into the handler
      if (widget.audioHandler is ArcampAudioHandler) {
        await (widget.audioHandler as ArcampAudioHandler).loadNewAudio(
          newFilePath,
          audioMetadata!,
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
          setState(() {
            _currentPosition = playbackState.position;
          });
        }
      }
    });
  }

  Future<void> _extractAudioMetadata(String filePath) async {
    final metadata = await AudioMetadataExtractor.extractMetadata(filePath);

    // Always set the metadata, regardless of whether album art exists
    setState(() {
      audioMetadata = metadata;
    });

    // Handle album art and color extraction separately
    if (metadata?.albumArt != null) {
      _palette = await AudioMetadataExtractor.extractColorPalette(
        metadata!.albumArt!,
      );

      final newColor =
          _palette?.darkMutedColor?.color ??
          _palette?.dominantColor?.color ??
          Colors.black;

      if (newColor != _dominantColor) {
        setState(() {
          _previousDominantColor = _dominantColor;
          _dominantColor = newColor;
          _accentColor = AudioMetadataExtractor.getComplementaryColor(
            _dominantColor,
          );
        });
      }
    } else {
      // Reset to default colors when no album art is present
      setState(() {
        _previousDominantColor = _dominantColor;
        _dominantColor = Colors.black;
        _accentColor = AudioMetadataExtractor.getComplementaryColor(
          _dominantColor,
        );
      });
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
        primarySwatch: Colors.deepPurple,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.grey[900],
      ),
      home: Scaffold(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        body: Stack(
          children: [
            selectedFilePath == null
                ? _buildWelcomeScreen()
                : _buildNowPlayingScreen(isDark),

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

        SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.only(
              left: 20.0,
              right: 20.0,
              top: MediaQuery.of(context).padding.top + 80,
              bottom: 20.0,
            ),
            child: Column(
              children: [
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
                            key: ValueKey(audioMetadata!.albumArt),
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
                            color: isDark
                                ? Colors.grey[400]
                                : Colors.grey[600], // Theme-aware icon color
                          ),
                  ),
                ),
                const SizedBox(height: 30),

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
                    print([title, artist, album]);

                    return Column(
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _getTextColor(
                              isDark,
                            ), // Changed from Colors.white
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
                            color: _getTextColor(
                              isDark,
                              opacity: 0.7,
                            ), // Changed from Colors.white70
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          album,
                          style: TextStyle(
                            fontSize: 16,
                            color: _getTextColor(
                              isDark,
                              opacity: 0.54,
                            ), // Changed from Colors.white54
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 30),
                SeekBarWidget(
                  isDark: isDark,
                  audioHandler: widget.audioHandler,
                  waveformData: _waveformData,
                  accentColor: _accentColor,
                  currentPosition: _currentPosition,
                  isLoadingWaveform: _isLoadingWaveform,
                  onSeek: (newPosition) {
                    widget.audioHandler.seek(newPosition);
                    setState(() {
                      _currentPosition = newPosition;
                    });
                  },
                  formatDuration: _formatDuration,
                  getTextColor: _getTextColor,
                ),
                const SizedBox(height: 30),
                AudioInfoRow(
                  filePath: audioMetadata!.filePath!,
                  getTextColor: _getTextColor,
                  formatCodecName: AudioMetadataExtractor.formatCodecName,
                ),
                const SizedBox(height: 30),
                AudioControlButtons(
                  widget: widget,
                  accentColor: _accentColor,
                  dominantColor: _dominantColor,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
