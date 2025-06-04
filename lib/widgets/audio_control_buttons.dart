import 'package:arcamp/screens/now_playing_screen.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';

class AudioControlButtons extends StatelessWidget {
  const AudioControlButtons({
    super.key,
    required this.widget,
    required Color accentColor,
    required Color dominantColor,
  }) : _accentColor = accentColor,
       _dominantColor = dominantColor;

  final App widget;
  final Color _accentColor;
  final Color _dominantColor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<PlaybackState>(
      stream: widget.audioHandler.playbackState,
      builder: (context, snapshot) {
        final isPlaying = snapshot.data?.playing ?? false;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: () {
                widget.audioHandler.skipToPrevious();
              },
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
              onPressed: () {
                widget.audioHandler.skipToNext();
              },
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
