import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:path_provider/path_provider.dart';

import 'face_capture_quality.dart';

class CapturedFacePhoto {
  const CapturedFacePhoto(this.pose, this.path);
  final CapturePose pose;
  final String path;
}

/// On-device 2D guided capture. No depth mesh, biometric ID, or cloud uploads.
class LiveFaceScanPage extends StatefulWidget {
  const LiveFaceScanPage({super.key});

  @override
  State<LiveFaceScanPage> createState() => _LiveFaceScanPageState();
}

class _LiveFaceScanPageState extends State<LiveFaceScanPage>
    with WidgetsBindingObserver {
  final _detector = FaceDetector(options: FaceDetectorOptions(
    enableClassification: true,
    enableLandmarks: true,
    enableTracking: true,
    performanceMode: FaceDetectorMode.accurate,
  ));
  final _stability = CaptureStability();
  final _shots = <CapturedFacePhoto>[];
  CameraController? _camera;
  CameraDescription? _description;
  String? _directory;
  String? _error;
  String _instruction = 'Preparing face detection';
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);
  int _index = 0;
  bool _consent = false;
  bool _starting = false;
  bool _processing = false;
  bool _taking = false;
  bool _disposed = false;
  bool _transferred = false;
  bool _invertYaw = false;

  static const _orientation = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed || !_consent) return;
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _pauseCamera();
    } else if (state == AppLifecycleState.resumed) {
      _startCamera();
    }
  }

  Future<void> _pauseCamera() async {
    final current = _camera;
    _camera = null;
    _stability.reset();
    if (mounted) setState(() => _instruction = 'Camera paused');
    try { await current?.dispose(); } catch (_) {}
  }

  Future<void> _startCamera() async {
    if (_starting || !_consent || _disposed || _camera != null ||
        _index >= CapturePose.values.length) return;
    _starting = true;
    CameraController? current;
    try {
      if (!Platform.isAndroid && !Platform.isIOS) {
        throw StateError('Capture requires Android or iOS');
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera detected');
      final description = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      current = CameraController(description, ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888,
      );
      await current.initialize();
      if (_disposed || !mounted || !_consent) {
        await current.dispose();
        return;
      }
      _description = description;
      _camera = current;
      await current.startImageStream(_onFrame);
      if (mounted) setState(() {
        _error = null;
        _instruction = CapturePose.values[_index].instruction;
      });
    } on CameraException catch (e) {
      if (identical(_camera, current)) _camera = null;
      try { await current?.dispose(); } catch (_) {}
      if (mounted) setState(() => _error = e.code == 'CameraAccessDenied'
          ? 'Camera permission denied. Enable it in system settings.'
          : 'Camera error: ' + (e.description ?? e.code));
    } catch (e) {
      if (identical(_camera, current)) _camera = null;
      try { await current?.dispose(); } catch (_) {}
      if (mounted) setState(() => _error = 'Could not start camera: ' + e.toString());
    } finally {
      _starting = false;
    }
  }

  InputImage? _convert(CameraImage frame, CameraController controller) {
    final sensor = _description;
    if (sensor == null || frame.planes.length != 1) return null;
    final format = InputImageFormatValue.fromRawValue(frame.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) return null;
    final degrees = Platform.isIOS
        ? sensor.sensorOrientation
        : _orientation[controller.value.deviceOrientation];
    if (degrees == null) return null;
    final adjusted = Platform.isIOS ? degrees
        : sensor.lensDirection == CameraLensDirection.front
            ? (sensor.sensorOrientation + degrees) % 360
            : (sensor.sensorOrientation - degrees + 360) % 360;
    final rotation = InputImageRotationValue.fromRawValue(adjusted);
    if (rotation == null) return null;
    final plane = frame.planes.single;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(frame.width.toDouble(), frame.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // Sample luma conservatively. This is a heuristic, not a calibrated blur test.
  ({double brightness, double detail})? _quality(CameraImage frame) {
    if (!Platform.isAndroid || frame.planes.isEmpty) return null;
    final data = frame.planes.first.bytes;
    final stride = frame.planes.first.bytesPerRow;
    if (stride <= 0 || frame.width < 32 || frame.height < 32) return null;
    double total = 0, delta = 0;
    var count = 0;
    for (var y = frame.height ~/ 4; y < frame.height * 3 ~/ 4; y += 8) {
      for (var x = frame.width ~/ 4; x < frame.width * 3 ~/ 4; x += 8) {
        final i = stride * y + x;
        if (i + 2 >= data.length) continue;
        total += data[i];
        delta += (data[i] - data[i + 2]).abs();
        count++;
      }
    }
    if (count == 0) return null;
    return (brightness: total / count, detail: delta / count);
  }

  void _onFrame(CameraImage frame) {
    if (_disposed || _processing || _taking || _camera == null ||
        _index >= CapturePose.values.length) return;
    final now = DateTime.now();
    if (now.difference(_lastFrame).inMilliseconds < 250) return;
    _lastFrame = now;
    _processing = true;
    _detect(frame);
  }

  Future<void> _detect(CameraImage frame) async {
    try {
      final current = _camera;
      if (current == null) return;
      final input = _convert(frame, current);
      if (input == null) {
        if (mounted && _error == null) setState(() =>
          _error = 'Camera stream format unsupported by ML Kit on this device.');
        return;
      }
      final faces = await _detector.processImage(input);
      if (!mounted || _disposed || _taking) return;
      FaceObservation? observation;
      if (faces.isNotEmpty) {
        final found = faces.first;
        final rotated = input.metadata?.rotation == InputImageRotation.rotation90deg ||
            input.metadata?.rotation == InputImageRotation.rotation270deg;
        final w = rotated ? frame.height.toDouble() : frame.width.toDouble();
        final h = rotated ? frame.width.toDouble() : frame.height.toDouble();
        final bounds = found.boundingBox;
        final quality = _quality(frame);
        observation = FaceObservation(
          faces: faces.length,
          centerX: bounds.center.dx / w,
          centerY: bounds.center.dy / h,
          faceWidthFraction: bounds.width / w,
          faceHeightFraction: bounds.height / h,
          yaw: found.headEulerAngleY,
          pitch: found.headEulerAngleX,
          roll: found.headEulerAngleZ,
          leftEyeOpen: found.leftEyeOpenProbability,
          rightEyeOpen: found.rightEyeOpenProbability,
          lumaMean: quality?.brightness,
          detailScore: quality?.detail,
        );
      }
      final assessment = CaptureQualityGate.check(
        CapturePose.values[_index], observation, invertYaw: _invertYaw,
      );
      final ready = _stability.observe(assessment);
      if (mounted && _instruction != assessment.message) {
        setState(() => _instruction = assessment.message);
      }
      if (ready && !_taking) _takePhoto();
    } catch (_) {
      _stability.reset();
      if (mounted && !_taking) setState(() =>
          _instruction = 'Tracking interrupted; adjust your position');
    } finally {
      _processing = false;
    }
  }

  Future<void> _takePhoto() async {
    final controller = _camera;
    if (_taking || controller == null) return;
    _taking = true;
    _stability.reset();
    final pose = CapturePose.values[_index];
    if (mounted) setState(() => _instruction = 'Capturing ' + pose.label);
    try {
      if (controller.value.isStreamingImages) await controller.stopImageStream();
      final capture = await controller.takePicture();
      final verified = await _detector.processImage(
          InputImage.fromFilePath(capture.path));
      if (verified.length != 1) throw StateError('Exactly one face required in photo');
      if (pose == CapturePose.front) {
        final face = verified.single;
        if (face.leftEyeOpenProbability == null ||
            face.rightEyeOpenProbability == null ||
            face.leftEyeOpenProbability! < .70 ||
            face.rightEyeOpenProbability! < .70) {
          throw StateError('Both eyes must be open in the front photo');
        }
      }
      if (_directory == null) {
        final tmp = await getTemporaryDirectory();
        final dir = Directory(tmp.path + '/hotice-scans-' +
            DateTime.now().microsecondsSinceEpoch.toString());
        await dir.create(recursive: true);
        _directory = dir.path;
      }
      final target = File(_directory! + '/' + pose.name + '.jpg');
      await File(capture.path).copy(target.path);
      try { await File(capture.path).delete(); } catch (_) {}
      if (_disposed || !mounted) {
        try { await target.delete(); } catch (_) {}
        return;
      }
      _shots.add(CapturedFacePhoto(pose, target.path));
      _index++;
      setState(() => _instruction = _index == CapturePose.values.length
          ? 'All five 2D photos captured. Review before saving.'
          : CapturePose.values[_index].instruction);
    } catch (e) {
      if (mounted && !_disposed) setState(() =>
          _instruction = 'Retake: ' + e.toString());
    } finally {
      _taking = false;
      if (!_disposed && mounted && identical(_camera, controller) &&
          _index < CapturePose.values.length &&
          controller.value.isInitialized &&
          !controller.value.isStreamingImages) {
        try {
          await controller.startImageStream(_onFrame);
        } catch (_) {
          if (mounted) setState(() =>
              _error = 'Camera stream stopped. Retry the camera.');
        }
      }
    }
  }

  Future<void> _retake() async {
    if (_taking || _shots.isEmpty) return;
    final last = _shots.removeLast();
    try { await File(last.path).delete(); } catch (_) {}
    _index--;
    _stability.reset();
    if (mounted) setState(() =>
        _instruction = CapturePose.values[_index].instruction);
    if (_camera == null) {
      await _startCamera();
    } else if (!_camera!.value.isStreamingImages) {
      await _camera!.startImageStream(_onFrame);
    }
  }

  void _finish() {
    if (_shots.length != CapturePose.values.length) return;
    _transferred = true;
    Navigator.of(context).pop(List<CapturedFacePhoto>.unmodifiable(_shots));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    _detector.close();
    if (!_transferred) {
      for (final photo in _shots) {
        File(photo.path).delete().catchError((Object _) => File(photo.path));
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final done = _index >= CapturePose.values.length;
    final controller = _camera;
    return Scaffold(
      backgroundColor: const Color(0xFF10141E),
      appBar: AppBar(
        backgroundColor: const Color(0xFF10141E),
        title: const Text('Guided face capture'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (!_consent) ...[
              const Icon(Icons.privacy_tip_outlined,
                  color: Color(0xFF94D8BC), size: 54),
              const SizedBox(height: 16),
              Text('On-device face capture',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 10),
              const Text(
                'HOTICE uses the selfie camera and on-device face detection '
                'to guide you through five angles and check that your eyes '
                'are open in the front portrait. The images remain in an '
                'unencrypted temporary app cache for this demo session. '
                'No photos or biometric data are uploaded. '
                'This is NOT 3D reconstruction, identity proof or liveness verification.',
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: () {
                  setState(() => _consent = true);
                  _startCamera();
                },
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('I agree — start camera'),
              ),
            ] else ...[
              Text(done ? 'Review five face views'
                  : 'Angle ' + (_index + 1).toString() + '/5 — ' +
                    CapturePose.values[_index].label,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (!done && controller != null && controller.value.isInitialized)
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: AspectRatio(
                    aspectRatio: 1 / controller.value.aspectRatio,
                    child: Stack(fit: StackFit.expand, children: [
                      CameraPreview(controller),
                      IgnorePointer(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(40, 35, 40, 40),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(180),
                              border: Border.all(
                                color: const Color(0xFF94D8BC), width: 3),
                            ),
                          ),
                        ),
                      ),
                    ]),
                  ),
                )
              else if (!done)
                const SizedBox(
                  height: 230,
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 12),
              Text(_instruction, textAlign: TextAlign.center),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(
                  color: Theme.of(context).colorScheme.error)),
                TextButton.icon(
                  onPressed: () async {
                    await _pauseCamera();
                    if (mounted) setState(() => _error = null);
                    await _startCamera();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry camera'),
                ),
              ],
              if (!done)
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Swap left/right guidance'),
                  subtitle: const Text(
                    'For mirrored selfie cameras with reversed prompts'),
                  value: _invertYaw,
                  onChanged: (value) => setState(() {
                    _invertYaw = value;
                    _stability.reset();
                  }),
                ),
              const SizedBox(height: 12),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final pose in CapturePose.values)
                  Chip(
                    avatar: Icon(_shots.any((p) => p.pose == pose)
                        ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 17),
                    label: Text(pose.label),
                  ),
              ]),
              if (done) ...[
                const SizedBox(height: 18),
                const Text('Five guided photos are ready. No 3D mesh exists.'),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _finish,
                  icon: const Icon(Icons.save_alt),
                  label: const Text('Use captured reference photos'),
                ),
              ],
              if (_shots.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: _taking ? null : _retake,
                  icon: const Icon(Icons.replay),
                  label: const Text('Retake previous angle'),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
