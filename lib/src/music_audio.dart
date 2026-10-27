import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'design.dart';

/// Local preview only. No audio bytes, file paths or cloud credentials are
/// persisted to a HOTICE account; a different project gets a fresh panel.
class MusicSongPreviewPanel extends StatefulWidget {
  const MusicSongPreviewPanel({super.key});

  @override
  State<MusicSongPreviewPanel> createState() => _MusicSongPreviewPanelState();
}

class _MusicSongPreviewPanelState extends State<MusicSongPreviewPanel> {
  static const maxAudioBytes = 150 * 1024 * 1024;
  static const allowedExtensions = <String>[
    'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg',
  ];

  AudioPlayer? _player;
  String? _songName;
  int? _songBytes;
  Duration? _songLength;
  bool _picking = false;

  @override
  void dispose() {
    // Audio must not continue after leaving this project's editor.
    _player?.dispose();
    super.dispose();
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _chooseSong() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
        withData: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final path = file.path;
      final extension = file.name.split('.').last.toLowerCase();
      if (!allowedExtensions.contains(extension)) {
        _notice('Choose a supported MP3, WAV, M4A, AAC, FLAC or OGG audio file.');
        return;
      }
      if (file.size == 0 || file.size > maxAudioBytes) {
        _notice('Song must be non-empty and no larger than 150 MB.');
        return;
      }
      if (path == null || path.isEmpty) {
        _notice('This device did not provide a readable local audio file.');
        return;
      }

      final candidate = AudioPlayer();
      try {
        final duration = await candidate.setFilePath(path);
        if (!mounted) {
          await candidate.dispose();
          return;
        }
        final previous = _player;
        setState(() {
          _player = candidate;
          _songName = file.name;
          _songBytes = file.size;
          _songLength = duration;
        });
        await previous?.dispose();
        _notice('Local song loaded for listening. No cloud upload or beat analysis.');
      } catch (_) {
        await candidate.dispose();
        _notice('Unable to play this file. Try another audio format.');
      }
    } catch (_) {
      _notice('Song picker could not open on this device.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _clearSong() {
    final previous = _player;
    setState(() {
      _player = null;
      _songName = null;
      _songBytes = null;
      _songLength = null;
    });
    previous?.dispose();
  }

  static String _clock(Duration time) {
    final seconds = time.inSeconds < 0 ? 0 : time.inSeconds;
    final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
    return '$minutes:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final player = _player;
    final length = _songLength;
    return StudioPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.library_music_outlined, size: 32),
            title: const Text('Song & local audio preview'),
            subtitle: const Text(
              'Select a device audio file and listen before building your storyboard.',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _picking ? null : _chooseSong,
            icon: const Icon(Icons.audio_file_outlined),
            label: Text(_picking ? 'Opening files…' : 'Choose a song'),
          ),
          if (_songName != null && player != null) ...[
            const SizedBox(height: 12),
            Text(
              _songName!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              '${(_songBytes! / (1024 * 1024)).toStringAsFixed(1)} MB · Local session only',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Row(
              children: [
                StreamBuilder<PlayerState>(
                  stream: player.playerStateStream,
                  builder: (context, snapshot) {
                    final playing = snapshot.data?.playing ?? player.playing;
                    final finished = snapshot.data?.processingState ==
                        ProcessingState.completed;
                    return IconButton(
                      tooltip: playing && !finished ? 'Pause song' : 'Play song',
                      icon: Icon(playing && !finished
                          ? Icons.pause_circle_filled_rounded
                          : Icons.play_circle_fill_rounded),
                      iconSize: 37,
                      onPressed: () async {
                        try {
                          if (playing && !finished) {
                            await player.pause();
                          } else {
                            if (finished) await player.seek(Duration.zero);
                            // play() completes when playback stops; do not await it.
                            player.play();
                          }
                        } catch (_) {
                          _notice('Audio playback failed.');
                        }
                      },
                    );
                  },
                ),
                Expanded(
                  child: length == null || length.inMilliseconds < 1
                      ? const Text('Duration unavailable')
                      : StreamBuilder<Duration>(
                          stream: player.positionStream,
                          builder: (context, snapshot) {
                            final elapsed = snapshot.data ?? Duration.zero;
                            final maximum = length.inMilliseconds.toDouble();
                            final progress = elapsed.inMilliseconds
                                .toDouble()
                                .clamp(0.0, maximum);
                            return Column(
                              children: [
                                Slider(
                                  value: progress,
                                  min: 0,
                                  max: maximum,
                                  onChanged: (value) {
                                    player.seek(
                                      Duration(milliseconds: value.round()),
                                    );
                                  },
                                ),
                                Text(
                                  '${_clock(elapsed)} / ${_clock(length)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            );
                          },
                        ),
                ),
                IconButton(
                  tooltip: 'Remove song from preview',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: _picking ? null : _clearSong,
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          const Divider(),
          const DemoNotice(
            'Audio plays locally in this temporary project session. '
            'It is not uploaded, transcribed, beat-matched, rendered or '
            'saved to a permanent music project. Please use audio you have permission to use.',
          ),
        ],
      ),
    );
  }
}
