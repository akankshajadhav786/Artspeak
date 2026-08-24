import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const coral = Color(0xffe87968);
const ink = Color(0xff273b36);
const sage = Color(0xff3f7669);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SUPABASE_URL');
  const key = String.fromEnvironment('SUPABASE_ANON_KEY');
  if (url.startsWith('https://') && !key.startsWith('your-')) {
    await Supabase.initialize(url: url, publishableKey: key);
  }
  runApp(const ArtspeakApp());
}

class ArtspeakApp extends StatelessWidget {
  const ArtspeakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Artspeak',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: coral,
          surface: const Color(0xfffffbf7),
        ),
        scaffoldBackgroundColor: const Color(0xfffffbf7),
        fontFamily: 'Georgia',
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const WelcomePage(),
    );
  }
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  int minutes = 10;

  Future<void> login(String role) async {
    final email = TextEditingController();
    final password = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xfffffbf7),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          MediaQuery.viewInsetsOf(sheetContext).bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$role sign in',
              style: const TextStyle(
                fontSize: 26,
                color: ink,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sign in to keep sessions connected to the right care team.',
            ),
            const SizedBox(height: 20),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () async {
                  try {
                    if (Supabase.instance.isInitialized) {
                      await Supabase.instance.client.auth.signInWithPassword(
                        email: email.text.trim(),
                        password: password.text,
                      );
                    }
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                    if (mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Supabase.instance.isInitialized
                                ? 'Signed in as $role.'
                                : 'Demo mode: add Supabase keys to enable sign in.',
                          ),
                        ),
                      );
                  } catch (error) {
                    if (sheetContext.mounted)
                      ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(content: Text('Sign in failed: $error')),
                      );
                  }
                },
                style: FilledButton.styleFrom(backgroundColor: sage),
                child: const Text('Continue'),
              ),
            ),
          ],
        ),
      ),
    );
    email.dispose();
    password.dispose();
  }

  Future<void> startSession() async {
    String? sessionId;
    final user = Supabase.instance.isInitialized
        ? Supabase.instance.client.auth.currentUser
        : null;
    if (user != null) {
      final row = await Supabase.instance.client
          .from('sessions')
          .insert({
            'duration_minutes': minutes,
            'role': 'caregiver',
            'caregiver_id': user.id,
          })
          .select('id')
          .single();
      sessionId = row['id'].toString();
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionPage(duration: minutes, sessionId: sessionId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 820),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'artspeak',
                    style: TextStyle(
                      fontSize: 25,
                      color: ink,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 64),
                  const Text(
                    'Welcome to\nArtspeak.',
                    style: TextStyle(
                      fontSize: 52,
                      height: 1.05,
                      color: ink,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'A gentle way to notice, express, and understand feelings without needing words.',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.5,
                      color: Color(0xff58716b),
                    ),
                  ),
                  const SizedBox(height: 34),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => login('Caregiver'),
                        icon: const Icon(Icons.person_outline),
                        label: const Text('Caregiver login'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => login('Child'),
                        icon: const Icon(Icons.favorite_border),
                        label: const Text('Child login'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: const Color(0xffffe6d7),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ready when you are',
                          style: TextStyle(
                            fontSize: 23,
                            color: ink,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text('Choose how long this session should feel.'),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: minutes.toDouble(),
                                min: 5,
                                max: 60,
                                divisions: 11,
                                activeColor: coral,
                                label: '$minutes min',
                                onChanged: (value) =>
                                    setState(() => minutes = value.round()),
                              ),
                            ),
                            Text(
                              '$minutes min',
                              style: const TextStyle(
                                color: ink,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            onPressed: startSession,
                            icon: const Icon(Icons.play_arrow),
                            label: const Text('Start session'),
                            style: FilledButton.styleFrom(
                              backgroundColor: coral,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Your session data stays private and is connected to your Supabase care workspace.',
                    style: TextStyle(color: Color(0xff58716b)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SessionPage extends StatefulWidget {
  const SessionPage({super.key, required this.duration, this.sessionId});
  final int duration;
  final String? sessionId;

  @override
  State<SessionPage> createState() => _SessionPageState();
}

class _SessionPageState extends State<SessionPage> {
  CameraController? controller;
  String status = 'Preparing camera...';

  @override
  void initState() {
    super.initState();
    openCamera();
  }

  Future<void> openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw Exception('No camera found');
      final nextController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await nextController.initialize();
      if (!mounted) return;
      setState(() {
        controller = nextController;
        status = 'Listening gently';
      });
    } catch (_) {
      if (mounted)
        setState(() => status = 'Camera permission is needed to begin');
    }
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your session'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              status,
              style: const TextStyle(
                fontSize: 28,
                color: ink,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${widget.duration} minute session${widget.sessionId == null ? ' · demo storage' : ' · saved'}',
              style: const TextStyle(color: Color(0xff58716b)),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: controller?.value.isInitialized == true
                    ? CameraPreview(controller!)
                    : Container(
                        color: const Color(0xffd7eee4),
                        child: const Center(
                          child: Icon(
                            Icons.videocam_outlined,
                            size: 72,
                            color: sage,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Move at your own pace. Artspeak is observing touch, rhythm, and gaze to create your visual story.',
              style: TextStyle(
                fontSize: 16,
                height: 1.4,
                color: Color(0xff58716b),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
