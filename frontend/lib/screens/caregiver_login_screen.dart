import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../services/art_speak_repository.dart';
import '../services/app_auth_cache.dart';
import 'caregiver_signup_screen.dart';
import 'child_details_screen.dart';
import 'caregiver_dashboard_screen.dart';
import 'welcome_screen.dart';

class CaregiverLoginScreen extends StatefulWidget {
  const CaregiverLoginScreen({super.key});

  @override
  State<CaregiverLoginScreen> createState() => _CaregiverLoginScreenState();
}

class _CaregiverLoginScreenState extends State<CaregiverLoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool get _validEmail => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_emailCtrl.text.trim());
  bool get _canContinue => _validEmail && _passCtrl.text.length >= 6;
  bool _busy = false;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _loadCachedEmail();
  }

  Future<void> _loadCachedEmail() async {
    final cached = await AppAuthCache.getCaregiverEmail();
    final remember = await AppAuthCache.isRememberMe();
    if (cached != null && cached.isNotEmpty && mounted) {
      setState(() {
        _emailCtrl.text = cached;
        _rememberMe = remember;
      });
    }
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      final email = _emailCtrl.text.trim();
      await artSpeakRepository.signIn(email: email, password: _passCtrl.text);

      if (_rememberMe) {
        await AppAuthCache.saveCaregiverEmail(email);
        await AppAuthCache.setRememberMe(true);
      } else {
        await AppAuthCache.clearAuthCache();
        await AppAuthCache.setRememberMe(false);
      }

      if (!mounted) return;
      final children = await artSpeakRepository.loadCaregiverChildren();
      if (!mounted) return;
      if (children.isNotEmpty) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => CaregiverDashboardScreen(initialProfile: children.first, allProfiles: children)),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ChildDetailsScreen()),
        );
      }
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(artSpeakRepository.authErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackdrop(
        child: SafeArea(
          child: Stack(
            children: [
              Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 90),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    constraints: const BoxConstraints(maxWidth: 460),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 24, offset: const Offset(0, 12))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const ArtSpeakLogo(size: 38),
                        const SizedBox(height: 26),
                        const StepHeader(activeStep: 1),
                        const SizedBox(height: 24),
                        Text('Caregiver Login',
                            style: GoogleFonts.fredoka(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.primaryDark)),
                        const SizedBox(height: 6),
                        Text('Sign in to manage sessions for your child.',
                            style: GoogleFonts.nunito(color: AppColors.textMuted, fontSize: 14.5)),
                        const SizedBox(height: 24),
                        Text('Email address', style: GoogleFonts.fredoka(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _emailCtrl,
                          onChanged: (_) => setState(() {}),
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: 'you@example.com',
                            errorText: _emailCtrl.text.isNotEmpty && !_validEmail
                                ? 'Enter a valid email address'
                                : null,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('Password', style: GoogleFonts.fredoka(fontWeight: FontWeight.w600, fontSize: 14)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _passCtrl,
                          onChanged: (_) => setState(() {}),
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            errorText: _passCtrl.text.isNotEmpty && _passCtrl.text.length < 6 ? 'Use at least 6 characters' : null,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            SizedBox(
                              width: 24,
                              height: 24,
                              child: Checkbox(
                                value: _rememberMe,
                                activeColor: AppColors.primary,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                                onChanged: (v) => setState(() => _rememberMe = v ?? true),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => setState(() => _rememberMe = !_rememberMe),
                              child: Text(
                                'Remember my email on this device',
                                style: GoogleFonts.nunito(fontSize: 13, color: AppColors.textDark, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        PrimaryButton(
                          label: 'Continue',
                          enabled: _canContinue,
                            onPressed: _busy ? null : _login,
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const CaregiverSignupScreen())),
                            child: Wrap(
                              children: [
                                Text("Don't have an account? ", style: GoogleFonts.nunito(color: AppColors.textMuted)),
                                Text('Sign up free',
                                    style: GoogleFonts.fredoka(color: AppColors.primary, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              BackPill(
                onTap: () => Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (_) => false,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
