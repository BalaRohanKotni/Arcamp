// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:flutter/material.dart';

int? _parseBitDepthFromSampleFormat(String? format) {
  if (format == null || format.isEmpty) return null;

  final lowerFormat = format.toLowerCase().trim();
  print('Parsing sample format: "$lowerFormat"');

  // Comprehensive sample format mapping
  final formatMap = <String, int>{
    // Standard PCM formats
    's16': 16, 's16p': 16, 's16le': 16, 's16be': 16,
    's24': 24, 's24p': 24, 's24le': 24, 's24be': 24,
    's32': 32, 's32p': 32, 's32le': 32, 's32be': 32,
    's64': 64, 's64p': 64, 's64le': 64, 's64be': 64,

    // Unsigned formats
    'u8': 8, 'u8p': 8,
    'u16': 16, 'u16p': 16, 'u16le': 16, 'u16be': 16,
    'u24': 24, 'u24p': 24, 'u24le': 24, 'u24be': 24,
    'u32': 32, 'u32p': 32, 'u32le': 32, 'u32be': 32,

    // Float formats (treated as their bit equivalents)
    'flt': 32, 'fltp': 32, 'f32le': 32, 'f32be': 32,
    'dbl': 64, 'dblp': 64, 'f64le': 64, 'f64be': 64,
  };

  // Direct lookup
  if (formatMap.containsKey(lowerFormat)) {
    return formatMap[lowerFormat];
  }

  // Pattern matching for variations
  for (final entry in formatMap.entries) {
    if (lowerFormat.contains(entry.key)) {
      return entry.value;
    }
  }

  // Extract numbers from format string as fallback
  final numberMatch = RegExp(r'(\d+)').firstMatch(lowerFormat);
  if (numberMatch != null) {
    final number = int.tryParse(numberMatch.group(1) ?? '');
    if (number != null && [8, 16, 24, 32, 64].contains(number)) {
      print('Extracted bit depth from format string: $number');
      return number;
    }
  }

  print('Could not parse bit depth from format: $format');
  return null;
}

// Enhanced detailed stream info parsing
int? _parseDetailedStreamInfo(String streamInfo) {
  final lines = streamInfo.split('\n');

  for (final line in lines) {
    final cleanLine = line.trim().toLowerCase();

    // Multiple ways to find bit depth information
    final patterns = [
      RegExp(r'bits_per_sample=(\d+)'),
      RegExp(r'bits_per_raw_sample=(\d+)'),
      RegExp(r'sample_fmt=(.+)'),
      RegExp(r'bit.?depth.?[:=]\s*(\d+)', caseSensitive: false),
      RegExp(r'(\d+).?bit', caseSensitive: false),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(cleanLine);
      if (match != null) {
        if (pattern.pattern.contains('sample_fmt')) {
          // Handle sample format
          final format = match.group(1);
          final bitDepth = _parseBitDepthFromSampleFormat(format);
          if (bitDepth != null) return bitDepth;
        } else {
          // Handle direct number extraction
          final bitDepth = int.tryParse(match.group(1) ?? '');
          if (bitDepth != null && bitDepth > 0 && bitDepth <= 64) {
            return bitDepth;
          }
        }
      }
    }
  }

  return null;
}

Future<int?> _getFlacBitDepthSpecific(String filePath) async {
  try {
    // Use ffprobe with FLAC-specific format detection
    final session = await FFprobeKit.execute(
      '-v error -f flac -show_streams -select_streams a:0 -print_format flat "$filePath"',
    );
    final output = await session.getOutput();

    if (output != null) {
      // Look for FLAC-specific bit depth indicators
      final lines = output.split('\n');
      for (final line in lines) {
        if (line.contains('bits_per_sample') ||
            line.contains('bits_per_raw_sample')) {
          final match = RegExp(r'(\d+)').firstMatch(line);
          if (match != null) {
            final bitDepth = int.tryParse(match.group(1) ?? '');
            if (bitDepth != null && bitDepth > 0) {
              return bitDepth;
            }
          }
        }
      }
    }

    // Alternative FLAC approach - use mediainfo-style output
    final session2 = await FFprobeKit.execute(
      '-v error -show_format -show_streams "$filePath" | grep -i "bit"',
    );
    final output2 = await session2.getOutput();

    if (output2 != null) {
      print('FLAC grep output: $output2');
      // Parse any bit-related information
      final bitMatch = RegExp(
        r'(\d+).?bit',
        caseSensitive: false,
      ).firstMatch(output2);
      if (bitMatch != null) {
        return int.tryParse(bitMatch.group(1) ?? '');
      }
    }

    return null;
  } catch (e) {
    print('Error in FLAC-specific bit depth detection: $e');
    return null;
  }
}

Future<int?> getBitDepthWithFFprobe(String filePath) async {
  try {
    final extension = filePath.toLowerCase().split('.').last;

    // Skip lossy formats entirely
    if (['mp3', 'aac', 'ogg', 'opus'].contains(extension)) {
      print('Skipping bit depth detection for lossy format: $extension');
      return null;
    }

    // Handle M4A container format
    if (extension == 'm4a') {
      final codecSession = await FFprobeKit.execute(
        '-v error -select_streams a:0 -show_entries stream=codec_name -of default=noprint_wrappers=1:nokey=1 "$filePath"',
      );
      final codecOutput = await codecSession.getOutput();
      print('M4A codec check: $codecOutput');

      if (codecOutput != null && codecOutput.trim().toLowerCase() == 'aac') {
        print('M4A file contains AAC (lossy) - skipping bit depth detection');
        return null;
      }
    }

    print('Attempting bit depth detection for: $extension');

    // FLAC-specific approach first
    if (extension == 'flac') {
      final bitDepth = await _getFlacBitDepthSpecific(filePath);
      if (bitDepth != null) {
        print('FLAC bit depth detected: $bitDepth');
        return bitDepth;
      }
    }

    // Method 1: JSON output with comprehensive stream info
    var session = await FFprobeKit.execute(
      '-v quiet -print_format json -show_streams -select_streams a:0 "$filePath"',
    );
    var output = await session.getOutput();

    if (output != null && output.trim().isNotEmpty) {
      try {
        final jsonData = json.decode(output);
        final streams = jsonData['streams'] as List<dynamic>?;

        if (streams != null && streams.isNotEmpty) {
          final audioStream = streams[0] as Map<String, dynamic>;

          // Check multiple possible fields for bit depth
          final possibleFields = [
            'bits_per_sample',
            'bits_per_raw_sample',
            'sample_fmt',
          ];

          for (final field in possibleFields) {
            if (audioStream.containsKey(field)) {
              final value = audioStream[field];
              print('Found $field: $value');

              if (field == 'sample_fmt') {
                final bitDepth = _parseBitDepthFromSampleFormat(
                  value?.toString(),
                );
                if (bitDepth != null) {
                  print('Parsed bit depth from sample_fmt: $bitDepth');
                  return bitDepth;
                }
              } else {
                final bitDepth = int.tryParse(value?.toString() ?? '');
                if (bitDepth != null && bitDepth > 0) {
                  print('Found bit depth via $field: $bitDepth');
                  return bitDepth;
                }
              }
            }
          }
        }
      } catch (e) {
        print('Error parsing JSON output: $e');
      }
    }

    // Method 2: Direct field extraction with error handling
    final fields = ['bits_per_sample', 'bits_per_raw_sample'];

    for (final field in fields) {
      session = await FFprobeKit.execute(
        '-v error -select_streams a:0 -show_entries stream=$field -of default=noprint_wrappers=1:nokey=1 "$filePath"',
      );
      output = await session.getOutput();

      print('FFprobe $field output: "$output"');

      if (output != null && output.trim().isNotEmpty) {
        final cleaned = output.trim();
        if (cleaned != 'N/A' && cleaned != '0') {
          final bitDepth = int.tryParse(cleaned);
          if (bitDepth != null && bitDepth > 0) {
            print('Found bit depth via $field: $bitDepth');
            return bitDepth;
          }
        }
      }
    }

    // Method 3: Sample format analysis
    session = await FFprobeKit.execute(
      '-v error -select_streams a:0 -show_entries stream=sample_fmt -of default=noprint_wrappers=1:nokey=1 "$filePath"',
    );
    output = await session.getOutput();

    if (output != null && output.trim().isNotEmpty) {
      final bitDepth = _parseBitDepthFromSampleFormat(output.trim());
      if (bitDepth != null) {
        print('Found bit depth via sample format: $bitDepth');
        return bitDepth;
      }
    }

    // Method 4: Detailed stream information parsing
    session = await FFprobeKit.execute(
      '-v error -show_streams -select_streams a:0 "$filePath"',
    );
    output = await session.getOutput();

    if (output != null) {
      final bitDepth = _parseDetailedStreamInfo(output);
      if (bitDepth != null) {
        print('Found bit depth via detailed parsing: $bitDepth');
        return bitDepth;
      }
    }

    print(
      'Could not determine bit depth for file: ${filePath.split('/').last}',
    );
    return null;
  } catch (e) {
    print('Error getting bit depth: $e');
    return null;
  }
}

Future<Map<String, dynamic>> getAudioTechnicalInfo(String filePath) async {
  try {
    final session = await FFprobeKit.execute(
      '-v quiet -print_format json -show_format -show_streams "$filePath"',
    );

    final output = await session.getOutput();
    if (output == null || output.isEmpty) {
      throw Exception('Failed to retrieve FFprobe output');
    }

    final Map<String, dynamic> jsonData = json.decode(output);
    final streams = jsonData['streams'] as List<dynamic>? ?? [];
    final format = jsonData['format'] as Map<String, dynamic>?;

    int? sampleRate;
    int? bitrate;
    String? codec;
    int? bitDepth;

    // Extract audio stream information
    for (final stream in streams) {
      final Map<String, dynamic> s = stream as Map<String, dynamic>;
      if (s['codec_type'] == 'audio') {
        sampleRate = int.tryParse(s['sample_rate']?.toString() ?? '');
        codec = s['codec_name']?.toString();

        // Try multiple fields for bit depth
        bitDepth =
            int.tryParse(s['bits_per_sample']?.toString() ?? '') ??
            int.tryParse(s['bits_per_raw_sample']?.toString() ?? '') ??
            _parseBitDepthFromSampleFormat(s['sample_fmt']?.toString());

        break;
      }
    }

    // Get bitrate from format
    bitrate = int.tryParse(format?['bit_rate']?.toString() ?? '');

    // If bit depth is still null, try the dedicated method
    if (bitDepth == null || bitDepth == 0) {
      print('Bit depth not found in stream info, trying dedicated method...');
      bitDepth = await getBitDepthWithFFprobe(filePath);
    }

    return {
      'samplingRate': (sampleRate ?? 0) / 1000,
      'bitrate': ((bitrate ?? 0) / 1000).round(),
      'bitDepth': bitDepth,
      'codec': codec ?? 'unknown',
    };
  } catch (e) {
    print('Error getting audio technical info: $e');
    // Return default values on error
    return {
      'samplingRate': 0.0,
      'bitrate': 0,
      'bitDepth': 0,
      'codec': 'unknown',
    };
  }
}

class AudioInfoRow extends StatelessWidget {
  final String filePath;
  final Color Function(bool isDark, {double opacity}) getTextColor;
  final String Function(String codec) formatCodecName;

  // Updated technical info method with better error handling
  const AudioInfoRow({
    super.key,
    required this.filePath,
    required this.getTextColor,
    required this.formatCodecName,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FutureBuilder<Map<dynamic, dynamic>>(
      future: getAudioTechnicalInfo(filePath),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            if (data['codec'] != null)
              Text(
                formatCodecName(data['codec']),
                style: TextStyle(
                  fontSize: 14,
                  color: getTextColor(isDark, opacity: 0.54),
                ),
              ),
            Text(
              "${data['bitrate']} kbps",
              style: TextStyle(
                fontSize: 14,
                color: getTextColor(isDark, opacity: 0.54),
              ),
            ),
            Text(
              "${data['samplingRate']} kHz",
              style: TextStyle(
                fontSize: 14,
                color: getTextColor(isDark, opacity: 0.54),
              ),
            ),
            if (data['bitDepth'] != null)
              Text(
                "${data['bitDepth']}-bit",
                style: TextStyle(
                  fontSize: 14,
                  color: getTextColor(isDark, opacity: 0.54),
                ),
              ),
          ],
        );
      },
    );
  }
}
