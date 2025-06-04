import 'dart:async';
import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:arcamp/widgets/waveform_seekbar.dart';

class SelfContainedSeekBar extends StatefulWidget {
  final bool isDark;
  final AudioHandler audioHandler;
  final List<double> waveformData;
  final Color accentColor;
  final bool isLoadingWaveform;
  final String Function(Duration?) formatDuration;
  final Color Function(bool, {double opacity}) getTextColor;

  const SelfContainedSeekBar({
    super.key,
    required this.isDark,
    required this.audioHandler,
    required this.waveformData,
    required this.accentColor,
    required this.isLoadingWaveform,
    required this.formatDuration,
    required this.getTextColor,
  });

  @override
  State<SelfContainedSeekBar> createState() => _SelfContainedSeekBarState();
}

class _SelfContainedSeekBarState extends State<SelfContainedSeekBar> {
  Duration _currentPosition = Duration.zero;
  Timer? _positionTimer;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initializeStreams();
    _startPositionTimer();
  }

  @override
  void dispose() {
    _positionTimer?.cancel();
    _playbackSubscription?.cancel();
    super.dispose();
  }

  void _initializeStreams() {
    // Listen to playback state changes
    _playbackSubscription = widget.audioHandler.playbackState.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state.playing;
          _currentPosition = state.position;
        });
      }
    });
  }

  void _startPositionTimer() {
    // High frequency timer for smooth seekbar updates (60fps)
    _positionTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (mounted && _isPlaying) {
        final playbackState = widget.audioHandler.playbackState.value;
        if (playbackState.playing) {
          setState(() {
            _currentPosition = playbackState.position;
          });
        }
      }
    });
  }

  void _onSeek(Duration newPosition) {
    widget.audioHandler.seek(newPosition);
    setState(() {
      _currentPosition = newPosition;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<MediaItem?>(
      stream: widget.audioHandler.mediaItem,
      builder: (context, mediaSnapshot) {
        final duration = mediaSnapshot.data?.duration ?? Duration.zero;
        final position = _currentPosition;
        final progress = duration.inMilliseconds > 0
            ? position.inMilliseconds / duration.inMilliseconds
            : 0.0;

        if (widget.isLoadingWaveform) {
          return Column(
            children: [
              Container(
                height: 80,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                child: Center(
                  child: CircularProgressIndicator(
                    color: widget.accentColor,
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
                      widget.formatDuration(position),
                      style: TextStyle(
                        color: widget.getTextColor(widget.isDark),
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      widget.formatDuration(duration),
                      style: TextStyle(
                        color: widget.getTextColor(widget.isDark, opacity: 0.7),
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
          waveformData: widget.waveformData,
          progress: progress.clamp(0.0, 1.0),
          accentColor: widget.accentColor,
          currentPosition: position,
          totalDuration: duration,
          onSeek: (value) {
            final newPosition = Duration(
              milliseconds: (value * duration.inMilliseconds).round(),
            );
            _onSeek(newPosition);
          },
        );
      },
    );
  }
}
