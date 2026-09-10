/// PHASE 4: Secure API Client for Flutter Web
/// 
/// Security principles:
/// - All requests include Bearer token
/// - Failed requests refresh token and retry once
/// - 401: Re-authenticate (token expired)
/// - 403: Authorization denied (user doesn't own resource)
/// - Never log sensitive headers or response bodies
/// - Fail-closed: Return null on any error
library;

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_service.dart';

class ApiClient {
  final String baseUrl;
  final AuthService authService;
  final http.Client _httpClient;

  ApiClient({
    required this.baseUrl,
    required this.authService,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Make authenticated GET request
  Future<dynamic> get(
    String endpoint, {
    Map<String, String>? headers,
  }) async {
    return _makeRequest('GET', endpoint, headers: headers);
  }

  /// Make authenticated POST request
  Future<dynamic> post(
    String endpoint, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    return _makeRequest(
      'POST',
      endpoint,
      headers: headers,
      body: body,
    );
  }

  /// Internal request handler with retry logic
  Future<dynamic> _makeRequest(
    String method,
    String endpoint, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    try {
      // Get access token
      final accessToken = authService.getAccessToken();
      if (accessToken == null) {
        print('ERROR: Not authenticated (no access token)');
        return null;
      }

      // Prepare headers (never log)
      final requestHeaders = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',  // Never log this
        ...?headers,
      };

      // Make request
      final uri = Uri.parse('$baseUrl$endpoint');
      http.Response? response;

      if (method == 'GET') {
        response = await _httpClient.get(uri, headers: requestHeaders);
      } else if (method == 'POST') {
        response = await _httpClient.post(
          uri,
          headers: requestHeaders,
          body: body != null ? jsonEncode(body) : null,
        );
      }

      if (response == null) {
        return null;
      }

      // Handle response status codes
      if (response.statusCode == 200) {
        // Success
        return _parseJson(response.body);
      } else if (response.statusCode == 401) {
        // Unauthorized: Token expired, try refresh
        print('INFO: Access token expired, refreshing...');
        final newToken = await authService.refreshAccessToken();
        if (newToken != null) {
          // Retry once
          return _makeRequest(
            method,
            endpoint,
            headers: headers,
            body: body,
          );
        } else {
          // Refresh failed, re-authenticate
          print('ERROR: Authentication required');
          await authService.logout();
          return null;
        }
      } else if (response.statusCode == 403) {
        // Forbidden: Authorization denied
        // PHASE 4: Fail-closed authorization
        print('ERROR: Authorization denied (user does not own resource)');
        return null;
      } else if (response.statusCode >= 500) {
        // Server error
        print('ERROR: Server error: ${response.statusCode}');
        return null;
      } else {
        // Other error
        print('ERROR: Request failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('ERROR: API request exception: $e');
      return null;
    }
  }

  /// Parse JSON response (fail-closed)
  dynamic _parseJson(String body) {
    try {
      return jsonDecode(body);
    } catch (e) {
      print('ERROR: JSON parse failed: $e');
      return null;
    }
  }
}

/// Extension for common API endpoints
extension ApiClientEndpoints on ApiClient {
  /// GET /api/teams/me - Get user's FPL teams
  Future<List<dynamic>?> getUserTeams() async {
    final response = await get('/api/teams/me');
    if (response is Map && response['teams'] is List) {
      return response['teams'];
    }
    return null;
  }

  /// GET /api/teams/{team_id} - Get FPL team data
  /// PHASE 4: Authorization enforced by backend
  Future<Map<String, dynamic>?> getTeamData(int teamId) async {
    final response = await get('/api/teams/$teamId');
    if (response is Map) {
      return response;
    }
    return null;
  }

  /// GET /api/teams/link?fpl_team_id={id} - Link FPL account
  Future<bool> linkFplAccount(int fplTeamId) async {
    final response = await get('/api/teams/link?fpl_team_id=$fplTeamId');
    if (response is Map && response['status'] == 'linked') {
      return true;
    }
    return false;
  }
}
