import 'package:arcamp/widgets/waveform_seekbar.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

class SeekBarWidget extends StatelessWidget {
  final bool isDark;
  final AudioHandler audioHandler;
  final List<double> waveformData;
  final Color accentColor;
  final Duration currentPosition;
  final bool isLoadingWaveform;
  final void Function(Duration) onSeek;
  final String Function(Duration) formatDuration;
  final Color Function(bool, {double opacity}) getTextColor;

  const SeekBarWidget({
    Key? key,
    required this.isDark,
    required this.audioHandler,
    required this.waveformData,
    required this.accentColor,
    required this.currentPosition,
    required this.isLoadingWaveform,
    required this.onSeek,
    required this.formatDuration,
    required this.getTextColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: audioHandler.mediaItem,
      builder: (context, mediaSnapshot) {
        final duration = mediaSnapshot.data?.duration ?? Duration.zero;
        final position = currentPosition;
        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        if (isLoadingWaveform) {
          return Column(
            children: [
              Container(
                height: 80,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: CircularProgressIndicator(
                    color: accentColor,
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
                      formatDuration(position),
                      style: TextStyle(
                        color: getTextColor(isDark),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      formatDuration(duration),
                      style: TextStyle(
                        color: getTextColor(isDark, opacity: 0.7),
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
          waveformData: waveformData,
          progress: progress.clamp(0.0, 1.0),
          accentColor: accentColor,
          currentPosition: position,
          totalDuration: duration,
          onSeek: (value) {
            final newPosition = Duration(
              milliseconds: (value * duration.inMilliseconds).round(),
            );
            onSeek(newPosition);
          },
        );
      },
    );
  }
}
