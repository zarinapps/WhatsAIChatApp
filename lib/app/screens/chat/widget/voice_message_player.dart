import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ovowpp/core/utils/my_color.dart';

class VoiceMessagePlayer extends StatefulWidget {
  final String audioPath;
  final bool isLocal;
  final Color? activeColor;
  final IconData? icon;

  const VoiceMessagePlayer({super.key, required this.audioPath, this.isLocal = false, this.activeColor, this.icon});

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer> {
  static _VoiceMessagePlayerState? currentlyPlaying;

  late final AudioPlayer _player;
  bool _isInitialized = false;
  bool _hasError = false;
  String? _loadedPath;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant VoiceMessagePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    final oldPath = oldWidget.audioPath.trim();
    final newPath = widget.audioPath.trim();

    if (oldPath != newPath) {
      _isInitialized = false;
      _hasError = false;
      _initializePlayer();
    }
  }

  Future<void> _initializePlayer() async {
    final path = widget.audioPath.trim();

    if (path.isEmpty) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
      return;
    }

    if (_isInitialized && _loadedPath == path) {
      return;
    }

    try {
      await _player.stop();
      if (widget.isLocal) {
        await _player.setFilePath(File(path).path);
      } else {
        await _player.setUrl(_normalizeNetworkAudioUrl(path));
      }

      if (!mounted) return;
      setState(() {
        _loadedPath = path;
        _isInitialized = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _hasError = true;
        });
      }
      debugPrint("Audio Player Error for '$path': $error");
    }
  }

  @override
  void dispose() {
    if (currentlyPlaying == this) {
      currentlyPlaying = null;
    }
    _player.dispose();
    super.dispose();
  }

  String _normalizeNetworkAudioUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return Uri.encodeFull(url);

    // ExoPlayer reports a generic Source error for unescaped spaces/unicode.
    return Uri.encodeFull(uri.toString());
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    String twoDigitMinutes = twoDigits(duration.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(duration.inSeconds.remainder(60));
    return '$twoDigitMinutes:$twoDigitSeconds';
  }

  Future<void> _togglePlayback(bool isPlaying, bool isCompleted) async {
    if (isPlaying) {
      await _player.pause();
      if (currentlyPlaying == this) {
        currentlyPlaying = null;
      }
      return;
    }

    if (isCompleted) {
      await _player.seek(Duration.zero);
    }

    if (currentlyPlaying != null && currentlyPlaying != this) {
      try {
        await currentlyPlaying!._player.pause();
      } catch (e) {
        // ignore errors if player is disposed
      }
    }
    currentlyPlaying = this;

    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    // if (_hasError) {
    //   return Container(
    //     padding: EdgeInsets.all(8.r),
    //     decoration: BoxDecoration(color: Colors.red.withAlpha(50), borderRadius: BorderRadius.circular(10.r)),
    //     child: const Icon(Icons.error_outline, color: Colors.red),
    //   );
    // }

    // if (!_isInitialized) {
    //   return Center(
    //     child: Container(
    //       padding: EdgeInsets.all(8.r),
    //       child: SizedBox(
    //         width: 20,
    //         height: 20,
    //         child: CircularProgressIndicator(strokeWidth: 2, color: widget.activeColor ?? MyColor.getPrimaryColor()),
    //       ),
    //     ),
    //   );
    // }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: (widget.activeColor ?? MyColor.getPrimaryColor()).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<PlayerState>(
            stream: _player.playerStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final isPlaying = state?.playing ?? false;
              final isCompleted = state?.processingState == ProcessingState.completed;

              return GestureDetector(
                onTap: () => _togglePlayback(isPlaying, isCompleted),
                child: Container(
                  padding: EdgeInsets.all(8.r),
                  decoration: BoxDecoration(
                    color: widget.activeColor ?? MyColor.getPrimaryColor(),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.white, size: 20.r),
                ),
              );
            },
          ),
          SizedBox(width: 8.w),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: _player.positionStream,
              initialData: _player.position,
              builder: (context, positionSnapshot) {
                return StreamBuilder<Duration?>(
                  stream: _player.durationStream,
                  initialData: _player.duration,
                  builder: (context, durationSnapshot) {
                    final position = positionSnapshot.data ?? Duration.zero;
                    final duration = durationSnapshot.data ?? Duration.zero;
                    final durationMs = duration.inMilliseconds;
                    final positionMs = position.inMilliseconds.clamp(0, durationMs);

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 2.h,
                            showValueIndicator: ShowValueIndicator.never,
                            thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6.r),
                            overlayShape: RoundSliderOverlayShape(overlayRadius: 12.r),
                            activeTrackColor: widget.activeColor ?? MyColor.getPrimaryColor(),
                            inactiveTrackColor: (widget.activeColor ?? MyColor.getPrimaryColor()).withValues(
                              alpha: 0.3,
                            ),
                            thumbColor: widget.activeColor ?? MyColor.getPrimaryColor(),
                          ),
                          child: Slider(
                            value: positionMs.toDouble(),
                            max: durationMs <= 0 ? 1 : durationMs.toDouble(),
                            onChanged: durationMs <= 0
                                ? null
                                : (value) {
                                    _player.seek(Duration(milliseconds: value.toInt()));
                                  },
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: 12.w),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(position),
                                style: TextStyle(fontSize: 10.sp, color: MyColor.getBodyTextColor()),
                              ),
                              Text(
                                _formatDuration(duration),
                                style: TextStyle(fontSize: 10.sp, color: MyColor.getBodyTextColor()),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          if (widget.icon != null) ...[
            SizedBox(width: 8.w),
            Icon(widget.icon, size: 20.r, color: widget.activeColor ?? MyColor.getPrimaryColor()),
          ],
        ],
      ),
    );
  }
}
