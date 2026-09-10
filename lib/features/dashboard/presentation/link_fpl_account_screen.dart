import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/error/result.dart';
import '../../../data_providers/models/player.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/dashboard_data.dart';
import 'dashboard_controller.dart';

/// Shown in two cases:
/// 1. User hasn't linked an FPL account → shows the correct link form.
/// 2. User has linked → shows the tactical pitch view.
///
/// ## Platform + configuration routing
///
/// ```
/// kIsWeb == false  →  _buildNativeForm()   email+password, direct to FPL
/// kIsWeb == true
///   Env.hasCloudRun == true   →  _buildWebEmailForm()  email+password via Cloud Run
///   Env.hasCloudRun == false  →  _buildWebTeamIdForm() manual Team ID fallback
/// ```
///
/// The web email form attempts Cloud Run first. If Cloud Run returns
/// [AppFailureType.cloudRunNotConfigured] at runtime (shouldn't happen
/// when hasCloudRun is true, but defensive), it drops to the Team ID form.
class LinkFplAccountScreen extends ConsumerStatefulWidget {
  const LinkFplAccountScreen({super.key});

  @override
  ConsumerState<LinkFplAccountScreen> createState() =>
      _LinkFplAccountScreenState();
}

class _LinkFplAccountScreenState extends ConsumerState<LinkFplAccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _teamIdController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _error;

  /// True when Cloud Run failed at runtime and we fell back to Team ID.
  bool _showingTeamIdFallback = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _teamIdController.dispose();
    super.dispose();
  }

  // ─── Submit handlers ────────────────────────────────────────────────

  /// Native + Web (Cloud Run) — email + password → fetchTeamId → save.
  Future<void> _submitEmailPassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    final result = await ref.read(fplAuthServiceProvider).fetchTeamId(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );

    if (!mounted) return;

    result.when(
      ok: (teamId) => _saveTeamId(teamId),
      err: (failure) {
        // Cloud Run not configured at runtime → drop to Team ID form
        if (failure.type == AppFailureType.cloudRunNotConfigured) {
          setState(() {
            _isSubmitting = false;
            _showingTeamIdFallback = true;
            _error = null;
          });
          return;
        }
        setState(() {
          _isSubmitting = false;
          _error = failure.message;
        });
      },
    );
  }

  /// Web fallback — manual Team ID entry.
  Future<void> _submitTeamId() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final teamId = int.tryParse(_teamIdController.text.trim());
    if (teamId == null || teamId <= 0) {
      setState(() => _error = 'Please enter a valid team ID number.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    await _saveTeamId(teamId);
  }

  /// Shared final step: validate ID against FPL public API, then persist.
  Future<void> _saveTeamId(int teamId) async {
    final linkResult =
        await ref.read(authRepositoryProvider).linkFplManagerId(teamId);
    if (!mounted) return;
    linkResult.when(
      ok: (_) => ref.invalidate(dashboardDataProvider),
      err: (failure) => setState(() {
        _isSubmitting = false;
        _error = failure.message;
      }),
    );
  }

  // ─── Build ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ref.watch(dashboardDataProvider).when(
          loading: () => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Scaffold(
            body: Center(
              child:
                  Text(e.toString(), style: const TextStyle(color: Colors.red)),
            ),
          ),
          data: (data) {
            if (data != null) return _buildPitch(data);

            if (!kIsWeb) return _buildNativeForm();
            if (Env.hasCloudRun && !_showingTeamIdFallback) {
              return _buildWebEmailForm();
            }
            return _buildWebTeamIdForm();
          },
        );
  }

  // ─── Native form ────────────────────────────────────────────────────

  Widget _buildNativeForm() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: _appBar('Connect FPL Account'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _buildHeader(
                title: 'Sign in with your FPL account',
                subtitle: 'We\'ll automatically find your team ID.\n'
                    'Your password is sent directly to FPL and never stored.',
              ),
              const SizedBox(height: 32),
              _emailField(),
              const SizedBox(height: 16),
              _passwordField(onSubmit: _submitEmailPassword),
              const SizedBox(height: 12),
              _buildErrorBanner(),
              const SizedBox(height: 20),
              _buildSubmitButton(
                label: 'Connect FPL Account',
                onPressed: _submitEmailPassword,
              ),
              const SizedBox(height: 24),
              _buildSecurityNote(
                'Your FPL password is sent directly to '
                'fantasy.premierleague.com and is never stored by SquadIQ. '
                'Only your team ID is saved.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Web — email+password form (Cloud Run) ──────────────────────────

  Widget _buildWebEmailForm() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: _appBar('Connect FPL Account'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _buildHeader(
                title: 'Sign in with your FPL account',
                subtitle: 'We\'ll automatically find your team ID.\n'
                    'Your password is never stored by SquadIQ.',
              ),
              const SizedBox(height: 32),
              _emailField(),
              const SizedBox(height: 16),
              _passwordField(onSubmit: _submitEmailPassword),
              const SizedBox(height: 12),
              _buildErrorBanner(),
              const SizedBox(height: 20),
              _buildSubmitButton(
                label: 'Connect FPL Account',
                onPressed: _submitEmailPassword,
              ),
              const SizedBox(height: 16),
              // Manual fallback link
              Center(
                child: TextButton(
                  onPressed: _isSubmitting
                      ? null
                      : () => setState(() {
                            _showingTeamIdFallback = true;
                            _error = null;
                          }),
                  child: const Text(
                    'Enter Team ID manually instead',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildSecurityNote(
                'Your password is sent over HTTPS to a secure proxy that '
                'calls FPL on your behalf. Only your team ID is stored.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Web — manual Team ID fallback ──────────────────────────────────

  Widget _buildWebTeamIdForm() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: _appBar('Connect FPL Account'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              _buildHeader(
                title: 'Enter your FPL Team ID',
                subtitle: 'Your team ID is the number in the URL '
                    'when you visit your team page.',
              ),
              const SizedBox(height: 32),

              // How-to card
              _buildInfoCard(
                icon: Icons.help_outline,
                iconColor: Colors.blue,
                content: RichText(
                  text: TextSpan(
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                    children: [
                      const TextSpan(text: '1. Go to '),
                      TextSpan(
                        text: 'fantasy.premierleague.com',
                        style: const TextStyle(
                          color: Colors.blue,
                          decoration: TextDecoration.underline,
                        ),
                        recognizer: TapGestureRecognizer()..onTap = () {},
                      ),
                      const TextSpan(
                          text: '\n2. Sign in → "My Team"\n'
                              '3. URL: .../entry/'),
                      const TextSpan(
                        text: '123456',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(
                          text: '/event/...\n4. That number is your Team ID'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              TextFormField(
                controller: _teamIdController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(color: Colors.white, fontSize: 18),
                textAlign: TextAlign.center,
                decoration: _inputDecoration(
                  label: 'FPL Team ID',
                  hint: 'e.g. 123456',
                  icon: Icons.tag,
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Please enter your team ID';
                  }
                  if (int.tryParse(v.trim()) == null) {
                    return 'Team ID must be a number';
                  }
                  if (int.parse(v.trim()) <= 0) {
                    return 'Enter a valid positive team ID';
                  }
                  return null;
                },
                onFieldSubmitted: (_) => _isSubmitting ? null : _submitTeamId(),
              ),

              const SizedBox(height: 12),
              _buildErrorBanner(),
              const SizedBox(height: 20),
              _buildSubmitButton(
                label: 'Connect FPL Account',
                onPressed: _submitTeamId,
              ),

              // Back to email form if Cloud Run is configured
              if (Env.hasCloudRun) ...[
                const SizedBox(height: 16),
                Center(
                  child: TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => setState(() {
                              _showingTeamIdFallback = false;
                              _error = null;
                            }),
                    child: const Text(
                      '← Sign in with email instead',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              _buildSecurityNote(
                'Your team ID is a public number — it doesn\'t give '
                'SquadIQ access to your FPL account. We use it only to '
                'read your squad from the FPL public API.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Shared form widgets ────────────────────────────────────────────

  Widget _emailField() => TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        style: const TextStyle(color: Colors.white),
        decoration: _inputDecoration(
          label: 'FPL Email',
          hint: 'your@email.com',
          icon: Icons.email_outlined,
        ),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'Email is required';
          if (!v.contains('@')) return 'Enter a valid email';
          return null;
        },
      );

  Widget _passwordField({required VoidCallback onSubmit}) => TextFormField(
        controller: _passwordController,
        obscureText: _obscurePassword,
        style: const TextStyle(color: Colors.white),
        decoration: _inputDecoration(
          label: 'FPL Password',
          hint: '••••••••',
          icon: Icons.lock_outline,
        ).copyWith(
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
              color: Colors.grey,
            ),
            onPressed: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
        validator: (v) {
          if (v == null || v.isEmpty) return 'Password is required';
          return null;
        },
        onFieldSubmitted: (_) => _isSubmitting ? null : onSubmit(),
      );

  AppBar _appBar(String title) => AppBar(
        title: Text(title),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      );

  Widget _buildHeader({required String title, required String subtitle}) =>
      Column(children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF15803D),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.sports_soccer, color: Colors.white, size: 40),
        ),
        const SizedBox(height: 20),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey, fontSize: 13)),
      ]);

  Widget _buildInfoCard({
    required IconData icon,
    required Color iconColor,
    required Widget content,
  }) =>
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: iconColor, size: 18),
            const SizedBox(width: 8),
            Expanded(child: content),
          ],
        ),
      );

  Widget _buildErrorBanner() {
    if (_error == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade900.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade700),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildSubmitButton({
    required String label,
    required VoidCallback onPressed,
  }) =>
      FilledButton(
        onPressed: _isSubmitting ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF15803D),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: _isSubmitting
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );

  Widget _buildSecurityNote(String text) => _buildInfoCard(
        icon: Icons.shield_outlined,
        iconColor: Colors.green,
        content: Text(text,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
      );

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.grey),
        labelStyle: const TextStyle(color: Colors.grey),
        hintStyle: const TextStyle(color: Colors.grey),
        filled: true,
        fillColor: const Color(0xFF1E293B),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF15803D), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 2),
        ),
      );

  // ─── Pitch view (after linking) ─────────────────────────────────────

  Widget _buildPitch(DashboardData data) {
    final starters = data.squad.where((p) => p.isStarting).toList();
    final bench = data.squad.where((p) => !p.isStarting).toList();

    final gks = starters
        .where((p) => p.player.position == PlayerPosition.goalkeeper)
        .toList();
    final defs = starters
        .where((p) => p.player.position == PlayerPosition.defender)
        .toList();
    final mids = starters
        .where((p) => p.player.position == PlayerPosition.midfielder)
        .toList();
    final fwds = starters
        .where((p) => p.player.position == PlayerPosition.forward)
        .toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: Text(data.manager.teamName,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () => ref.invalidate(dashboardDataProvider),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 4,
            child: Container(
              margin: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white30, width: 2),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF166534),
                    Color(0xFF15803D),
                    Color(0xFF166534),
                  ],
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildRow(fwds),
                  _buildRow(mids),
                  _buildRow(defs),
                  _buildRow(gks),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            color: const Color(0xFF1E293B),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bench',
                    style: TextStyle(
                        color: Colors.grey,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
                const SizedBox(height: 8),
                _buildRow(bench, isBench: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(List<DashboardSquadPlayer> players, {bool isBench = false}) {
    if (players.isEmpty) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children:
          players.map((p) => _buildPlayerCard(p, isBench: isBench)).toList(),
    );
  }

  Widget _buildPlayerCard(DashboardSquadPlayer entry, {bool isBench = false}) {
    final name = entry.player.webName;
    final radius = isBench ? 22.0 : 26.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            CircleAvatar(
              radius: radius,
              backgroundColor: entry.isAvailabilityRisk
                  ? Colors.red.shade900
                  : isBench
                      ? Colors.grey.shade800
                      : const Color(0xFF0F172A),
              child: Icon(
                Icons.person,
                color: entry.isAvailabilityRisk
                    ? Colors.red.shade300
                    : isBench
                        ? Colors.grey
                        : Colors.green.shade400,
                size: radius * 1.3,
              ),
            ),
            if (entry.isCaptain)
              const CircleAvatar(
                radius: 9,
                backgroundColor: Colors.amber,
                child: Text('C',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
              )
            else if (entry.isViceCaptain)
              const CircleAvatar(
                radius: 9,
                backgroundColor: Colors.blue,
                child: Text('V',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ),
        if (entry.isAvailabilityRisk)
          const Text('⚠', style: TextStyle(fontSize: 10, color: Colors.orange)),
      ],
    );
  }
}
