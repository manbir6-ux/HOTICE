import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'actor_pose_gate.dart';
import 'actor_photo_quality.dart';

/// Android/iOS capture only. Images stay on-device in a dedicated *temporary*
/// directory and are never uploaded by this feature. No depth/3D model is built.
/// The capture is deliberately manual after the live quality check goes green.
class GuidedActorCameraPage extends StatefulWidget {
  const GuidedActorCameraPage({super.key, required this.actorName});
  final String actorName;

  @override
  State<GuidedActorCameraPage> createState() => _GuidedActorCameraPageState();
}

/// Paths are short-lived local reference photos, NOT a persistent identity
/// model, encrypted biometric repository, or certified liveness check.
class ActorCameraResult {
  ActorCameraResult(List<String> captured)
      : paths = List<String>.unmodifiable(captured);
  final List<String> paths;
  String get front => paths[0];
  String get left => paths[1];
  String get right => paths[2];
}

class _GuidedActorCameraPageState extends State<GuidedActorCameraPage>
    with WidgetsBindingObserver {
  static const _poses = <ScanPose>[
    ScanPose.front,
    ScanPose.left,
    ScanPose.right,
    ScanPose.leftProfile,
    ScanPose.rightProfile,
    ScanPose.chinUp,
    ScanPose.chinDown,
  ];
  static const _labels = <String>[
    'Front portrait',
    'Left 25–35°',
    'Right 25–35°',
    'Left profile 40–60°',
    'Right profile 40–60°',
    'Chin slightly up',
    'Chin slightly down',
  ];

  final _detector = FaceDetector(
    options: FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,
      enableTracking: true,
      enableLandmarks: false,
      enableContours: false,
      enableClassification: false,
    ),
  );
  CameraController? _controller;
  Future<void>? _stopOperation;
  final List<String> _captures = [];
  final Map<int, List<String>> _qualityWarnings = {};
  bool _agreed = false;
  bool _resumed = true;
  bool _initializing = false;
  bool _processing = false;
  bool _capturing = false;
  bool _disposed = false;
  bool _completed = false;
  bool _reviewing = false;
  bool _retaking = false;
  bool _swapDirections = false;
  bool _swapPitch = false;
  String? _error;
  String _instruction = 'Starting front camera...';
  bool _ready = false;
  int _streak = 0;
  DateTime _lastAnalysis = DateTime.fromMillisecondsSinceEpoch(0);
  int _step = 0;

  ScanPose get _pose => _poses[_step];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _start() async {
    if (_disposed || _initializing || !_resumed || !_agreed ||
        (!Platform.isAndroid && !Platform.isIOS)) return;
    _initializing = true;
    try {
      // Retake and app-resume must not open the same camera while its
      // previous image stream/controller is still being disposed.
      if (_stopOperation != null) await _stopOperation;
      if (_controller != null) await _stopCamera();
      if (_disposed || !_resumed || !_agreed) return;
      final cameras = await availableCameras();
      final front = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (front.isEmpty) {
        throw StateError('No front-facing camera is available.');
      }
      final camera = front.first;
      final controller = CameraController(
        camera, ResolutionPreset.high, enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await controller.initialize();
      if (_disposed || !mounted || !_resumed) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      await controller.startImageStream(_onFrame);
      if (mounted) setState(() => _error = null);
    } on CameraException catch (e) {
      if (mounted) setState(() {
        _error = e.code == 'CameraAccessDenied'
            ? 'Camera permission denied. Allow camera access in Settings.'
            : 'Camera unavailable: ${e.description ?? e.code}';
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not start front camera: $e');
    } finally {
      _initializing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_agreed || _disposed) return;
    _resumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      if (_controller == null) _start();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _stopCamera();
    }
  }

  Future<void> _stopCamera() async {
    final stopping = _stopOperation;
    if (stopping != null) {
      await stopping;
      return;
    }
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    final operation = _disposeCameraController(controller);
    _stopOperation = operation;
    try {
      await operation;
    } finally {
      _stopOperation = null;
      if (mounted && !_disposed) setState(() => _ready = false);
    }
  }

  Future<void> _disposeCameraController(CameraController controller) async {
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Camera may already be shutting down during app lifecycle changes.
    }
    try { await controller.dispose(); } catch (_) {}
  }

  InputImage? _inputFromFrame(CameraImage frame, CameraController camera) {
    // CameraX fixed the NV21/YUV420 tagging issue in newer versions. A
    // single tightly packed plane is required. Reject other layouts rather
    // than passing corrupt image bytes to native ML Kit.
    if (frame.planes.length != 1) return null;
    final android = Platform.isAndroid;
    final ios = Platform.isIOS;
    if (!android && !ios) return null;
    if (android &&
        frame.planes.first.bytes.length < frame.width * frame.height * 3 ~/ 2) {
      return null;
    }
    final format = android ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    // ML Kit's Android byte-buffer rotation must account for how the phone
    // is held, plus the front-camera sensor orientation. iOS obtains
    // orientation from the native image and ignores metadata rotation.
    final deviceDegrees = switch (camera.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final sensorDegrees = camera.description.sensorOrientation;
    final imageDegrees = camera.description.lensDirection ==
            CameraLensDirection.front
        ? (sensorDegrees + deviceDegrees) % 360
        : (sensorDegrees - deviceDegrees + 360) % 360;
    final rotation = InputImageRotationValue.fromRawValue(
      ios ? 0 : imageDegrees,
    );
    if (rotation == null) return null;
    return InputImage.fromBytes(
      bytes: frame.planes.first.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: frame.planes.first.bytesPerRow,
      ),
    );
  }

  void _onFrame(CameraImage frame) {
    if (!_agreed || _reviewing || _capturing || _processing || _disposed || !mounted) return;
    final now = DateTime.now();
    if (now.difference(_lastAnalysis).inMilliseconds < 170) return;
    _lastAnalysis = now;
    final camera = _controller;
    if (camera == null || !camera.value.isInitialized) return;
    final image = _inputFromFrame(frame, camera);
    if (image == null) {
      if (_error != 'This device does not provide supported face-analysis frames.') {
        setState(() {
          _ready = false;
          _streak = 0;
          _error = 'This device does not provide supported face-analysis frames.';
        });
      }
      return;
    }
    _processing = true;
    _detector.processImage(image).then((faces) {
      if (_disposed || !mounted || _capturing || !_resumed ||
          _controller != camera) return;
      final face = faces.isEmpty ? null : faces.first;
      final portrait = camera.description.sensorOrientation == 90 ||
          camera.description.sensorOrientation == 270;
      final width = portrait ? frame.height.toDouble() : frame.width.toDouble();
      final height = portrait ? frame.width.toDouble() : frame.height.toDouble();
      final box = face?.boundingBox;
      final assessment = ActorPoseGate.evaluate(
        pose: _pose,
        faceCount: faces.length,
        yaw: ActorPoseGate.selfieYaw(face?.headEulerAngleY,
          mirroredFront: !_swapDirections),
        roll: face?.headEulerAngleZ,
        pitch: ActorPoseGate.selfiePitch(face?.headEulerAngleX,
            reversed: _swapPitch),
        faceWidthFraction: box == null ? 0 : box.width / width,
        faceHeightFraction: box == null ? 0 : box.height / height,
        horizontalCenterOffset: box == null ? 1 : box.center.dx / width - .5,
        verticalCenterOffset: box == null ? 1 : box.center.dy / height - .5,
      );
      _streak = assessment.ready ? _streak + 1 : 0;
      final stable = _streak >= 4;
      if (stable && !_ready) {
        SystemSound.play(SystemSoundType.click);
        HapticFeedback.lightImpact();
      }
      setState(() {
        _ready = stable;
        _instruction = stable ? 'Great! Ready to capture.' : assessment.instruction;
        _error = null;
      });
    }).catchError((Object _) {
      if (mounted && !_disposed) {
        setState(() {
          _ready = false;
          _instruction = 'Face detection failed. Adjust lighting or retry.';
        });
      }
    }).whenComplete(() => _processing = false);
  }

  Future<void> _capture() async {
    final camera = _controller;
    if (!_ready || _capturing || camera == null || !_agreed) return;
    setState(() { _capturing = true; _ready = false; });
    String? saved;
    String? cameraOriginal;
    try {
      if (camera.value.isStreamingImages) {
        await camera.stopImageStream();
      }
      final photo = await camera.takePicture();
      cameraOriginal = photo.path;
      final faces = await _detector.processImage(
        InputImage.fromFilePath(photo.path),
      );
      final latest = faces.isEmpty ? null : faces.first;
      final userYaw = ActorPoseGate.selfieYaw(latest?.headEulerAngleY,
          mirroredFront: !_swapDirections);
      final angleOk = ActorPoseGate.matchesAngle(
        pose: _pose,
        yaw: userYaw,
        roll: latest?.headEulerAngleZ,
        pitch: ActorPoseGate.selfiePitch(latest?.headEulerAngleX,
            reversed: _swapPitch),
      );
      if (faces.length != 1 || !angleOk) {
        throw StateError(
          'Keep one face at the required angle for the actual photo. Retry.',
        );
      }
      // These files are intentionally temporary; no server access, gallery
      // publication, or background upload. Purge/restart contract documented.
      final temp = Directory('${(await getTemporaryDirectory()).path}/hotice_actor_capture');
      await temp.create(recursive: true);
      final file = File('${temp.path}/${DateTime.now().microsecondsSinceEpoch}_${_step}.jpg');
      await File(photo.path).copy(file.path);
      saved = file.path;
      // Advisory only. A well-framed face can legitimately be captured
      // in creative low-key lighting, so quality never silently rejects
      // or beautifies the user's original photo.
      var warnings = <String>[];
      try {
        if (await file.length() <= 16 * 1024 * 1024) {
          final decoded = img.decodeImage(await file.readAsBytes());
          if (decoded != null) {
            warnings = ActorPhotoQuality.assess(decoded).warnings;
          }
        } else {
          warnings = ['Large photo — check sharpness before continuing.'];
        }
      } catch (_) {
        warnings = ['Could not assess photo quality; review this angle.'];
      }
      _qualityWarnings[_step] = warnings;
      if (_retaking) {
        final previous = _captures[_step];
        _captures[_step] = saved;
        _retaking = false;
        try { await File(previous).delete(); } catch (_) {}
        setState(() {
          _reviewing = true;
          _streak = 0;
        });
        await _stopCamera();
      } else {
        _captures.add(saved);
        if (_step == _poses.length - 1) {
          setState(() {
            _reviewing = true;
            _streak = 0;
          });
          await _stopCamera();
        } else {
          setState(() {
            _step++;
            _streak = 0;
            _instruction = _labels[_step];
          });
        }
      }
    } catch (e) {
      if (saved != null && !_captures.contains(saved)) {
        try { await File(saved).delete(); } catch (_) {}
      }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Capture unsuccessful: $e')),
      );
    } finally {
      if (cameraOriginal != null) {
        try { await File(cameraOriginal).delete(); } catch (_) {}
      }
      _capturing = false;
      if (mounted && !_completed && !_reviewing && _controller == camera) {
        try { await camera.startImageStream(_onFrame); } catch (e) {
          if (mounted) setState(() => _error = 'Unable to resume face detection: $e');
        }
      }
    }
  }

  Future<void> _retake(int index) async {
    if (_capturing || !_reviewing || index < 0 || index >= _captures.length) {
      return;
    }
    setState(() {
      _step = index;
      _retaking = true;
      _reviewing = false;
      _ready = false;
      _streak = 0;
      _instruction = ActorPoseGate.instruction(_poses[index]);
    });
    // Wait for the *previous* controller disposal before starting a retake.
    await _stopCamera();
    if (mounted && !_disposed) await _start();
  }

  void _confirmActor() {
    if (!_reviewing || _captures.length != _poses.length ||
        !_captures.every((path) => File(path).existsSync())) return;
    _completed = true;
    Navigator.pop(context, ActorCameraResult(_captures));
  }

  void _agree() {
    setState(() {
      _agreed = true;
      _instruction = _labels[_step];
    });
    _start();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    _detector.close();
    if (!_completed) {
      for (final path in _captures) {
        File(path).delete().catchError((_) => File(path));
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _controller;
    final active = camera != null && camera.value.isInitialized;
    final accent = _ready ? const Color(0xFF35DC91) : const Color(0xFFFF667D);
    return Scaffold(
      appBar: AppBar(title: Text('Scan actor: ${widget.actorName}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (!_agreed) ...[
              const Icon(Icons.privacy_tip_outlined, size: 62),
              const SizedBox(height: 15),
              Text('Your face. Your choice.',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              const Text('HOTICE will use your front camera to detect one face and guide seven photos: front, both side angles, two profiles and chin up/down. Face analysis runs on your device. Photos stay temporarily on this device; nothing is uploaded. This is not a depth or 3D face scan.'),
              const SizedBox(height: 12),
              const Text('Only scan yourself or a person who has agreed. This demo does not verify identity or reconstruct a 3D actor. You can cancel at any point.'),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: Platform.isAndroid || Platform.isIOS ? _agree : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('I agree — start camera'),
              ),
            ] else if (_reviewing) ...[
              Text('Review Actor: ${widget.actorName}',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'Check every face photo. Retake any angle before saving. '
                'Nothing is uploaded or reconstructed into 3D.',
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 13,
                children: [
                  for (var i = 0; i < _captures.length; i++)
                    SizedBox(
                      width: 136,
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              File(_captures[i]),
                              width: 128,
                              height: 160,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox(
                                width: 128, height: 160,
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(_labels[i],
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 11)),
                          if ((_qualityWarnings[i] ?? const <String>[]).isNotEmpty)
                            for (final message in _qualityWarnings[i]!)
                              Text(
                                message,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Colors.orangeAccent,
                                ),
                              ),
                          OutlinedButton(
                            onPressed: () => _retake(i),
                            child: const Text('Retake'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 17),
              FilledButton.icon(
                onPressed: _confirmActor,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Save Actor with 7 views'),
              ),
              const SizedBox(height: 8),
              const Text(
                'Temporary, unencrypted images on this device. '
                'A secure Actor vault and actual 3D reconstruction are '
                'separate future features.',
                style: TextStyle(fontSize: 12),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(child: Text('Angle ${_step + 1} of ${_poses.length}',
                      style: Theme.of(context).textTheme.titleLarge)),
                  Text('${_captures.length}/${_poses.length} saved',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 440),
                decoration: BoxDecoration(
                  color: Colors.black,
                  border: Border.all(color: accent, width: 3),
                  borderRadius: BorderRadius.circular(25),
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 3 / 4,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (active)
                        LayoutBuilder(
                          builder: (context, bounds) {
                            final nativeSize = camera.value.previewSize;
                            if (nativeSize == null) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            // Preview comes from landscape sensor coordinates.
                            // Portrait viewport uses swapped dimensions, and
                            // BoxFit.cover crops without ever stretching face.
                            return ClipRect(
                              child: FittedBox(
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                                child: SizedBox(
                                  width: nativeSize.height,
                                  height: nativeSize.width,
                                  child: CameraPreview(camera),
                                ),
                              ),
                            );
                          },
                        )
                      else const Center(child: CircularProgressIndicator()),
                      Center(
                        child: FractionallySizedBox(
                          widthFactor: .69,
                          heightFactor: .81,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(color: accent, width: 3),
                              borderRadius: BorderRadius.circular(140),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 12, left: 12, right: 12,
                        child: Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: const Color(0xCC0B1725),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(_ready ? '● GREEN · Good alignment'
                              : '● RED · Adjust your position',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Swap left/right directions'),
                subtitle: const Text(
                  'Enable if this phone guides the opposite head turn.',
                ),
                value: _swapDirections,
                onChanged: _capturing ? null : (value) {
                  setState(() {
                    _swapDirections = value;
                    _streak = 0;
                    _ready = false;
                    _instruction = ActorPoseGate.instruction(_pose);
                  });
                },
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Swap chin up/down directions'),
                subtitle: const Text(
                  'Enable if this phone guides chin movement in reverse.',
                ),
                value: _swapPitch,
                onChanged: _capturing ? null : (value) {
                  setState(() {
                    _swapPitch = value;
                    _streak = 0;
                    _ready = false;
                    _instruction = ActorPoseGate.instruction(_pose);
                  });
                },
              ),
              const SizedBox(height: 15),
              Text(ActorPoseGate.instruction(_pose),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(_instruction, textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!, textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.orangeAccent)),
                TextButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry camera'),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _ready && !_capturing ? _capture : null,
                icon: Icon(_capturing ? Icons.hourglass_top : Icons.camera),
                label: Text(_capturing ? 'Capturing...' : 'Capture this angle'),
              ),
              const SizedBox(height: 9),
              const Text('A soft click/vibration indicates stable alignment. Camera and images are never sent to an AI provider in this preview.',
                  style: TextStyle(fontSize: 12), textAlign: TextAlign.center),
            ],
          ],
        ),
      ),
    );
  }
}
