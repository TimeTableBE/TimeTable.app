import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class NetlifyAuthException implements Exception {
  NetlifyAuthException(
    this.message, {
    this.statusCode,
    this.isNetworkError = false,
  });

  final String message;
  final int? statusCode;
  final bool isNetworkError;

  @override
  String toString() => message;
}

class NetlifyIdentityService {
  static final String _siteUrl = const String.fromEnvironment(
    'NETLIFY_SITE_URL',
    defaultValue: '',
  ).trim();
  static final String _inviteFunctionPath = const String.fromEnvironment(
    'NETLIFY_INVITE_FUNCTION_PATH',
    defaultValue: '/.netlify/functions/send-invite',
  ).trim();
  static final String _inviteCodeFunctionPath = const String.fromEnvironment(
    'NETLIFY_INVITE_CODE_FUNCTION_PATH',
    defaultValue: '/.netlify/functions/invite-code',
  ).trim();
  static final String _mailFunctionPath = const String.fromEnvironment(
    'NETLIFY_MAIL_FUNCTION_PATH',
    defaultValue: '/.netlify/functions/send-mail',
  ).trim();

  static bool get isConfigured => _siteUrl.isNotEmpty;

  static Uri _identityUri(String path) {
    final normalizedBase = _siteUrl.endsWith('/')
        ? _siteUrl.substring(0, _siteUrl.length - 1)
        : _siteUrl;
    return Uri.parse('$normalizedBase/.netlify/identity$path');
  }

  static Uri _functionUri(String path) {
    final normalizedBase = _siteUrl.endsWith('/')
        ? _siteUrl.substring(0, _siteUrl.length - 1)
        : _siteUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$normalizedBase$normalizedPath');
  }

  static Future<String?> signup({
    required String email,
    required String password,
    required String name,
    required String company,
    required String businessNumber,
    required String street,
    required String houseNumber,
    String? box,
    required String postalCode,
    required String city,
  }) async {
    if (!isConfigured) return null;
    final response = await http.post(
      _identityUri('/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
        'data': {
          'name': name.trim(),
          'role': 'Beheerder',
          'company': company.trim(),
          'businessNumber': businessNumber.trim(),
          'street': street.trim(),
          'houseNumber': houseNumber.trim(),
          'box': (box ?? '').trim(),
          'postalCode': postalCode.trim(),
          'city': city.trim(),
        },
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return null;
    }
    return _extractErrorMessage(response.body, 'Registratie mislukt.');
  }

  static Future<String?> signupWithInvitation({
    required String email,
    required String password,
    required String name,
    required String company,
    required String role,
    String? contractor,
    String? team,
    required String invitationCode,
  }) async {
    if (!isConfigured) return null;
    final response = await http.post(
      _identityUri('/signup'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'password': password,
        'data': {
          'name': name.trim(),
          'company': company.trim(),
          'role': role.trim(),
          'contractor': (contractor ?? '').trim(),
          'team': (team ?? '').trim(),
          'invitationCode': invitationCode.trim().toUpperCase(),
        },
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return null;
    }
    return _extractErrorMessage(response.body, 'Registratie mislukt.');
  }

  static Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    if (!isConfigured) return null;
    late http.Response response;
    try {
      response = await http.post(
        _identityUri('/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'password',
          'username': email.trim().toLowerCase(),
          'password': password,
        },
      );
    } on SocketException {
      throw NetlifyAuthException(
        'Geen internetverbinding. Probeer opnieuw.',
        isNetworkError: true,
      );
    } on http.ClientException {
      throw NetlifyAuthException(
        'Netwerkfout tijdens aanmelden.',
        isNetworkError: true,
      );
    }
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      Map<String, dynamic> session = <String, dynamic>{};
      if (decoded is Map<String, dynamic>) {
        session = decoded;
      } else if (decoded is Map) {
        session = decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      final accessToken = (session['access_token']?.toString() ?? '').trim();
      final hasUserPayload = session['user'] is Map;
      if (!hasUserPayload && accessToken.isNotEmpty) {
        final enrichedUser = await _fetchCurrentUser(accessToken);
        if (enrichedUser != null) {
          session['user'] = enrichedUser;
        }
      }
      return session;
    }
    throw NetlifyAuthException(
      _extractErrorMessage(response.body, 'Inloggen mislukt.'),
      statusCode: response.statusCode,
    );
  }

  static Future<Map<String, dynamic>?> _fetchCurrentUser(
    String accessToken,
  ) async {
    try {
      final response = await http.get(
        _identityUri('/user'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  static Future<String?> sendPasswordReset(String email) async {
    if (!isConfigured) {
      return 'NETLIFY_SITE_URL is niet ingesteld.';
    }
    final response = await http.post(
      _identityUri('/recover'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.trim().toLowerCase()}),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return null;
    }
    return _extractErrorMessage(response.body, 'Reset-mail versturen mislukt.');
  }

  static Future<String?> inviteUser({
    required String email,
    required String name,
    required String role,
    required String invitedBy,
    String? company,
    String? contractor,
    String? team,
  }) async {
    if (!isConfigured) {
      return 'NETLIFY_SITE_URL is niet ingesteld.';
    }
    final response = await http.post(
      _functionUri(_inviteFunctionPath),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email.trim().toLowerCase(),
        'name': name.trim(),
        'role': role,
        'invitedBy': invitedBy,
        'company': (company ?? '').trim(),
        'contractor': (contractor ?? '').trim(),
        'team': (team ?? '').trim(),
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return null;
    }
    return _extractErrorMessage(
      response.body,
      'Uitnodiging versturen mislukt.',
    );
  }

  static Future<String?> sendInvitationNoticeEmail({
    required String email,
    required String name,
    required String role,
    required String invitedBy,
    required String company,
  }) async {
    if (!isConfigured) return null;
    final response = await http.post(
      _functionUri(_mailFunctionPath),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'type': 'invite_notice',
        'email': email.trim().toLowerCase(),
        'name': name.trim(),
        'role': role,
        'invitedBy': invitedBy,
        'company': company.trim(),
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return null;
    return _extractErrorMessage(
      response.body,
      'Uitnodigingsmail versturen mislukt.',
    );
  }

  static Future<String?> sendInvitationCodeEmail({
    required String email,
    required String name,
    required String role,
    required String company,
    required String invitedBy,
    required String code,
    required DateTime expiresAt,
    String? contractor,
    String? team,
  }) async {
    if (!isConfigured) return null;
    final response = await http.post(
      _functionUri(_mailFunctionPath),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'type': 'invite_code',
        'email': email.trim().toLowerCase(),
        'name': name.trim(),
        'role': role,
        'company': company.trim(),
        'invitedBy': invitedBy.trim(),
        'code': code.trim().toUpperCase(),
        'expiresAt': expiresAt.toIso8601String(),
        'contractor': (contractor ?? '').trim(),
        'team': (team ?? '').trim(),
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) return null;
    return _extractErrorMessage(
      response.body,
      'Uitnodigingscode-mail versturen mislukt.',
    );
  }

  static Future<Map<String, dynamic>?> createInvitationCode({
    required String email,
    required String name,
    required String role,
    required String company,
    required String invitedBy,
    String? contractor,
    String? team,
    int ttlHours = 24,
  }) async {
    if (!isConfigured) return null;
    final response = await http.post(
      _functionUri(_inviteCodeFunctionPath),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'create',
        'email': email.trim().toLowerCase(),
        'name': name.trim(),
        'role': role.trim(),
        'company': company.trim(),
        'invitedBy': invitedBy.trim(),
        'contractor': (contractor ?? '').trim(),
        'team': (team ?? '').trim(),
        'ttlHours': ttlHours,
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return null;
    }
    throw NetlifyAuthException(
      _extractErrorMessage(response.body, 'Uitnodigingscode aanmaken mislukt.'),
      statusCode: response.statusCode,
    );
  }

  static Future<Map<String, dynamic>?> validateInvitationCode({
    required String email,
    required String code,
  }) async {
    if (!isConfigured) return null;
    final response = await http.post(
      _functionUri(_inviteCodeFunctionPath),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'validate',
        'email': email.trim().toLowerCase(),
        'code': code.trim().toUpperCase(),
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return null;
    }
    throw NetlifyAuthException(
      _extractErrorMessage(response.body, 'Code-validatie mislukt.'),
      statusCode: response.statusCode,
    );
  }

  static Future<String?> consumeInvitationCode({
    required String email,
    required String code,
  }) async {
    if (!isConfigured) return null;
    final response = await http.post(
      _functionUri(_inviteCodeFunctionPath),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'action': 'consume',
        'email': email.trim().toLowerCase(),
        'code': code.trim().toUpperCase(),
      }),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return null;
    }
    return _extractErrorMessage(response.body, 'Code niet kunnen afwerken.');
  }

  static String _extractErrorMessage(String raw, String fallback) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final direct =
            decoded['error_description'] ??
            decoded['msg'] ??
            decoded['error'] ??
            decoded['message'];
        if (direct != null && direct.toString().trim().isNotEmpty) {
          return direct.toString();
        }
      }
      if (decoded is List && decoded.isNotEmpty) {
        final first = decoded.first;
        if (first != null && first.toString().trim().isNotEmpty) {
          return first.toString();
        }
      }
      if (decoded is String && decoded.trim().isNotEmpty) return decoded;
    } catch (_) {}
    return fallback;
  }
}
