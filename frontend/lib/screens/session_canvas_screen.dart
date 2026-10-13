import 'dart:async';
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/session_record.dart';
import '../theme/app_theme.dart';
import '../services/art_speak_repository.dart';

/// Total length of the combined draw + facial-expression-capture session.
const int kSessionSeconds = 20;

class _Stroke {
  final List<Offset> points;
  final List<int> timestamps;
  final List<double> pressures;
  final Color color;
  final double width;
  _Stroke(this.color, this.width)
      : points = [],
        timestamps = [],
        pressures = [];
}

/// A simple coloring-book style outline the child is asked to trace/draw.
enum _RefPicture {
  sun('Sun', '☀️'),
  house('House', '🏠'),
  star('Star', '⭐'),
  flower('Flower', '🌸'),
  tree('Tree', '🌳'),
  boat('Boat', '⛵'),
  butterfly('Butterfly', '🦋');

  final String label;
  final String emoji;
  const _RefPicture(this.label, this.emoji);
}

class SessionCanvasScreen extends StatefulWidget {
  final String childName;
  final String sessionId;
  final CameraController? existingCameraController;
  final String? stimulusCategory;
  final String? stimulusImageId;
  final String? stimulusImageAsset;

  const SessionCanvasScreen({
    super.key,
    required this.childName,
    required this.sessionId,
    this.existingCameraController,
    this.stimulusCategory,
    this.stimulusImageId,
    this.stimulusImageAsset,
  });

  @override
  State<SessionCanvasScreen> createState() => _SessionCanvasScreenState();
}

class _SessionCanvasScreenState extends State<SessionCanvasScreen> {
  final List<_Stroke> _strokes = [];
  Color _color = const Color(0xFF3D5AFE);
  double _brushSize = 6;
  Timer? _timer;
  int _secondsLeft = kSessionSeconds;
  bool _sessionOver = false;
  late _RefPicture _refPicture;

  CameraController? _cameraController;
  bool _isRecording = false;
  bool _cameraStarting = true;
  String? _cameraError;
  XFile? _recordedVideo;
  late final DateTime _sessionStartedAt;
  bool _saving = false;

  final _palette = const [
    Color(0xFF3D5AFE),
    Color(0xFF7C93FF),
    Color(0xFFA9C2FF),
    Color(0xFFE0616B),
    Color(0xFFF4A340),
    Color(0xFF4CAF8E),
    Color(0xFF8E6ED8),
  ];
  final _sizes = const [3.0, 6.0, 10.0, 16.0];

  static _RefPicture _defaultRefForCategory(String? cat) {
    switch (cat?.toLowerCase()) {
      case 'animals':
        return _RefPicture.butterfly;
      case 'nature':
        return _RefPicture.tree;
      case 'objects':
        return _RefPicture.house;
      case 'people':
        return _RefPicture.star;
      default:
        return _RefPicture.sun;
    }
  }

  @override
  void initState() {
    super.initState();
    _sessionStartedAt = DateTime.now();
    _refPicture = _defaultRefForCategory(widget.stimulusCategory);
    if (widget.existingCameraController != null) {
      _cameraController = widget.existingCameraController;
      _isRecording = true;
      _cameraStarting = false;
      _startTimer();
    } else {
      _initHiddenCameraAndStart();
    }
  }

  /// Starts the front-camera recording and keeps a preview visible so camera
  /// permission and recording state are clear during a session.
  Future<void> _initHiddenCameraAndStart() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw StateError('No camera was found on this device.');
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(cam, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      await controller.startVideoRecording();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _isRecording = true;
        _cameraStarting = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _cameraStarting = false;
          _cameraError = error.toString().replaceFirst('Bad state: ', '');
        });
      }
    }
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        t.cancel();
        _finishRecordingTimer();
      }
    });
  }

  Future<void> _finishRecordingTimer() async {
    await _stopHiddenCamera();
    if (mounted) setState(() => _sessionOver = true);
  }

  Future<void> _stopHiddenCamera() async {
    final controller = _cameraController;
    if (controller != null && _isRecording) {
      try {
        _recordedVideo = await controller.stopVideoRecording();
      } catch (error) {
        if (mounted) {
          setState(() => _cameraError = 'Camera recording failed: $error');
        }
      }
      _isRecording = false;
    }
  }

  void _startStroke(Offset p) {
    final nowMs = DateTime.now().difference(_sessionStartedAt).inMilliseconds;
    final stroke = _Stroke(_color, _brushSize);
    stroke.points.add(p);
    stroke.timestamps.add(nowMs);
    stroke.pressures.add(0.50);
    setState(() => _strokes.add(stroke));
  }

  void _extendStroke(Offset p) {
    if (_strokes.isEmpty) return;
    final stroke = _strokes.last;
    final nowMs = DateTime.now().difference(_sessionStartedAt).inMilliseconds;
    double dynamicPressure = 0.50;
    if (stroke.points.isNotEmpty && stroke.timestamps.isNotEmpty) {
      final lastPoint = stroke.points.last;
      final lastMs = stroke.timestamps.last;
      final dist = (p - lastPoint).distance;
      final dt = (nowMs - lastMs).clamp(1, 1000);
      final speedPxS = (dist / dt) * 1000.0;
      // High speed scribbling yields elevated pressure up to ~0.95
      dynamicPressure = (0.42 + (speedPxS / 1000.0) * 0.45).clamp(0.20, 0.95);
    }
    stroke.points.add(p);
    stroke.timestamps.add(nowMs);
    stroke.pressures.add(dynamicPressure);
    setState(() {});
  }

  Future<void> _endSession() async {
    if (_saving) return;
    setState(() => _saving = true);
    await _stopHiddenCamera();
    final strokeCount = _strokes.fold<int>(0, (sum, s) => sum + s.points.length);
    final events = <Map<String, dynamic>>[];
    var strokeId = 0;
    for (final stroke in _strokes) {
      for (var i = 0; i < stroke.points.length; i++) {
        final point = stroke.points[i];
        final ts = i < stroke.timestamps.length ? stroke.timestamps[i] : (i * 20);
        final pr = i < stroke.pressures.length ? stroke.pressures[i] : 0.50;
        events.add({
          'timestamp_ms': ts,
          'stroke_id': strokeId,
          'event_type': i == 0 ? 'down' : (i == stroke.points.length - 1 ? 'up' : 'move'),
          'x': point.dx,
          'y': point.dy,
          'pressure': pr,
          'brush_size': stroke.width,
        });
      }
      strokeId++;
    }
    final drawingStrokes = _strokes.map((s) => {
      'color': s.color.value,
      'width': s.width,
      'points': s.points.map((p) => [p.dx, p.dy]).toList(),
    }).toList();

    try {
      await artSpeakRepository.saveTouchEvents(widget.sessionId, events);
      
      final video = _recordedVideo;
      if (video != null) {
        try {
          await artSpeakRepository.saveVideo(widget.sessionId, await video.readAsBytes(), kSessionSeconds);
        } catch (e) {
          debugPrint('Notice saving video: $e');
        }
      }
      
      await artSpeakRepository.markProcessing(widget.sessionId);
      await artSpeakRepository.requestInference(
        widget.sessionId,
        drawingReference: _refPicture.name,
        drawingStrokes: drawingStrokes,
        stimulusCategory: widget.stimulusCategory,
        stimulusImageId: widget.stimulusImageId,
      );

      // Attempt to retrieve generated report from backend (poll up to 10s)
      SessionRecord? completedRecord;
      for (var i = 0; i < 10; i++) {
        completedRecord = await artSpeakRepository.fetchSessionReport(widget.sessionId);
        if (completedRecord != null) break;
        await Future.delayed(const Duration(seconds: 1));
      }

      final finalRecord = (completedRecord != null)
          ? SessionRecord(
              id: completedRecord.id,
              date: completedRecord.date,
              recordingSeconds: completedRecord.recordingSeconds,
              canvasSeconds: completedRecord.canvasSeconds,
              mood: completedRecord.mood,
              valence: completedRecord.valence,
              arousal: completedRecord.arousal,
              dominance: completedRecord.dominance,
              strokeCount: strokeCount,
              caregiverSummary: completedRecord.caregiverSummary,
              distressAlert: completedRecord.distressAlert,
              stimulusCategory: widget.stimulusCategory ?? completedRecord.stimulusCategory,
              stimulusImageId: widget.stimulusImageId ?? completedRecord.stimulusImageId,
              stimulusReactionSummary: completedRecord.stimulusReactionSummary,
              simpleLanguageReport: completedRecord.simpleLanguageReport,
              drawingReference: _refPicture.name,
              drawingStrokes: drawingStrokes,
              insights: completedRecord.insights,
              recommendations: completedRecord.recommendations,
            )
          : SessionRecord.mockFromSession(
              recordingSeconds: 10,
              canvasSeconds: kSessionSeconds,
              strokeCount: strokeCount,
              stimulusCategory: widget.stimulusCategory,
              stimulusImageId: widget.stimulusImageId,
              drawingReference: _refPicture.name,
              drawingStrokes: drawingStrokes,
            );

      if (mounted) {
        Navigator.of(context).pop(finalRecord);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Column(
          children: [
            Text("${widget.childName}'s Session",
                style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, color: AppColors.primaryDark, fontSize: 16)),
            Text('${_strokes.length} strokes', style: GoogleFonts.nunito(fontSize: 11, color: AppColors.textMuted)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _sessionOver ? AppColors.alertRed.withOpacity(0.1) : AppColors.accentSoft,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.timer_outlined, size: 16, color: _sessionOver ? AppColors.alertRed : AppColors.primary),
                    const SizedBox(width: 6),
                    Text(_sessionOver ? "Time's up" : '$_secondsLeft s',
                        style: GoogleFonts.fredoka(
                            fontWeight: FontWeight.w700, color: _sessionOver ? AppColors.alertRed : AppColors.primary)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Row(
        children: [
          _ToolRail(
            palette: _palette,
            sizes: _sizes,
            selectedColor: _color,
            selectedSize: _brushSize,
            onColor: (c) => setState(() => _color = c),
            onSize: (s) => setState(() => _brushSize = s),
          ),
          Expanded(
            child: Column(
              children: [
                // Top half: the reference picture to trace/draw. No gesture
                // handling here at all, so it can never be scribbled on.
                Expanded(
                  flex: 1,
                  child: Container(
                    width: double.infinity,
                    color: const Color(0xFFFDF9F0),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Text(
                                    'Draw this ${_refPicture.label.toLowerCase()}!',
                                    style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, color: AppColors.primaryDark, fontSize: 15),
                                  ),
                                  if (widget.stimulusCategory != null) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.accentSoft,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${widget.stimulusCategory!.toUpperCase()} THEME',
                                        style: GoogleFonts.fredoka(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            _CameraStatus(
                              controller: _cameraController,
                              starting: _cameraStarting,
                              recording: _isRecording,
                              error: _cameraError,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        // Quick-switch chips for easy drawings (Sun, House, Star, Flower, etc.)
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _RefPicture.values.map((pic) {
                              final isSelected = _refPicture == pic;
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: InkWell(
                                  onTap: () => setState(() => _refPicture = pic),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isSelected ? AppColors.primary : Colors.white,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: isSelected ? AppColors.primary : AppColors.accentSoft,
                                        width: 1.4,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(pic.emoji, style: const TextStyle(fontSize: 13)),
                                        const SizedBox(width: 4),
                                        Text(
                                          pic.label,
                                          style: GoogleFonts.nunito(
                                            color: isSelected ? Colors.white : AppColors.primaryDark,
                                            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: AppColors.accentSoft, width: 1.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.04),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: AspectRatio(
                                aspectRatio: 1.35,
                                child: CustomPaint(painter: _ReferencePainter(_refPicture)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 2, thickness: 2, color: Color(0xFFE9ECF5)),
                // Bottom half: the actual drawing canvas.
                Expanded(
                  flex: 1,
                  child: Stack(
                    children: [
                      Container(color: const Color(0xFFF7F9FF)),
                      GestureDetector(
                        onPanStart: (d) => _startStroke(d.localPosition),
                        onPanUpdate: (d) => _extendStroke(d.localPosition),
                        child: CustomPaint(
                          painter: _CanvasPainter(_strokes),
                          size: Size.infinite,
                        ),
                      ),
                      if (_strokes.isEmpty && !_sessionOver)
                        Center(
                          child: Text('Draw here, ${widget.childName}…',
                              style: GoogleFonts.nunito(color: AppColors.textMuted.withOpacity(0.6), fontSize: 16)),
                        ),
                      if (_sessionOver)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 20,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 18, offset: const Offset(0, 8))]),
                              child: ElevatedButton.icon(
                                onPressed: _saving ? null : _endSession,
                                icon: const Icon(Icons.check_circle_rounded),
                                label: Text('End Session', style: GoogleFonts.fredoka(fontWeight: FontWeight.w700, fontSize: 16)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      if (_saving)
        Container(
          color: Colors.black.withValues(alpha: 0.55),
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 32),
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 48,
                    height: 48,
                    child: CircularProgressIndicator(strokeWidth: 4, color: AppColors.primary),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Synthesizing AI Caregiver Report...',
                    style: GoogleFonts.fredoka(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primaryDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Analyzing multimodal face emotion, gaze attention, and stroke rhythm…',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.nunito(
                      fontSize: 13,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  ),
);
  }
}

class _ToolRail extends StatelessWidget {
  final List<Color> palette;
  final List<double> sizes;
  final Color selectedColor;
  final double selectedSize;
  final ValueChanged<Color> onColor;
  final ValueChanged<double> onSize;

  const _ToolRail({
    required this.palette,
    required this.sizes,
    required this.selectedColor,
    required this.selectedSize,
    required this.onColor,
    required this.onSize,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: SingleChildScrollView(
        child: Column(
          children: [
            Text('SIZE', style: GoogleFonts.nunito(fontSize: 10, color: AppColors.textMuted, letterSpacing: 1)),
            const SizedBox(height: 10),
            ...sizes.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => onSize(s),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selectedSize == s ? AppColors.primary : AppColors.accentSoft, width: 1.6),
                      ),
                      child: Center(
                        child: Container(
                          width: s + 4,
                          height: s + 4,
                          decoration: BoxDecoration(color: AppColors.textDark.withOpacity(0.6), shape: BoxShape.circle),
                        ),
                      ),
                    ),
                  ),
                )),
            const SizedBox(height: 16),
            Text('COLOR', style: GoogleFonts.nunito(fontSize: 10, color: AppColors.textMuted, letterSpacing: 1)),
            const SizedBox(height: 10),
            ...palette.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: GestureDetector(
                    onTap: () => onColor(c),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: selectedColor == c ? Border.all(color: Colors.white, width: 3) : null,
                        boxShadow: selectedColor == c
                            ? [BoxShadow(color: c.withOpacity(0.6), blurRadius: 8, spreadRadius: 1)]
                            : [],
                      ),
                    ),
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _CameraStatus extends StatelessWidget {
  final CameraController? controller;
  final bool starting;
  final bool recording;
  final String? error;

  const _CameraStatus({
    required this.controller,
    required this.starting,
    required this.recording,
    required this.error,
  });

  @override
  Widget build(BuildContext context) {
    if (starting) {
      return _statusBox(const CircularProgressIndicator(strokeWidth: 2), 'Starting camera');
    }
    if (error != null || controller == null) {
      return _statusBox(
        const Icon(Icons.videocam_off_outlined, color: AppColors.alertRed, size: 20),
        error ?? 'Camera unavailable',
      );
    }
    return Container(
      width: 150,
      height: 100,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.black),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(controller!),
          Positioned(
            left: 8,
            bottom: 7,
            child: DecoratedBox(
              decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(10)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.fiber_manual_record, size: 9, color: recording ? AppColors.alertRed : Colors.white),
                    const SizedBox(width: 4),
                    Text(recording ? 'Recording' : 'Camera ready', style: const TextStyle(color: Colors.white, fontSize: 10)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBox(Widget icon, String label) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 150),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 6),
          Flexible(child: Text(label, style: const TextStyle(fontSize: 10))),
        ],
      ),
    );
  }
}

class _CanvasPainter extends CustomPainter {
  final List<_Stroke> strokes;
  _CanvasPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (int i = 0; i < stroke.points.length - 1; i++) {
        canvas.drawLine(stroke.points[i], stroke.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}

/// Draws a simple coloring-book style outline for the child to copy.
class _ReferencePainter extends CustomPainter {
  final _RefPicture picture;
  _ReferencePainter(this.picture);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primaryDark
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    final w = size.width, h = size.height;

    switch (picture) {
      case _RefPicture.house:
        final path = Path()
          ..moveTo(w * 0.15, h * 0.95)
          ..lineTo(w * 0.15, h * 0.5)
          ..lineTo(w * 0.5, h * 0.15)
          ..lineTo(w * 0.85, h * 0.5)
          ..lineTo(w * 0.85, h * 0.95)
          ..close();
        canvas.drawPath(path, paint);
        canvas.drawRect(Rect.fromLTWH(w * 0.42, h * 0.6, w * 0.16, h * 0.35), paint);
        canvas.drawRect(Rect.fromLTWH(w * 0.22, h * 0.6, w * 0.14, h * 0.14), paint);
        break;
      case _RefPicture.star:
        final path = Path();
        const points = 5;
        final outerR = min(w, h) * 0.42;
        final innerR = outerR * 0.45;
        final cx = w / 2, cy = h / 2;
        for (int i = 0; i < points * 2; i++) {
          final r = i.isEven ? outerR : innerR;
          final angle = (pi / points) * i - pi / 2;
          final x = cx + r * cos(angle);
          final y = cy + r * sin(angle);
          if (i == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        path.close();
        canvas.drawPath(path, paint);
        break;
      case _RefPicture.sun:
        final cx = w / 2, cy = h / 2;
        final r = min(w, h) * 0.22;
        canvas.drawCircle(Offset(cx, cy), r, paint);
        for (int i = 0; i < 8; i++) {
          final angle = (pi / 4) * i;
          final start = Offset(cx + r * 1.25 * cos(angle), cy + r * 1.25 * sin(angle));
          final end = Offset(cx + r * 1.7 * cos(angle), cy + r * 1.7 * sin(angle));
          canvas.drawLine(start, end, paint);
        }
        break;
      case _RefPicture.flower:
        final cx = w / 2, cy = h / 2;
        final petalR = min(w, h) * 0.16;
        for (int i = 0; i < 6; i++) {
          final angle = (pi / 3) * i;
          final petalCenter = Offset(cx + petalR * 1.1 * cos(angle), cy + petalR * 1.1 * sin(angle));
          canvas.drawCircle(petalCenter, petalR, paint);
        }
        canvas.drawCircle(Offset(cx, cy), petalR * 0.7, paint);
        canvas.drawLine(Offset(cx, cy + petalR * 1.6), Offset(cx, h * 0.95), paint);
        break;
      case _RefPicture.butterfly:
        final cx = w / 2, cy = h / 2;
        canvas.drawLine(Offset(cx, h * 0.15), Offset(cx, h * 0.9), paint);
        final leftWingTop = Path()
          ..moveTo(cx, cy * 0.75)
          ..quadraticBezierTo(w * 0.05, h * 0.1, w * 0.1, h * 0.45)
          ..quadraticBezierTo(w * 0.15, h * 0.65, cx, cy * 0.95)
          ..close();
        final rightWingTop = Path()
          ..moveTo(cx, cy * 0.75)
          ..quadraticBezierTo(w * 0.95, h * 0.1, w * 0.9, h * 0.45)
          ..quadraticBezierTo(w * 0.85, h * 0.65, cx, cy * 0.95)
          ..close();
        final leftWingBottom = Path()
          ..moveTo(cx, cy * 1.05)
          ..quadraticBezierTo(w * 0.1, h * 0.75, w * 0.2, h * 0.95)
          ..quadraticBezierTo(w * 0.3, h * 1.0, cx, cy * 1.2)
          ..close();
        final rightWingBottom = Path()
          ..moveTo(cx, cy * 1.05)
          ..quadraticBezierTo(w * 0.9, h * 0.75, w * 0.8, h * 0.95)
          ..quadraticBezierTo(w * 0.7, h * 1.0, cx, cy * 1.2)
          ..close();
        canvas.drawPath(leftWingTop, paint);
        canvas.drawPath(rightWingTop, paint);
        canvas.drawPath(leftWingBottom, paint);
        canvas.drawPath(rightWingBottom, paint);
        break;
      case _RefPicture.tree:
        // Tree trunk
        canvas.drawRect(Rect.fromLTWH(w * 0.44, h * 0.52, w * 0.12, h * 0.42), paint);
        // Fluffy cloud-like treetop
        final foliagePath = Path()
          ..moveTo(w * 0.25, h * 0.55)
          ..quadraticBezierTo(w * 0.12, h * 0.45, w * 0.22, h * 0.32)
          ..quadraticBezierTo(w * 0.18, h * 0.16, w * 0.38, h * 0.16)
          ..quadraticBezierTo(w * 0.5, h * 0.06, w * 0.62, h * 0.16)
          ..quadraticBezierTo(w * 0.82, h * 0.16, w * 0.78, h * 0.32)
          ..quadraticBezierTo(w * 0.88, h * 0.45, w * 0.75, h * 0.55)
          ..close();
        canvas.drawPath(foliagePath, paint);
        break;
      case _RefPicture.boat:
        // Boat hull
        final hullPath = Path()
          ..moveTo(w * 0.18, h * 0.72)
          ..lineTo(w * 0.82, h * 0.72)
          ..lineTo(w * 0.72, h * 0.92)
          ..lineTo(w * 0.28, h * 0.92)
          ..close();
        canvas.drawPath(hullPath, paint);
        // Mast
        canvas.drawLine(Offset(w * 0.48, h * 0.2), Offset(w * 0.48, h * 0.72), paint);
        // Triangle Sail
        final sailPath = Path()
          ..moveTo(w * 0.5, h * 0.22)
          ..lineTo(w * 0.78, h * 0.65)
          ..lineTo(w * 0.5, h * 0.65)
          ..close();
        canvas.drawPath(sailPath, paint);
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _ReferencePainter oldDelegate) => oldDelegate.picture != picture;
}
