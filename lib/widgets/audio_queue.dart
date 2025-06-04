import 'package:flutter/material.dart';
import 'package:flutter_media_metadata/flutter_media_metadata.dart';
import 'package:desktop_drop/desktop_drop.dart';

class QueueItem {
  final String filePath;
  final Metadata? metadata;
  final String displayName;

  QueueItem({required this.filePath, this.metadata, required this.displayName});
}

class AnimatedEqualizer extends StatefulWidget {
  final Color color;
  final double size;
  final bool isPlaying;

  const AnimatedEqualizer({
    super.key,
    required this.color,
    this.size = 20,
    this.isPlaying = false,
  });

  @override
  State<AnimatedEqualizer> createState() => _AnimatedEqualizerState();
}

class _AnimatedEqualizerState extends State<AnimatedEqualizer>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();

    _controllers = List.generate(3, (index) {
      return AnimationController(
        duration: Duration(milliseconds: 600 + (index * 100)),
        vsync: this,
      );
    });

    _animations = _controllers.map((controller) {
      return Tween<double>(
        begin: 0.3,
        end: 1.0,
      ).animate(CurvedAnimation(parent: controller, curve: Curves.easeInOut));
    }).toList();

    // Start animations with slight delays
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 100), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size / 1.25,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _animations[index],
            builder: (context, child) {
              // Show static bars when paused, animated when playing
              final heightMultiplier = widget.isPlaying
                  ? _animations[index].value
                  : 0.5; // Static height when paused

              return Container(
                width: 2.5,
                height: (widget.size * heightMultiplier) / 1.25,
                decoration: BoxDecoration(color: widget.color),
              );
            },
          );
        }),
      ),
    );
  }
}

class AudioQueueWidget extends StatefulWidget {
  final List<QueueItem> queueItems;
  final int currentQueueIndex;
  final Function(List<String>) onFilesAdded;
  final Function(int) onQueueItemSelected;
  final Function(int) onQueueItemRemoved;
  final Color Function(bool, {double opacity}) getTextColor;
  final Metadata? audioMetadata;
  final Color accentColor;
  final bool isDark;
  final bool isPlaying;

  const AudioQueueWidget({
    super.key,
    required this.queueItems,
    required this.currentQueueIndex,
    required this.onFilesAdded,
    required this.onQueueItemSelected,
    required this.onQueueItemRemoved,
    required this.getTextColor,
    required this.audioMetadata,
    required this.accentColor,
    required this.isDark,
    this.isPlaying = false,
  });

  @override
  State<AudioQueueWidget> createState() => _AudioQueueWidgetState();
}

class _AudioQueueWidgetState extends State<AudioQueueWidget> {
  bool _isDragging = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(AudioQueueWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Auto-scroll when current queue index changes
    if (widget.currentQueueIndex != oldWidget.currentQueueIndex &&
        widget.currentQueueIndex >= 0 &&
        widget.queueItems.isNotEmpty) {
      _scrollToCurrentItem();
    }
  }

  void _scrollToCurrentItem() {
    if (widget.currentQueueIndex >= 0 &&
        widget.currentQueueIndex < widget.queueItems.length &&
        _scrollController.hasClients) {
      // Calculate the position of the current item
      // Each item is approximately 82 pixels (ListTile height + margins)
      const double itemHeight = 82.0;
      final double targetPosition = widget.currentQueueIndex * itemHeight;

      // Animate to the target position
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            targetPosition,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get 3/5th of screen height with minimum height for 3-4 songs
    // Each song item is approximately 82px (ListTile + margins)
    // Header is approximately 68px
    // So minimum for 3-4 songs = (3.5 * 82) + 68 = ~355px
    const double minHeight = 355.0;
    final double calculatedHeight = MediaQuery.of(context).size.height * 0.6;
    final double containerHeight = calculatedHeight < minHeight
        ? minHeight
        : calculatedHeight;

    return DropTarget(
      onDragDone: (detail) async {
        final filePaths = detail.files.map((file) => file.path).toList();
        widget.onFilesAdded(filePaths);
      },
      onDragEntered: (detail) {
        setState(() {
          _isDragging = true;
        });
      },
      onDragExited: (detail) {
        setState(() {
          _isDragging = false;
        });
      },
      child: Container(
        width: double.infinity,
        height: containerHeight,
        decoration: BoxDecoration(
          color: _isDragging
              ? (widget.audioMetadata?.albumArt != null
                    ? widget.accentColor.withAlpha(77)
                    : (widget.isDark
                          ? Colors.blue.withAlpha(77)
                          : Colors.blue.withAlpha(51)))
              : (widget.audioMetadata?.albumArt != null
                    ? Colors.white.withAlpha(26)
                    : (widget.isDark ? Colors.grey[800] : Colors.grey[200])),
          borderRadius: BorderRadius.circular(16),
          border: _isDragging
              ? Border.all(
                  color: widget.audioMetadata?.albumArt != null
                      ? widget.accentColor
                      : Colors.blue,
                  width: 2,
                )
              : Border.all(
                  color: widget.audioMetadata?.albumArt != null
                      ? Colors.white.withAlpha(51)
                      : (widget.isDark ? Colors.grey[600]! : Colors.grey[300]!),
                  width: 1,
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            Expanded(child: _buildQueueContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Icon(
            Icons.queue_music,
            color: widget.getTextColor(widget.isDark),
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            'Queue',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: widget.getTextColor(widget.isDark),
            ),
          ),
          const Spacer(),
          if (widget.queueItems.isNotEmpty)
            Text(
              '${widget.queueItems.length} track${widget.queueItems.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 14,
                color: widget.getTextColor(widget.isDark, opacity: 0.7),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildQueueContent() {
    if (widget.queueItems.isEmpty) {
      return _buildEmptyState();
    } else {
      return Column(
        children: [
          if (_isDragging) _buildDropZone(),
          Expanded(child: _buildScrollableQueueItems()),
        ],
      );
    }
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isDragging ? Icons.file_download : Icons.queue_music_outlined,
            size: 48,
            color: widget.getTextColor(widget.isDark, opacity: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _isDragging
                ? 'Drop your audio files here'
                : 'Drop audio files here to add to queue',
            style: TextStyle(
              fontSize: 16,
              color: widget.getTextColor(widget.isDark, opacity: 0.7),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Supported formats: MP3, WAV, FLAC, M4A, AAC, OGG',
            style: TextStyle(
              fontSize: 12,
              color: widget.getTextColor(widget.isDark, opacity: 0.5),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDropZone() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color:
            (widget.audioMetadata?.albumArt != null
                    ? widget.accentColor
                    : Colors.blue)
                .withAlpha(102),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.audioMetadata?.albumArt != null
              ? widget.accentColor
              : Colors.blue,
          width: 2,
          style: BorderStyle.solid,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.file_download, color: Colors.white, size: 24),
          const SizedBox(width: 8),
          Text(
            'Drop files to add to queue',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScrollableQueueItems() {
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: widget.queueItems.length,
        itemBuilder: (context, index) {
          final item = widget.queueItems[index];
          final isCurrentlyPlaying = index == widget.currentQueueIndex;

          return _buildQueueItemCard(item, index, isCurrentlyPlaying);
        },
      ),
    );
  }

  Widget _buildQueueItemCard(
    QueueItem item,
    int index,
    bool isCurrentlyPlaying,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isCurrentlyPlaying
            ? (widget.audioMetadata?.albumArt != null
                  ? widget.accentColor.withAlpha(51)
                  : (widget.isDark
                        ? Colors.blue.withAlpha(51)
                        : Colors.blue.withAlpha(26)))
            : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isCurrentlyPlaying
            ? Border.all(
                color: widget.audioMetadata?.albumArt != null
                    ? widget.accentColor
                    : Colors.blue,
                width: 1,
              )
            : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildAlbumArt(item),
        title: Text(
          item.metadata?.trackName ?? item.displayName,
          style: TextStyle(
            color: widget.getTextColor(widget.isDark),
            fontWeight: isCurrentlyPlaying ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          item.metadata?.trackArtistNames?.join(', ') ?? 'Unknown Artist',
          style: TextStyle(
            color: widget.getTextColor(widget.isDark, opacity: 0.7),
            fontSize: 12,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _buildTrailingActions(index, isCurrentlyPlaying),
        onTap: () => widget.onQueueItemSelected(index),
      ),
    );
  }

  Widget _buildAlbumArt(QueueItem item) {
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: widget.isDark ? Colors.grey[700] : Colors.grey[300],
        borderRadius: BorderRadius.circular(8),
      ),
      child: item.metadata?.albumArt != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(item.metadata!.albumArt!, fit: BoxFit.cover),
            )
          : Icon(
              Icons.music_note,
              color: widget.isDark ? Colors.grey[500] : Colors.grey[600],
              size: 24,
            ),
    );
  }

  Widget _buildTrailingActions(int index, bool isCurrentlyPlaying) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCurrentlyPlaying)
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: AnimatedEqualizer(
              color: widget.audioMetadata?.albumArt != null
                  ? widget.accentColor
                  : Colors.deepPurple,
              size: 20,
              isPlaying: widget.isPlaying, // Pass the playing state
            ),
          ),
        IconButton(
          icon: Icon(
            Icons.close,
            color: widget.getTextColor(widget.isDark, opacity: 0.7),
            size: 18,
          ),
          onPressed: () => widget.onQueueItemRemoved(index),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }
}
