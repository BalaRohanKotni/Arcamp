// ignore_for_file: avoid_print
import 'dart:async';
import 'dart:ui';
import 'package:arcamp/services/arcamp_audio_handler.dart';
import 'package:arcamp/components/waveform_seekbar.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_waveforms/audio_waveforms.dart'; // Add this import
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
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

  Color getComplementaryColor(Color color) {
    HSLColor hsl = HSLColor.fromColor(color);
    if (hsl.lightness < 0.5) {
      return hsl.withLightness((hsl.lightness + 0.6).clamp(0.0, 1.0)).toColor();
    } else {
      return hsl.withLightness((hsl.lightness - 0.6).clamp(0.0, 1.0)).toColor();
    }
  }

  // Extract waveform data from audio file
  Future<List<double>> _extractWaveformData(String audioPath) async {
    // Create a unique cache key using file path and modification time
    final file = File(audioPath);
    final fileStats = await file.stat();
    final cacheKey =
        '${audioPath}_${fileStats.modified.millisecondsSinceEpoch}';

    // Check cache first
    if (_waveformCache.containsKey(cacheKey)) {
      print('Using cached waveform for: ${audioPath.split('/').last}');
      return _waveformCache[cacheKey]!;
    }

    setState(() {
      _isLoadingWaveform = true;
    });

    print('Extracting waveform for: ${audioPath.split('/').last}');

    try {
      // Method 1: Try using audio_waveforms package
      final waveformData = await _extractWithAudioWaveforms(audioPath);

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
        return normalizedData;
      }

      // Method 2: Fallback to file-based analysis
      print('Falling back to file-based waveform generation');
      final fallbackData = await _generateFileBasedWaveform(audioPath);
      _waveformCache[cacheKey] = fallbackData;

      setState(() {
        _waveformData = fallbackData;
        _isLoadingWaveform = false;
      });

      return fallbackData;
    } catch (e) {
      print('Error extracting waveform: $e');
      setState(() {
        _isLoadingWaveform = false;
      });

      // Generate file-specific fallback waveform
      final fallbackData = await _generateFileBasedWaveform(audioPath);
      _waveformCache[cacheKey] = fallbackData;
      setState(() {
        _waveformData = fallbackData;
      });

      return fallbackData;
    }
  }

  Future<List<double>> _extractWithAudioWaveforms(String audioPath) async {
    final PlayerController controller = PlayerController();

    try {
      await controller.preparePlayer(path: audioPath);

      final waveformData = await controller.extractWaveformData(
        path: audioPath,
        noOfSamples: 200,
      );

      return waveformData;
    } finally {
      controller.dispose();
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

    return List.generate(200, (index) {
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

  Future<void> showChangeSourceDialog() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      final newFilePath = result.files.single.path!;

      setState(() {
        selectedFilePath = newFilePath;
        _waveformData = []; // Clear previous waveform data
        _isLoadingWaveform = false;
      });

      print('Selected new file: ${newFilePath.split('/').last}');
      await _extractAudioMetadata(newFilePath);
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

  Future<void> _extractAudioMetadata(String filePath) async {
    try {
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

  // Updated seekbar method with waveform
  Widget _buildSeekBar() {
    return StreamBuilder<MediaItem?>(
      stream: widget.audioHandler.mediaItem,
      builder: (context, mediaSnapshot) {
        final duration = mediaSnapshot.data?.duration ?? Duration.zero;
        final position = _currentPosition;
        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        // Show loading indicator while waveform is being extracted
        if (_isLoadingWaveform) {
          return Column(
            children: [
              Container(
                height: 80,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: CircularProgressIndicator(
                    color: _accentColor,
                    strokeWidth: 2.0,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(position),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      _formatDuration(duration),
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }

        return WaveformSeekbar(
          waveformData: _waveformData,
          progress: progress.clamp(0.0, 1.0),
          accentColor: _accentColor,
          currentPosition: position,
          totalDuration: duration,
          onSeek: (value) {
            final newPosition = Duration(
              milliseconds: (value * duration.inMilliseconds).round(),
            );
            widget.audioHandler.seek(newPosition);
            setState(() {
              _currentPosition = newPosition;
            });
          },
        );
      },
    );
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

  Future<int?> getBitDepthWithFFprobe(String filePath) async {
    try {
      // Method 1: Try bits_per_sample first

      final extension = filePath.toLowerCase().split('.').last;
      if (extension == 'm4a') {
        // Check if it's AAC (lossy) or ALAC (lossless)
        final codecSession = await FFprobeKit.execute(
          '-v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$filePath"',
        );
        final codecOutput = await codecSession.getOutput();
        print('M4A codec check: $codecOutput');

        if (codecOutput != null && codecOutput.trim().toLowerCase() == 'aac') {
          print('M4A file contains AAC (lossy) - skipping bit depth detection');
          return null;
        }
        // If it's ALAC or other lossless codec in M4A, continue with detection
        print(
          'M4A file contains lossless codec - proceeding with bit depth detection',
        );
      } else if (['mp3', 'aac', 'ogg', 'opus'].contains(extension)) {
        // These are always lossy formats
        print('Skipping bit depth detection for lossy format: $extension');
        return null;
      }

      var session = await FFprobeKit.execute(
        '-v error -select_streams a:0 -show_entries stream=bits_per_sample -of default=noprint_wrappers=1:nokey=1 "$filePath"',
      );
      var output = await session.getOutput();
      print('FFprobe bits_per_sample output: $output');

      if (output != null &&
          output.trim().isNotEmpty &&
          output.trim() != 'N/A') {
        final bitDepth = int.tryParse(output.trim());
        if (bitDepth != null && bitDepth > 0) {
          print('Found bit depth via bits_per_sample: $bitDepth');
          return bitDepth;
        }
      }

      // Method 2: Try bits_per_raw_sample
      session = await FFprobeKit.execute(
        '-v error -select_streams a:0 -show_entries stream=bits_per_raw_sample -of default=noprint_wrappers=1:nokey=1 "$filePath"',
      );
      output = await session.getOutput();
      print('FFprobe bits_per_raw_sample output: $output');

      if (output != null &&
          output.trim().isNotEmpty &&
          output.trim() != 'N/A') {
        final bitDepth = int.tryParse(output.trim());
        if (bitDepth != null && bitDepth > 0) {
          print('Found bit depth via bits_per_raw_sample: $bitDepth');
          return bitDepth;
        }
      }

      // Method 3: Parse from codec info
      session = await FFprobeKit.execute(
        '-v error -select_streams a:0 -show_entries stream=codec_name,sample_fmt -of default=noprint_wrappers=1 "$filePath"',
      );
      output = await session.getOutput();
      print('FFprobe codec info output: $output');

      if (output != null) {
        final bitDepth = _parseBitDepthFromFormat(output);
        if (bitDepth != null) {
          print('Found bit depth via codec parsing: $bitDepth');
          return bitDepth;
        }
      }

      // Method 4: Get detailed stream info and parse manually
      session = await FFprobeKit.execute(
        '-v error -show_streams -select_streams a:0 "$filePath"',
      );
      output = await session.getOutput();
      print('FFprobe detailed stream info: $output');

      if (output != null) {
        final bitDepth = _parseDetailedStreamInfo(output);
        if (bitDepth != null) {
          print('Found bit depth via detailed parsing: $bitDepth');
          return bitDepth;
        }
      }

      print('Could not determine bit depth for file: $filePath');
      return null;
    } catch (e) {
      print('Error getting bit depth: $e');
      return null;
    }
  }

  int? _parseBitDepthFromFormat(String formatInfo) {
    // Common sample format to bit depth mappings
    final formatMap = {
      's16': 16,
      's16p': 16,
      's24': 24,
      's24p': 24,
      's32': 32,
      's32p': 32,
      'fltp': 32, // 32-bit float
      'dblp': 64, // 64-bit double (rare)
      'u8': 8,
      'u8p': 8,
    };

    for (final entry in formatMap.entries) {
      if (formatInfo.toLowerCase().contains(entry.key)) {
        return entry.value;
      }
    }

    return null;
  }

  int? _parseDetailedStreamInfo(String streamInfo) {
    // Look for various bit depth indicators in the detailed stream info
    final lines = streamInfo.split('\n');

    for (final line in lines) {
      final cleanLine = line.trim().toLowerCase();

      // Look for bits_per_sample
      if (cleanLine.startsWith('bits_per_sample=')) {
        final value = cleanLine.split('=')[1];
        final bitDepth = int.tryParse(value);
        if (bitDepth != null && bitDepth > 0) return bitDepth;
      }

      // Look for bits_per_raw_sample
      if (cleanLine.startsWith('bits_per_raw_sample=')) {
        final value = cleanLine.split('=')[1];
        final bitDepth = int.tryParse(value);
        if (bitDepth != null && bitDepth > 0) return bitDepth;
      }

      // Look for sample_fmt and parse it
      if (cleanLine.startsWith('sample_fmt=')) {
        final format = cleanLine.split('=')[1];
        final bitDepth = _parseBitDepthFromFormat(format);
        if (bitDepth != null) return bitDepth;
      }
    }

    return null;
  }

  Future<String?> getCodecWithFFprobe(String filePath) async {
    try {
      final session = await FFprobeKit.execute(
        '-v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$filePath"',
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

  Future<Map> getAudioTechnicalInfo(String filePath) async {
    final session = await FFmpegKit.execute('-i "$filePath"');
    final logs = await session.getAllLogs();

    int? sampleRate;
    int? bitrate;
    String? codec;

    final sampleRateRegex = RegExp(r'(\d{4,5})\s*Hz');
    final bitrateRegex = RegExp(r'Audio:.*?(\d+)\s*kb/s');
    final codecRegex = RegExp(r'Audio:\s*([^,\s]+)');

    Map<String, dynamic> def = {};

    for (final log in logs) {
      final msg = log.getMessage();
      if (sampleRate == null) {
        final match = sampleRateRegex.firstMatch(msg);
        if (match != null) {
          sampleRate = int.tryParse(match.group(1)!);
        }
      }

      if (bitrate == null) {
        final match = bitrateRegex.firstMatch(msg);
        if (match != null) {
          bitrate = int.tryParse(match.group(1)!);
        }
      }
      if (codec == null) {
        final match = codecRegex.firstMatch(msg);
        if (match != null) {
          codec = match.group(1);
        }
      }
    }
    codec ??= await getCodecWithFFprobe(filePath);
    def['samplingRate'] = (sampleRate ?? 0) / 1000;
    def['bitrate'] = bitrate ?? 0.0;
    def['bitDepth'] = await getBitDepthWithFFprobe(filePath);
    def['codec'] = codec;

    print("asdf\nasddd\nasdfffff");
    print(def);
    return def;
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
                            color: Colors.grey[400],
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

                _buildSeekBar(),
                const SizedBox(height: 30),
                _buildAudioTechnicalInfoRow(),
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

  FutureBuilder<Map<dynamic, dynamic>> _buildAudioTechnicalInfoRow() {
    return FutureBuilder(
      future: getAudioTechnicalInfo(audioMetadata!.filePath!),
      builder: (ctxt, snapshot) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (snapshot.data!['codec'] != null)
              Text(
                _formatCodecName(snapshot.data!['codec']),
                style: const TextStyle(fontSize: 14, color: Colors.white54),
              ),
            Text(
              "${snapshot.data!['bitrate']} kbps",
              style: TextStyle(fontSize: 14, color: Colors.white54),
            ),
            Text(
              "${snapshot.data!['samplingRate']} kHz",
              style: TextStyle(fontSize: 14, color: Colors.white54),
            ),

            if (snapshot.data!['bitDepth'] != null)
              Text(
                "${snapshot.data!['bitDepth']}-bit",
                style: const TextStyle(fontSize: 14, color: Colors.white54),
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
              iconSize: 32,
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
                iconSize: 40,
                padding: const EdgeInsets.all(20),
              ),
            ),
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.skip_next),
              iconSize: 32,
              color: _accentColor,
            ),
          ],
        );
      },
    );
  }
}
