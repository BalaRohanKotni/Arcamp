// ignore_for_file: avoid_print
import 'package:arcamp/widgets/waveform_painter.dart';
import 'package:flutter/material.dart';

class WaveformSeekbar extends StatefulWidget {
  final List<double> waveformData;
  final double progress;
  final Function(double) onSeek;
  final Color accentColor;
  final Duration currentPosition;
  final Duration totalDuration;

  const WaveformSeekbar({
    super.key,
    required this.waveformData,
    required this.progress,
    required this.onSeek,
    required this.accentColor,
    required this.currentPosition,
    required this.totalDuration,
  });

  @override
  State<WaveformSeekbar> createState() => _WaveformSeekbarState();
}

class _WaveformSeekbarState extends State<WaveformSeekbar> {
  bool _isDragging = false;
  double _dragProgress = 0.0;

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final currentProgress = _isDragging ? _dragProgress : widget.progress;

    return Column(
      children: [
        Container(
          height: 80,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onPanStart: (details) {
              setState(() {
                _isDragging = true;
              });
            },
            onPanUpdate: (details) {
              final RenderBox renderBox =
                  context.findRenderObject() as RenderBox;
              final localPosition = renderBox.globalToLocal(
                details.globalPosition,
              );
              final progress = (localPosition.dx / renderBox.size.width).clamp(
                0.0,
                1.0,
              );
              setState(() {
                _dragProgress = progress;
              });
            },
            onPanEnd: (details) {
              widget.onSeek(_dragProgress);
              setState(() {
                _isDragging = false;
              });
            },
            onTapDown: (details) {
              final RenderBox renderBox =
                  context.findRenderObject() as RenderBox;
              final localPosition = renderBox.globalToLocal(
                details.globalPosition,
              );
              final progress = (localPosition.dx / renderBox.size.width).clamp(
                0.0,
                1.0,
              );
              widget.onSeek(progress);
            },
            child: CustomPaint(
              painter: WaveformPainter(
                waveformData: widget.waveformData,
                progress: currentProgress,
                accentColor: widget.accentColor,
                isDragging: _isDragging,
              ),
              size: Size.infinite,
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
                _formatDuration(widget.currentPosition),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              Text(
                _formatDuration(widget.totalDuration),
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
