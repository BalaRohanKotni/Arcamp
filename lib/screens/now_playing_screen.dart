// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:ui';
import 'package:arcamp/services/arcamp_audio_handler.dart';
import 'package:arcamp/services/metadata_extractor.dart';
import 'package:arcamp/services/waveform_extractor.dart';
import 'package:arcamp/widgets/audio_control_buttons.dart';
import 'package:arcamp/widgets/audio_info_row.dart';
import 'package:arcamp/widgets/audio_queue.dart';
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
  // Audio state
  String? selectedFilePath;
  Metadata? audioMetadata;
  List<double> _waveformData = [];
  bool _isLoadingWaveform = false;

  // Color state
  PaletteGenerator? _palette;
  Color _dominantColor = Colors.black;
  Color _accentColor = Colors.white;
  // ignore: unused_field
  Color _previousDominantColor = Colors.black;

  // Queue state
  // ignore: prefer_final_fields
  List<QueueItem> _queueItems = [];
  int _currentQueueIndex = -1;

  bool _isPlaying = false;
  StreamSubscription<PlaybackState>? _playbackStateSubscription;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  @override
  void dispose() {
    _playbackStateSubscription?.cancel();
    super.dispose();
  }

  // MARK: - Initialization
  void _initializeApp() {
    _listenToPlaybackState();
    _accentColor = AudioMetadataExtractor.getComplementaryColor(_dominantColor);
    if (widget.audioHandler is ArcampAudioHandler) {
      (widget.audioHandler as ArcampAudioHandler).setQueueCallbacks(
        skipToNext: _skipToNextTrack,
        skipToPrevious: _skipToPreviousTrack,
      );
    }
  }

  void _listenToPlaybackState() {
    _playbackStateSubscription = widget.audioHandler.playbackState.listen((
      state,
    ) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
        });
      }
    });
  }

  // MARK: - Color Management
  Color _getTextColor(bool isDark, {double opacity = 1.0}) {
    if (audioMetadata?.albumArt != null) {
      return Colors.white.withAlpha((opacity * 255).round());
    } else {
      return isDark
          ? Colors.white.withAlpha((opacity * 255).round())
          : Colors.black.withAlpha((opacity * 255).round());
    }
  }

  Future<void> _updateColorsFromAlbumArt(Metadata? metadata) async {
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
      setState(() {
        _previousDominantColor = _dominantColor;
        _dominantColor = Colors.black;
        _accentColor = AudioMetadataExtractor.getComplementaryColor(
          _dominantColor,
        );
      });
    }
  }

  // MARK: - Audio File Management
  Future<void> showChangeSourceDialog() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);

    if (result != null && result.files.single.path != null) {
      final newFilePath = result.files.single.path!;
      await _loadNewAudioFile(newFilePath);
    }
  }

  Future<void> _loadNewAudioFile(String filePath) async {
    setState(() {
      selectedFilePath = filePath;
      _isLoadingWaveform = false;
    });

    print('Selected new file: ${filePath.split('/').last}');

    // Extract metadata and handle colors
    await _extractAudioMetadata(filePath);

    // Extract waveform data
    await _extractWaveformData(filePath);

    // Add current song to queue if not already present
    await _addCurrentSongToQueue(filePath, audioMetadata);

    // Load the new audio file into the handler
    if (widget.audioHandler is ArcampAudioHandler) {
      await (widget.audioHandler as ArcampAudioHandler).loadNewAudio(
        filePath,
        audioMetadata!,
      );
    }
  }

  Future<void> _extractAudioMetadata(String filePath) async {
    final metadata = await AudioMetadataExtractor.extractMetadata(filePath);

    setState(() {
      audioMetadata = metadata;
    });

    await _updateColorsFromAlbumArt(metadata);
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
        _waveformData = [];
      });
    }
  }

  // MARK: - Queue Management

  Future<void> _loadQueueItem(int index) async {
    if (index < 0 || index >= _queueItems.length) return;

    final queueItem = _queueItems[index];

    setState(() {
      selectedFilePath = queueItem.filePath;
      audioMetadata = queueItem.metadata;
      _currentQueueIndex = index;
      _isLoadingWaveform = false;
    });

    // Extract metadata if not already available
    if (queueItem.metadata == null) {
      await _extractAudioMetadata(queueItem.filePath);
      // Update the queue item with the extracted metadata
      setState(() {
        _queueItems[index] = QueueItem(
          filePath: queueItem.filePath,
          metadata: audioMetadata,
          displayName: queueItem.displayName,
        );
      });
    } else {
      await _updateColorsFromAlbumArt(queueItem.metadata);
    }

    // Extract waveform data
    await _extractWaveformData(queueItem.filePath);

    // Load the new audio file into the handler (without playing)
    if (widget.audioHandler is ArcampAudioHandler) {
      await (widget.audioHandler as ArcampAudioHandler).loadNewAudio(
        queueItem.filePath,
        audioMetadata!,
      );
    }
  }

  Future<void> _addFilesToQueue(List<String> filePaths) async {
    for (String filePath in filePaths) {
      if (_isAudioFile(filePath)) {
        await _processAndAddToQueue(filePath);
      }
    }
  }

  Future<void> _processAndAddToQueue(String filePath) async {
    try {
      final metadata = await AudioMetadataExtractor.extractMetadata(filePath);
      final displayName = filePath.split('/').last;

      setState(() {
        _queueItems.add(
          QueueItem(
            filePath: filePath,
            metadata: metadata,
            displayName: displayName,
          ),
        );
      });
    } catch (e) {
      print('Error processing file $filePath: $e');
      // Add file without metadata if extraction fails
      setState(() {
        _queueItems.add(
          QueueItem(filePath: filePath, displayName: filePath.split('/').last),
        );
      });
    }
  }

  Future<void> _addCurrentSongToQueue(
    String filePath,
    Metadata? metadata,
  ) async {
    final isAlreadyInQueue = _queueItems.any(
      (item) => item.filePath == filePath,
    );

    if (!isAlreadyInQueue) {
      final displayName = filePath.split('/').last;
      setState(() {
        _queueItems.add(
          QueueItem(
            filePath: filePath,
            metadata: metadata,
            displayName: displayName,
          ),
        );
        _currentQueueIndex = _queueItems.length - 1;
      });
      print('Added current song to queue: $displayName');
    } else {
      final index = _queueItems.indexWhere((item) => item.filePath == filePath);
      setState(() {
        _currentQueueIndex = index;
      });
      print('Current song already in queue, updated index to: $index');
    }
  }

  Future<void> _playQueueItem(int index) async {
    if (index < 0 || index >= _queueItems.length) return;

    final queueItem = _queueItems[index];

    setState(() {
      selectedFilePath = queueItem.filePath;
      audioMetadata = queueItem.metadata;
      _currentQueueIndex = index;
      _isLoadingWaveform = false;
    });

    // Extract metadata if not already available
    if (queueItem.metadata == null) {
      await _extractAudioMetadata(queueItem.filePath);
      // Update the queue item with the extracted metadata
      setState(() {
        _queueItems[index] = QueueItem(
          filePath: queueItem.filePath,
          metadata: audioMetadata,
          displayName: queueItem.displayName,
        );
      });
    } else {
      await _updateColorsFromAlbumArt(queueItem.metadata);
    }

    // Extract waveform data
    await _extractWaveformData(queueItem.filePath);

    // Load the new audio file into the handler
    if (widget.audioHandler is ArcampAudioHandler) {
      await (widget.audioHandler as ArcampAudioHandler).loadNewAudio(
        queueItem.filePath,
        audioMetadata!,
      );
    }

    // Auto-play the selected song
    await widget.audioHandler.play();
  }

  void _removeFromQueue(int index) {
    setState(() {
      _queueItems.removeAt(index);
      if (_currentQueueIndex == index) {
        _currentQueueIndex = -1;
      } else if (_currentQueueIndex > index) {
        _currentQueueIndex--;
      }
    });
  }

  bool _isAudioFile(String filePath) {
    const supportedExtensions = [
      '.mp3',
      '.wav',
      '.flac',
      '.m4a',
      '.aac',
      '.ogg',
    ];
    return supportedExtensions.any(
      (ext) => filePath.toLowerCase().endsWith(ext),
    );
  }

  // MARK: - Queue Navigation Methods
  Future<void> _skipToNextTrack() async {
    if (_queueItems.isNotEmpty && _currentQueueIndex < _queueItems.length - 1) {
      final nextIndex = _currentQueueIndex + 1;
      final wasPlaying = _isPlaying;
      print('Skipping to next track: index $nextIndex');

      // Load the next track without auto-playing
      await _loadQueueItem(nextIndex);

      // Only play if the previous track was playing
      if (wasPlaying) {
        await widget.audioHandler.play();
      }
    } else {
      print('No next track available in queue');
    }
  }

  Future<void> _skipToPreviousTrack() async {
    if (_queueItems.isNotEmpty && _currentQueueIndex > 0) {
      final previousIndex = _currentQueueIndex - 1;
      final wasPlaying = _isPlaying;
      print('Skipping to previous track: index $previousIndex');

      // Load the previous track without auto-playing
      await _loadQueueItem(previousIndex);

      // Only play if the previous track was playing
      if (wasPlaying) {
        await widget.audioHandler.play();
      }
    } else {
      print('No previous track available in queue');
    }
  }

  // MARK: - Utility Methods
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

  // MARK: - UI Building Methods
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
            _buildFloatingActionButton(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingActionButton(bool isDark) {
    return Positioned(
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
            color: selectedFilePath != null ? _dominantColor : Colors.white,
          ),
          onPressed: showChangeSourceDialog,
          tooltip: 'Select Audio File',
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
    return Stack(children: [_buildBackground(isDark), _buildContent(isDark)]);
  }

  Widget _buildBackground(bool isDark) {
    if (audioMetadata?.albumArt != null) {
      return Stack(
        children: [
          SizedBox.expand(
            child: Image.memory(audioMetadata!.albumArt!, fit: BoxFit.cover),
          ),
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
            child: Container(color: _dominantColor.withAlpha(153)),
          ),
        ],
      );
    } else {
      return Container(color: isDark ? Colors.black : Colors.white);
    }
  }

  Widget _buildContent(bool isDark) {
    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20.0,
          right: 20.0,
          top: MediaQuery.of(context).padding.top + 80,
          bottom: 20.0,
        ),
        child: Column(
          children: [
            _buildAlbumArt(isDark),
            const SizedBox(height: 30),
            _buildTrackInfo(isDark),
            const SizedBox(height: 30),
            _buildOptimizedSeekBar(isDark),
            const SizedBox(height: 30),
            _buildAudioInfo(),
            const SizedBox(height: 30),
            _buildControlButtons(),
            const SizedBox(height: 40),
            _buildQueueSection(isDark),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumArt(bool isDark) {
    double albumArtSideLength = 280;
    if (MediaQuery.sizeOf(context).height / (900 / 280) < 175) {
      albumArtSideLength = 175;
    } else if (MediaQuery.sizeOf(context).height / (900 / 280) >
        MediaQuery.sizeOf(context).width) {
      albumArtSideLength = MediaQuery.sizeOf(context).width;
    } else {
      albumArtSideLength = MediaQuery.sizeOf(context).height / (900 / 280);
    }
    return Container(
      width: albumArtSideLength,
      height: albumArtSideLength,
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
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
      ),
    );
  }

  Widget _buildTrackInfo(bool isDark) {
    return StreamBuilder<MediaItem?>(
      stream: widget.audioHandler.mediaItem,
      builder: (context, snapshot) {
        final mediaItem = snapshot.data;
        final title =
            audioMetadata?.trackName ?? mediaItem?.title ?? 'Unknown Title';
        final artist =
            audioMetadata?.trackArtistNames?.join(', ') ??
            mediaItem?.artist ??
            'Unknown Artist';
        final album =
            audioMetadata?.albumName ?? mediaItem?.album ?? 'Unknown Album';

        return Column(
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _getTextColor(isDark),
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
                color: _getTextColor(isDark, opacity: 0.7),
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
                color: _getTextColor(isDark, opacity: 0.54),
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }

  Widget _buildOptimizedSeekBar(bool isDark) {
    return SelfContainedSeekBar(
      isDark: isDark,
      audioHandler: widget.audioHandler,
      waveformData: _waveformData,
      accentColor: _accentColor,
      isLoadingWaveform: _isLoadingWaveform,
      formatDuration: _formatDuration,
      getTextColor: _getTextColor,
    );
  }

  Widget _buildAudioInfo() {
    return AudioInfoRow(
      filePath: audioMetadata!.filePath!,
      getTextColor: _getTextColor,
      formatCodecName: AudioMetadataExtractor.formatCodecName,
    );
  }

  Widget _buildQueueSection(bool isDark) {
    return AudioQueueWidget(
      queueItems: _queueItems,
      currentQueueIndex: _currentQueueIndex,
      onFilesAdded: _addFilesToQueue,
      onQueueItemSelected: _playQueueItem,
      onQueueItemRemoved: _removeFromQueue,
      getTextColor: _getTextColor,
      audioMetadata: audioMetadata,
      accentColor: _accentColor,
      isDark: isDark,
      isPlaying: _isPlaying,
    );
  }

  Widget _buildControlButtons() {
    return AudioControlButtons(
      widget: widget,
      accentColor: _accentColor,
      dominantColor: _dominantColor,
    );
  }
}
