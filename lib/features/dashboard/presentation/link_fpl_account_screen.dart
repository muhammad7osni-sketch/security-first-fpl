import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data_providers/models/player.dart';
import '../../authentication/presentation/auth_providers.dart';
import '../domain/dashboard_data.dart';
import 'dashboard_controller.dart';

/// Shown in two cases:
/// 1. User hasn't linked an FPL account yet → shows FPL login form.
/// 2. User has linked → shows the tactical pitch view of their squad.
///
/// On login, [FplAuthService] POSTs to FPL's official login endpoint,
/// reads the team ID from /me/, then saves it via [AuthRepository].
/// The FPL password is never stored — only the integer team ID is kept.
class LinkFplAccountScreen extends ConsumerStatefulWidget {
  const LinkFplAccountScreen({super.key});

  @override
  ConsumerState<LinkFplAccountScreen> createState() =>
      _LinkFplAccountScreenState();
}

class _LinkFplAccountScreenState extends ConsumerState<LinkFplAccountScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSubmitting = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    // Step 1: Login to FPL and get team ID automatically
    final fplAuth = ref.read(fplAuthServiceProvider);
    final teamIdResult = await fplAuth.fetchTeamId(
      email: email,
      password: password,
    );

    if (!mounted) return;

    // Step 2: If successful, save the team ID to our Supabase users table
    await teamIdResult.when(
      ok: (teamId) async {
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
      },
      err: (failure) {
        setState(() {
          _isSubmitting = false;
          _error = failure.message;
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final asyncData = ref.watch(dashboardDataProvider);

    return asyncData.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Text(e.toString(), style: const TextStyle(color: Colors.red)),
        ),
      ),
      data: (data) {
        if (data == null) return _buildLoginForm();
        return _buildPitch(data);
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FPL Login Form
  // ─────────────────────────────────────────────────────────────
  Widget _buildLoginForm() {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        title: const Text('Connect FPL Account'),
        backgroundColor: const Color(0xFF1E293B),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              // ── Logo / Header ──────────────────────────────────
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: const Color(0xFF15803D),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.sports_soccer,
                      color: Colors.white, size: 40),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Sign in with your FPL account',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'We\'ll automatically find your team ID.\n'
                'Your password is sent directly to FPL and never stored.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 32),
              // ── Email Field ────────────────────────────────────
              TextFormField(
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
              ),
              const SizedBox(height: 16),
              // ── Password Field ─────────────────────────────────
              TextFormField(
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
                onFieldSubmitted: (_) => _isSubmitting ? null : _submit(),
              ),
              const SizedBox(height: 12),
              // ── Error Message ──────────────────────────────────
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade700),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline,
                          color: Colors.red, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              // ── Submit Button ──────────────────────────────────
              FilledButton(
                onPressed: _isSubmitting ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF15803D),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Connect FPL Account',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
              const SizedBox(height: 24),
              // ── Security note ──────────────────────────────────
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, color: Colors.green, size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your FPL password is sent directly to '
                        'fantasy.premierleague.com and is never stored '
                        'by SquadIQ. Only your team ID is saved.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
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
  }

  // ─────────────────────────────────────────────────────────────
  // Tactical pitch (after linking)
  // ─────────────────────────────────────────────────────────────
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
        title: Text(
          data.manager.teamName,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
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
                const Text(
                  'Bench',
                  style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
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
    final isCaptain = entry.isCaptain;
    final isVice = entry.isViceCaptain;
    final hasRisk = entry.isAvailabilityRisk;
    final radius = isBench ? 22.0 : 26.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.topRight,
          children: [
            CircleAvatar(
              radius: radius,
              backgroundColor: hasRisk
                  ? Colors.red.shade900
                  : isBench
                      ? Colors.grey.shade800
                      : const Color(0xFF0F172A),
              child: Icon(
                Icons.person,
                color: hasRisk
                    ? Colors.red.shade300
                    : isBench
                        ? Colors.grey
                        : Colors.green.shade400,
                size: radius * 1.3,
              ),
            ),
            if (isCaptain)
              const CircleAvatar(
                radius: 9,
                backgroundColor: Colors.amber,
                child: Text('C',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.black)),
              )
            else if (isVice)
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
          child: Text(
            name,
            style: const TextStyle(
                color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        if (hasRisk)
          const Text('⚠', style: TextStyle(fontSize: 10, color: Colors.orange)),
      ],
    );
  }
}
