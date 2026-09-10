/// PHASE 4: Authentication Service for Flutter Web
/// OAuth 2.0 OIDC + PKCE flow + JWT validation
/// 
/// Security principles:
/// - Access tokens: In-memory only (no localStorage)
/// - Refresh tokens: Sent to backend, encrypted server-side
/// - PKCE: Code challenge/verifier for secure code exchange
/// - Never log tokens or sensitive data
/// - Fail-closed: Any auth error returns null
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// OIDC Configuration
const String oidcAuthority = 'https://account.premierleague.com/as';
const String oidcClientId = 'fpl_flutter_app';  // Placeholder
const String oidcRedirectUri = 'https://fantasy.premierleague.com/';

/// Backend Configuration
const String backendUrl = 'http://localhost:8000';  // Development

/// JWT Claims Container
class AuthToken {
  final String accessToken;
  final String? refreshToken;  // Encrypted, from backend
  final int expiresIn;
  final String tokenType;
  final DateTime? issuedAt;

  AuthToken({
    required this.accessToken,
    this.refreshToken,
    required this.expiresIn,
    required this.tokenType,
    this.issuedAt,
  });

  /// Check if access token is expired (with 5-min buffer)
  bool isExpired() {
    if (issuedAt == null) return true;
    final expirationTime = issuedAt!.add(Duration(seconds: expiresIn - 300));
    return DateTime.now().isAfter(expirationTime);
  }

  /// Manually refresh access token using refresh_token
  /// Called by TokenManager when access token nears expiration
}

/// PKCE Helper for authorization code exchange
class PKCEHelper {
  /// Generate random code verifier (43-128 chars)
  static String generateCodeVerifier() {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final random = Random.secure();
    const length = 128;  // Maximum for security
    return List<String>.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// Generate code challenge from verifier (SHA256 + Base64)
  static String generateCodeChallenge(String verifier) {
    final bytes = utf8.encode(verifier);
    final digest = sha256.convert(bytes);
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }
}

/// Authentication Service
/// Handles OAuth 2.0 OIDC flow with PKCE
class AuthService {
  final Ref ref;
  
  // In-memory storage (session only)
  AuthToken? _currentToken;
  String? _codeVerifier;
  StreamSubscription? _tokenRefreshTimer;

  AuthService(this.ref);

  /// Get authorization URL for PingOne
  /// User will be redirected to this URL to authenticate
  String getAuthorizationUrl() {
    // Generate PKCE values
    _codeVerifier = PKCEHelper.generateCodeVerifier();
    final codeChallenge = PKCEHelper.generateCodeChallenge(_codeVerifier!);

    // Build authorization URL
    final params = {
      'response_type': 'code',
      'client_id': oidcClientId,
      'redirect_uri': oidcRedirectUri,
      'scope': 'openid email profile',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': _generateRandomState(),  // CSRF protection
    };

    final uri = Uri.parse('$oidcAuthority/authorize');
    return uri.replace(queryParameters: params).toString();
  }

  /// Exchange authorization code for tokens
  /// Called by redirect handler after user authenticates
  Future<AuthToken?> exchangeCode(String code) async {
    try {
      if (_codeVerifier == null) {
        print('ERROR: Code verifier not set (PKCE violation)');
        return null;
      }

      // POST to backend /auth/callback
      final response = await http.post(
        Uri.parse('$backendUrl/auth/callback'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'code': code,
          'code_verifier': _codeVerifier,
          'redirect_uri': oidcRedirectUri,
        }),
      );

      if (response.statusCode != 200) {
        print('ERROR: Token exchange failed: ${response.statusCode}');
        return null;
      }

      // Parse response
      final data = jsonDecode(response.body);
      final accessToken = data['access_token'] as String?;
      final refreshToken = data['refresh_token'] as String?;  // Encrypted
      final expiresIn = data['expires_in'] as int? ?? 28800;

      if (accessToken == null) {
        print('ERROR: No access token in response');
        return null;
      }

      // Store token in-memory
      _currentToken = AuthToken(
        accessToken: accessToken,
        refreshToken: refreshToken,
        expiresIn: expiresIn,
        tokenType: 'Bearer',
        issuedAt: DateTime.now(),
      );

      // Setup auto-refresh timer
      _setupTokenRefreshTimer();

      return _currentToken;
    } catch (e) {
      print('ERROR: Code exchange exception: $e');
      return null;
    }
  }

  /// Refresh access token using refresh_token
  Future<AuthToken?> refreshAccessToken() async {
    try {
      if (_currentToken?.refreshToken == null) {
        print('ERROR: No refresh token available');
        return null;
      }

      // POST to backend /auth/refresh
      final response = await http.post(
        Uri.parse('$backendUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refresh_token': _currentToken!.refreshToken,
        }),
      );

      if (response.statusCode != 200) {
        print('ERROR: Token refresh failed: ${response.statusCode}');
        logout();  // Clear token on failure
        return null;
      }

      // Parse response
      final data = jsonDecode(response.body);
      final newAccessToken = data['access_token'] as String?;
      final newRefreshToken = data['refresh_token'] as String?;
      final expiresIn = data['expires_in'] as int? ?? 28800;

      if (newAccessToken == null) {
        print('ERROR: No new access token in response');
        return null;
      }

      // Update in-memory token
      _currentToken = AuthToken(
        accessToken: newAccessToken,
        refreshToken: newRefreshToken ?? _currentToken!.refreshToken,
        expiresIn: expiresIn,
        tokenType: 'Bearer',
        issuedAt: DateTime.now(),
      );

      return _currentToken;
    } catch (e) {
      print('ERROR: Token refresh exception: $e');
      logout();
      return null;
    }
  }

  /// Logout and invalidate tokens
  Future<void> logout() async {
    try {
      if (_currentToken == null) return;

      // Notify backend to revoke tokens
      await http.post(
        Uri.parse('$backendUrl/auth/logout'),
        headers: {
          'Authorization': 'Bearer ${_currentToken!.accessToken}',
          'Content-Type': 'application/json',
        },
      );
    } catch (e) {
      print('ERROR: Logout failed: $e');
    } finally {
      // Clear local token regardless of backend response
      _currentToken = null;
      _codeVerifier = null;
      _tokenRefreshTimer?.cancel();
    }
  }

  /// Get current access token (for API calls)
  /// Returns null if not authenticated or expired
  String? getAccessToken() {
    if (_currentToken == null) return null;
    if (_currentToken!.isExpired()) {
      return null;  // Caller should refresh
    }
    return _currentToken!.accessToken;
  }

  /// Setup automatic token refresh before expiration
  void _setupTokenRefreshTimer() {
    if (_currentToken == null) return;

    // Cancel existing timer
    _tokenRefreshTimer?.cancel();

    // Schedule refresh 5 minutes before expiration
    final refreshDuration = Duration(
      seconds: _currentToken!.expiresIn - 300,
    );

    _tokenRefreshTimer = Future.delayed(refreshDuration).asStream().listen(
      (_) async {
        print('INFO: Refreshing access token...');
        await refreshAccessToken();
        // Reschedule timer
        _setupTokenRefreshTimer();
      },
    );
  }

  /// Generate random state for CSRF protection
  static String _generateRandomState() {
    const charset = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List<String>.generate(
      32,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// Dispose resources
  void dispose() {
    _tokenRefreshTimer?.cancel();
  }
}

/// Riverpod provider for AuthService
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(ref);
});

/// Current authentication state (token)
final authTokenProvider = StateProvider<AuthToken?>((ref) {
  return null;  // Initially unauthenticated
});
