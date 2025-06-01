// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:arcamp/services/arcamp_audio_handler.dart';
import 'package:arcamp/widgets/audio_control_buttons.dart';
import 'package:arcamp/widgets/audio_info_row.dart';
import 'package:arcamp/widgets/seek_bar.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'dart:io';
import 'dart:math' as math;
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

  // Add waveform-related variables
  List<double> _waveformData = [];
  bool _isLoadingWaveform = false;
  final Map<String, List<double>> _waveformCache = {};

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

  Color getComplementaryColor(Color color) {
    HSLColor hsl = HSLColor.fromColor(color);
    if (hsl.lightness < 0.5) {
      return hsl.withLightness((hsl.lightness + 0.6).clamp(0.0, 1.0)).toColor();
    } else {
      return hsl.withLightness((hsl.lightness - 0.6).clamp(0.0, 1.0)).toColor();
    }
  }

  Future<String?> _convertFlacToWav(String flacPath) async {
    final wavPath = '${flacPath}_temp.wav';
    final session = await FFmpegKit.execute(
      '-y -i "$flacPath" -ac 1 -ar 44100 -f wav "$wavPath"',
    );
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      return wavPath;
    }
    return null;
  }

  Future<List<double>> _extractWithAudioWaveforms(String audioPath) async {
    PlayerController? controller;

    try {
      controller = PlayerController();
      await controller.preparePlayer(path: audioPath);

      final waveformData = await controller.extractWaveformData(
        path: audioPath,
        noOfSamples: 300,
      );

      return waveformData;
    } catch (e) {
      print('Error in _extractWithAudioWaveforms: $e');
      return [];
    } finally {
      // Ensure controller is always disposed
      controller?.dispose();
    }
  }

  // Check if all values in the array are the same (indicating failed extraction)
  bool _isAllSameValue(List<double> data) {
    if (data.isEmpty) return true;
    final firstValue = data.first;
    return data.every((value) => (value - firstValue).abs() < 0.001);
  }

  // Generate waveform based on file characteristics
  Future<List<double>> _generateFileBasedWaveform(String audioPath) async {
    final file = File(audioPath);
    final fileSize = await file.length();
    final fileName = audioPath.split('/').last;

    // Use file size and name to generate a unique seed
    final seed = fileName.hashCode + fileSize.hashCode;
    final random = math.Random(seed);

    print(
      'Generating file-based waveform with seed: $seed for file: $fileName',
    );

    return List.generate(300, (index) {
      // Create different patterns based on file characteristics
      double base = math.sin(index * 0.08 + seed * 0.001) * 0.4;
      double secondary = math.cos(index * 0.15 + seed * 0.002) * 0.3;
      double noise = (random.nextDouble() - 0.5) * 0.6;

      // Create envelope based on file size
      double envelope = math.exp(
        -math.pow(index - 100, 2) / (2000 + (fileSize % 1000)),
      );

      // Combine all components
      double value = (base + secondary + noise * envelope).abs();

      // Add some file-specific variation
      if (index % (seed % 20 + 5) == 0) {
        value *= 1.5; // Create peaks at file-specific intervals
      }

      return value.clamp(0.05, 1.0);
    });
  }

  // Normalize waveform data to 0-1 range
  List<double> _normalizeWaveformData(List<double> data) {
    if (data.isEmpty) return [];

    final maxValue = data.reduce((a, b) => math.max(a.abs(), b.abs()));
    if (maxValue == 0) return data;

    return data
        .map((value) => (value.abs() / maxValue).clamp(0.0, 1.0))
        .toList();
  }

  Future<List<double>> _extractWaveformData(String audioPath) async {
    // Create a unique cache key using file path and modification time
    final file = File(audioPath);
    final fileStats = await file.stat();

    // Store the original path for cache key (before any conversion)
    final originalPath = audioPath;
    String actualAudioPath = audioPath;

    // Handle FLAC conversion
    if (audioPath.toLowerCase().endsWith('.flac')) {
      final wavPath = await _convertFlacToWav(audioPath);
      if (wavPath != null) {
        actualAudioPath = wavPath; // Use WAV path for processing
        print('Converted FLAC to WAV: $wavPath');
      } else {
        print('Failed to convert FLAC to WAV');
      }
    }

    // Use original file path for cache key to ensure consistency
    final cacheKey =
        '${originalPath}_${fileStats.modified.millisecondsSinceEpoch}';

    // Check cache first
    if (_waveformCache.containsKey(cacheKey)) {
      print('Using cached waveform for: ${originalPath.split('/').last}');
      final cachedData = _waveformCache[cacheKey]!;

      // Update UI state with cached data
      setState(() {
        _waveformData = cachedData;
        _isLoadingWaveform = false;
      });

      return cachedData;
    }

    setState(() {
      _isLoadingWaveform = true;
    });

    print('Extracting waveform for: ${originalPath.split('/').last}');

    try {
      // Method 1: Try using audio_waveforms package
      final waveformData = await _extractWithAudioWaveforms(actualAudioPath);

      if (waveformData.isNotEmpty && !_isAllSameValue(waveformData)) {
        final normalizedData = _normalizeWaveformData(waveformData);
        _waveformCache[cacheKey] = normalizedData;

        setState(() {
          _waveformData = normalizedData;
          _isLoadingWaveform = false;
        });

        print(
          'Successfully extracted ${normalizedData.length} waveform samples',
        );

        // Clean up temporary WAV file if it was created
        if (actualAudioPath != originalPath) {
          _cleanupTempFile(actualAudioPath);
        }

        return normalizedData;
      }

      // Method 2: Fallback to file-based analysis
      print('Falling back to file-based waveform generation');
      final fallbackData = await _generateFileBasedWaveform(
        originalPath,
      ); // Use original path for consistency
      _waveformCache[cacheKey] = fallbackData;

      setState(() {
        _waveformData = fallbackData;
        _isLoadingWaveform = false;
      });

      // Clean up temporary WAV file if it was created
      if (actualAudioPath != originalPath) {
        _cleanupTempFile(actualAudioPath);
      }

      return fallbackData;
    } catch (e) {
      print('Error extracting waveform: $e');
      setState(() {
        _isLoadingWaveform = false;
      });

      // Generate file-specific fallback waveform
      final fallbackData = await _generateFileBasedWaveform(
        originalPath,
      ); // Use original path for consistency
      _waveformCache[cacheKey] = fallbackData;
      setState(() {
        _waveformData = fallbackData;
      });

      // Clean up temporary WAV file if it was created
      if (actualAudioPath != originalPath) {
        _cleanupTempFile(actualAudioPath);
      }

      return fallbackData;
    }
  }

  void _cleanupTempFile(String tempFilePath) {
    try {
      final tempFile = File(tempFilePath);
      if (tempFile.existsSync()) {
        tempFile.deleteSync();
        print('Cleaned up temporary file: ${tempFilePath.split('/').last}');
      }
    } catch (e) {
      print('Warning: Could not delete temporary file $tempFilePath: $e');
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
        // Don't clear waveform data here - let the extraction method handle it
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

  bool _isMetadataIncomplete(Metadata? metadata) {
    if (metadata == null) return true;

    return (metadata.trackName == null || metadata.trackName!.isEmpty) ||
        (metadata.trackArtistNames == null ||
            metadata.trackArtistNames!.isEmpty) ||
        (metadata.albumName == null || metadata.albumName!.isEmpty);
  }

  // Extract metadata using FFprobe as fallback
  Future<Metadata?> _extractMetadataWithFFprobe(String filePath) async {
    try {
      print('Extracting FLAC metadata with FFprobe...');

      // Add -v quiet to suppress verbose output
      final session = await FFprobeKit.execute(
        '-v quiet -print_format json -show_format -show_streams "$filePath"',
      );

      final output = await session.getOutput();
      if (output == null || output.isEmpty) {
        print('No FFprobe output received');
        return null;
      }

      // Parse JSON output
      final Map<String, dynamic> jsonData = json.decode(output);
      final format = jsonData['format'] as Map<String, dynamic>?;
      final tags = format?['tags'] as Map<String, dynamic>?;

      if (tags == null) {
        print('No tags found in FFprobe output');
        return null;
      }

      // ... rest of your existing code remains the same
      // Extract metadata from tags
      String? trackName = _getTagValue(tags, ['TITLE', 'title']);
      String? artist = _getTagValue(tags, [
        'ARTIST',
        'artist',
        'ALBUMARTIST',
        'album_artist',
      ]);
      String? album = _getTagValue(tags, ['ALBUM', 'album']);
      String? albumArtist = _getTagValue(tags, [
        'ALBUMARTIST',
        'album_artist',
        'ARTIST',
        'artist',
      ]);
      String? year = _getTagValue(tags, ['DATE', 'date', 'YEAR', 'year']);
      String? genre = _getTagValue(tags, ['GENRE', 'genre']);
      String? trackNumberStr = _getTagValue(tags, [
        'TRACK',
        'track',
        'TRACKNUMBER',
        'tracknumber',
      ]);
      String? discNumberStr = _getTagValue(tags, [
        'DISC',
        'disc',
        'DISCNUMBER',
        'discnumber',
      ]);

      // Parse numbers
      int? trackNumber;
      int? discNumber;
      int? yearInt;

      if (trackNumberStr != null) {
        final trackParts = trackNumberStr.split('/');
        trackNumber = int.tryParse(trackParts[0]);
      }

      if (discNumberStr != null) {
        final discParts = discNumberStr.split('/');
        discNumber = int.tryParse(discParts[0]);
      }

      if (year != null) {
        yearInt = int.tryParse(year);
      }

      // Get duration from format
      Duration? trackDuration;
      final durationStr = format?['duration'] as String?;
      if (durationStr != null) {
        final durationSeconds = double.tryParse(durationStr);
        if (durationSeconds != null) {
          trackDuration = Duration(
            milliseconds: (durationSeconds * 1000).round(),
          );
        }
      }

      print('FFprobe extracted metadata:');
      print('Title: $trackName');
      print('Artist: $artist');
      print('Album: $album');
      print('Year: $year');
      print('Genre: $genre');

      return Metadata(
        trackName: trackName,
        trackArtistNames: artist != null ? [artist] : null,
        albumName: album,
        albumArtistName: albumArtist,
        trackNumber: trackNumber,
        year: yearInt,
        genre: genre,
        discNumber: discNumber,
        trackDuration: trackDuration?.inSeconds,
        filePath: filePath,
      );
    } catch (e) {
      print('Error extracting metadata with FFprobe: $e');
      return null;
    }
  }

  // Helper to get tag value with case-insensitive fallbacks
  String? _getTagValue(Map<String, dynamic> tags, List<String> keys) {
    for (final key in keys) {
      // Try exact match first
      if (tags.containsKey(key) && tags[key] != null) {
        return tags[key].toString().trim();
      }

      // Try case-insensitive match
      for (final tagKey in tags.keys) {
        if (tagKey.toLowerCase() == key.toLowerCase() && tags[tagKey] != null) {
          return tags[tagKey].toString().trim();
        }
      }
    }
    return null;
  }

  Future<void> _extractAudioMetadata(String filePath) async {
    try {
      // First, try the existing flutter_media_metadata approach
      final metadata = await MetadataRetriever.fromFile(File(filePath));

      // For FLAC files, also try FFprobe as a fallback
      final fileExtension = filePath.toLowerCase().split('.').last;
      Metadata? enhancedMetadata;

      if (fileExtension == 'flac' && _isMetadataIncomplete(metadata)) {
        print(
          'FLAC detected with incomplete metadata, trying FFprobe fallback...',
        );
        enhancedMetadata = await _extractMetadataWithFFprobe(filePath);

        // Merge the metadata, preferring FFprobe results for missing fields
        enhancedMetadata = _mergeMetadata(metadata, enhancedMetadata);
      } else {
        enhancedMetadata = metadata;
      }

      // Always set the metadata, regardless of whether album art exists
      setState(() {
        audioMetadata = enhancedMetadata;
      });

      // Handle album art and color extraction separately
      if (enhancedMetadata.albumArt != null) {
        _palette = await PaletteGenerator.fromImageProvider(
          MemoryImage(enhancedMetadata.albumArt!),
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
      } else {
        // For FLAC files without embedded album art, try extracting with FFmpeg
        if (fileExtension == 'flac') {
          print('FLAC file without album art, trying FFmpeg extraction...');
          final extractedArt = await _extractAlbumArtWithFFmpeg(filePath);
          if (extractedArt != null) {
            // Create new metadata with extracted album art
            enhancedMetadata = Metadata(
              trackName: enhancedMetadata.trackName,
              trackArtistNames: enhancedMetadata.trackArtistNames,
              albumName: enhancedMetadata.albumName,
              albumArtistName: enhancedMetadata.albumArtistName,
              trackNumber: enhancedMetadata.trackNumber,
              albumLength: enhancedMetadata.albumLength,
              year: enhancedMetadata.year,
              genre: enhancedMetadata.genre,
              authorName: enhancedMetadata.authorName,
              writerName: enhancedMetadata.writerName,
              discNumber: enhancedMetadata.discNumber,
              mimeType: enhancedMetadata.mimeType,
              trackDuration: enhancedMetadata.trackDuration,
              bitrate: enhancedMetadata.bitrate,
              albumArt: extractedArt,
              filePath: enhancedMetadata.filePath,
            );

            setState(() {
              audioMetadata = enhancedMetadata;
            });

            // Process the extracted album art for colors
            _palette = await PaletteGenerator.fromImageProvider(
              MemoryImage(extractedArt),
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
          } else {
            // Reset to default colors when no album art is present
            setState(() {
              _previousDominantColor = _dominantColor;
              _dominantColor = Colors.black;
              _accentColor = getComplementaryColor(_dominantColor);
            });
          }
        } else {
          // Reset to default colors when no album art is present
          setState(() {
            _previousDominantColor = _dominantColor;
            _dominantColor = Colors.black;
            _accentColor = getComplementaryColor(_dominantColor);
          });
        }
      }
    } catch (e) {
      print('Error extracting audio metadata: $e');
      // Even if there's an error, we should reset the metadata state
      setState(() {
        audioMetadata = null;
      });
    }
  }

  // Merge two metadata objects, preferring non-null values from the second
  Metadata _mergeMetadata(Metadata? original, Metadata? fallback) {
    if (original == null) return fallback ?? Metadata();
    if (fallback == null) return original;

    return Metadata(
      trackName: fallback.trackName ?? original.trackName,
      trackArtistNames: fallback.trackArtistNames ?? original.trackArtistNames,
      albumName: fallback.albumName ?? original.albumName,
      albumArtistName: fallback.albumArtistName ?? original.albumArtistName,
      trackNumber: fallback.trackNumber ?? original.trackNumber,
      albumLength: fallback.albumLength ?? original.albumLength,
      year: fallback.year ?? original.year,
      genre: fallback.genre ?? original.genre,
      authorName: fallback.authorName ?? original.authorName,
      writerName: fallback.writerName ?? original.writerName,
      discNumber: fallback.discNumber ?? original.discNumber,
      mimeType: fallback.mimeType ?? original.mimeType,
      trackDuration: fallback.trackDuration ?? original.trackDuration,
      bitrate: fallback.bitrate ?? original.bitrate,
      albumArt:
          original.albumArt ?? fallback.albumArt, // Prefer original album art
      filePath: original.filePath ?? fallback.filePath,
    );
  }

  // Extract album art using FFmpeg
  Future<Uint8List?> _extractAlbumArtWithFFmpeg(String filePath) async {
    try {
      print('Attempting to extract album art with FFmpeg...');

      final tempDir = Directory.systemTemp;
      final tempImagePath =
          '${tempDir.path}/temp_album_art_${DateTime.now().millisecondsSinceEpoch}.jpg';

      // Add -v quiet to suppress verbose output
      final session = await FFmpegKit.execute(
        '-v quiet -i "$filePath" -an -vcodec copy "$tempImagePath"',
      );

      final returnCode = await session.getReturnCode();

      if (ReturnCode.isSuccess(returnCode)) {
        final imageFile = File(tempImagePath);
        if (await imageFile.exists()) {
          final imageBytes = await imageFile.readAsBytes();

          try {
            await imageFile.delete();
          } catch (e) {
            print('Warning: Could not delete temp file: $e');
          }

          print(
            'Successfully extracted album art (${imageBytes.length} bytes)',
          );
          return imageBytes;
        }
      } else {
        print(
          'FFmpeg album art extraction failed with return code: $returnCode',
        );
      }

      try {
        final imageFile = File(tempImagePath);
        if (await imageFile.exists()) {
          await imageFile.delete();
        }
      } catch (e) {
        print('Warning: Could not delete temp file: $e');
      }

      return null;
    } catch (e) {
      print('Error extracting album art with FFmpeg: $e');
      return null;
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

  Future<String?> getCodecWithFFprobe(String filePath) async {
    try {
      // Add -v quiet to suppress verbose output
      final session = await FFprobeKit.execute(
        '-v quiet -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$filePath"',
      );
      final output = await session.getOutput();
      print('FFprobe codec output: $output');

      if (output != null &&
          output.trim().isNotEmpty &&
          output.trim() != 'N/A') {
        return output.trim();
      }
      return null;
    } catch (e) {
      print('Error getting codec: $e');
      return null;
    }
  }

  String _formatCodecName(String? codec) {
    if (codec == null) return 'Unknown';

    // Map technical codec names to user-friendly names
    final codecMap = {
      'aac': 'AAC',
      'mp3': 'MP3',
      'mp3float': 'MP3',
      'flac': 'FLAC',
      'alac': 'ALAC',
      'pcm_s16le': 'PCM',
      'pcm_s24le': 'PCM',
      'pcm_s32le': 'PCM',
      'pcm_f32le': 'PCM',
      'vorbis': 'Vorbis',
      'opus': 'Opus',
      'dts': 'DTS',
      'ac3': 'AC3',
      'eac3': 'E-AC3',
      'wmav2': 'WMA',
      'ape': 'APE',
      'wavpack': 'WavPack',
      'musepack8': 'Musepack',
      'tta': 'TTA',
    };

    final lowerCodec = codec.toLowerCase();
    return codecMap[lowerCodec] ?? codec.toUpperCase();
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
                  formatCodecName: _formatCodecName,
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
