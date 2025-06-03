// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:flutter/material.dart';

class AudioMetadataExtractor {
  static Future<Metadata?> extractMetadata(String filePath) async {
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

      // For FLAC files without embedded album art, try extracting with FFmpeg
      if (fileExtension == 'flac' && enhancedMetadata.albumArt == null) {
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
        }
      }

      return enhancedMetadata;
    } catch (e) {
      print('Error extracting audio metadata: $e');
      return null;
    }
  }

  static bool _isMetadataIncomplete(Metadata? metadata) {
    if (metadata == null) return true;

    return (metadata.trackName == null || metadata.trackName!.isEmpty) ||
        (metadata.trackArtistNames == null ||
            metadata.trackArtistNames!.isEmpty) ||
        (metadata.albumName == null || metadata.albumName!.isEmpty);
  }

  // Extract metadata using FFprobe as fallback
  static Future<Metadata?> _extractMetadataWithFFprobe(String filePath) async {
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
  static String? _getTagValue(Map<String, dynamic> tags, List<String> keys) {
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

  // Merge two metadata objects, preferring non-null values from the second
  static Metadata _mergeMetadata(Metadata? original, Metadata? fallback) {
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
  static Future<Uint8List?> _extractAlbumArtWithFFmpeg(String filePath) async {
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

  static Future<String?> getCodecWithFFprobe(String filePath) async {
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

  static String formatCodecName(String? codec) {
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

  static Future<PaletteGenerator?> extractColorPalette(
    Uint8List albumArt,
  ) async {
    try {
      return await PaletteGenerator.fromImageProvider(MemoryImage(albumArt));
    } catch (e) {
      print('Error extracting color palette: $e');
      return null;
    }
  }

  static Color getComplementaryColor(Color color) {
    HSLColor hsl = HSLColor.fromColor(color);
    if (hsl.lightness < 0.5) {
      return hsl.withLightness((hsl.lightness + 0.6).clamp(0.0, 1.0)).toColor();
    } else {
      return hsl.withLightness((hsl.lightness - 0.6).clamp(0.0, 1.0)).toColor();
    }
  }
}
