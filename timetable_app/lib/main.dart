import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:hive/hive.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDataStore.init();
  runApp(const TimeTableApp());
}

PageRoute<T> _appPageRoute<T>({required WidgetBuilder builder}) {
  if (Platform.isIOS) {
    return CupertinoPageRoute<T>(builder: builder);
  }
  return MaterialPageRoute<T>(builder: builder);
}

class TimeTableApp extends StatefulWidget {
  const TimeTableApp({super.key});

  @override
  State<TimeTableApp> createState() => _TimeTableAppState();
}

class _TimeTableAppState extends State<TimeTableApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      AppDataStore.save();
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTextTheme = GoogleFonts.spaceGroteskTextTheme();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'TimeTable',
      theme: ThemeData(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF0B2E2B),
          secondary: Color(0xFFFFA64D),
          surface: Color(0xFFF7F4EF),
          error: Color(0xFFB42318),
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F1EA),
        textTheme: baseTextTheme.copyWith(
          headlineLarge: baseTextTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0B2E2B),
          ),
          titleLarge: baseTextTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w600,
            color: const Color(0xFF0B2E2B),
          ),
          bodyMedium: baseTextTheme.bodyMedium?.copyWith(
            color: const Color(0xFF243B3A),
          ),
        ),
        useMaterial3: true,
      ),
      builder: (context, child) {
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: child,
        );
      },
      home: const LoginScreen(),
    );
  }
}

class CurrentUserStore {
  static String role = '';
  static String name = '';
  static String email = '';
  static String company = '';
  static String team = '';
  static String contractor = '';
}

class AuthUser {
  const AuthUser({
    required this.name,
    required this.email,
    required this.company,
    required this.passwordHash,
    required this.passwordSalt,
    this.role = 'Beheerder',
    this.team,
  });

  final String name;
  final String email;
  final String company;
  final String passwordHash;
  final String passwordSalt;
  final String role;
  final String? team;
}

class CompanyProfile {
  const CompanyProfile({
    required this.name,
    required this.businessNumber,
    required this.address,
    required this.adminName,
    required this.adminEmail,
    required this.createdAt,
  });

  final String name;
  final String businessNumber;
  final String address;
  final String adminName;
  final String adminEmail;
  final DateTime createdAt;
}

class AuthStore {
  static final List<AuthUser> users = [];
  static final Map<String, CompanyProfile> companies = {};

  static String _companyKey(String name) => name.trim().toLowerCase();

  static bool seedIfEmpty() {
    if (users.isNotEmpty) return false;
    _RoleManagementStore.seedIfEmpty();
    final usedEmails = <String>{};
    for (final account in _testAccounts) {
      final normalizedCompany = account.company.trim();
      final baseEmail = _emailFromNameAndCompany(account.name, normalizedCompany);
      final uniqueEmail = _ensureUniqueEmail(baseEmail, usedEmails);
      final salt = _generateSalt();
      users.add(
        AuthUser(
          name: account.name,
          email: uniqueEmail,
          company: normalizedCompany,
          passwordHash: _hashPassword('Test1234!', salt),
          passwordSalt: salt,
          role: account.role,
          team: account.team,
        ),
      );
      final key = _companyKey(normalizedCompany);
      companies.putIfAbsent(
        key,
        () => CompanyProfile(
          name: normalizedCompany,
          businessNumber: 'BE0000000000',
          address: 'Onbekend',
          adminName: 'Nick',
          adminEmail: 'nick@finestone.be',
          createdAt: DateTime.now(),
        ),
      );
    }
    return true;
  }

  static AuthUser? authenticate(String email, String password) {
    seedIfEmpty();
    final normalizedEmail = email.trim().toLowerCase();
    final user = users.firstWhere(
      (entry) => entry.email.toLowerCase() == normalizedEmail,
      orElse: () => const AuthUser(
        name: '',
        email: '',
        company: '',
        passwordHash: '',
        passwordSalt: '',
      ),
    );
    if (user.email.isEmpty) return null;
    final incomingHash = _hashPassword(password, user.passwordSalt);
    if (incomingHash != user.passwordHash) return null;
    return user;
  }

  static String? registerCompany({
    required String companyName,
    required String businessNumber,
    required String address,
    required String adminName,
    required String adminEmail,
    required String password,
  }) {
    seedIfEmpty();
    final normalizedCompany = companyName.trim();
    final normalizedBusinessNumber = businessNumber.trim();
    final normalizedAddress = address.trim();
    final normalizedAdminName = adminName.trim();
    final normalizedAdminEmail = adminEmail.trim().toLowerCase();
    final key = _companyKey(normalizedCompany);

    if (normalizedCompany.isEmpty ||
        normalizedBusinessNumber.isEmpty ||
        normalizedAddress.isEmpty ||
        normalizedAdminName.isEmpty ||
        normalizedAdminEmail.isEmpty ||
        password.isEmpty) {
      return 'Vul alle velden in.';
    }
    if (!normalizedAdminEmail.contains('@') ||
        normalizedAdminEmail.startsWith('@') ||
        normalizedAdminEmail.endsWith('@')) {
      return 'Vul een geldig e-mailadres in.';
    }
    if (password.length < 8) {
      return 'Wachtwoord moet minstens 8 tekens hebben.';
    }
    if (users.any(
      (entry) => entry.email.toLowerCase() == normalizedAdminEmail,
    )) {
      return 'Dit e-mailadres is al in gebruik.';
    }
    if (companies.containsKey(key)) {
      return 'Dit bedrijf bestaat al.';
    }

    final salt = _generateSalt();
    users.add(
      AuthUser(
        name: normalizedAdminName,
        email: normalizedAdminEmail,
        company: normalizedCompany,
        passwordHash: _hashPassword(password, salt),
        passwordSalt: salt,
        role: 'Beheerder',
      ),
    );
    companies[key] = CompanyProfile(
      name: normalizedCompany,
      businessNumber: normalizedBusinessNumber,
      address: normalizedAddress,
      adminName: normalizedAdminName,
      adminEmail: normalizedAdminEmail,
      createdAt: DateTime.now(),
    );

    _RoleManagementStore.seedIfEmpty();
    final hasRoleAssignment = _RoleManagementStore.assignments.any(
      (assignment) =>
          assignment.email.toLowerCase() == normalizedAdminEmail,
    );
    if (!hasRoleAssignment) {
      _RoleManagementStore.assignments.add(
        _RoleAssignment(
          name: normalizedAdminName,
          email: normalizedAdminEmail,
          role: 'Beheerder',
        ),
      );
    }
    AppDataStore.scheduleSave();
    return null;
  }

  static TestAccount toAccount(AuthUser user) {
    _RoleManagementStore.seedIfEmpty();
    final assignment = _RoleManagementStore.assignments.firstWhere(
      (entry) =>
          entry.email.toLowerCase() == user.email.toLowerCase(),
      orElse: () => _RoleAssignment(
        name: user.name,
        email: user.email,
        role: user.role,
        team: user.team,
      ),
    );
    return TestAccount(
      name: assignment.name,
      email: user.email,
      role: assignment.role,
      company: user.company,
      team: assignment.team ?? user.team,
    );
  }

  static AuthUser? findByEmail(String email) {
    seedIfEmpty();
    final normalizedEmail = email.trim().toLowerCase();
    for (final user in users) {
      if (user.email.toLowerCase() == normalizedEmail) {
        return user;
      }
    }
    return null;
  }

  static void upsertUserFromIdentity({
    required String email,
    required String name,
    required String company,
    String role = 'Werknemer',
    String? team,
  }) {
    seedIfEmpty();
    final normalizedEmail = email.trim().toLowerCase();
    final index = users.indexWhere(
      (entry) => entry.email.toLowerCase() == normalizedEmail,
    );
    final existing = index == -1 ? null : users[index];
    final safeName = name.trim().isEmpty ? normalizedEmail : name.trim();
    final safeCompany = company.trim().isEmpty ? 'Finestone' : company.trim();
    final replacement = AuthUser(
      name: safeName,
      email: normalizedEmail,
      company: safeCompany,
      passwordHash: existing?.passwordHash ?? '',
      passwordSalt: existing?.passwordSalt ?? '',
      role: role,
      team: team,
    );
    if (index == -1) {
      users.add(replacement);
    } else {
      users[index] = replacement;
    }
    AppDataStore.scheduleSave();
  }

  static TestAccount accountForEmail(
    String email, {
    String fallbackName = '',
    String fallbackCompany = '',
  }) {
    _RoleManagementStore.seedIfEmpty();
    final normalizedEmail = email.trim().toLowerCase();
    final assignment = _RoleManagementStore.assignments.firstWhere(
      (entry) => entry.email.trim().toLowerCase() == normalizedEmail,
      orElse: () => _RoleAssignment(
        name: fallbackName.isEmpty ? normalizedEmail : fallbackName,
        email: normalizedEmail,
        role: 'Werknemer',
      ),
    );
    final knownUser = findByEmail(normalizedEmail);
    final company =
        fallbackCompany.isNotEmpty ? fallbackCompany : (knownUser?.company ?? 'Finestone');
    upsertUserFromIdentity(
      email: normalizedEmail,
      name: assignment.name,
      company: company,
      role: assignment.role,
      team: assignment.team,
    );
    return TestAccount(
      name: assignment.name,
      email: normalizedEmail,
      role: assignment.role,
      company: company,
      team: assignment.team,
    );
  }

  static String _hashPassword(String password, String salt) {
    final bytes = utf8.encode('$salt::$password');
    return sha256.convert(bytes).toString();
  }

  static String _generateSalt() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return base64UrlEncode(bytes);
  }

  static String _emailFromNameAndCompany(String name, String company) {
    final local = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '.')
        .replaceAll(RegExp(r'\.+'), '.')
        .replaceAll(RegExp(r'^\.|\.$'), '');
    final domain = company
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '')
        .replaceAll(RegExp(r'^\.|\.$'), '');
    final safeLocal = local.isEmpty ? 'user' : local;
    final safeDomain = domain.isEmpty ? 'bedrijf' : domain;
    return '$safeLocal@$safeDomain.be';
  }

  static String _ensureUniqueEmail(String email, Set<String> usedEmails) {
    var candidate = email;
    var counter = 2;
    while (usedEmails.contains(candidate)) {
      final parts = candidate.split('@');
      final local = parts.first;
      final domain = parts.length > 1 ? parts[1] : 'bedrijf.be';
      candidate = '$local$counter@$domain';
      counter += 1;
    }
    usedEmails.add(candidate);
    return candidate;
  }
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
    required String address,
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
          'businessNumber': businessNumber.trim(),
          'address': address.trim(),
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
    final response = await http.post(
      _identityUri('/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'password',
        'username': email.trim().toLowerCase(),
        'password': password,
      },
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
      return <String, dynamic>{};
    }
    throw Exception(_extractErrorMessage(response.body, 'Inloggen mislukt.'));
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
    return _extractErrorMessage(
      response.body,
      'Reset-mail versturen mislukt.',
    );
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

  static String _extractErrorMessage(String raw, String fallback) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        final direct = decoded['error_description'] ??
            decoded['error'] ??
            decoded['message'];
        if (direct != null && direct.toString().trim().isNotEmpty) {
          return direct.toString();
        }
      }
      if (decoded is String && decoded.trim().isNotEmpty) return decoded;
    } catch (_) {}
    return fallback;
  }
}

class ScheduleStore {
  static final List<TeamAssignment> scheduled = [];
}

class PlanningOrderStore {
  static final Map<String, List<String>> orderByDay = {};

  static String _keyFor(String team, DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$team|$y-$m-$d';
  }

  static List<String> orderFor(String team, DateTime day) {
    final key = _keyFor(team, day);
    return List<String>.from(orderByDay[key] ?? const []);
  }

  static void setOrder(String team, DateTime day, List<String> projects) {
    final key = _keyFor(team, day);
    orderByDay[key] = List<String>.from(projects);
  }
}

abstract class DataRepository {
  Future<void> init();
  Future<Map<String, dynamic>?> read();
  Future<void> write(Map<String, dynamic> data);
}

class JsonFileRepository implements DataRepository {
  JsonFileRepository(this.fileName);

  final String fileName;
  File? _file;

  @override
  Future<void> init() async {
    _file ??= await _dataFile();
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    final file = _file ?? await _dataFile();
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    final file = _file ?? await _dataFile();
    await file.writeAsString(jsonEncode(data));
  }

  Future<File> _dataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }
}

class HiveRepository implements DataRepository {
  HiveRepository(this.boxName);

  final String boxName;
  Box<String>? _box;

  @override
  Future<void> init() async {
    if (_box != null) return;
    final dir = await getApplicationDocumentsDirectory();
    Hive.init(dir.path);
    _box = await Hive.openBox<String>(boxName);
  }

  @override
  Future<Map<String, dynamic>?> read() async {
    final box = _box ?? await Hive.openBox<String>(boxName);
    final raw = box.get('data');
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  @override
  Future<void> write(Map<String, dynamic> data) async {
    final box = _box ?? await Hive.openBox<String>(boxName);
    await box.put('data', jsonEncode(data));
  }
}

class AppDataStore {
  static const String _fileName = 'timetable_data.json';
  static bool hasStoredData = false;
  static int _projectResetVersion = 0;
  static const int _targetProjectResetVersion = 3;
  static Timer? _saveTimer;
  static bool _isSaving = false;
  static final DataRepository _primaryRepository =
      HiveRepository('timetable_db');
  static final DataRepository _fallbackRepository =
      JsonFileRepository(_fileName);

  static Future<void> init() async {
    await _primaryRepository.init();
    await _fallbackRepository.init();
    Map<String, dynamic>? data;
    try {
      data = await _primaryRepository.read();
    } catch (_) {
      data = null;
    }
    if (data == null || data.isEmpty) {
      final fallback = await _fallbackRepository.read();
      if (fallback != null && fallback.isNotEmpty) {
        _import(fallback);
        hasStoredData = true;
        await _primaryRepository.write(_export());
      }
    } else {
      _import(data);
      hasStoredData = true;
    }
    OfferCatalogStore.seedIfEmpty();
    if (!hasStoredData) {
      _RoleManagementStore.seedIfEmpty();
    }
    final didSeedAuth = AuthStore.seedIfEmpty();
    if (didSeedAuth) {
      scheduleSave();
    }
    final hasAnyProjects = ProjectStore.projectsByGroup.values.any(
      (group) => group.values.any((list) => list.isNotEmpty),
    );
    if (_projectResetVersion < _targetProjectResetVersion) {
      ProjectStore.clearAllProjects();
      ProjectStore.seedIfEmpty();
      _projectResetVersion = _targetProjectResetVersion;
      scheduleSave();
    } else if (!hasStoredData || !hasAnyProjects) {
      ProjectStore.seedIfEmpty();
      scheduleSave();
    } else {
      _normalizeScheduledDurations();
    }
  }

  static void scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), () {
      save();
    });
  }

  static Future<void> save() async {
    if (_isSaving) return;
    _isSaving = true;
    try {
      final data = _export();
      await _primaryRepository.write(data);
      await _fallbackRepository.write(data);
      hasStoredData = true;
    } finally {
      _isSaving = false;
    }
  }

  static void _normalizeScheduledDurations() {
    var changed = false;
    for (int i = 0; i < ScheduleStore.scheduled.length; i++) {
      final assignment = ScheduleStore.scheduled[i];
      if (assignment.isBackorder) continue;
      final clamped = _clampScheduledDays(assignment.estimatedDays);
      if (clamped != assignment.estimatedDays) {
        final start = _normalizeDateOnly(assignment.startDate);
        final end = _endDateFromWorkingDays(start, clamped, assignment.team);
        ScheduleStore.scheduled[i] = TeamAssignment(
          project: assignment.project,
          team: assignment.team,
          startDate: start,
          endDate: end,
          estimatedDays: clamped,
          isBackorder: assignment.isBackorder,
          group: assignment.group,
        );
        changed = true;
      }
      final details = ProjectStore.details[assignment.project];
      if (details != null && details.estimatedDays != clamped) {
        ProjectStore.details[assignment.project] = ProjectDetails(
          address: details.address,
          phone: details.phone,
          delivery: details.delivery,
          finish: details.finish,
          extraNotes: details.extraNotes,
          estimatedDays: clamped,
        );
        changed = true;
      }
    }
    if (changed) {
      scheduleSave();
    }
  }

  static Map<String, dynamic> _export() {
    return {
      'projectsByGroup': ProjectStore.projectsByGroup.map(
        (group, statuses) => MapEntry(
          group,
          statuses.map(
            (status, list) => MapEntry(status, List<String>.from(list)),
          ),
        ),
      ),
      'creators': Map<String, String>.from(ProjectStore.creators),
      'details': ProjectStore.details.map(
        (name, details) => MapEntry(name, _detailsToJson(details)),
      ),
      'comments': ProjectStore.comments.map(
        (name, list) => MapEntry(name, List<String>.from(list)),
      ),
      'beforePhotos': ProjectStore.beforePhotos.map(
        (name, files) =>
            MapEntry(name, files.map(_fileToJson).toList()),
      ),
      'afterPhotos': ProjectStore.afterPhotos.map(
        (name, files) =>
            MapEntry(name, files.map(_fileToJson).toList()),
      ),
      'extraWorks': ProjectStore.extraWorks.map(
        (name, entries) =>
            MapEntry(name, entries.map(_extraWorkToJson).toList()),
      ),
      'backorderItems': ProjectStore.backorderItems.map(
        (name, list) => MapEntry(name, List<String>.from(list)),
      ),
      'backorderHours': Map<String, double>.from(ProjectStore.backorderHours),
      'backorderNotes': Map<String, String>.from(ProjectStore.backorderNotes),
      'isBackorder': Map<String, bool>.from(ProjectStore.isBackorder),
      'offers': ProjectStore.offers.map(
        (name, lines) =>
            MapEntry(name, lines.map(_offerLineToJson).toList()),
      ),
      'documents': ProjectStore.documents.map(
        (name, docs) =>
            MapEntry(name, docs.map(_projectDocumentToJson).toList()),
      ),
      'completionTeams':
          Map<String, String>.from(ProjectStore.completionTeams),
      'workLogs': ProjectStore.workLogs.map(
        (name, entries) =>
            MapEntry(name, entries.map(_workDayToJson).toList()),
      ),
      'projectLogs': ProjectLogStore.logs.map(
        (name, entries) =>
            MapEntry(name, entries.map(_projectLogEntryToJson).toList()),
      ),
      'offerRequests':
          OfferRequestStore.requests.map(_offerRequestToJson).toList(),
      'estimatedDayRequests': EstimatedDaysChangeStore.requests
          .map(_estimatedDaysRequestToJson)
          .toList(),
      'invoiceRecords': InvoiceStore.records.map(
        (project, record) => MapEntry(project, _invoiceRecordToJson(record)),
      ),
      'schedule': ScheduleStore.scheduled.map(_assignmentToJson).toList(),
      'profileDocs': ProfileDocumentStore.documentsByUser.map(
        (name, docs) =>
            MapEntry(name, docs.map(_profileDocumentToJson).toList()),
      ),
      'leaveRequests':
          LeaveRequestStore.requests.map(_leaveRequestToJson).toList(),
      'holidays':
          PlanningCalendarStore.holidays.map(_dateToString).toList(),
      'vacations':
          PlanningCalendarStore.vacations.map(_dateToString).toList(),
      'dayOrders': PlanningOrderStore.orderByDay.map(
        (key, value) => MapEntry(key, List<String>.from(value)),
      ),
      'roles': _RoleManagementStore.assignments
          .map(_roleAssignmentToJson)
          .toList(),
      'teams': _RoleManagementStore.teams
          .map(_teamAssignmentToJson)
          .toList(),
      'offerCatalog':
          OfferCatalogStore.categories.map(_offerCategoryToJson).toList(),
      'authUsers': AuthStore.users.map(_authUserToJson).toList(),
      'companyProfiles':
          AuthStore.companies.values.map(_companyProfileToJson).toList(),
      'projectResetVersion': _projectResetVersion,
    };
  }

  static void _import(Map<String, dynamic> data) {
    ProjectStore.projectsByGroup
      ..clear()
      ..addAll(_mapGroups(data['projectsByGroup']));
    ProjectStore.creators
      ..clear()
      ..addAll(_stringMap(data['creators']));
    ProjectStore.details
      ..clear()
      ..addAll(_detailsMap(data['details']));
    ProjectStore.comments
      ..clear()
      ..addAll(_stringListMap(data['comments']));
    ProjectStore.beforePhotos
      ..clear()
      ..addAll(_fileListMap(data['beforePhotos']));
    ProjectStore.afterPhotos
      ..clear()
      ..addAll(_fileListMap(data['afterPhotos']));
    ProjectStore.extraWorks
      ..clear()
      ..addAll(_extraWorkMap(data['extraWorks']));
    ProjectStore.backorderItems
      ..clear()
      ..addAll(_stringListMap(data['backorderItems']));
    ProjectStore.backorderHours
      ..clear()
      ..addAll(_doubleMap(data['backorderHours']));
    ProjectStore.backorderNotes
      ..clear()
      ..addAll(_stringMap(data['backorderNotes']));
    ProjectStore.isBackorder
      ..clear()
      ..addAll(_boolMap(data['isBackorder']));
    ProjectStore.offers
      ..clear()
      ..addAll(_offerMap(data['offers']));
    ProjectStore.documents
      ..clear()
      ..addAll(_projectDocumentMap(data['documents']));
    ProjectStore.completionTeams
      ..clear()
      ..addAll(_stringMap(data['completionTeams']));
    ProjectStore.workLogs
      ..clear()
      ..addAll(_workLogMap(data['workLogs']));
    ProjectLogStore.logs
      ..clear()
      ..addAll(_projectLogMap(data['projectLogs']));
    OfferRequestStore.requests
      ..clear()
      ..addAll(_offerRequestList(data['offerRequests']));
    EstimatedDaysChangeStore.requests
      ..clear()
      ..addAll(_estimatedDaysRequestList(data['estimatedDayRequests']));
    InvoiceStore.records
      ..clear()
      ..addAll(_invoiceRecordMap(data['invoiceRecords']));
    ScheduleStore.scheduled
      ..clear()
      ..addAll(_scheduleList(data['schedule']));
    ProfileDocumentStore.documentsByUser
      ..clear()
      ..addAll(_profileDocumentMap(data['profileDocs']));
    LeaveRequestStore.requests
      ..clear()
      ..addAll(_leaveRequestsList(data['leaveRequests']));
    PlanningCalendarStore.holidays
      ..clear()
      ..addAll(_dateSet(data['holidays']));
    PlanningCalendarStore.vacations
      ..clear()
      ..addAll(_dateSet(data['vacations']));
    PlanningOrderStore.orderByDay
      ..clear()
      ..addAll(_stringListMap(data['dayOrders']));
    _RoleManagementStore.assignments =
        _roleAssignmentsList(data['roles']);
    _RoleManagementStore.teams =
        _teamAssignmentsList(data['teams']);
    final catalog = _offerCatalogList(data['offerCatalog']);
    if (catalog.isNotEmpty) {
      OfferCatalogStore.categories
        ..clear()
        ..addAll(catalog);
      OfferCatalogStore.markSeeded();
    }
    AuthStore.users
      ..clear()
      ..addAll(_authUserList(data['authUsers']));
    AuthStore.companies
      ..clear()
      ..addAll(_companyProfileMap(data['companyProfiles']));
    _projectResetVersion = (data['projectResetVersion'] as num?)?.toInt() ?? 0;
    ProjectStore.markSeeded();
  }

  static Map<String, Map<String, List<String>>> _mapGroups(dynamic value) {
    if (value is! Map) return {};
    final output = <String, Map<String, List<String>>>{};
    value.forEach((groupKey, statusValue) {
      if (statusValue is! Map) return;
      final statuses = <String, List<String>>{};
      statusValue.forEach((statusKey, listValue) {
        statuses[statusKey.toString()] =
            (listValue as List?)?.map((e) => e.toString()).toList() ??
                <String>[];
      });
      output[groupKey.toString()] = statuses;
    });
    return output;
  }

  static Map<String, String> _stringMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(key.toString(), val?.toString() ?? ''),
    );
  }

  static Map<String, bool> _boolMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(key.toString(), val == true),
    );
  }

  static Map<String, double> _doubleMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(key.toString(), (val as num?)?.toDouble() ?? 0),
    );
  }

  static Map<String, List<String>> _stringListMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        (val as List?)?.map((e) => e.toString()).toList() ?? <String>[],
      ),
    );
  }

  static Map<String, ProjectDetails> _detailsMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        _detailsFromJson(val as Map? ?? {}),
      ),
    );
  }

  static Map<String, List<PlatformFile>> _fileListMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        (val as List?)
                ?.map((e) => _fileFromJson(e as Map? ?? {}))
                .toList() ??
            <PlatformFile>[],
      ),
    );
  }

  static Map<String, List<ExtraWorkEntry>> _extraWorkMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        (val as List?)
                ?.map((e) => _extraWorkFromJson(e as Map? ?? {}))
                .toList() ??
            <ExtraWorkEntry>[],
      ),
    );
  }

  static Map<String, List<OfferLine>> _offerMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        (val as List?)
                ?.map((e) => _offerLineFromJson(e as Map? ?? {}))
                .toList() ??
            <OfferLine>[],
      ),
    );
  }

  static Map<String, List<ProjectDocument>> _projectDocumentMap(
    dynamic value,
  ) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        (val as List?)
                ?.map((e) => _projectDocumentFromJson(e as Map? ?? {}))
                .toList() ??
            <ProjectDocument>[],
      ),
    );
  }

  static Map<String, List<WorkDayEntry>> _workLogMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        (val as List?)
                ?.map((e) => _workDayFromJson(e as Map? ?? {}))
                .toList() ??
            <WorkDayEntry>[],
      ),
    );
  }

  static Map<String, List<ProjectLogEntry>> _projectLogMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        (val as List?)
                ?.map((e) => _projectLogEntryFromJson(e as Map? ?? {}))
                .toList() ??
            <ProjectLogEntry>[],
      ),
    );
  }

  static List<TeamAssignment> _scheduleList(dynamic value) {
    if (value is! List) return <TeamAssignment>[];
    return value
        .map((e) => _assignmentFromJson(e as Map? ?? {}))
        .toList();
  }

  static Map<String, List<DocumentEntry>> _profileDocumentMap(
    dynamic value,
  ) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        (val as List?)
                ?.map((e) => _profileDocumentFromJson(e as Map? ?? {}))
                .toList() ??
            <DocumentEntry>[],
      ),
    );
  }

  static List<LeaveRequest> _leaveRequestsList(dynamic value) {
    if (value is! List) return <LeaveRequest>[];
    return value
        .map((e) => _leaveRequestFromJson(e as Map? ?? {}))
        .toList();
  }

  static LinkedHashSet<DateTime> _dateSet(dynamic value) {
    if (value is! List) {
      return LinkedHashSet<DateTime>(
        equals: isSameDay,
        hashCode: _dayHashCode,
      );
    }
    final set = LinkedHashSet<DateTime>(
      equals: isSameDay,
      hashCode: _dayHashCode,
    );
    for (final item in value) {
      if (item is String) {
        final parsed = DateTime.tryParse(item);
        if (parsed != null) {
          set.add(DateTime(parsed.year, parsed.month, parsed.day));
        }
      }
    }
    return set;
  }

  static List<_RoleAssignment> _roleAssignmentsList(dynamic value) {
    if (value is! List) return <_RoleAssignment>[];
    return value
        .map((e) => _roleAssignmentFromJson(e as Map? ?? {}))
        .toList();
  }

  static List<_TeamAssignment> _teamAssignmentsList(dynamic value) {
    if (value is! List) return <_TeamAssignment>[];
    return value
        .map((e) => _teamAssignmentFromJson(e as Map? ?? {}))
        .toList();
  }

  static List<OfferRequest> _offerRequestList(dynamic value) {
    if (value is! List) return <OfferRequest>[];
    return value
        .map((e) => _offerRequestFromJson(e as Map? ?? {}))
        .toList();
  }

  static List<EstimatedDaysChangeRequest> _estimatedDaysRequestList(
    dynamic value,
  ) {
    if (value is! List) return <EstimatedDaysChangeRequest>[];
    return value
        .map((e) => _estimatedDaysRequestFromJson(e as Map? ?? {}))
        .toList();
  }

  static Map<String, InvoiceRecord> _invoiceRecordMap(dynamic value) {
    if (value is! Map) return {};
    return value.map(
      (key, val) => MapEntry(
        key.toString(),
        _invoiceRecordFromJson(val as Map? ?? {}),
      ),
    );
  }

  static List<OfferCategory> _offerCatalogList(dynamic value) {
    if (value is! List) return <OfferCategory>[];
    return value
        .map((e) => _offerCategoryFromJson(e as Map? ?? {}))
        .toList();
  }

  static List<AuthUser> _authUserList(dynamic value) {
    if (value is! List) return <AuthUser>[];
    return value
        .map((e) => _authUserFromJson(e as Map? ?? {}))
        .toList();
  }

  static Map<String, CompanyProfile> _companyProfileMap(dynamic value) {
    if (value is! List) return {};
    final map = <String, CompanyProfile>{};
    for (final raw in value) {
      if (raw is! Map) continue;
      final profile = _companyProfileFromJson(raw);
      map[profile.name.trim().toLowerCase()] = profile;
    }
    return map;
  }

  static Map<String, dynamic> _detailsToJson(ProjectDetails details) => {
        'address': details.address,
        'phone': details.phone,
        'delivery': details.delivery,
        'finish': details.finish,
        'extraNotes': details.extraNotes,
        'estimatedDays': details.estimatedDays,
      };

  static ProjectDetails _detailsFromJson(Map data) => ProjectDetails(
        address: data['address']?.toString() ?? '',
        phone: data['phone']?.toString() ?? '',
        delivery: data['delivery']?.toString() ?? '',
        finish: data['finish']?.toString() ?? '',
        extraNotes: data['extraNotes']?.toString() ?? '',
        estimatedDays: (data['estimatedDays'] as num?)?.toInt() ?? 1,
      );

  static Map<String, dynamic> _fileToJson(PlatformFile file) {
    final rawBytes = file.bytes ?? _readFileBytes(file.path);
    return {
      'name': file.name,
      'path': file.path,
      'size': file.size,
      'extension': file.extension,
      'bytes': rawBytes != null ? base64Encode(rawBytes) : null,
    };
  }

  static List<int>? _readFileBytes(String? path) {
    if (path == null || path.isEmpty) return null;
    try {
      return File(path).readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  static PlatformFile _fileFromJson(Map data) {
    final bytes = data['bytes'] != null
        ? base64Decode(data['bytes'].toString())
        : null;
    final size = (data['size'] as num?)?.toInt() ?? (bytes?.length ?? 0);
    return PlatformFile(
      name: data['name']?.toString() ?? 'bestand',
      size: size,
      path: data['path']?.toString(),
      bytes: bytes,
    );
  }

  static Map<String, dynamic> _offerLineToJson(OfferLine line) => {
        'category': line.category,
        'item': line.item,
        'quantity': line.quantity,
      };

  static OfferLine _offerLineFromJson(Map data) => OfferLine(
        category: data['category']?.toString() ?? '',
        item: data['item']?.toString() ?? '',
        quantity: (data['quantity'] as num?)?.toInt() ?? 0,
      );

  static Map<String, dynamic> _projectDocumentToJson(ProjectDocument doc) => {
        'description': doc.description,
        'file': _fileToJson(doc.file),
      };

  static ProjectDocument _projectDocumentFromJson(Map data) =>
      ProjectDocument(
        description: data['description']?.toString() ?? '',
        file: _fileFromJson(data['file'] as Map? ?? {}),
      );

  static Map<String, dynamic> _profileDocumentToJson(DocumentEntry doc) => {
        'description': doc.description,
        'expiry': doc.expiry.toIso8601String(),
        'file': _fileToJson(doc.file),
      };

  static DocumentEntry _profileDocumentFromJson(Map data) => DocumentEntry(
        description: data['description']?.toString() ?? '',
        expiry: DateTime.tryParse(data['expiry']?.toString() ?? '') ??
            DateTime.now(),
        file: _fileFromJson(data['file'] as Map? ?? {}),
      );

  static Map<String, dynamic> _extraWorkToJson(ExtraWorkEntry entry) => {
        'description': entry.description,
        'hours': entry.hours,
        'chargeType': entry.chargeType,
        'photos': entry.photos.map(_fileToJson).toList(),
      };

  static ExtraWorkEntry _extraWorkFromJson(Map data) => ExtraWorkEntry(
        description: data['description']?.toString() ?? '',
        hours: (data['hours'] as num?)?.toDouble() ?? 0,
        chargeType: data['chargeType']?.toString() ?? 'Klant',
        photos: (data['photos'] as List?)
                ?.map((e) => _fileFromJson(e as Map? ?? {}))
                .toList() ??
            <PlatformFile>[],
      );

  static Map<String, dynamic> _workDayToJson(WorkDayEntry entry) => {
        'date': entry.date.toIso8601String(),
        'startMinutes': entry.startMinutes,
        'endMinutes': entry.endMinutes,
        'breakMinutes': entry.breakMinutes,
        'workers': entry.workers,
      };

  static WorkDayEntry _workDayFromJson(Map data) => WorkDayEntry(
        date: DateTime.tryParse(data['date']?.toString() ?? '') ??
            DateTime.now(),
        startMinutes: (data['startMinutes'] as num?)?.toInt() ?? 0,
        endMinutes: (data['endMinutes'] as num?)?.toInt() ?? 0,
        breakMinutes: (data['breakMinutes'] as num?)?.toInt() ?? 0,
        workers: (data['workers'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            <String>[],
      );

  static Map<String, dynamic> _assignmentToJson(TeamAssignment assignment) => {
        'project': assignment.project,
        'team': assignment.team,
        'startDate': assignment.startDate.toIso8601String(),
        'endDate': assignment.endDate.toIso8601String(),
        'estimatedDays': assignment.estimatedDays,
        'isBackorder': assignment.isBackorder,
        'group': assignment.group,
      };

  static TeamAssignment _assignmentFromJson(Map data) => TeamAssignment(
        project: data['project']?.toString() ?? '',
        team: data['team']?.toString() ?? '',
        startDate: DateTime.tryParse(data['startDate']?.toString() ?? '') ??
            DateTime.now(),
        endDate: DateTime.tryParse(data['endDate']?.toString() ?? '') ??
            DateTime.now(),
        estimatedDays: (data['estimatedDays'] as num?)?.toInt() ?? 1,
        isBackorder: data['isBackorder'] == true,
        group: data['group']?.toString() ?? 'Klanten',
      );

  static Map<String, dynamic> _leaveRequestToJson(LeaveRequest request) => {
        'requester': request.requester,
        'role': request.role,
        'from': request.from.toIso8601String(),
        'to': request.to.toIso8601String(),
        'reason': request.reason,
        'status': request.status,
      };

  static LeaveRequest _leaveRequestFromJson(Map data) => LeaveRequest(
        requester: data['requester']?.toString() ?? '',
        role: data['role']?.toString() ?? '',
        from: DateTime.tryParse(data['from']?.toString() ?? '') ??
            DateTime.now(),
        to: DateTime.tryParse(data['to']?.toString() ?? '') ??
            DateTime.now(),
        reason: data['reason']?.toString() ?? '',
        status: data['status']?.toString() ?? 'In afwachting',
      );

  static Map<String, dynamic> _offerRequestToJson(OfferRequest request) => {
        'project': request.project,
        'requester': request.requester,
        'createdAt': request.createdAt.toIso8601String(),
        'note': request.note,
      };

  static OfferRequest _offerRequestFromJson(Map data) => OfferRequest(
        project: data['project']?.toString() ?? '',
        requester: data['requester']?.toString() ?? '',
        createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        note: data['note']?.toString() ?? '',
      );

  static Map<String, dynamic> _estimatedDaysRequestToJson(
    EstimatedDaysChangeRequest request,
  ) =>
      {
        'project': request.project,
        'team': request.team,
        'oldDays': request.oldDays,
        'newDays': request.newDays,
        'requester': request.requester,
        'requesterRole': request.requesterRole,
        'createdAt': request.createdAt.toIso8601String(),
        'status': request.status,
      };

  static EstimatedDaysChangeRequest _estimatedDaysRequestFromJson(Map data) =>
      EstimatedDaysChangeRequest(
        project: data['project']?.toString() ?? '',
        team: data['team']?.toString() ?? '',
        oldDays: (data['oldDays'] as num?)?.toInt() ?? 1,
        newDays: (data['newDays'] as num?)?.toInt() ?? 1,
        requester: data['requester']?.toString() ?? '',
        requesterRole: data['requesterRole']?.toString() ?? '',
        createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
            DateTime.now(),
        status: data['status']?.toString() ?? 'In afwachting',
      );

  static Map<String, dynamic> _invoiceRecordToJson(InvoiceRecord record) => {
        'offerBilled': record.offerBilled,
        'extraHoursBilled': record.extraHoursBilled,
      };

  static InvoiceRecord _invoiceRecordFromJson(Map data) => InvoiceRecord(
        offerBilled: data['offerBilled'] == true,
        extraHoursBilled: (data['extraHoursBilled'] as num?)?.toDouble() ?? 0,
      );

  static Map<String, dynamic> _projectLogEntryToJson(
    ProjectLogEntry entry,
  ) =>
      {
        'timestamp': entry.timestamp.toIso8601String(),
        'user': entry.user,
        'role': entry.role,
        'message': entry.message,
      };

  static ProjectLogEntry _projectLogEntryFromJson(Map data) => ProjectLogEntry(
        timestamp: DateTime.tryParse(data['timestamp']?.toString() ?? '') ??
            DateTime.now(),
        user: data['user']?.toString() ?? '',
        role: data['role']?.toString() ?? '',
        message: data['message']?.toString() ?? '',
      );

  static Map<String, dynamic> _offerCategoryToJson(OfferCategory category) => {
        'name': category.name,
        'items': category.items.map(_offerItemToJson).toList(),
      };

  static OfferCategory _offerCategoryFromJson(Map data) => OfferCategory(
        name: data['name']?.toString() ?? '',
        items: (data['items'] as List?)
                ?.map((e) => _offerItemFromJson(e as Map? ?? {}))
                .toList() ??
            <OfferItem>[],
      );

  static Map<String, dynamic> _offerItemToJson(OfferItem item) => {
        'name': item.name,
        'price': item.price,
        'unit': item.unit,
        'hours': item.hours,
      };

  static OfferItem _offerItemFromJson(Map data) => OfferItem(
        name: data['name']?.toString() ?? '',
        price: (data['price'] as num?)?.toDouble() ?? 0,
        unit: data['unit']?.toString() ?? '',
        hours: (data['hours'] as num?)?.toDouble(),
      );

  static Map<String, dynamic> _authUserToJson(AuthUser user) => {
        'name': user.name,
        'email': user.email,
        'company': user.company,
        'passwordHash': user.passwordHash,
        'passwordSalt': user.passwordSalt,
        'role': user.role,
        'team': user.team,
      };

  static AuthUser _authUserFromJson(Map data) => AuthUser(
        name: data['name']?.toString() ?? '',
        email: data['email']?.toString() ?? '',
        company: data['company']?.toString() ?? '',
        passwordHash: data['passwordHash']?.toString() ?? '',
        passwordSalt: data['passwordSalt']?.toString() ?? '',
        role: data['role']?.toString() ?? 'Beheerder',
        team: data['team']?.toString(),
      );

  static Map<String, dynamic> _companyProfileToJson(CompanyProfile company) => {
        'name': company.name,
        'businessNumber': company.businessNumber,
        'address': company.address,
        'adminName': company.adminName,
        'adminEmail': company.adminEmail,
        'createdAt': company.createdAt.toIso8601String(),
      };

  static CompanyProfile _companyProfileFromJson(Map data) => CompanyProfile(
        name: data['name']?.toString() ?? '',
        businessNumber: data['businessNumber']?.toString() ?? '',
        address: data['address']?.toString() ?? '',
        adminName: data['adminName']?.toString() ?? '',
        adminEmail: data['adminEmail']?.toString() ?? '',
        createdAt: DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
            DateTime.now(),
      );

  static String _dateToString(DateTime date) =>
      DateTime(date.year, date.month, date.day).toIso8601String();

  static Map<String, dynamic> _roleAssignmentToJson(
    _RoleAssignment assignment,
  ) =>
      {
        'name': assignment.name,
        'email': assignment.email,
        'role': assignment.role,
        'contractor': assignment.contractor,
        'team': assignment.team,
      };

  static _RoleAssignment _roleAssignmentFromJson(Map data) => _RoleAssignment(
        name: data['name']?.toString() ?? '',
        email: data['email']?.toString() ?? '',
        role: data['role']?.toString() ?? '',
        contractor: data['contractor']?.toString(),
        team: data['team']?.toString(),
      );

  static Map<String, dynamic> _teamAssignmentToJson(_TeamAssignment team) => {
        'name': team.name,
        'contractor': team.contractor,
        'workingDays': team.workingDays.toList(),
      };

  static _TeamAssignment _teamAssignmentFromJson(Map data) => _TeamAssignment(
        name: data['name']?.toString() ?? '',
        contractor: data['contractor']?.toString() ?? '',
        workingDays: (data['workingDays'] as List?)
                ?.map((e) => (e as num).toInt())
                .toSet() ??
            _RoleManagementStore._defaultWorkingDays,
      );
}

bool _isExternalRole(String role) {
  return role == 'Onderaannemer' ||
      role == 'Onderaannemer beheerder' ||
      role == 'Werknemer';
}

bool _canSeeOfferPrices(String role) {
  return role == 'Beheerder' ||
      role == 'Onderaannemer' ||
      role == 'Onderaannemer beheerder';
}

bool _canSeeOfferHours(String role) {
  return role == 'Onderaannemer' ||
      role == 'Onderaannemer beheerder' ||
      role == 'Werknemer';
}

List<String> _teamsForCurrentUser() {
  final role = CurrentUserStore.role;
  if (role == 'Werknemer') {
    return CurrentUserStore.team.isEmpty ? [] : [CurrentUserStore.team];
  }
  if (role == 'Onderaannemer' || role == 'Onderaannemer beheerder') {
    final contractor = CurrentUserStore.contractor;
    if (contractor.isEmpty) return [];
    return _RoleManagementStore.teams
        .where((team) => team.contractor == contractor)
        .map((team) => team.name)
        .toList();
  }
  return [];
}

class TestAccount {
  const TestAccount({
    required this.name,
    required this.role,
    required this.company,
    this.email = '',
    this.team,
  });

  final String name;
  final String role;
  final String company;
  final String email;
  final String? team;
}

const _projectGroups = ['Klanten', 'Nabestellingen'];

const _statusStages = [
  'In opmaak',
  'In bestelling',
  'Geleverd',
  'Ingepland',
  'Afgewerkt',
];

const _editableStatusStages = [
  'In opmaak',
  'In bestelling',
  'Geleverd',
];

const _extraWorkChargeTypes = [
  'Klant',
  'Interne fout',
];

const _roleOptions = [
  'Beheerder',
  'Planner',
  'Administratie',
  'Boekhouding',
  'Projectleider',
  'Onderaannemer',
  'Onderaannemer beheerder',
  'Team',
  'Werknemer',
];

const _adminRoles = [
  'Beheerder',
  'Planner',
  'Administratie',
  'Boekhouding',
  'Projectleider',
];

const _practicalRoles = [
  'Onderaannemer',
  'Onderaannemer beheerder',
  'Team',
  'Werknemer',
];

class OfferLine {
  const OfferLine({
    required this.category,
    required this.item,
    required this.quantity,
  });

  final String category;
  final String item;
  final int quantity;
}

class ProjectDocument {
  const ProjectDocument({
    required this.description,
    required this.file,
  });

  final String description;
  final PlatformFile file;
}

class WorkDayEntry {
  WorkDayEntry({
    required this.date,
    required this.startMinutes,
    required this.endMinutes,
    required this.breakMinutes,
    required this.workers,
  });

  DateTime date;
  int startMinutes;
  int endMinutes;
  int breakMinutes;
  List<String> workers;
}

class OfferItem {
  OfferItem({
    required this.name,
    required this.price,
    required this.unit,
    this.hours,
  });

  String name;
  double price;
  String unit;
  double? hours;
}

class OfferCategory {
  OfferCategory({
    required this.name,
    List<OfferItem>? items,
  }) : items = items ?? [];

  String name;
  final List<OfferItem> items;
}

class OfferCatalogStore {
  static final List<OfferCategory> categories = [];
  static bool _seeded = false;

  static void seedIfEmpty() {
    if (_seeded) return;
    if (categories.isEmpty) {
      categories.addAll([
        OfferCategory(
          name: 'Demontage',
          items: [
            OfferItem(name: 'Tot 100 kg', price: 55, unit: 'stuk', hours: 1.5),
            OfferItem(
              name: '100 tot 200 kg',
              price: 80,
              unit: 'stuk',
              hours: 2,
            ),
            OfferItem(
              name: '200 tot 300 kg',
              price: 125,
              unit: 'stuk',
              hours: 3.5,
            ),
          ],
        ),
        OfferCategory(
          name: 'Raam montage',
          items: [
            OfferItem(
              name: 'Tot 100 kg',
              price: 130,
              unit: 'stuk',
              hours: 3.5,
            ),
            OfferItem(
              name: '100 tot 150 kg',
              price: 160,
              unit: 'stuk',
              hours: 4.5,
            ),
            OfferItem(
              name: '150 tot 200 kg',
              price: 185,
              unit: 'stuk',
              hours: 5,
            ),
            OfferItem(
              name: '200 tot 300 kg',
              price: 270,
              unit: 'stuk',
              hours: 7,
            ),
          ],
        ),
        OfferCategory(
          name: 'Deur montage',
          items: [
            OfferItem(
              name: 'Enkele deur',
              price: 190,
              unit: 'stuk',
              hours: 5,
            ),
            OfferItem(
              name: 'Dubbele deur',
              price: 275,
              unit: 'stuk',
              hours: 7.5,
            ),
            OfferItem(
              name: 'Deur met koppeling met andere elementen',
              price: 400,
              unit: 'stuk',
              hours: 10,
            ),
          ],
        ),
        OfferCategory(
          name: 'Schuifraam montage',
          items: [
            OfferItem(
              name: 'Tot 200 kg',
              price: 270,
              unit: 'stuk',
              hours: 7.5,
            ),
            OfferItem(
              name: 'Boven 200 kg',
              price: 395,
              unit: 'stuk',
              hours: 11,
            ),
            OfferItem(
              name: 'Gedemonteerd geleverd',
              price: 120,
              unit: 'stuk',
              hours: 3.5,
            ),
          ],
        ),
        OfferCategory(
          name: 'Extra bevestiging van elementen',
          items: [
            OfferItem(
              name: 'Profielen (verbredingen, ventilatie, koppelprofiel)',
              price: 20,
              unit: 'stuk',
              hours: 0.5,
            ),
            OfferItem(
              name: 'Rolluiken, screens, schuifvliegenramen, plissee, vliegendeur, …',
              price: 50,
              unit: 'stuk',
              hours: 1.5,
            ),
            OfferItem(
              name: 'Aansluiting rolluik',
              price: 35,
              unit: 'stuk',
              hours: 1,
            ),
            OfferItem(
              name: 'Plaatsing sectionale poort',
              price: 500,
              unit: 'stuk',
              hours: 12,
            ),
            OfferItem(
              name: 'Plaatsing op verdiep (tot 5 stuks)',
              price: 105,
              unit: 'stuk',
              hours: 3,
            ),
          ],
        ),
        OfferCategory(
          name: 'Afwerking in MDF',
          items: [
            OfferItem(
              name: 'Omlijstingen + tablet (tot 5 m2)',
              price: 175,
              unit: 'stuk',
              hours: 3,
            ),
            OfferItem(
              name: 'Omlijstingen + tablet (boven 5 m2)',
              price: 270,
              unit: 'stuk',
              hours: 5,
            ),
            OfferItem(
              name: 'Gordijnbak (tot 3 m)',
              price: 70,
              unit: 'stuk',
              hours: 1.5,
            ),
            OfferItem(
              name: 'Gordijnbak (boven 3 m)',
              price: 115,
              unit: 'stuk',
              hours: 2,
            ),
            OfferItem(
              name: 'Rolluikbak (tot 3 m)',
              price: 135,
              unit: 'stuk',
              hours: 2.5,
            ),
            OfferItem(
              name: 'Rolluikbak (boven 3 m)',
              price: 205,
              unit: 'stuk',
              hours: 4,
            ),
            OfferItem(
              name: 'Rolluikbak geïsoleerd (tot 3 m)',
              price: 160,
              unit: 'stuk',
              hours: 3,
            ),
            OfferItem(
              name: 'Rolluikbak geïsoleerd (boven 3 m)',
              price: 250,
              unit: 'stuk',
              hours: 4.5,
            ),
          ],
        ),
        OfferCategory(
          name: 'Afwerking PVC',
          items: [
            OfferItem(
              name: 'Omlijsting (tot 2,5 m2)',
              price: 175,
              unit: 'stuk',
              hours: 3,
            ),
            OfferItem(
              name: 'Omlijsting (tot 5 m2)',
              price: 255,
              unit: 'stuk',
              hours: 4,
            ),
            OfferItem(
              name: 'Omlijsting (boven 5 m2)',
              price: 355,
              unit: 'stuk',
              hours: 5,
            ),
          ],
        ),
        OfferCategory(
          name: 'Afwerking pleister',
          items: [
            OfferItem(
              name: 'Omlijstingen (tot 2,5 m2)',
              price: 220,
              unit: 'stuk',
              hours: 4,
            ),
            OfferItem(
              name: 'Omlijstingen (tot 5 m2)',
              price: 500,
              unit: 'stuk',
              hours: 9,
            ),
            OfferItem(
              name: 'Rolluikbak pleisteren (tot 3 m)',
              price: 180,
              unit: 'stuk',
              hours: 3.5,
            ),
          ],
        ),
        OfferCategory(
          name: 'Siliconeren',
          items: [
            OfferItem(
              name: 'Transparant (voegbreedte maximaal 1 cm)',
              price: 5,
              unit: 'lm',
              hours: 0.1,
            ),
          ],
        ),
        OfferCategory(
          name: 'Extra km vergoeding (boven 100 km)',
          items: [
            OfferItem(
              name: 'Extra km',
              price: 1.5,
              unit: 'euro/km',
              hours: 0.04,
            ),
          ],
        ),
      ]);
    }
    _seeded = true;
  }

  static void markSeeded() {
    _seeded = true;
  }

  static void addCategory(String name) {
    if (name.trim().isEmpty) return;
    categories.add(OfferCategory(name: name.trim()));
    AppDataStore.scheduleSave();
  }

  static void addItem(String categoryName, OfferItem item) {
    final category =
        categories.firstWhere((entry) => entry.name == categoryName);
    category.items.add(item);
    AppDataStore.scheduleSave();
  }

  static OfferItem? findItem(String categoryName, String itemName) {
    for (final category in categories) {
      if (category.name != categoryName) continue;
      for (final item in category.items) {
        if (item.name == itemName) {
          return item;
        }
      }
    }
    return null;
  }
}

class ProjectStore {
  static bool _seeded = false;
  static final Map<String, Map<String, List<String>>> projectsByGroup = {
    'Klanten': {
      'In opmaak': [],
      'In bestelling': [],
      'Geleverd': [],
      'Ingepland': [],
      'Afgewerkt': [],
    },
    'Nabestellingen': {
      'In opmaak': [],
      'In bestelling': [],
      'Geleverd': [],
      'Ingepland': [],
      'Afgewerkt': [],
    },
  };

  static final Map<String, String> creators = {};

  static final Map<String, ProjectDetails> details = {};

  static final Map<String, List<String>> comments = {};
  static final Map<String, List<PlatformFile>> beforePhotos = {};
  static final Map<String, List<PlatformFile>> afterPhotos = {};
  static final Map<String, List<ExtraWorkEntry>> extraWorks = {};
  static final Map<String, List<String>> backorderItems = {};
  static final Map<String, double> backorderHours = {};
  static final Map<String, String> backorderNotes = {};
  static final Map<String, bool> isBackorder = {};
  static final Map<String, List<OfferLine>> offers = {};
  static final Map<String, List<ProjectDocument>> documents = {};
  static final Map<String, String> completionTeams = {};
  static final Map<String, List<WorkDayEntry>> workLogs = {};

  static void clearAllProjects() {
    _seeded = false;
    for (final groupEntry in projectsByGroup.values) {
      for (final list in groupEntry.values) {
        list.clear();
      }
    }
    creators.clear();
    details.clear();
    comments.clear();
    beforePhotos.clear();
    afterPhotos.clear();
    extraWorks.clear();
    backorderItems.clear();
    backorderHours.clear();
    backorderNotes.clear();
    isBackorder.clear();
    offers.clear();
    documents.clear();
    completionTeams.clear();
    workLogs.clear();
    ProjectLogStore.logs.clear();
    InvoiceStore.records.clear();
    EstimatedDaysChangeStore.requests.clear();
    OfferRequestStore.requests.clear();
    ScheduleStore.scheduled.clear();
  }

  static void seedIfEmpty() {
    final hasProjects = projectsByGroup.values.any(
      (group) => group.values.any((list) => list.isNotEmpty),
    );
    if (_seeded && hasProjects) return;
    if (hasProjects) {
      _seeded = true;
      return;
    }
    OfferCatalogStore.seedIfEmpty();
    ScheduleStore.scheduled.clear();
    final random = Random(42);
    final firstNames = [
      'Emma',
      'Liam',
      'Noah',
      'Olivia',
      'Mila',
      'Lucas',
      'Fleur',
      'Bram',
      'Lotte',
      'Jules',
      'Sarah',
      'Nora',
      'Kobe',
      'Elise',
      'Ruben',
      'Lea',
      'Arne',
      'Anouk',
      'Tibo',
      'Hanne',
      'Julie',
      'Aline',
      'Lore',
      'Senna',
      'Maud',
      'Xander',
      'Niels',
      'Sander',
      'Jasper',
      'Kaat',
    ];
    final lastNames = [
      'De Smet',
      'Peeters',
      'Maes',
      'Jacobs',
      'Mertens',
      'Claeys',
      'Willems',
      'Goossens',
      'Vandermeulen',
      'Lefebvre',
      'Dumont',
      'Vandenberghe',
      'Desmet',
      'Vermeulen',
      'De Bruyne',
      'Van den Broeck',
      'Pieters',
      'De Cock',
      'Van Damme',
      'Vermote',
      'De Clercq',
      'Van Acker',
      'Buyse',
      'Vandamme',
      'Huybrechts',
      'Lemaire',
      'Van den Abeele',
      'Van Hove',
      'Declercq',
      'Van Hulle',
    ];
    final streets = [
      'Kerkstraat',
      'Stationsstraat',
      'Nieuwstraat',
      'Molenstraat',
      'Schoolstraat',
      'Dorpstraat',
      'Zandstraat',
      'Hofstraat',
      'Bloemenlaan',
      'Parklaan',
      'Lindelaan',
      'Kouter',
      'Leopoldlaan',
      'Koningin Astridlaan',
      'Warandestraat',
      'Veldstraat',
      'Keizerslaan',
      'Bruggestraat',
      'Kapelstraat',
      'Hoogstraat',
      'Sint-Jansstraat',
      'Stationsplein',
      'Kasteelstraat',
      'Kruisstraat',
      'Boterstraat',
      'Meersstraat',
      'Ooststraat',
      'Westlaan',
    ];
    final cities = [
      'Gent',
      'Brugge',
      'Kortrijk',
      'Aalst',
      'Roeselare',
      'Oostende',
      'Sint-Niklaas',
      'Waregem',
      'Dendermonde',
      'Tielt',
      'Deinze',
      'Eeklo',
      'Izegem',
      'Harelbeke',
      'Ronse',
      'Geraardsbergen',
      'Zottegem',
      'Lokeren',
      'Wetteren',
      'Zelzate',
    ];
    final postalCodes = [
      '9000',
      '8000',
      '8500',
      '9300',
      '8800',
      '8400',
      '9100',
      '8790',
      '9200',
      '8700',
      '9800',
      '9900',
      '8870',
      '8530',
      '9600',
      '9500',
      '9620',
      '9160',
      '9230',
      '9060',
    ];
    final finishes = [
      'Afwerking PVC',
      'Afwerking in MDF',
      'Afwerking pleister',
      'Afwerking in MDF + tablet',
      'Afwerking PVC + dorpels',
      'Zonder afwerking',
    ];
    final plannerNotes = [
      'Let op: parkeerplaats beperkt.',
      'Klant vraagt extra bescherming vloer.',
      'Opletten met gordijnbakken.',
      'Klant wil afwerking dezelfde dag.',
      'Levering via zij-ingang.',
    ];
    final leaderNotes = [
      'Werf klaarzetten voor montage.',
      'Afwerking controleren met klant.',
      'Extra profielen voorzien.',
      'Schuifraam afstellen na montage.',
      'Nazicht siliconen na plaatsing.',
    ];
    final backorderPool = [
      'Extra profiel plaatsen',
      'Kader bijregelen',
      'Dorpel vervangen',
      'Afkitten raam',
      'Ventilatierooster plaatsen',
      'Rolluikbak afwerken',
      'Scharnieren bijstellen',
      'Extra glaslat toevoegen',
    ];
    final extraWorkPool = [
      'Extra dichtingsrubber geplaatst',
      'Afwerking binnenmuur aangepast',
      'Extra raamkader uitgelijnd',
      'Herstelling beschadigde dorpel',
      'Kleine bijwerking siliconen',
    ];
    final teams = ['Team 1', 'Team 2', 'Team 3', 'Team 4', 'Team 5'];
    final teamWorkers = {
      'Team 1': ['Ihor', 'Vova', 'Kiryl'],
      'Team 2': ['Vitaly', 'Bohdan', 'Vitaly Y'],
      'Team 3': ['Pavlo', 'Ruslan', 'Vadim'],
      'Team 4': ['Sergei', 'Dmitri', 'Oleg'],
      'Team 5': ['Anton', 'Nikita', 'Yuri'],
    };
    final teamNextDate = <String, DateTime>{
      for (final team in teams) team: _nextWorkingDayForTeam(DateTime.now(), team),
    };
    final teamLastEnd = <String, DateTime?>{
      for (final team in teams) team: null,
    };
    final regularDaysByTeam = <String, Set<DateTime>>{
      for (final team in teams) team: <DateTime>{},
    };
    final backorderDayCounts = <String, Map<DateTime, int>>{
      for (final team in teams) team: <DateTime, int>{},
    };

    PlatformFile dummyFile(String name) =>
        PlatformFile(name: name, size: 0, bytes: Uint8List(0));

    List<OfferLine> buildOfferLines(int seed) {
      final lines = <OfferLine>[];
      final count = 2 + (seed % 3);
      for (int i = 0; i < count; i++) {
        final category = OfferCatalogStore
            .categories[(seed + i) % OfferCatalogStore.categories.length];
        final item = category.items[(seed + i) % category.items.length];
        lines.add(
          OfferLine(
            category: category.name,
            item: item.name,
            quantity: 1 + ((seed + i) % 3),
          ),
        );
      }
      return lines;
    }

    String phoneFor(int seed) {
      final a = 470 + (seed % 20);
      final b = 10 + (seed % 80);
      final c = 20 + (seed % 70);
      final d = 30 + (seed % 60);
      return '0$a $b $c $d';
    }

    String customerName(int seed, {String suffix = ''}) {
      final first = firstNames[seed % firstNames.length];
      final last = lastNames[(seed ~/ firstNames.length) % lastNames.length];
      return suffix.isEmpty ? '$first $last' : '$first $last $suffix';
    }

    void addWorkLogs(String name, String team, int days) {
      final workers = teamWorkers[team] ?? [team];
      final startBase = _normalizeDateOnly(
        DateTime.now().subtract(Duration(days: 30 + (random.nextInt(150)))),
      );
      final entries = <WorkDayEntry>[];
      var current = startBase;
      var logged = 0;
      while (logged < days) {
        if (_isWorkingDayForTeam(current, team)) {
          entries.add(
            WorkDayEntry(
              date: _normalizeDateOnly(current),
              startMinutes: 7 * 60 + (logged % 2 == 0 ? 30 : 0),
              endMinutes: 16 * 60,
              breakMinutes: 30,
              workers: workers,
            ),
          );
          logged += 1;
        }
        current = current.add(const Duration(days: 1));
      }
      workLogs[name] = entries;
    }

    void addRegularSchedule(
      String name,
      String team,
      int plannedDays,
    ) {
      final lastEnd = teamLastEnd[team];
      DateTime baseStart = teamNextDate[team]!;
      if (lastEnd != null &&
          random.nextDouble() < 0.2 &&
          _isWorkingDayForTeam(lastEnd, team)) {
        baseStart = lastEnd;
      }
      final start = _nextWorkingDayForTeam(baseStart, team);
      final end = _endDateFromWorkingDays(start, plannedDays, team);
      ScheduleStore.scheduled.add(
        TeamAssignment(
          project: name,
          team: team,
          startDate: start,
          endDate: end,
          estimatedDays: plannedDays,
          isBackorder: false,
          group: 'Klanten',
        ),
      );
      var day = start;
      while (!day.isAfter(end)) {
        if (_isWorkingDayForTeam(day, team)) {
          regularDaysByTeam[team]!.add(_normalizeDateOnly(day));
        }
        day = day.add(const Duration(days: 1));
      }
      teamLastEnd[team] = end;
      teamNextDate[team] = end.add(const Duration(days: 1));
    }

    DateTime pickBackorderDay(String team) {
      for (int i = 0; i < 80; i++) {
        var candidate =
            DateTime.now().add(Duration(days: random.nextInt(90)));
        candidate = _nextWorkingDayForTeam(candidate, team);
        final normalized = _normalizeDateOnly(candidate);
        final regularBusy = regularDaysByTeam[team]!.contains(normalized);
        final max = regularBusy ? 2 : 4;
        final current = backorderDayCounts[team]![normalized] ?? 0;
        if (current < max) {
          backorderDayCounts[team]![normalized] = current + 1;
          return normalized;
        }
      }
      final fallback = _nextWorkingDayForTeam(DateTime.now(), team);
      backorderDayCounts[team]![fallback] =
          (backorderDayCounts[team]![fallback] ?? 0) + 1;
      return fallback;
    }

    DateTime pickClusterDay(String team) {
      for (int i = 0; i < 40; i++) {
        var candidate =
            DateTime.now().add(Duration(days: 15 + random.nextInt(60)));
        candidate = _nextWorkingDayForTeam(candidate, team);
        final normalized = _normalizeDateOnly(candidate);
        if (!regularDaysByTeam[team]!.contains(normalized)) {
          return normalized;
        }
      }
      return _nextWorkingDayForTeam(DateTime.now(), team);
    }

    final regularStatuses = <String>[
      ...List.filled(110, 'Ingepland'),
      ...List.filled(60, 'Afgewerkt'),
      ...List.filled(15, 'Geleverd'),
      ...List.filled(10, 'In bestelling'),
      ...List.filled(5, 'In opmaak'),
    ]..shuffle(random);
    final backorderStatuses = <String>[
      ...List.filled(40, 'Ingepland'),
      ...List.filled(40, 'Afgewerkt'),
      ...List.filled(10, 'Geleverd'),
      ...List.filled(5, 'In bestelling'),
      ...List.filled(5, 'In opmaak'),
    ]..shuffle(random);

    final completedRegular = <String>[];

    for (int i = 0; i < 200; i++) {
      final name = customerName(i + 1, suffix: '${i + 1}');
      final city = cities[i % cities.length];
      final postal = postalCodes[i % postalCodes.length];
      final street = streets[i % streets.length];
      final number = 5 + (i * 3) % 95;
      final status = regularStatuses[i];
      final offerLines = buildOfferLines(i);
      final estimatedDays = 3 + random.nextInt(5);
      final detailDays =
          status == 'Ingepland' ? _clampScheduledDays(estimatedDays) : estimatedDays;
      addProject(
        name: name,
        group: 'Klanten',
        status: status,
        creator: 'Julie',
        details: ProjectDetails(
          address: '$street $number, $postal $city',
          phone: phoneFor(i),
          delivery: 'Werf $city',
          finish: finishes[i % finishes.length],
          extraNotes: random.nextDouble() < 0.4
              ? plannerNotes[i % plannerNotes.length]
              : '',
          estimatedDays: detailDays,
        ),
        offerLines: offerLines,
      );

      if (random.nextDouble() < 0.25) {
        comments[name] = [
          'Planner: ${plannerNotes[(i + 1) % plannerNotes.length]}',
          if (random.nextDouble() < 0.5)
            'Werfleider: ${leaderNotes[(i + 2) % leaderNotes.length]}',
        ];
      }

      if (status == 'Ingepland') {
        final team = teams[i % teams.length];
        addRegularSchedule(name, team, _clampScheduledDays(estimatedDays));
      } else if (status == 'Afgewerkt') {
        final team = teams[(i + 1) % teams.length];
        completionTeams[name] = team;
        completedRegular.add(name);
        addWorkLogs(name, team, _clampScheduledDays(estimatedDays));
        if (random.nextDouble() < 0.6) {
          beforePhotos[name] = [dummyFile('before_${name.hashCode}.jpg')];
          afterPhotos[name] = [dummyFile('after_${name.hashCode}.jpg')];
        }
        if (random.nextDouble() < 0.35) {
          extraWorks[name] = [
            ExtraWorkEntry(
              description: extraWorkPool[i % extraWorkPool.length],
              photos: [dummyFile('extra_${name.hashCode}.jpg')],
              hours: 0.5 + random.nextInt(3),
              chargeType: random.nextDouble() < 0.7 ? 'Klant' : 'Interne fout',
            ),
          ];
        }
      }

      if (random.nextDouble() < 0.2) {
        documents[name] = [
          ProjectDocument(
            description: 'Bestek / order ${i + 1}',
            file: dummyFile('order_${name.hashCode}.pdf'),
          ),
        ];
      }
    }

    final clusterDays = <String, DateTime>{
      for (final team in teams) team: pickClusterDay(team),
    };
    final clusterCounts = <String, int>{
      for (final team in teams) team: 0,
    };
    var forcedClusterUsed = 0;

    for (int i = 0; i < 100; i++) {
      final seed = 300 + i;
      final name = customerName(seed, suffix: 'N');
      final city = cities[seed % cities.length];
      final postal = postalCodes[seed % postalCodes.length];
      final street = streets[seed % streets.length];
      final number = 3 + (seed * 2) % 90;
      final status = backorderStatuses[i];
      final offerLines = buildOfferLines(seed);
      addProject(
        name: name,
        group: 'Nabestellingen',
        status: status,
        creator: 'Julie',
        details: ProjectDetails(
          address: '$street $number, $postal $city',
          phone: phoneFor(seed),
          delivery: 'Werf $city',
          finish: 'Nabestelling',
          extraNotes: random.nextDouble() < 0.35
              ? leaderNotes[seed % leaderNotes.length]
              : '',
          estimatedDays: 1,
        ),
        offerLines: offerLines,
      );

      isBackorder[name] = true;
      backorderItems[name] = [
        backorderPool[(seed + 1) % backorderPool.length],
        if (random.nextDouble() < 0.4)
          backorderPool[(seed + 3) % backorderPool.length],
      ];
      backorderHours[name] = 1 + random.nextInt(7) + (random.nextBool() ? 0.5 : 0);
      if (completedRegular.isNotEmpty && random.nextDouble() < 0.25) {
        backorderNotes[name] =
            'Nabestelling na ${completedRegular[random.nextInt(completedRegular.length)]}';
      }

      if (status == 'Ingepland') {
        String team = teams[random.nextInt(teams.length)];
        DateTime start;
        if (forcedClusterUsed < 4) {
          team = 'Team 1';
          start = clusterDays[team]!;
          forcedClusterUsed += 1;
          backorderDayCounts[team]![start] =
              (backorderDayCounts[team]![start] ?? 0) + 1;
        } else if (clusterCounts[team]! < 4 && random.nextDouble() < 0.35) {
          start = clusterDays[team]!;
          clusterCounts[team] = clusterCounts[team]! + 1;
          backorderDayCounts[team]![start] =
              (backorderDayCounts[team]![start] ?? 0) + 1;
        } else {
          start = pickBackorderDay(team);
        }
        ScheduleStore.scheduled.add(
          TeamAssignment(
            project: name,
            team: team,
            startDate: start,
            endDate: start,
            estimatedDays: 1,
            isBackorder: true,
            group: 'Nabestellingen',
          ),
        );
      } else if (status == 'Afgewerkt') {
        final team = teams[(i + 2) % teams.length];
        completionTeams[name] = team;
        addWorkLogs(name, team, 1);
        if (random.nextDouble() < 0.4) {
          extraWorks[name] = [
            ExtraWorkEntry(
              description: extraWorkPool[(seed + 2) % extraWorkPool.length],
              photos: [dummyFile('extra_bo_${name.hashCode}.jpg')],
              hours: 0.5 + random.nextInt(2),
              chargeType: random.nextDouble() < 0.7 ? 'Klant' : 'Interne fout',
            ),
          ];
        }
      }
    }

    _seeded = true;
  }

  static void markSeeded() {
    _seeded = true;
  }

  static void addProject({
    required String name,
    required String group,
    required String status,
    required ProjectDetails details,
    required String creator,
    List<OfferLine> offerLines = const [],
    List<ProjectDocument> documents = const [],
  }) {
    final groupMap = projectsByGroup[group];
    if (groupMap == null) return;
    for (final entry in groupMap.entries) {
      entry.value.remove(name);
    }
    groupMap[status]?.add(name);
    creators[name] = creator;
    ProjectStore.details[name] = details;
    offers[name] = List<OfferLine>.from(offerLines);
    ProjectStore.documents[name] = List<ProjectDocument>.from(documents);
    ProjectLogStore.add(
      name,
      'Project aangemaakt (groep: $group, status: $status)',
    );
    AppDataStore.scheduleSave();
  }

  static void deleteProject(String name) {
    ProjectLogStore.add(name, 'Project verwijderd');
    for (final groupEntry in projectsByGroup.values) {
      for (final list in groupEntry.values) {
        list.remove(name);
      }
    }
    creators.remove(name);
    details.remove(name);
    comments.remove(name);
    beforePhotos.remove(name);
    afterPhotos.remove(name);
    extraWorks.remove(name);
    backorderItems.remove(name);
    backorderHours.remove(name);
    backorderNotes.remove(name);
    isBackorder.remove(name);
    offers.remove(name);
    documents.remove(name);
    completionTeams.remove(name);
    workLogs.remove(name);
    ProjectLogStore.logs.remove(name);
    InvoiceStore.records.remove(name);
    EstimatedDaysChangeStore.requests
        .removeWhere((request) => request.project == name);
    ScheduleStore.scheduled.removeWhere(
      (assignment) => assignment.project == name,
    );
    OfferRequestStore.requests.removeWhere(
      (request) => request.project == name,
    );
    AppDataStore.scheduleSave();
  }

  static void addComment(String projectName, String comment) {
    comments.putIfAbsent(projectName, () => []);
    comments[projectName]!.add(comment);
    final summary = _truncateText(comment.trim(), 60);
    ProjectLogStore.add(
      projectName,
      summary.isEmpty ? 'Opmerking toegevoegd' : 'Opmerking toegevoegd: $summary',
    );
    AppDataStore.scheduleSave();
  }

  static void addBeforePhoto(String projectName, PlatformFile file) {
    beforePhotos.putIfAbsent(projectName, () => []);
    beforePhotos[projectName]!.add(file);
    AppDataStore.scheduleSave();
  }

  static void addAfterPhoto(String projectName, PlatformFile file) {
    afterPhotos.putIfAbsent(projectName, () => []);
    afterPhotos[projectName]!.add(file);
    AppDataStore.scheduleSave();
  }

  static void addExtraWork(String projectName, ExtraWorkEntry entry) {
    extraWorks.putIfAbsent(projectName, () => []);
    extraWorks[projectName]!.add(entry);
    final summary = _truncateText(entry.description.trim(), 60);
    ProjectLogStore.add(
      projectName,
      summary.isEmpty ? 'Extra werk toegevoegd' : 'Extra werk toegevoegd: $summary',
    );
    AppDataStore.scheduleSave();
  }

  static void setWorkLog(String projectName, List<WorkDayEntry> entries) {
    workLogs[projectName] = entries;
    ProjectLogStore.add(projectName, 'Urenregistratie aangepast');
    AppDataStore.scheduleSave();
  }

  static void setBackorder(
    String projectName, {
    required bool backorder,
    required List<String> items,
  }) {
    isBackorder[projectName] = backorder;
    backorderItems[projectName] = List<String>.from(items);
    if (!backorder) {
      backorderHours.remove(projectName);
      backorderNotes.remove(projectName);
    }
    AppDataStore.scheduleSave();
  }

  static String? findGroupForProject(String name) {
    for (final entry in projectsByGroup.entries) {
      for (final list in entry.value.values) {
        if (list.contains(name)) return entry.key;
      }
    }
    return null;
  }

  static String? findStatusForProject(String name) {
    for (final entry in projectsByGroup.entries) {
      for (final statusEntry in entry.value.entries) {
        if (statusEntry.value.contains(name)) return statusEntry.key;
      }
    }
    return null;
  }

  static void updateStatus({
    required String name,
    required String group,
    required String status,
  }) {
    final groupMap = projectsByGroup[group];
    if (groupMap == null) return;
    final previousStatus = findStatusForProject(name);
    for (final entry in groupMap.entries) {
      entry.value.remove(name);
    }
    groupMap[status]?.add(name);
    if (previousStatus != status) {
      final label = previousStatus == null
          ? 'Status ingesteld op $status'
          : 'Status gewijzigd van $previousStatus naar $status';
      ProjectLogStore.add(name, label);
    }
    AppDataStore.scheduleSave();
  }

  static void moveToGroupStatus({
    required String name,
    required String group,
    required String status,
  }) {
    final previousGroup = findGroupForProject(name);
    final previousStatus = findStatusForProject(name);
    for (final groupEntry in projectsByGroup.values) {
      for (final list in groupEntry.values) {
        list.remove(name);
      }
    }
    projectsByGroup[group]?[status]?.add(name);
    if (previousGroup != group || previousStatus != status) {
      final fromLabel = (previousGroup == null && previousStatus == null)
          ? ''
          : ' van ${previousGroup ?? '-'} · ${previousStatus ?? '-'}';
      ProjectLogStore.add(
        name,
        'Verplaatst$fromLabel naar $group · $status',
      );
    }
    AppDataStore.scheduleSave();
  }
}

class OfferRequest {
  OfferRequest({
    required this.project,
    required this.requester,
    required this.createdAt,
    this.note = '',
  });

  final String project;
  final String requester;
  final DateTime createdAt;
  final String note;
}

class OfferRequestStore {
  static final List<OfferRequest> requests = [];

  static void add(OfferRequest request) {
    requests.insert(0, request);
    ProjectLogStore.add(
      request.project,
      'Offerte aanvraag ingediend',
    );
    AppDataStore.scheduleSave();
  }

  static void remove(OfferRequest request) {
    requests.remove(request);
    AppDataStore.scheduleSave();
  }
}

class EstimatedDaysChangeRequest {
  EstimatedDaysChangeRequest({
    required this.project,
    required this.team,
    required this.oldDays,
    required this.newDays,
    required this.requester,
    required this.requesterRole,
    required this.createdAt,
    this.status = 'In afwachting',
  });

  final String project;
  final String team;
  final int oldDays;
  final int newDays;
  final String requester;
  final String requesterRole;
  final DateTime createdAt;
  String status;
}

class EstimatedDaysChangeStore {
  static final List<EstimatedDaysChangeRequest> requests = [];

  static void add(EstimatedDaysChangeRequest request) {
    requests.removeWhere(
      (entry) =>
          entry.project == request.project &&
          entry.status == 'In afwachting',
    );
    requests.insert(0, request);
    AppDataStore.scheduleSave();
  }

  static List<EstimatedDaysChangeRequest> pending() {
    return requests
        .where((entry) => entry.status == 'In afwachting')
        .toList();
  }

  static EstimatedDaysChangeRequest? pendingForProject(String project) {
    for (final entry in requests) {
      if (entry.project == project && entry.status == 'In afwachting') {
        return entry;
      }
    }
    return null;
  }
}

class ProjectLogEntry {
  ProjectLogEntry({
    required this.timestamp,
    required this.user,
    required this.role,
    required this.message,
  });

  final DateTime timestamp;
  final String user;
  final String role;
  final String message;
}

class ProjectLogStore {
  static final Map<String, List<ProjectLogEntry>> logs = {};

  static void add(String project, String message) {
    final user = CurrentUserStore.name.isNotEmpty
        ? CurrentUserStore.name
        : 'Systeem';
    final role = CurrentUserStore.role.isNotEmpty
        ? CurrentUserStore.role
        : 'Systeem';
    logs.putIfAbsent(project, () => []);
    logs[project]!.insert(
      0,
      ProjectLogEntry(
        timestamp: DateTime.now(),
        user: user,
        role: role,
        message: message,
      ),
    );
    AppDataStore.scheduleSave();
  }

  static List<ProjectLogEntry> forProject(String project) {
    return List<ProjectLogEntry>.from(logs[project] ?? const []);
  }
}

class ExtraWorkEntry {
  ExtraWorkEntry({
    required this.description,
    required this.photos,
    required this.hours,
    this.chargeType = 'Klant',
  });

  final String description;
  final List<PlatformFile> photos;
  final double hours;
  final String chargeType;
}

class ProjectDetails {
  const ProjectDetails({
    required this.address,
    required this.phone,
    required this.delivery,
    required this.finish,
    required this.extraNotes,
    required this.estimatedDays,
  });

  final String address;
  final String phone;
  final String delivery;
  final String finish;
  final String extraNotes;
  final int estimatedDays;
}


class _ProjectResult {
  const _ProjectResult({
    required this.name,
    required this.group,
    required this.status,
  });

  final String name;
  final String group;
  final String status;
}

class _InvoiceItem {
  _InvoiceItem({
    required this.name,
    required this.group,
    required this.status,
    required this.isBackorder,
    required this.offerLines,
    required this.offerHours,
    required this.extraHoursTotal,
    required this.extraHoursDelta,
    required this.includeOffer,
  });

  final String name;
  final String group;
  final String status;
  final bool isBackorder;
  final List<OfferLine> offerLines;
  final double offerHours;
  final double extraHoursTotal;
  final double extraHoursDelta;
  final bool includeOffer;
}

class _PlanningItem {
  _PlanningItem({
    required this.name,
    required this.estimatedDays,
    required this.phone,
    required this.address,
    required this.group,
  });

  final String name;
  final int estimatedDays;
  final String phone;
  final String address;
  final String group;
}

class _ExternalProjectItem {
  _ExternalProjectItem({
    required this.assignment,
    required this.details,
  });

  final TeamAssignment assignment;
  final ProjectDetails? details;
}

class TeamAssignment {
  TeamAssignment({
    required this.project,
    required this.team,
    required this.startDate,
    required this.endDate,
    required this.estimatedDays,
    required this.isBackorder,
    required this.group,
  });

  final String project;
  final String team;
  final DateTime startDate;
  final DateTime endDate;
  final int estimatedDays;
  final bool isBackorder;
  final String group;
}

const _testAccounts = [
  TestAccount(
    name: 'Nick',
    role: 'Beheerder',
    company: 'Finestone',
  ),
  TestAccount(
    name: 'Julie',
    role: 'Planner',
    company: 'Finestone',
  ),
  TestAccount(
    name: 'Thomas',
    role: 'Projectleider',
    company: 'Finestone',
  ),
  TestAccount(
    name: 'Igor',
    role: 'Onderaannemer beheerder',
    company: 'Finestone',
    team: 'Team 1',
  ),
  TestAccount(
    name: 'Victor',
    role: 'Onderaannemer beheerder',
    company: 'Finestone',
  ),
  TestAccount(
    name: 'Ihor',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 1',
  ),
  TestAccount(
    name: 'Vova',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 1',
  ),
  TestAccount(
    name: 'Kiryl',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 1',
  ),
  TestAccount(
    name: 'Vitaly',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 2',
  ),
  TestAccount(
    name: 'Bohdan',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 2',
  ),
  TestAccount(
    name: 'Vitaly Y',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 2',
  ),
  TestAccount(
    name: 'Pavlo',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 3',
  ),
  TestAccount(
    name: 'Ruslan',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 3',
  ),
  TestAccount(
    name: 'Vadim',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 3',
  ),
  TestAccount(
    name: 'Maksim',
    role: 'Onderaannemer beheerder',
    company: 'Finestone',
    team: 'Team 4',
  ),
  TestAccount(
    name: 'Sergei',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 4',
  ),
  TestAccount(
    name: 'Dmitri',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 4',
  ),
  TestAccount(
    name: 'Oleg',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 4',
  ),
  TestAccount(
    name: 'Anton',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 5',
  ),
  TestAccount(
    name: 'Nikita',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 5',
  ),
  TestAccount(
    name: 'Yuri',
    role: 'Werknemer',
    company: 'Finestone',
    team: 'Team 5',
  ),
];

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vul e-mail en wachtwoord in.'),
        ),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    TestAccount? account;
    if (NetlifyIdentityService.isConfigured) {
      try {
        final session = await NetlifyIdentityService.login(
          email: email,
          password: password,
        );
        final user = (session?['user'] as Map?) ?? {};
        final metadata = (user['user_metadata'] as Map?) ?? {};
        final identityName =
            metadata['name']?.toString() ?? user['email']?.toString() ?? email;
        final identityCompany =
            metadata['company']?.toString() ?? 'Finestone';
        account = AuthStore.accountForEmail(
          email,
          fallbackName: identityName,
          fallbackCompany: identityCompany,
        );
      } catch (error) {
        if (!mounted) return;
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
        return;
      }
    } else {
      final user = AuthStore.authenticate(email, password);
      if (user != null) {
        account = AuthStore.toAccount(user);
      }
    }
    setState(() => _isSubmitting = false);
    if (account == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ongeldige logingegevens.')),
      );
      return;
    }
    final resolvedAccount = account;
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      _appPageRoute(
        builder: (_) => DashboardScreen(account: resolvedAccount),
      ),
    );
  }

  Future<void> _resetPassword() async {
    final controller = TextEditingController(text: _emailController.text.trim());
    final email = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wachtwoord resetten'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: 'E-mailadres'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Annuleer'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Versturen'),
          ),
        ],
      ),
    );
    if (email == null || email.isEmpty) return;
    final error = await NetlifyIdentityService.sendPasswordReset(email);
    if (!mounted) return;
    if (error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Reset-link verzonden. Controleer je e-mail.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Text(
                  'TimeTable',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 24),
                _InputCard(
                  title: 'Inloggen',
                  children: [
                    _EditableInputField(
                      label: 'E-mail',
                      hint: 'E-mailadres',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      controller: _emailController,
                    ),
                    const SizedBox(height: 12),
                    _EditableInputField(
                      label: 'Wachtwoord',
                      hint: 'Wachtwoord',
                      icon: Icons.lock_outline,
                      obscure: true,
                      controller: _passwordController,
                    ),
                    const SizedBox(height: 16),
                    _PrimaryButton(
                      label: _isSubmitting ? 'Inloggen...' : 'Inloggen',
                      fullWidth: true,
                      onTap: _isSubmitting ? null : _login,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: _SecondaryButton(
                        label: 'Registreren als bedrijf',
                        onTap: () {
                          Navigator.of(context).push(
                            _appPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: _SecondaryButton(
                        label: 'Wachtwoord vergeten',
                        onTap: _resetPassword,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      NetlifyIdentityService.isConfigured
                          ? 'Na registratie ontvang je een bevestigingsmail.'
                          : 'Testusers zijn vooraf aangemaakt. Gebruik hun e-mail en wachtwoord `Test1234!`.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF6A7C78)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _companyNameController =
      TextEditingController();
  final TextEditingController _businessNumberController =
      TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _adminNameController = TextEditingController();
  final TextEditingController _adminEmailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _companyNameController.dispose();
    _businessNumberController.dispose();
    _addressController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wachtwoorden komen niet overeen.')),
      );
      return;
    }
    setState(() => _isSubmitting = true);
    String? error;
    if (NetlifyIdentityService.isConfigured) {
      error = await NetlifyIdentityService.signup(
        email: _adminEmailController.text,
        password: password,
        name: _adminNameController.text,
        company: _companyNameController.text,
        businessNumber: _businessNumberController.text,
        address: _addressController.text,
      );
      if (error != null &&
          (error.toLowerCase().contains('already') ||
              error.toLowerCase().contains('exists') ||
              error.toLowerCase().contains('in use'))) {
        error = 'E-mailadres is al in gebruik. Gebruik wachtwoord resetten.';
      }
    }
    error ??= AuthStore.registerCompany(
      companyName: _companyNameController.text,
      businessNumber: _businessNumberController.text,
      address: _addressController.text,
      adminName: _adminNameController.text,
      adminEmail: _adminEmailController.text,
      password: password,
    );
    if (error != null) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
      return;
    }
    setState(() => _isSubmitting = false);
    if (!mounted) return;
    if (NetlifyIdentityService.isConfigured) {
      try {
        final session = await NetlifyIdentityService.login(
          email: _adminEmailController.text.trim(),
          password: _passwordController.text,
        );
        final user = (session?['user'] as Map?) ?? {};
        final metadata = (user['user_metadata'] as Map?) ?? {};
        final identityName = metadata['name']?.toString() ??
            _adminNameController.text.trim();
        final identityCompany = metadata['company']?.toString() ??
            _companyNameController.text.trim();
        final account = AuthStore.accountForEmail(
          _adminEmailController.text.trim(),
          fallbackName: identityName,
          fallbackCompany: identityCompany,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account aangemaakt. Bevestigingsmail is verzonden.'),
          ),
        );
        Navigator.of(context).pushReplacement(
          _appPageRoute(
            builder: (_) => DashboardScreen(account: account),
          ),
        );
      } catch (_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Account aangemaakt. Bevestigingsmail is verzonden.',
            ),
          ),
        );
        Navigator.of(context).pop();
      }
      return;
    }
    final user = AuthStore.authenticate(
      _adminEmailController.text.trim(),
      _passwordController.text,
    );
    if (user == null) return;
    final account = AuthStore.toAccount(user);
    Navigator.of(context).pushReplacement(
      _appPageRoute(
        builder: (_) => DashboardScreen(account: account),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                      Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Registreren',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InputCard(
                  title: 'Bedrijf aanmaken',
                  children: [
                    _EditableInputField(
                      label: 'Bedrijfsnaam',
                      hint: 'Bedrijfsnaam',
                      icon: Icons.business_outlined,
                      controller: _companyNameController,
                    ),
                    const SizedBox(height: 12),
                    _EditableInputField(
                      label: 'Bedrijfsnummer',
                      hint: 'Bedrijfsnummer',
                      icon: Icons.badge_outlined,
                      controller: _businessNumberController,
                    ),
                    const SizedBox(height: 12),
                    _EditableInputField(
                      label: 'Adres bedrijf',
                      hint: 'Adres bedrijf',
                      icon: Icons.location_on_outlined,
                      controller: _addressController,
                    ),
                    const SizedBox(height: 12),
                    _EditableInputField(
                      label: 'Voornaam & achternaam',
                      hint: 'Voornaam & achternaam',
                      icon: Icons.person_outline,
                      controller: _adminNameController,
                    ),
                    const SizedBox(height: 12),
                    _EditableInputField(
                      label: 'E-mail',
                      hint: 'E-mailadres',
                      icon: Icons.mail_outline,
                      keyboardType: TextInputType.emailAddress,
                      controller: _adminEmailController,
                    ),
                    const SizedBox(height: 12),
                    _EditableInputField(
                      label: 'Wachtwoord',
                      hint: 'Wachtwoord',
                      icon: Icons.lock_outline,
                      obscure: true,
                      controller: _passwordController,
                    ),
                    const SizedBox(height: 12),
                    _EditableInputField(
                      label: 'Bevestig wachtwoord',
                      hint: 'Bevestig wachtwoord',
                      icon: Icons.lock_outline,
                      obscure: true,
                      controller: _confirmPasswordController,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _PrimaryButton(
                  label: _isSubmitting
                      ? 'Account aanmaken...'
                      : 'Account aanmaken',
                  fullWidth: true,
                  onTap: _isSubmitting ? null : _register,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.account});

  final TestAccount account;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  final List<TeamAssignment> _scheduled = ScheduleStore.scheduled;

  @override
  void initState() {
    super.initState();
    _RoleManagementStore.seedIfEmpty();
    ProjectStore.seedIfEmpty();
    final accountEmail = widget.account.email.trim().toLowerCase();
    _RoleAssignment? match;
    if (accountEmail.isNotEmpty) {
      for (final assignment in _RoleManagementStore.assignments) {
        if (assignment.email.trim().toLowerCase() == accountEmail) {
          match = assignment;
          break;
        }
      }
    }
    match ??= _RoleManagementStore.assignments.firstWhere(
      (assignment) => assignment.name == widget.account.name,
      orElse: () => _RoleAssignment(
        name: widget.account.name,
        email: widget.account.email,
        role: widget.account.role,
        contractor: '',
        team: widget.account.team,
      ),
    );
    CurrentUserStore.role = match.role;
    CurrentUserStore.name = match.name;
    CurrentUserStore.email = widget.account.email;
    CurrentUserStore.company = widget.account.company;
    CurrentUserStore.team = match.team ?? widget.account.team ?? '';
    CurrentUserStore.contractor =
        match.contractor ?? (match.role == 'Onderaannemer' ? match.name : '');
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      TodayTab(
        account: widget.account,
        scheduled: _scheduled,
        onScheduleChanged: () => setState(() {}),
      ),
      PlanningTab(
        account: widget.account,
        scheduled: _scheduled,
        onScheduleChanged: () => setState(() {}),
        onCalendarSaved: _recalculateSchedules,
      ),
      ProjectsTab(
        account: widget.account,
        scheduled: _scheduled,
      ),
      StatisticsTab(
        account: widget.account,
        scheduled: _scheduled,
      ),
      ProfileTab(
        account: widget.account,
        assignments: _scheduled,
        onCalendarSaved: _recalculateSchedules,
      ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                        Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TimeTable',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineLarge,
                              ),
                            ],
                          ),
                          Container(
                            height: 42,
                            width: 42,
                            decoration: BoxDecoration(
                              color: const Color(0xFF0B2E2B),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.notifications_none,
                              color: Color(0xFFFFE9CC),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: pages[_selectedIndex],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomNavBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() {
          _selectedIndex = index;
        }),
      ),
    );
  }

  bool _isWorkingDay(DateTime date, String team) {
    final weekday = date.weekday;
    final workingDays = _RoleManagementStore.workingDaysForTeam(team);
    if (!workingDays.contains(weekday)) {
      return false;
    }
    return !PlanningCalendarStore.isNonWorkingDay(date);
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _nextWorkingDay(DateTime date, String team) {
    var day = _normalizeDate(date);
    while (!_isWorkingDay(day, team)) {
      day = day.add(const Duration(days: 1));
    }
    return day;
  }

  DateTime _endDateFrom(DateTime start, int days, String team) {
    var current = _normalizeDate(start);
    int counted = 0;
    while (true) {
      if (_isWorkingDay(current, team)) {
        counted += 1;
        if (counted == days) {
          return current;
        }
      }
      current = current.add(const Duration(days: 1));
    }
  }

  void _recalculateSchedules() {
    final byTeam = <String, List<TeamAssignment>>{};
    for (final assignment in _scheduled) {
      byTeam.putIfAbsent(assignment.team, () => []).add(assignment);
    }

    final updated = <TeamAssignment>[];
    for (final entry in byTeam.entries) {
      final team = entry.key;
      final items = [...entry.value]
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      final regularItems =
          items.where((item) => !item.isBackorder).toList();
      final backorderItems =
          items.where((item) => item.isBackorder).toList();

      DateTime? cursor;
      for (final item in regularItems) {
        final startBase = cursor ?? item.startDate;
        final start = _nextWorkingDay(startBase, team);
        final end = _endDateFrom(start, item.estimatedDays, team);
        updated.add(
          TeamAssignment(
            project: item.project,
            team: team,
            startDate: start,
            endDate: end,
            estimatedDays: item.estimatedDays,
            isBackorder: item.isBackorder,
            group: item.group,
          ),
        );
        cursor = end.add(const Duration(days: 1));
      }

      for (final item in backorderItems) {
        final start = _nextWorkingDay(item.startDate, team);
        updated.add(
          TeamAssignment(
            project: item.project,
            team: team,
            startDate: start,
            endDate: start,
            estimatedDays: item.estimatedDays,
            isBackorder: item.isBackorder,
            group: item.group,
          ),
        );
      }
    }

    setState(() {
      _scheduled
        ..clear()
        ..addAll(updated);
    });
    AppDataStore.scheduleSave();
  }
}

class PlanningTab extends StatefulWidget {
  const PlanningTab({
    super.key,
    required this.account,
    required this.scheduled,
    this.onScheduleChanged,
    this.onCalendarSaved,
  });

  final TestAccount account;
  final List<TeamAssignment> scheduled;
  final VoidCallback? onScheduleChanged;
  final VoidCallback? onCalendarSaved;

  @override
  State<PlanningTab> createState() => _PlanningTabState();
}

class TodayTab extends StatefulWidget {
  const TodayTab({
    super.key,
    required this.account,
    required this.scheduled,
    this.onScheduleChanged,
  });

  final TestAccount account;
  final List<TeamAssignment> scheduled;
  final VoidCallback? onScheduleChanged;

  @override
  State<TodayTab> createState() => _TodayTabState();

  DateTime _normalize(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  List<TeamAssignment> _assignmentsForDay(DateTime day) {
    final normalized = _normalize(day);
    final list = scheduled.where((assignment) {
      final start = _normalize(assignment.startDate);
      final end = _normalize(assignment.endDate);
      return !normalized.isBefore(start) && !normalized.isAfter(end);
    }).toList();
    list.sort((a, b) => a.startDate.compareTo(b.startDate));
    return list;
  }

  Map<String, List<TeamAssignment>> _groupByTeam(
    DateTime day,
    List<TeamAssignment> items,
  ) {
    final grouped = <String, List<TeamAssignment>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.team, () => []).add(item);
    }
    for (final entry in grouped.entries) {
      entry.value.sort((a, b) => a.startDate.compareTo(b.startDate));
      final order = PlanningOrderStore.orderFor(entry.key, day);
      if (order.isNotEmpty) {
        final remaining = List<TeamAssignment>.from(entry.value);
        final ordered = <TeamAssignment>[];
        for (final name in order) {
          final index =
              remaining.indexWhere((assignment) => assignment.project == name);
          if (index != -1) {
            ordered.add(remaining.removeAt(index));
          }
        }
        ordered.addAll(remaining);
        entry.value
          ..clear()
          ..addAll(ordered);
      }
    }
    return grouped;
  }

  String _uniqueOfferProjectName(String base) {
    var candidate = base;
    var counter = 2;
    while (ProjectStore.findGroupForProject(candidate) != null) {
      candidate = '$base $counter';
      counter += 1;
    }
    return candidate;
  }

  Future<void> _showOfferRequestDialog(
    BuildContext context,
    List<TeamAssignment> assignments,
  ) async {
    if (assignments.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geen project vandaag om aan te vragen.')),
      );
      return;
    }
    String selected = assignments.first.project;
    final noteController = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Extra offerte aanvragen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (assignments.length > 1)
                DropdownButtonFormField<String>(
                  initialValue: selected,
                  items: assignments
                      .map(
                        (assignment) => DropdownMenuItem(
                          value: assignment.project,
                          child: Text(assignment.project),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    selected = value;
                  },
                  decoration: const InputDecoration(
                    labelText: 'Project',
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    selected,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Toelichting (optioneel)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Annuleren'),
            ),
            TextButton(
              onPressed: () {
                OfferRequestStore.add(
                  OfferRequest(
                    project: selected,
                    requester: CurrentUserStore.name,
                    createdAt: DateTime.now(),
                    note: noteController.text.trim(),
                  ),
                );
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Offerte-aanvraag verstuurd.'),
                  ),
                );
              },
              child: const Text('Verzenden'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleOfferRequest(
    BuildContext context,
    OfferRequest request,
  ) async {
    final details = ProjectStore.details[request.project];
    final phone = details?.phone ?? '—';
    final noteController = TextEditingController();
    final descriptionController = TextEditingController();
    var createNewOffer = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('Offerte-aanvraag afhandelen'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.project,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Telefoon: $phone',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: const Color(0xFF6A7C78)),
                    ),
                    const SizedBox(height: 8),
                    _InlineButton(
                      label: 'Bel klant',
                      icon: Icons.call_outlined,
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Bellen naar $phone'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Opmerking voor de klant (project)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Checkbox(
                          value: createNewOffer,
                          onChanged: (value) => setDialogState(() {
                            createNewOffer = value ?? false;
                          }),
                        ),
                        const Expanded(
                          child: Text('Nieuwe offerte in opmaak aanmaken'),
                        ),
                      ],
                    ),
                    if (createNewOffer) ...[
                      const SizedBox(height: 6),
                      TextField(
                        controller: descriptionController,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          labelText: 'Korte beschrijving',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Annuleren'),
                ),
                TextButton(
                  onPressed: () {
                    final note = noteController.text.trim();
                    if (note.isNotEmpty) {
                      ProjectStore.addComment(request.project, note);
                    }
                    if (createNewOffer) {
                      final baseName = 'Extra offerte - ${request.project}';
                      final name = _uniqueOfferProjectName(baseName);
                      final description = descriptionController.text.trim();
                      final existing = ProjectStore.details[request.project];
                      ProjectStore.addProject(
                        name: name,
                        group: 'Klanten',
                        status: 'In opmaak',
                        creator: CurrentUserStore.name,
                        details: ProjectDetails(
                          address: existing?.address ?? '—',
                          phone: existing?.phone ?? '—',
                          delivery: existing?.delivery ?? '—',
                          finish: existing?.finish ?? '—',
                          extraNotes: description.isEmpty
                              ? 'Extra offerte in opmaak.'
                              : description,
                          estimatedDays: 1,
                        ),
                      );
                    }
                    OfferRequestStore.remove(request);
                    (context as Element).markNeedsBuild();
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Offerte-aanvraag verwerkt.'),
                      ),
                    );
                  },
                  child: const Text('Verzenden'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, VoidCallback onUpdated) {
    final today = DateTime.now();
    final isExternal = _isExternalRole(CurrentUserStore.role);
    final isWorker = CurrentUserStore.role == 'Werknemer';
    final isProjectLeader = CurrentUserStore.role == 'Projectleider';
    final canApproveDays =
        _canApproveEstimatedDaysChanges(CurrentUserStore.role);
    final pendingDayRequests = EstimatedDaysChangeStore.pending();
    final teams = isExternal ? _teamsForCurrentUser() : const <String>[];
    final matches = _assignmentsForDay(today);
    final visible = isExternal
        ? matches.where((assignment) => teams.contains(assignment.team)).toList()
        : matches;
    final backordersToday = visible
        .where((assignment) =>
            assignment.isBackorder || assignment.group == 'Nabestellingen')
        .length;
    final customersToday = visible.length - backordersToday;
    final grouped = _groupByTeam(today, visible);
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SectionHeader(
            title: 'Vandaag',
            subtitle: _formatDate(today),
          ),
          if (isExternal)
            _InlineButton(
              label: 'Offerte',
              icon: Icons.request_quote_outlined,
              onTap: () => _showOfferRequestDialog(context, visible),
            ),
        ],
      ),
    );

    if (isWorker) {
      return Column(
        children: [
          header,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: visible.isEmpty
                  ? const _EmptyStateCard(
                      title: 'Geen planning vandaag',
                      subtitle: 'Er zijn vandaag geen projecten ingepland.',
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (customersToday > 0 || backordersToday > 0)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Text(
                              'Klanten: $customersToday · Nabestellingen: $backordersToday',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF6A7C78)),
                            ),
                          ),
                        Expanded(
                          child: _TodayProjectFullCard(
                            assignment: visible.first,
                            details: ProjectStore.details[visible.first.project],
                            onUpdated: onUpdated,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        header,
        Expanded(
          child: ListView(
            key: const ValueKey('today'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            physics: const ClampingScrollPhysics(),
            children: [
              if (canApproveDays && pendingDayRequests.isNotEmpty) ...[
                const SizedBox(height: 12),
                _InputCard(
                  title: 'Aanvragen geschatte dagen',
                  children: [
                    ...pendingDayRequests.map(
                      (request) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Material(
                          color: const Color(0xFFF4F1EA),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              await Navigator.of(context).push(
                                _appPageRoute(
                                  builder: (_) => EstimatedDaysChangeDetailScreen(
                                    request: request,
                                    scheduled: scheduled,
                                    onUpdated: onUpdated,
                                  ),
                                ),
                              );
                              onUpdated();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFE1DAD0),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          request.project,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${request.team} · ${request.oldDays} → ${request.newDays} dagen',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color:
                                                    const Color(0xFF6A7C78),
                                              ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Aangevraagd door ${request.requester}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color:
                                                    const Color(0xFF6A7C78),
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const Icon(
                                    Icons.chevron_right,
                                    color: Color(0xFF6A7C78),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (isProjectLeader && OfferRequestStore.requests.isNotEmpty) ...[
                const SizedBox(height: 12),
                _InputCard(
                  title: 'Offerte-aanvragen',
                  children: [
                    ...OfferRequestStore.requests.map(
                      (request) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              request.project,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Aangevraagd door ${request.requester}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF6A7C78)),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Telefoon: ${ProjectStore.details[request.project]?.phone ?? '—'}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF6A7C78)),
                            ),
                            if (request.note.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                request.note,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                _InlineButton(
                                  label: 'Bel',
                                  icon: Icons.call_outlined,
                                  onTap: () {
                                    final phone =
                                        ProjectStore
                                                .details[request.project]
                                                ?.phone ??
                                            '—';
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Bellen naar $phone'),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(width: 8),
                                _InlineButton(
                                  label: 'Afhandelen',
                                  icon: Icons.check_circle_outline,
                                  onTap: () =>
                                      _handleOfferRequest(context, request),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const _EmptyStateCard(
                  title: 'Geen planning vandaag',
                  subtitle: 'Er zijn vandaag geen projecten ingepland.',
                )
              else if (isExternal)
                ...grouped.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TodayTeamCard(
                      team: entry.key,
                      assignments: entry.value,
                      onOpen: (assignment) async {
                        final changed =
                            await Navigator.of(context).push<bool>(
                          _appPageRoute(
                            builder: (_) => ProjectDetailScreen(
                              customerName: assignment.project,
                              group: assignment.group,
                              status: ProjectStore.findStatusForProject(
                                    assignment.project,
                                  ) ??
                                  'Ingepland',
                            ),
                          ),
                        );
                        if (changed == true) {
                          (context as Element).markNeedsBuild();
                        }
                      },
                    ),
                  ),
                )
              else
                ...grouped.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _TodayTeamCard(
                      team: entry.key,
                      assignments: entry.value,
                      onOpen: (assignment) async {
                        final changed =
                            await Navigator.of(context).push<bool>(
                          _appPageRoute(
                            builder: (_) => ProjectDetailScreen(
                              customerName: assignment.project,
                              group: assignment.group,
                              status: ProjectStore.findStatusForProject(
                                    assignment.project,
                                  ) ??
                                  'Ingepland',
                            ),
                          ),
                        );
                        if (changed == true) {
                          (context as Element).markNeedsBuild();
                        }
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TodayTabState extends State<TodayTab> {
  @override
  Widget build(BuildContext context) {
    return widget._buildContent(context, () => setState(() {}));
  }
}

class _TodayTeamCard extends StatelessWidget {
  const _TodayTeamCard({
    required this.team,
    required this.assignments,
    required this.onOpen,
  });

  final String team;
  final List<TeamAssignment> assignments;
  final void Function(TeamAssignment assignment) onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(team, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ...assignments.map(
            (assignment) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                onTap: () => onOpen(assignment),
                child: Row(
                  children: [
                    const Icon(Icons.circle,
                        size: 8, color: Color(0xFF0B2E2B)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            assignment.project,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: const Color(0xFF5A6F6C)),
                          ),
                          if ((ProjectStore
                                      .details[assignment.project]
                                      ?.address ??
                                  '')
                              .trim()
                              .isNotEmpty)
                            Text(
                              ProjectStore
                                      .details[assignment.project]
                                      ?.address ??
                                  '',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: const Color(0xFF6A7C78),
                                  ),
                            ),
                        ],
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

class _TodayProjectFullCard extends StatefulWidget {
  const _TodayProjectFullCard({
    required this.assignment,
    required this.details,
    this.onUpdated,
  });

  final TeamAssignment assignment;
  final ProjectDetails? details;
  final VoidCallback? onUpdated;

  @override
  State<_TodayProjectFullCard> createState() => _TodayProjectFullCardState();
}

class _TodayProjectFullCardState extends State<_TodayProjectFullCard> {
  int _tabIndex = 0;
  int _siteTabIndex = 0;
  late List<PlatformFile> _beforePhotos;
  late List<PlatformFile> _afterPhotos;
  late List<ExtraWorkEntry> _extraWorks;
  late List<WorkDayEntry> _workLogs;
  DateTime _workDate = DateTime.now();
  int? _workStartMinutes;
  int? _workEndMinutes;
  final TextEditingController _workBreakController =
      TextEditingController(text: '30');
  List<String> _selectedWorkers = [];
  int? _editingWorkLogIndex;
  final TextEditingController _extraWorkController = TextEditingController();
  final TextEditingController _extraHoursController = TextEditingController();
  String _extraWorkChargeType = _extraWorkChargeTypes.first;
  final TextEditingController _commentController = TextEditingController();
  List<PlatformFile> _extraWorkFiles = [];
  int? _editingExtraWorkIndex;
  bool _isBackorder = false;
  final TextEditingController _backorderController = TextEditingController();
  final TextEditingController _backorderNoteController =
      TextEditingController();
  final List<String> _backorderItems = [];
  final TextEditingController _daysChangeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final name = widget.assignment.project;
    _beforePhotos =
        List<PlatformFile>.from(ProjectStore.beforePhotos[name] ?? const []);
    _afterPhotos =
        List<PlatformFile>.from(ProjectStore.afterPhotos[name] ?? const []);
    _extraWorks =
        List<ExtraWorkEntry>.from(ProjectStore.extraWorks[name] ?? const []);
    _workLogs =
        List<WorkDayEntry>.from(ProjectStore.workLogs[name] ?? const []);
    _isBackorder = ProjectStore.isBackorder[name] ?? false;
    _backorderItems
      ..clear()
      ..addAll(ProjectStore.backorderItems[name] ?? const []);
    _backorderNoteController.text =
        ProjectStore.backorderNotes[name] ?? '';
  }

  @override
  void dispose() {
    _extraWorkController.dispose();
    _extraHoursController.dispose();
    _commentController.dispose();
    _workBreakController.dispose();
    _backorderController.dispose();
    _backorderNoteController.dispose();
    _daysChangeController.dispose();
    super.dispose();
  }

  List<String> _teamWorkers() {
    _RoleManagementStore.seedIfEmpty();
    final team = widget.assignment.team;
    final workers = _RoleManagementStore.assignments
        .where((assignment) =>
            assignment.role == 'Werknemer' && assignment.team == team)
        .map((assignment) => assignment.name)
        .toList();
    if (workers.isEmpty) {
      return [CurrentUserStore.name];
    }
    return workers;
  }

  int? _minutesFromTimeOfDay(TimeOfDay? time) {
    if (time == null) return null;
    return time.hour * 60 + time.minute;
  }

  String _formatMinutes(int minutes) {
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    return '${hours.toString().padLeft(2, '0')}:${mins.toString().padLeft(2, '0')}';
  }

  Future<void> _pickWorkDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _workDate,
      firstDate: DateTime(_workDate.year - 1),
      lastDate: DateTime(_workDate.year + 1),
    );
    if (picked == null) return;
    setState(() {
      _workDate = picked;
    });
  }

  void _saveWorkLog() {
    final start = _workStartMinutes;
    final end = _workEndMinutes;
    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kies een begin- en einduur.')),
      );
      return;
    }
    if (end <= start) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Einduur moet na beginuur vallen.')),
      );
      return;
    }
    if (_selectedWorkers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecteer wie er gewerkt heeft.')),
      );
      return;
    }
    final breakMinutes =
        int.tryParse(_workBreakController.text.trim()) ?? 0;
    final entry = WorkDayEntry(
      date: DateTime(_workDate.year, _workDate.month, _workDate.day),
      startMinutes: start,
      endMinutes: end,
      breakMinutes: breakMinutes,
      workers: List<String>.from(_selectedWorkers),
    );
    setState(() {
      if (_editingWorkLogIndex != null &&
          _editingWorkLogIndex! >= 0 &&
          _editingWorkLogIndex! < _workLogs.length) {
        _workLogs[_editingWorkLogIndex!] = entry;
        _editingWorkLogIndex = null;
      } else {
        _workLogs.add(entry);
      }
      ProjectStore.setWorkLog(widget.assignment.project, _workLogs);
      _workStartMinutes = null;
      _workEndMinutes = null;
      _workBreakController.text = '30';
      _selectedWorkers = [];
    });
  }

  void _editWorkLog(int index) {
    if (index < 0 || index >= _workLogs.length) return;
    final entry = _workLogs[index];
    setState(() {
      _editingWorkLogIndex = index;
      _workDate = entry.date;
      _workStartMinutes = entry.startMinutes;
      _workEndMinutes = entry.endMinutes;
      _workBreakController.text = entry.breakMinutes.toString();
      _selectedWorkers = List<String>.from(entry.workers);
    });
  }

  void _deleteWorkLog(int index) {
    if (index < 0 || index >= _workLogs.length) return;
    setState(() {
      _workLogs.removeAt(index);
      ProjectStore.setWorkLog(widget.assignment.project, _workLogs);
    });
  }

  Future<void> _pickBeforePhotos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;
    setState(() {
      _beforePhotos.addAll(result.files);
      ProjectStore.beforePhotos[widget.assignment.project] = _beforePhotos;
    });
    ProjectLogStore.add(
      widget.assignment.project,
      "Foto's voor de werf toegevoegd (${result.files.length})",
    );
  }

  Future<void> _pickAfterPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;
    setState(() {
      _afterPhotos.addAll(result.files);
      ProjectStore.afterPhotos[widget.assignment.project] = _afterPhotos;
    });
    ProjectLogStore.add(
      widget.assignment.project,
      "Foto's na de werf toegevoegd (${result.files.length})",
    );
  }

  void _removeBeforePhoto(int index) {
    setState(() {
      if (index < 0 || index >= _beforePhotos.length) return;
      _beforePhotos.removeAt(index);
      ProjectStore.beforePhotos[widget.assignment.project] = _beforePhotos;
    });
    ProjectLogStore.add(widget.assignment.project, 'Foto voor de werf verwijderd');
  }

  void _removeAfterPhoto(int index) {
    setState(() {
      if (index < 0 || index >= _afterPhotos.length) return;
      _afterPhotos.removeAt(index);
      ProjectStore.afterPhotos[widget.assignment.project] = _afterPhotos;
    });
    ProjectLogStore.add(widget.assignment.project, 'Foto na de werf verwijderd');
  }

  Future<void> _pickExtraWorkPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;
    setState(() {
      _extraWorkFiles = result.files;
    });
  }

  void _addExtraWork() {
    final description = _extraWorkController.text.trim();
    if (description.isEmpty || _extraWorkFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voeg een beschrijving en foto’s toe')),
      );
      return;
    }
    final hours = double.tryParse(_extraHoursController.text.trim()) ?? 0;
    final entry = ExtraWorkEntry(
      description: description,
      photos: List<PlatformFile>.from(_extraWorkFiles),
      hours: hours,
      chargeType: _extraWorkChargeType,
    );
    setState(() {
      if (_editingExtraWorkIndex != null &&
          _editingExtraWorkIndex! >= 0 &&
          _editingExtraWorkIndex! < _extraWorks.length) {
        _extraWorks[_editingExtraWorkIndex!] = entry;
        ProjectStore.extraWorks[widget.assignment.project] =
            List<ExtraWorkEntry>.from(_extraWorks);
        final summary = _truncateText(description, 60);
        ProjectLogStore.add(
          widget.assignment.project,
          summary.isEmpty
              ? 'Extra werk aangepast'
              : 'Extra werk aangepast: $summary',
        );
      } else {
        _extraWorks.add(entry);
        ProjectStore.addExtraWork(widget.assignment.project, entry);
      }
      _extraWorkController.clear();
      _extraHoursController.clear();
      _extraWorkChargeType = _extraWorkChargeTypes.first;
      _extraWorkFiles = [];
      _editingExtraWorkIndex = null;
    });
  }

  void _editExtraWork(int index) {
    if (index < 0 || index >= _extraWorks.length) return;
    final entry = _extraWorks[index];
    setState(() {
      _editingExtraWorkIndex = index;
      _extraWorkController.text = entry.description;
      _extraHoursController.text = _formatPrice(entry.hours);
      _extraWorkFiles = List<PlatformFile>.from(entry.photos);
      _extraWorkChargeType = entry.chargeType;
    });
  }

  void _deleteExtraWork(int index) {
    setState(() {
      if (index < 0 || index >= _extraWorks.length) return;
      final removed = _extraWorks.removeAt(index);
      ProjectStore.extraWorks[widget.assignment.project] =
          List<ExtraWorkEntry>.from(_extraWorks);
      if (_editingExtraWorkIndex == index) {
        _editingExtraWorkIndex = null;
        _extraWorkController.clear();
        _extraHoursController.clear();
        _extraWorkChargeType = _extraWorkChargeTypes.first;
        _extraWorkFiles = [];
      }
      final summary = _truncateText(removed.description, 60);
      ProjectLogStore.add(
        widget.assignment.project,
        summary.isEmpty
            ? 'Extra werk verwijderd'
            : 'Extra werk verwijderd: $summary',
      );
    });
  }

  void _addBackorderItem() {
    final text = _backorderController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _backorderItems.add(text);
      _backorderController.clear();
    });
    ProjectStore.setBackorder(
      widget.assignment.project,
      backorder: true,
      items: _backorderItems,
    );
    ProjectLogStore.add(
      widget.assignment.project,
      'Nabestelling item toegevoegd: ${_truncateText(text, 60)}',
    );
  }

  void _editBackorderItem(int index) {
    if (index < 0 || index >= _backorderItems.length) return;
    final removed = _backorderItems[index];
    _backorderController.text = removed;
    setState(() {
      _backorderItems.removeAt(index);
    });
    ProjectStore.setBackorder(
      widget.assignment.project,
      backorder: true,
      items: _backorderItems,
    );
    ProjectLogStore.add(
      widget.assignment.project,
      'Nabestelling item verwijderd: ${_truncateText(removed, 60)}',
    );
  }

  void _deleteBackorderItem(int index) {
    if (index < 0 || index >= _backorderItems.length) return;
    setState(() {
      final removed = _backorderItems.removeAt(index);
      ProjectLogStore.add(
        widget.assignment.project,
        'Nabestelling item verwijderd: ${_truncateText(removed, 60)}',
      );
    });
    ProjectStore.setBackorder(
      widget.assignment.project,
      backorder: true,
      items: _backorderItems,
    );
  }

  void _submitEstimatedDaysChange() {
    final details =
        widget.details ?? ProjectStore.details[widget.assignment.project];
    final currentDays = details?.estimatedDays ?? 1;
    final parsed = int.tryParse(_daysChangeController.text.trim()) ?? 0;
    if (parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul een geldig aantal dagen in.')),
      );
      return;
    }
    if (parsed == currentDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aantal dagen is ongewijzigd.')),
      );
      return;
    }
    EstimatedDaysChangeStore.add(
      EstimatedDaysChangeRequest(
        project: widget.assignment.project,
        team: widget.assignment.team,
        oldDays: currentDays,
        newDays: parsed,
        requester: CurrentUserStore.name,
        requesterRole: CurrentUserStore.role,
        createdAt: DateTime.now(),
      ),
    );
    ProjectLogStore.add(
      widget.assignment.project,
      'Aanvraag geschatte dagen: $currentDays → $parsed',
    );
    _daysChangeController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aanvraag verstuurd.')),
    );
    setState(() {});
  }

  bool _hasBeforeAfterPhotos() {
    return _beforePhotos.isNotEmpty && _afterPhotos.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final isWorker = CurrentUserStore.role == 'Werknemer';
    final details = widget.details;
    final backorderHours =
        ProjectStore.backorderHours[widget.assignment.project] ?? 0;
    final pendingDaysRequest = EstimatedDaysChangeStore.pendingForProject(
      widget.assignment.project,
    );
    final infoContent = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _InfoTextBlock(
                title: 'Informatie',
                lines: [
                  if (_isBackorder)
                    const _PlainInfoLine(
                      label: 'Type',
                      value: 'Nabestelling',
                    ),
                  _PlainInfoLine(
                    label: 'Klantnaam',
                    value: widget.assignment.project,
                  ),
                  if (details?.phone.trim().isNotEmpty == true)
                    _PlainInfoLine(
                      label: 'Telefoonnummer',
                      value: details!.phone,
                    ),
                  if (details?.address.trim().isNotEmpty == true)
                    _PlainInfoLine(
                      label: 'Adres',
                      value: details!.address,
                    ),
                  if (details?.delivery.trim().isNotEmpty == true)
                    _PlainInfoLine(
                      label: 'Leveradres ramen',
                      value: details!.delivery,
                    ),
                  if (details?.finish.trim().isNotEmpty == true)
                    _PlainInfoLine(
                      label: 'Afwerking',
                      value: details!.finish,
                    ),
                  if (details?.extraNotes.trim().isNotEmpty == true)
                    _PlainInfoLine(
                      label: 'Extra notes',
                      value: details!.extraNotes,
                    ),
                  if (_isBackorder && backorderHours > 0)
                    _PlainInfoLine(
                      label: 'Duur',
                      value: _formatHours(backorderHours),
                    ),
                  if ((ProjectStore.backorderNotes[widget.assignment.project] ??
                          '')
                      .trim()
                      .isNotEmpty)
                    _PlainInfoLine(
                      label: 'Beschrijving nabestelling',
                      value:
                          ProjectStore.backorderNotes[widget.assignment.project]!
                              .trim(),
                    ),
                  if (details != null)
                    _PlainInfoLine(
                      label: 'Geschatte dagen',
                      value: _formatDays(_isBackorder ? 1 : details.estimatedDays),
                    ),
                ],
              ),
              if (!_isBackorder) ...[
                const SizedBox(height: 12),
                if (pendingDaysRequest != null)
                  _InfoTextBlock(
                    title: 'Aanvraag geschatte dagen',
                    lines: [
                      _PlainInfoLine(
                        label: 'Aangevraagd',
                        value:
                            '${pendingDaysRequest.oldDays} → ${pendingDaysRequest.newDays} dagen',
                      ),
                      _PlainInfoLine(
                        label: 'Status',
                        value: pendingDaysRequest.status,
                      ),
                    ],
                  )
                else
                  _InputCard(
                    title: 'Geschatte dagen aanpassen',
                    children: [
                      _PlainInfoLine(
                        label: 'Huidig',
                        value: _formatDays(details?.estimatedDays ?? 1),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _daysChangeController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Nieuw aantal dagen',
                          filled: true,
                          fillColor: const Color(0xFFF4F1EA),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFFE1DAD0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide:
                                const BorderSide(color: Color(0xFF0B2E2B)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _PrimaryButton(
                        label: 'Aanvraag versturen',
                        onTap: _submitEstimatedDaysChange,
                      ),
                    ],
                  ),
              ],
              if (ProjectStore.documents[widget.assignment.project]
                      ?.isNotEmpty ==
                  true) ...[
                const SizedBox(height: 12),
                _ProjectDocumentsCard(
                  customerName: widget.assignment.project,
                ),
              ],
              if (ProjectStore.offers[widget.assignment.project]?.isNotEmpty ==
                  true) ...[
                const SizedBox(height: 12),
                _OfferOverviewCard(
                  customerName: widget.assignment.project,
                ),
              ],
            ],
          );
    final followUpContent = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProjectSiteFollowUp(
                siteTabIndex: _siteTabIndex,
                onTabChange: (index) => setState(() => _siteTabIndex = index),
                beforePhotos: _beforePhotos,
                afterPhotos: _afterPhotos,
                canEdit: true,
                onAddBefore: _pickBeforePhotos,
                onAddAfter: _pickAfterPhotos,
                onRemoveBefore: _removeBeforePhoto,
                onRemoveAfter: _removeAfterPhoto,
              ),
              if ((ProjectStore.comments[widget.assignment.project]
                          ?.isNotEmpty ??
                      false)) ...[
                const SizedBox(height: 12),
                _ProjectCommentsSection(
                  comments:
                      ProjectStore.comments[widget.assignment.project] ??
                          const [],
                  canAdd: false,
                  controller: _commentController,
                  onAdd: () {},
                ),
              ],
              if (isWorker) ...[
                const SizedBox(height: 12),
                _InputCard(
                  title: 'Urenregistratie',
                  children: [
                    if (_workLogs.isEmpty)
                      Text(
                        'Nog geen uren geregistreerd.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: const Color(0xFF6A7C78)),
                      )
                    else
                      ..._workLogs.asMap().entries.map(
                        (entry) {
                          final item = entry.value;
                          final range =
                              '${_formatDate(item.date)} · ${_formatMinutes(item.startMinutes)} - ${_formatMinutes(item.endMinutes)}';
                          final breakText = item.breakMinutes > 0
                              ? ' · pauze ${item.breakMinutes} min'
                              : '';
                          final workersText = item.workers.join(', ');
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '$range$breakText',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        workersText,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFF6A7C78),
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _editWorkLog(entry.key),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteWorkLog(entry.key),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _InlineButton(
                          label: _formatDate(_workDate),
                          icon: Icons.calendar_today,
                          onTap: _pickWorkDate,
                        ),
                        const SizedBox(width: 8),
                        _InlineButton(
                          label: _workStartMinutes == null ||
                                  _workEndMinutes == null
                              ? 'Uren instellen'
                              : '${_formatMinutes(_workStartMinutes!)} - ${_formatMinutes(_workEndMinutes!)}',
                          icon: Icons.schedule,
                          onTap: () async {
                            int? tempStart = _workStartMinutes;
                            int? tempEnd = _workEndMinutes;
                            final tempBreakController = TextEditingController(
                              text: _workBreakController.text,
                            );
                            await showDialog<void>(
                              context: context,
                              builder: (dialogContext) {
                                return StatefulBuilder(
                                  builder: (dialogContext, setDialogState) {
                                    return AlertDialog(
                                      title: const Text('Uren instellen'),
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: _InlineButton(
                                                  label: tempStart == null
                                                      ? 'Beginuur'
                                                      : _formatMinutes(
                                                          tempStart!,
                                                        ),
                                                  icon: Icons.schedule,
                                                  onTap: () async {
                                                    final picked =
                                                        await showTimePicker(
                                                      context: dialogContext,
                                                      initialTime:
                                                          TimeOfDay.now(),
                                                    );
                                                    if (picked == null) return;
                                                    setDialogState(() {
                                                      tempStart =
                                                          _minutesFromTimeOfDay(
                                                        picked,
                                                      );
                                                    });
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: _InlineButton(
                                                  label: tempEnd == null
                                                      ? 'Einduur'
                                                      : _formatMinutes(
                                                          tempEnd!,
                                                        ),
                                                  icon: Icons.schedule,
                                                  onTap: () async {
                                                    final picked =
                                                        await showTimePicker(
                                                      context: dialogContext,
                                                      initialTime:
                                                          TimeOfDay.now(),
                                                    );
                                                    if (picked == null) return;
                                                    setDialogState(() {
                                                      tempEnd =
                                                          _minutesFromTimeOfDay(
                                                        picked,
                                                      );
                                                    });
                                                  },
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          TextField(
                                            controller: tempBreakController,
                                            keyboardType: TextInputType.number,
                                            decoration: InputDecoration(
                                              labelText: 'Pauze (minuten)',
                                              filled: true,
                                              fillColor:
                                                  const Color(0xFFF4F1EA),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFFE1DAD0),
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFF0B2E2B),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(dialogContext).pop(),
                                          child: const Text('Annuleren'),
                                        ),
                                        TextButton(
                                          onPressed: () {
                                            setState(() {
                                              _workStartMinutes = tempStart;
                                              _workEndMinutes = tempEnd;
                                              _workBreakController.text =
                                                  tempBreakController.text;
                                            });
                                            Navigator.of(dialogContext).pop();
                                          },
                                          child: const Text('Opslaan'),
                                        ),
                                      ],
                                    );
                                  },
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _teamWorkers().map((name) {
                        final selected = _selectedWorkers.contains(name);
                        return FilterChip(
                          label: Text(name),
                          selected: selected,
                          onSelected: (value) {
                            setState(() {
                              if (value) {
                                _selectedWorkers.add(name);
                              } else {
                                _selectedWorkers.remove(name);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    _PrimaryButton(
                      label: _editingWorkLogIndex == null
                          ? 'Uren toevoegen'
                          : 'Uren opslaan',
                      onTap: _saveWorkLog,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              _ExtraWorkSection(
                canEdit: true,
                isEditingExtraWork: _editingExtraWorkIndex != null,
                extraWorks: _extraWorks,
                extraWorkController: _extraWorkController,
                extraHoursController: _extraHoursController,
                extraWorkChargeType: _extraWorkChargeType,
                onChargeTypeChanged: (value) => setState(() {
                  _extraWorkChargeType =
                      value ?? _extraWorkChargeTypes.first;
                }),
                extraWorkFiles: _extraWorkFiles,
                onRemoveExtraPhoto: (index) => setState(() {
                  if (index < 0 || index >= _extraWorkFiles.length) return;
                  _extraWorkFiles.removeAt(index);
                }),
                onEditExtraWork: _editExtraWork,
                onDeleteExtraWork: _deleteExtraWork,
                onPickExtraPhotos: _pickExtraWorkPhotos,
                onAddExtraWork: _addExtraWork,
                showExtraWorkSection: true,
              ),
              const SizedBox(height: 12),
              _InputCard(
                title: 'Afronding',
                children: [
                  _ChoiceToggle(
                    label: 'Status',
                    options: const ['Nabestelling', 'Klaar'],
                    selectedIndex: _isBackorder ? 0 : 1,
                    onSelect: (index) => setState(() {
                      _isBackorder = index == 0;
                    }),
                  ),
                  if (_isBackorder) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _backorderNoteController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Beschrijving nabestelling',
                        filled: true,
                        fillColor: const Color(0xFFF4F1EA),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _AddItemRow(
                      controller: _backorderController,
                      onAdd: _addBackorderItem,
                    ),
                    const SizedBox(height: 10),
                    if (_backorderItems.isEmpty)
                      Text(
                        'Nog geen materialen',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: const Color(0xFF6A7C78)),
                      )
                    else
                      ..._backorderItems.asMap().entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _EditableBackorderItemRow(
                            label: entry.value,
                            onEdit: () => _editBackorderItem(entry.key),
                            onDelete: () => _deleteBackorderItem(entry.key),
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  _PrimaryButton(
                    label: 'Verzenden',
                    onTap: () {
                      if (!_hasBeforeAfterPhotos()) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Voeg foto’s voor en na de werf toe.'),
                          ),
                        );
                        return;
                      }
                      if (_isBackorder && _backorderItems.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Voeg eerst materialen toe.'),
                          ),
                        );
                        return;
                      }
                      ProjectStore.setBackorder(
                        widget.assignment.project,
                        backorder: _isBackorder,
                        items: _isBackorder ? _backorderItems : const [],
                      );
                      if (_isBackorder) {
                        final note = _backorderNoteController.text.trim();
                        final previousNote =
                            ProjectStore.backorderNotes[widget.assignment.project] ??
                                '';
                        if (note.isNotEmpty) {
                          ProjectStore.backorderNotes[
                              widget.assignment.project] = note;
                        } else {
                          ProjectStore.backorderNotes
                              .remove(widget.assignment.project);
                        }
                        if (note.trim() != previousNote.trim()) {
                          final summary = _truncateText(note, 80);
                          if (summary.isNotEmpty) {
                            ProjectLogStore.add(
                              widget.assignment.project,
                              'Beschrijving nabestelling aangepast: $summary',
                            );
                          }
                        }
                      } else {
                        ProjectStore.backorderNotes
                            .remove(widget.assignment.project);
                      }
                      ProjectStore.completionTeams[widget.assignment.project] =
                          widget.assignment.team;
                      ScheduleStore.scheduled.removeWhere(
                        (assignment) =>
                            assignment.project == widget.assignment.project,
                      );
                      if (_isBackorder) {
                        ProjectStore.moveToGroupStatus(
                          name: widget.assignment.project,
                          group: 'Nabestellingen',
                          status: 'In opmaak',
                        );
                        ProjectLogStore.add(
                          widget.assignment.project,
                          'Nabestelling verzonden',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Nabestelling verzonden'),
                          ),
                        );
                      } else {
                        final targetGroup =
                            ProjectStore.findGroupForProject(
                                  widget.assignment.project,
                                ) ??
                                widget.assignment.group;
                        ProjectStore.moveToGroupStatus(
                          name: widget.assignment.project,
                          group: targetGroup,
                          status: 'Afgewerkt',
                        );
                        ProjectLogStore.add(
                          widget.assignment.project,
                          'Project afgerond',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Project afgerond')),
                        );
                      }
                      setState(() {});
                      widget.onUpdated?.call();
                    },
                  ),
                ],
              ),
            ],
          );
    final tabContent = _tabIndex == 0 ? infoContent : followUpContent;

    if (isWorker) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TabToggle(
            labels: const ['Informatie', 'Werfopvolging'],
            selectedIndex: _tabIndex,
            onSelect: (index) => setState(() => _tabIndex = index),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tabContent,
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabToggle(
          labels: const ['Informatie', 'Werfopvolging'],
          selectedIndex: _tabIndex,
          onSelect: (index) => setState(() => _tabIndex = index),
        ),
        const SizedBox(height: 12),
        tabContent,
        const SizedBox(height: 12),
      ],
    );
  }
}

class _PlanningTabState extends State<PlanningTab> {
  List<String> get _teams {
    _RoleManagementStore.seedIfEmpty();
    final teams = _RoleManagementStore.teams.map((team) => team.name).toList();
    return teams.isEmpty ? ['Team 1'] : teams;
  }
  String _selectedPlanningGroup = _projectGroups.first;
  final TextEditingController _planningSearchController =
      TextEditingController();

  @override
  void dispose() {
    _planningSearchController.dispose();
    super.dispose();
  }

  bool _matchesPlanningSearch(String name) {
    final query = _planningSearchController.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    return name.toLowerCase().contains(query);
  }

  List<_PlanningItem> get _deliveredNew {
    final items = ProjectStore.projectsByGroup['Klanten']?['Geleverd'] ??
        const <String>[];
    return items
        .map((name) => _PlanningItem(
              name: name,
              estimatedDays: ProjectStore.details[name]?.estimatedDays ?? 1,
              phone: ProjectStore.details[name]?.phone ?? '—',
              address: ProjectStore.details[name]?.address ?? '—',
              group: 'Klanten',
            ))
        .toList();
  }

  List<_PlanningItem> get _deliveredBackorder {
    final items = ProjectStore.projectsByGroup['Nabestellingen']?['Geleverd'] ??
        const <String>[];
    return items
        .map((name) => _PlanningItem(
              name: name,
              estimatedDays: 1,
              phone: ProjectStore.details[name]?.phone ?? '—',
              address: ProjectStore.details[name]?.address ?? '—',
              group: 'Nabestellingen',
            ))
        .toList();
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isBackorderGroup(String projectName, String fallbackGroup) {
    if (fallbackGroup == 'Nabestellingen') return true;
    final group = ProjectStore.findGroupForProject(projectName);
    return group == 'Nabestellingen';
  }

  int _countProjectsOnDay(String team, DateTime day) {
    final normalized = _normalizeDate(day);
    int count = 0;
    for (final assignment in widget.scheduled) {
      if (assignment.team != team) continue;
      if (_isBackorderGroup(assignment.project, assignment.group)) continue;
      final start = _normalizeDate(assignment.startDate);
      final end = _normalizeDate(assignment.endDate);
      if (!normalized.isBefore(start) && !normalized.isAfter(end)) {
        count += 1;
      }
    }
    return count;
  }

  int _countBackordersOnDay(String team, DateTime day) {
    final normalized = _normalizeDate(day);
    int count = 0;
    for (final assignment in widget.scheduled) {
      if (assignment.team != team) continue;
      if (!_isBackorderGroup(assignment.project, assignment.group)) continue;
      final start = _normalizeDate(assignment.startDate);
      final end = _normalizeDate(assignment.endDate);
      if (!normalized.isBefore(start) && !normalized.isAfter(end)) {
        count += 1;
      }
    }
    return count;
  }

  bool _canScheduleOnDay(
    String team,
    DateTime day,
    bool isBackorder,
  ) {
    final projects = _countProjectsOnDay(team, day);
    final backorders = _countBackordersOnDay(team, day);
    if (isBackorder) {
      return backorders + 1 <= 5 && projects <= 3;
    }
    return projects + 1 <= 3 && backorders <= 5;
  }

  bool _isWorkingDay(DateTime date, String team) {
    final weekday = date.weekday;
    final workingDays = _RoleManagementStore.workingDaysForTeam(team);
    if (!workingDays.contains(weekday)) {
      return false;
    }
    return !PlanningCalendarStore.isNonWorkingDay(date);
  }

  DateTime? _calculateEndDate(
    String team,
    DateTime start,
    int days,
    bool isBackorder,
  ) {
    if (days <= 0) return null;
    final normalizedStart = _normalizeDate(start);
    if (!_isWorkingDay(normalizedStart, team)) return null;
    if (isBackorder) {
      return normalizedStart;
    }
    var current = normalizedStart;
    int counted = 0;
    for (int i = 0; i < 366; i++) {
      final day = current.add(Duration(days: i));
      final normalized = _normalizeDate(day);
      if (_isWorkingDay(normalized, team)) {
        counted += 1;
        if (counted == days) {
          return normalized;
        }
      }
    }
    return null;
  }

  bool _canScheduleRange(
    String team,
    DateTime start,
    DateTime end,
    bool isBackorder,
  ) {
    var day = _normalizeDate(start);
    final last = _normalizeDate(end);
    while (!day.isAfter(last)) {
      if (_isWorkingDay(day, team)) {
        if (!_canScheduleOnDay(team, day, isBackorder)) {
          return false;
        }
      }
      day = day.add(const Duration(days: 1));
    }
    return true;
  }

  List<DateTime> _availableStartDates(
    String team,
    int days,
    bool isBackorder,
  ) {
    final starts = <DateTime>[];
    final today = _normalizeDate(DateTime.now());
    for (int i = 0; i < 720; i++) {
      final candidate = today.add(Duration(days: i));
      if (!_isWorkingDay(candidate, team)) continue;
      final end = _calculateEndDate(team, candidate, days, isBackorder);
      if (end != null) {
        starts.add(candidate);
      }
    }
    return starts;
  }

  List<_ExternalProjectItem> _externalProjectsForGroupName(
    List<TeamAssignment> assignments,
    String group,
  ) {
    final filtered = <_ExternalProjectItem>[];
    for (final assignment in assignments) {
      final assignmentGroup =
          ProjectStore.findGroupForProject(assignment.project) ?? 'Klanten';
      if (assignmentGroup != group) continue;
      filtered.add(
        _ExternalProjectItem(
          assignment: assignment,
          details: ProjectStore.details[assignment.project],
        ),
      );
    }
    filtered.sort((a, b) =>
        a.assignment.startDate.compareTo(b.assignment.startDate));
    return filtered;
  }

  void _assignItem(
    _PlanningItem item,
    String team,
    DateTime startDate, {
    double? backorderHours,
  }) {
    final plannedDays = item.group == 'Nabestellingen'
        ? 1
        : _clampScheduledDays(item.estimatedDays);
    final endDate = _calculateEndDate(
      team,
      startDate,
      plannedDays,
      item.group == 'Nabestellingen',
    );
    if (endDate == null) {
      return;
    }
    if (!_canScheduleRange(team, startDate, endDate, item.group == 'Nabestellingen')) {
      return;
    }
    setState(() {
      widget.scheduled.add(TeamAssignment(
        project: item.name,
        team: team,
        startDate: startDate,
        endDate: endDate,
        estimatedDays: plannedDays,
        isBackorder: item.group == 'Nabestellingen',
        group: item.group,
      ));
      // Lists are derived from ProjectStore now.
    });
    if (item.group == 'Nabestellingen') {
      final hours = backorderHours ?? 0;
      if (hours > 0) {
        ProjectStore.backorderHours[item.name] = hours;
      } else {
        ProjectStore.backorderHours.remove(item.name);
      }
    }
    final rangeLabel =
        '${_formatDate(startDate)} - ${_formatDate(endDate)}';
    final hoursLabel = item.group == 'Nabestellingen' &&
            (backorderHours ?? 0) > 0
        ? ' · ${_formatHours(backorderHours!)}'
        : '';
    ProjectLogStore.add(
      item.name,
      'Planning ingepland: $team ($rangeLabel)$hoursLabel',
    );
    if (item.group != 'Nabestellingen') {
      final details = ProjectStore.details[item.name];
      if (details != null && details.estimatedDays != plannedDays) {
        ProjectStore.details[item.name] = ProjectDetails(
          address: details.address,
          phone: details.phone,
          delivery: details.delivery,
          finish: details.finish,
          extraNotes: details.extraNotes,
          estimatedDays: plannedDays,
        );
      }
    }
    ProjectStore.updateStatus(
      name: item.name,
      group: item.group,
      status: 'Ingepland',
    );
    widget.onScheduleChanged?.call();
  }

  void _rescheduleAssignment(TeamAssignment assignment, DateTime newStart) {
    final isBackorder = assignment.group == 'Nabestellingen';
    final days = isBackorder ? 1 : assignment.estimatedDays;
    final endDate =
        _calculateEndDate(assignment.team, newStart, days, isBackorder);
    if (endDate == null) return;
    if (!_canScheduleRange(assignment.team, newStart, endDate, isBackorder)) {
      return;
    }
    final updated = TeamAssignment(
      project: assignment.project,
      team: assignment.team,
      startDate: _normalizeDate(newStart),
      endDate: endDate,
      estimatedDays: assignment.estimatedDays,
      isBackorder: assignment.isBackorder,
      group: assignment.group,
    );
    var didUpdate = false;
    final index = widget.scheduled.indexWhere(
      (item) =>
          item.project == assignment.project &&
          item.team == assignment.team &&
          item.startDate == assignment.startDate &&
          item.endDate == assignment.endDate,
    );
    if (index != -1) {
      widget.scheduled[index] = updated;
      didUpdate = true;
    }
    final storeIndex = ScheduleStore.scheduled.indexWhere(
      (item) =>
          item.project == assignment.project &&
          item.team == assignment.team &&
          item.startDate == assignment.startDate &&
          item.endDate == assignment.endDate,
    );
    if (storeIndex != -1) {
      ScheduleStore.scheduled[storeIndex] = updated;
      didUpdate = true;
    }
    if (!didUpdate) return;
    setState(() {});
    ProjectLogStore.add(
      assignment.project,
      'Planning aangepast: ${_formatDate(newStart)} - ${_formatDate(endDate)}',
    );
    AppDataStore.scheduleSave();
    widget.onScheduleChanged?.call();
  }

  void _cancelAssignment(TeamAssignment assignment) {
    setState(() {
      widget.scheduled.remove(assignment);
      // Lists are derived from ProjectStore now.
    });
    ProjectLogStore.add(
      assignment.project,
      'Planning geannuleerd',
    );
    ProjectStore.updateStatus(
      name: assignment.project,
      group: assignment.group,
      status: 'Geleverd',
    );
    widget.onScheduleChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isExternal = _isExternalRole(CurrentUserStore.role);
    final isWorker = CurrentUserStore.role == 'Werknemer';
    final isProjectLeader = CurrentUserStore.role == 'Projectleider';
    final onlyScheduledView = isExternal || isProjectLeader;
    final visibleTeams = isProjectLeader ? _teams : _teamsForCurrentUser();
    final visibleScheduled = (isExternal && !isProjectLeader)
        ? widget.scheduled
            .where((assignment) => visibleTeams.contains(assignment.team))
            .toList()
        : widget.scheduled;
    final overviewAssignments = isProjectLeader
        ? widget.scheduled
        : (isExternal ? visibleScheduled : widget.scheduled);
    final filteredDeliveredNew =
        _deliveredNew.where((item) => _matchesPlanningSearch(item.name)).toList();
    final filteredDeliveredBackorder = _deliveredBackorder
        .where((item) => _matchesPlanningSearch(item.name))
        .toList();
    final filteredExternalScheduled = visibleScheduled
        .where((assignment) => _matchesPlanningSearch(assignment.project))
        .toList();
    final overviewGrouped = <String, List<TeamAssignment>>{};
    for (final item in overviewAssignments) {
      if (!visibleTeams.contains(item.team)) continue;
      overviewGrouped.putIfAbsent(item.team, () => []).add(item);
    }
    final overviewTeams = overviewGrouped.keys.toList()..sort();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _SectionHeader(
                      title: 'Planning',
                      subtitle: '',
                    ),
                  ),
                  if (!onlyScheduledView)
                    Row(
                      children: [
                        _InlineButton(
                        label: 'Verlof',
                          onTap: () => Navigator.of(context).push(
                            _appPageRoute(
                              builder: (_) => HolidayCalendarScreen(
                                assignments: widget.scheduled,
                                onSaved: widget.onCalendarSaved,
                              ),
                            ),
                          ),
                          icon: Icons.calendar_today,
                        ),
                        const SizedBox(width: 8),
                        _InlineButton(
                          label: 'Overzicht',
                          onTap: () => Navigator.of(context).push(
                            _appPageRoute(
                              builder: (_) => _PlanningOverviewScreen(
                                assignments: widget.scheduled,
                                onCancel: _cancelAssignment,
                                canEditPlanning:
                                    CurrentUserStore.role == 'Planner' ||
                                        CurrentUserStore.role == 'Beheerder',
                                onReschedule: _rescheduleAssignment,
                                availableStarts: _availableStartDates,
                                calculateEndDate: _calculateEndDate,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              if (!isWorker) ...[
                const SizedBox(height: 12),
                if (!onlyScheduledView) ...[
                  _GroupToggle(
                  groups: _projectGroups,
                  selected: _selectedPlanningGroup,
                  onSelect: (group) => setState(() {
                    _selectedPlanningGroup = group;
                  }),
                  labelBuilder: !isExternal
                      ? (group) {
                          final count = group == 'Klanten'
                              ? _deliveredNew.length
                              : _deliveredBackorder.length;
                          return '$group ($count)';
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                _SearchField(
                  controller: _planningSearchController,
                  hintText: 'Zoek klant',
                  onChanged: (_) => setState(() {}),
                ),
                ],
              ],
            ],
          ),
        ),
        Expanded(
          child: ListView(
            key: const ValueKey('planning'),
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
              if (onlyScheduledView) ...[
                const SizedBox(height: 12),
                if (overviewTeams.isEmpty)
                  const _EmptyStateCard(
                    title: 'Geen planning',
                    subtitle: 'Nog geen ingeplande projecten.',
                  )
                else
                  ...overviewTeams.map(
                    (team) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _TeamMonthlyScheduleCard(
                        team: team,
                        assignments: overviewGrouped[team] ?? const [],
                        onOpen: (assignment) {
                          Navigator.of(context).push(
                            _appPageRoute(
                              builder: (_) => ProjectDetailScreen(
                                customerName: assignment.project,
                                group: assignment.group,
                                status: ProjectStore.findStatusForProject(
                                      assignment.project,
                                    ) ??
                                    'Ingepland',
                              ),
                            ),
                          );
                        },
                        onCancel: (_) async {},
                        canEditPlanning: false,
                        onReschedule: _rescheduleAssignment,
                        availableStarts: _availableStartDates,
                        calculateEndDate: _calculateEndDate,
                        showHeader: CurrentUserStore.role != 'Werknemer',
                        initiallyExpanded:
                            CurrentUserStore.role == 'Werknemer',
                      ),
                    ),
                  ),
              ] else ...[
                const SizedBox(height: 12),
                if (!isExternal && !isProjectLeader) ...[
                  if (_selectedPlanningGroup == 'Klanten') ...[
                      ...filteredDeliveredNew.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _PlanningAssignCard(
                                key: ValueKey(item.name),
                                item: item,
                                teams: _teams,
                                onAssign: _assignItem,
                                availableStarts: _availableStartDates,
                                calculateEndDate: _calculateEndDate,
                                scheduled: widget.scheduled,
                              ),
                            ),
                          ),
                      if (filteredDeliveredNew.isEmpty)
                        const _EmptyStateCard(
                          title: 'Geen projecten',
                          subtitle: 'Geen geleverde nieuwe projecten.',
                        ),
                  ] else ...[
                      ...filteredDeliveredBackorder.map(
                            (item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _PlanningAssignCard(
                                key: ValueKey(item.name),
                                item: item,
                                teams: _teams,
                                onAssign: _assignItem,
                                availableStarts: _availableStartDates,
                                calculateEndDate: _calculateEndDate,
                                scheduled: widget.scheduled,
                              ),
                            ),
                          ),
                      if (filteredDeliveredBackorder.isEmpty)
                        const _EmptyStateCard(
                          title: 'Geen nabestellingen',
                          subtitle: 'Geen geleverde nabestellingen.',
                        ),
                  ],
                ],
                if (onlyScheduledView) ...[
                  ..._externalProjectsForGroupName(
                    filteredExternalScheduled,
                    _selectedPlanningGroup,
                  ).map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ExternalPlanningProjectCard(
                        assignment: item.assignment,
                        details: item.details,
                        onOpen: () async {
                          final changed =
                              await Navigator.of(context).push<bool>(
                            _appPageRoute(
                              builder: (_) => ProjectDetailScreen(
                                customerName: item.assignment.project,
                                group: item.assignment.group,
                                status: ProjectStore.findStatusForProject(
                                      item.assignment.project,
                                    ) ??
                                    'Ingepland',
                              ),
                            ),
                          );
                          if (changed == true) {
                            setState(() {});
                          }
                        },
                      ),
                    ),
                  ),
                  if (_externalProjectsForGroupName(
                    visibleScheduled,
                    _selectedPlanningGroup,
                  ).isEmpty)
                    _EmptyStateCard(
                      title: 'Geen projecten ingepland',
                      subtitle: _selectedPlanningGroup == 'Klanten'
                          ? 'Nog geen ingeplande projecten voor klanten.'
                          : 'Nog geen ingeplande projecten voor nabestellingen.',
                    ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ProjectsTab extends StatefulWidget {
  const ProjectsTab({
    super.key,
    required this.account,
    required this.scheduled,
  });

  final TestAccount account;
  final List<TeamAssignment> scheduled;

  @override
  State<ProjectsTab> createState() => _ProjectsTabState();
}

class StatisticsTab extends StatefulWidget {
  const StatisticsTab({
    super.key,
    required this.account,
    required this.scheduled,
  });

  final TestAccount account;
  final List<TeamAssignment> scheduled;

  @override
  State<StatisticsTab> createState() => _StatisticsTabState();
}

class _StatisticsTabState extends State<StatisticsTab> {
  final TextEditingController _rateController = TextEditingController(text: '45');
  late DateTime _weekStart;
  DateTime? _selectedWeekDay;
  late int _selectedYear;
  String? _selectedTeam;
  int _performancePeriodIndex = 1; // 0 dag, 1 week, 2 maand
  late DateTime _performanceDay;
  late DateTime _performanceWeekStart;
  late DateTime _performanceMonthStart;

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
    _selectedWeekDay = _dateOnly(DateTime.now());
    _selectedYear = DateTime.now().year;
    _performanceDay = _dateOnly(DateTime.now());
    _performanceWeekStart = _startOfWeek(_performanceDay);
    _performanceMonthStart =
        DateTime(_performanceDay.year, _performanceDay.month, 1);
    final teams = _teamsForCurrentUser();
    if (teams.isNotEmpty) {
      _selectedTeam = teams.first;
    }
  }

  @override
  void dispose() {
    _rateController.dispose();
    super.dispose();
  }

  bool get _isExternal => _isExternalRole(CurrentUserStore.role);

  bool get _isAdmin =>
      !_isExternal && _adminRoles.contains(CurrentUserStore.role);

  List<String> get _visibleTeams => _teamsForCurrentUser();

  List<String> _membersForTeam(String team) {
    _RoleManagementStore.seedIfEmpty();
    return _RoleManagementStore.assignments
        .where((assignment) =>
            assignment.role == 'Werknemer' && assignment.team == team)
        .map((assignment) => assignment.name)
        .toList();
  }

  int _workingDaysCount(String team, DateTime start, DateTime end) {
    int count = 0;
    var day = _dateOnly(start);
    final last = _dateOnly(end);
    final workingDays = _RoleManagementStore.workingDaysForTeam(team);
    while (!day.isAfter(last)) {
      if (workingDays.contains(day.weekday) &&
          !PlanningCalendarStore.isNonWorkingDay(day)) {
        count += 1;
      }
      day = day.add(const Duration(days: 1));
    }
    return count;
  }

  double _offerHoursForProject(String name) {
    final lines = ProjectStore.offers[name] ?? const <OfferLine>[];
    double total = 0;
    for (final line in lines) {
      final item = OfferCatalogStore.findItem(line.category, line.item);
      final hours = item?.hours ?? 0;
      total += hours * line.quantity;
    }
    return total;
  }

  double _offerPriceForProject(String name) {
    final lines = ProjectStore.offers[name] ?? const <OfferLine>[];
    double total = 0;
    for (final line in lines) {
      final item = OfferCatalogStore.findItem(line.category, line.item);
      final price = item?.price ?? 0;
      total += price * line.quantity;
    }
    return total;
  }

  double _extraHoursForProject(String name) {
    final entries = ProjectStore.extraWorks[name] ?? const <ExtraWorkEntry>[];
    double total = 0;
    for (final entry in entries) {
      total += entry.hours;
    }
    return total;
  }

  double _avgProjectsPerWeek(Iterable<TeamAssignment> assignments) {
    if (assignments.isEmpty) return 0;
    final weeks = <String, int>{};
    for (final assignment in assignments) {
      final start = assignment.startDate;
      final weekKey = '${start.year}-W${_weekNumber(start)}';
      weeks[weekKey] = (weeks[weekKey] ?? 0) + 1;
    }
    final total = weeks.values.fold<int>(0, (sum, v) => sum + v);
    return total / weeks.length;
  }

  int _weekNumber(DateTime date) {
    final firstDay = DateTime(date.year, 1, 1);
    final diff = date.difference(firstDay).inDays;
    return ((diff + firstDay.weekday) / 7).ceil();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _startOfWeek(DateTime date) {
    final normalized = _dateOnly(date);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  List<DateTime> _weekDays(DateTime start) {
    return List.generate(7, (index) => start.add(Duration(days: index)));
  }

  String _weekdayLabel(DateTime day) {
    const labels = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
    return labels[day.weekday - 1];
  }

  String _monthLabel(int month) {
    const labels = [
      'Jan',
      'Feb',
      'Mrt',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Dec',
    ];
    return labels[month - 1];
  }

  DateTime _performanceStartDate() {
    if (_performancePeriodIndex == 0) {
      return _performanceDay;
    }
    if (_performancePeriodIndex == 1) {
      return _performanceWeekStart;
    }
    return _performanceMonthStart;
  }

  DateTime _performanceEndDate() {
    if (_performancePeriodIndex == 0) {
      return _performanceDay;
    }
    if (_performancePeriodIndex == 1) {
      return _performanceWeekStart.add(const Duration(days: 6));
    }
    return DateTime(_performanceMonthStart.year, _performanceMonthStart.month + 1, 0);
  }

  String _contractorForTeam(String team) {
    _RoleManagementStore.seedIfEmpty();
    final match = _RoleManagementStore.teams.firstWhere(
      (entry) => entry.name == team,
      orElse: () => _TeamAssignment(
        name: team,
        contractor: 'Onbekend',
        workingDays: _RoleManagementStore._defaultWorkingDays,
      ),
    );
    return match.contractor.isEmpty ? 'Onbekend' : match.contractor;
  }

  Set<String> _projectsForTeamInRange(
    String team,
    DateTime start,
    DateTime end,
  ) {
    final teamMembers = _membersForTeam(team);
    if (teamMembers.isEmpty) {
      return <String>{};
    }
    final projects = <String>{};
    for (final entry in ProjectStore.workLogs.entries) {
      final project = entry.key;
      for (final log in entry.value) {
        final day = _dateOnly(log.date);
        if (day.isBefore(start) || day.isAfter(end)) {
          continue;
        }
        if (log.workers.any((worker) => teamMembers.contains(worker))) {
          projects.add(project);
          break;
        }
      }
    }
    return projects;
  }

  _PlacementStats _placementStatsForProjects(Set<String> projects) {
    int windows = 0;
    int sliding = 0;
    int doors = 0;
    int gates = 0;
    int finishMdf = 0;
    int finishPvc = 0;
    int finishPleister = 0;
    final windowBreakdown = <String, int>{};
    final slidingBreakdown = <String, int>{};
    final doorBreakdown = <String, int>{};
    final gateBreakdown = <String, int>{};
    final mdfBreakdown = <String, int>{};
    final pvcBreakdown = <String, int>{};
    final pleisterBreakdown = <String, int>{};

    for (final project in projects) {
      final lines = ProjectStore.offers[project] ?? const <OfferLine>[];
      for (final line in lines) {
        final category = line.category.toLowerCase();
        final item = line.item;
        final qty = line.quantity;
        if (category.contains('schuifraam')) {
          sliding += qty;
          slidingBreakdown[item] = (slidingBreakdown[item] ?? 0) + qty;
          continue;
        }
        if (category.contains('raam montage')) {
          windows += qty;
          windowBreakdown[item] = (windowBreakdown[item] ?? 0) + qty;
          continue;
        }
        if (category.contains('deur montage')) {
          doors += qty;
          doorBreakdown[item] = (doorBreakdown[item] ?? 0) + qty;
          continue;
        }
        if (category.contains('afwerking') && category.contains('mdf')) {
          finishMdf += qty;
          mdfBreakdown[item] = (mdfBreakdown[item] ?? 0) + qty;
          continue;
        }
        if (category.contains('afwerking') && category.contains('pvc')) {
          finishPvc += qty;
          pvcBreakdown[item] = (pvcBreakdown[item] ?? 0) + qty;
          continue;
        }
        if (category.contains('afwerking') && category.contains('pleister')) {
          finishPleister += qty;
          pleisterBreakdown[item] = (pleisterBreakdown[item] ?? 0) + qty;
          continue;
        }
        if (item.toLowerCase().contains('poort')) {
          gates += qty;
          gateBreakdown[item] = (gateBreakdown[item] ?? 0) + qty;
        }
      }
    }

    return _PlacementStats(
      windows: windows,
      sliding: sliding,
      doors: doors,
      gates: gates,
      finishMdf: finishMdf,
      finishPvc: finishPvc,
      finishPleister: finishPleister,
      windowBreakdown: windowBreakdown,
      slidingBreakdown: slidingBreakdown,
      doorBreakdown: doorBreakdown,
      gateBreakdown: gateBreakdown,
      mdfBreakdown: mdfBreakdown,
      pvcBreakdown: pvcBreakdown,
      pleisterBreakdown: pleisterBreakdown,
    );
  }

  _ExtraHoursBreakdown _extraHoursBreakdownForProjects(Set<String> projects) {
    double chargeable = 0;
    double internal = 0;
    for (final project in projects) {
      final entries = ProjectStore.extraWorks[project] ?? const [];
      for (final entry in entries) {
        final type = entry.chargeType.trim().toLowerCase();
        if (type.contains('interne')) {
          internal += entry.hours;
        } else {
          chargeable += entry.hours;
        }
      }
    }
    return _ExtraHoursBreakdown(
      chargeable: chargeable,
      internal: internal,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSeePrices = _canSeeOfferPrices(CurrentUserStore.role);
    final canSeeHours = _canSeeOfferHours(CurrentUserStore.role);
    final isWorker = CurrentUserStore.role == 'Werknemer';
    final isSubcontractorAdmin =
        CurrentUserStore.role == 'Onderaannemer beheerder' ||
            CurrentUserStore.role == 'Onderaannemer';

    final assignments = _isExternal
        ? widget.scheduled
            .where((assignment) => _visibleTeams.contains(assignment.team))
            .toList()
        : widget.scheduled;

    final avgPerWeek = _avgProjectsPerWeek(assignments);

    double totalOfferPrice = 0;
    double totalOfferHours = 0;
    double totalExtraHours = 0;
    final projectNames = <String>{};
    if (_isExternal) {
      for (final assignment in assignments) {
        projectNames.add(assignment.project);
      }
      for (final entry in ProjectStore.completionTeams.entries) {
        if (_visibleTeams.contains(entry.value)) {
          projectNames.add(entry.key);
        }
      }
    } else {
      for (final group in ProjectStore.projectsByGroup.values) {
        for (final list in group.values) {
          projectNames.addAll(list);
        }
      }
    }
    for (final name in projectNames) {
      totalOfferPrice += _offerPriceForProject(name);
      totalOfferHours += _offerHoursForProject(name);
      totalExtraHours += _extraHoursForProject(name);
    }
    final avgCost =
        projectNames.isEmpty ? 0.0 : totalOfferPrice / projectNames.length;

    final rate = double.tryParse(_rateController.text.trim()) ?? 0;
    final estimatedValue = rate * (totalOfferHours + totalExtraHours);

    if (isWorker) {
      final user = CurrentUserStore.name;
      final now = DateTime.now();
      final weekDays = _weekDays(_weekStart);
      final paidByDay = <DateTime, double>{};
      final actualByDay = <DateTime, double>{};
      final projectsByDay = <DateTime, Set<String>>{};
      final paidByMonth = <int, double>{};
      final actualByMonth = <int, double>{};
      double prevMonthPaid = 0;
      double prevMonthActual = 0;
      double currentMonthPaid = 0;
      double currentMonthActual = 0;
      final prevMonthStart = DateTime(now.year, now.month - 1, 1);
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart = DateTime(now.year, now.month + 1, 1);

      for (final entry in ProjectStore.workLogs.entries) {
        final project = entry.key;
        final logs = entry.value;
        if (logs.isEmpty) continue;
        final totalPaid =
            _offerHoursForProject(project) + _extraHoursForProject(project);
        double totalPersonHours = 0;
        for (final log in logs) {
          final minutes =
              log.endMinutes - log.startMinutes - log.breakMinutes;
          if (minutes <= 0) continue;
          totalPersonHours += (minutes / 60) * log.workers.length;
        }
        if (totalPersonHours <= 0) continue;
        final factor = totalPaid / totalPersonHours;
        for (final log in logs) {
          if (!log.workers.contains(user)) continue;
          final minutes =
              log.endMinutes - log.startMinutes - log.breakMinutes;
          if (minutes <= 0) continue;
          final hours = minutes / 60;
          final day = _dateOnly(log.date);
          final paid = hours * factor;
          actualByDay[day] = (actualByDay[day] ?? 0) + hours;
          paidByDay[day] = (paidByDay[day] ?? 0) + paid;
          projectsByDay.putIfAbsent(day, () => <String>{}).add(project);
          if (day.isAfter(prevMonthStart.subtract(const Duration(days: 1))) &&
              day.isBefore(currentMonthStart)) {
            prevMonthActual += hours;
            prevMonthPaid += paid;
          }
          if (day.isAfter(currentMonthStart.subtract(const Duration(days: 1))) &&
              day.isBefore(nextMonthStart)) {
            currentMonthActual += hours;
            currentMonthPaid += paid;
          }
          if (day.year == _selectedYear) {
            final month = day.month;
            actualByMonth[month] = (actualByMonth[month] ?? 0) + hours;
            paidByMonth[month] = (paidByMonth[month] ?? 0) + paid;
          }
        }
      }

      final maxWeekValue = weekDays.fold<double>(
        0,
        (maxValue, day) {
          final paid = paidByDay[day] ?? 0;
          final actual = actualByDay[day] ?? 0;
          final dayMax = paid > actual ? paid : actual;
          return dayMax > maxValue ? dayMax : maxValue;
        },
      );
      final barMax = maxWeekValue <= 0 ? 1 : maxWeekValue;
      final selectedDay = weekDays.firstWhere(
        (day) =>
            _selectedWeekDay != null &&
            _dateOnly(_selectedWeekDay!) == day,
        orElse: () => weekDays.first,
      );
      final selectedProjects =
          projectsByDay[selectedDay]?.toList() ?? const [];

      return Column(
        key: const ValueKey('stats'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SectionHeader(
                title: 'Statistieken',
                subtitle: 'Jouw overzicht',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              children: [
                _InputCard(
                  title: 'Uren per dag (deze week)',
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => setState(() {
                            _weekStart =
                                _weekStart.subtract(const Duration(days: 7));
                          }),
                        ),
                        Expanded(
                          child: Text(
                            '${_formatDate(_weekStart)} - ${_formatDate(_weekStart.add(const Duration(days: 6)))}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => setState(() {
                            _weekStart =
                                _weekStart.add(const Duration(days: 7));
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: weekDays.map((day) {
                        final paid = paidByDay[day] ?? 0;
                        final actual = actualByDay[day] ?? 0;
                        final paidHeight = (paid / barMax) * 80;
                        final actualHeight = (actual / barMax) * 80;
                        final isSelected = selectedDay == day;
                        return Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() {
                              _selectedWeekDay = day;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF0B2E2B)
                                        .withValues(alpha: 0.06)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 90,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: actualHeight,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFB8ADA0),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          width: 8,
                                          height: paidHeight,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0B2E2B),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _weekdayLabel(day),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: isSelected
                                              ? const Color(0xFF0B2E2B)
                                              : const Color(0xFF6A7C78),
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _LegendDot(
                          color: const Color(0xFF0B2E2B),
                          label: 'Gekregen uren',
                        ),
                        const SizedBox(width: 12),
                        _LegendDot(
                          color: const Color(0xFFB8ADA0),
                          label: 'Gepresteerd',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Projecten op ${_formatDate(selectedDay)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    if (selectedProjects.isEmpty)
                      Text(
                        'Geen projecten.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF6A7C78)),
                      )
                    else
                      ...selectedProjects.map(
                        (project) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            project,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _InputCard(
                  title: 'Vorige maand',
                  children: [
                    _StatRow(
                      label: 'Gekregen uren',
                      value: _formatHours(prevMonthPaid),
                    ),
                    const SizedBox(height: 8),
                    _StatRow(
                      label: 'Gepresteerd',
                      value: _formatHours(prevMonthActual),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InputCard(
                  title: 'Deze maand',
                  children: [
                    _StatRow(
                      label: 'Gekregen uren',
                      value: _formatHours(currentMonthPaid),
                    ),
                    const SizedBox(height: 8),
                    _StatRow(
                      label: 'Gepresteerd',
                      value: _formatHours(currentMonthActual),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InputCard(
                  title: 'Jaaroverzicht',
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => setState(() {
                            _selectedYear -= 1;
                          }),
                        ),
                        Expanded(
                          child: Text(
                            '$_selectedYear',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => setState(() {
                            _selectedYear += 1;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Maand',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFF6A7C78)),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Gekregen',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFF6A7C78)),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Gepresteerd',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFF6A7C78)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...List.generate(12, (index) {
                      final month = index + 1;
                      final paid = paidByMonth[month] ?? 0;
                      final actual = actualByMonth[month] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                _monthLabel(month),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _formatHours(paid),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _formatHours(actual),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (isSubcontractorAdmin) {
      final teams = _visibleTeams;
      if (_selectedTeam == null || !teams.contains(_selectedTeam)) {
        _selectedTeam = teams.isNotEmpty ? teams.first : null;
      }
      final selectedTeam = _selectedTeam;
      if (selectedTeam == null) {
        return Column(
          key: const ValueKey('stats'),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _SectionHeader(
                  title: 'Statistieken',
                  subtitle: 'Geen teams gevonden',
                ),
              ),
            ),
          ],
        );
      }
      final teamMembers = _membersForTeam(selectedTeam);
      final now = DateTime.now();
      final weekDays = _weekDays(_weekStart);
      final paidByDay = <DateTime, double>{};
      final actualByDay = <DateTime, double>{};
      final projectsByDay = <DateTime, Set<String>>{};
      final paidByMonth = <int, double>{};
      final actualByMonth = <int, double>{};
      double prevMonthPaid = 0;
      double prevMonthActual = 0;
      double currentMonthPaid = 0;
      double currentMonthActual = 0;
      final prevMonthStart = DateTime(now.year, now.month - 1, 1);
      final currentMonthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart = DateTime(now.year, now.month + 1, 1);
      final teamProjects = <String>{};

      for (final entry in ProjectStore.workLogs.entries) {
        final project = entry.key;
        final logs = entry.value;
        if (logs.isEmpty) continue;
        final totalPaid =
            _offerHoursForProject(project) + _extraHoursForProject(project);
        double totalPersonHours = 0;
        for (final log in logs) {
          final minutes =
              log.endMinutes - log.startMinutes - log.breakMinutes;
          if (minutes <= 0) continue;
          totalPersonHours += (minutes / 60) * log.workers.length;
        }
        if (totalPersonHours <= 0) continue;
        final factor = totalPaid / totalPersonHours;
        for (final log in logs) {
          final minutes =
              log.endMinutes - log.startMinutes - log.breakMinutes;
          if (minutes <= 0) continue;
          final matchingWorkers = log.workers
              .where((worker) => teamMembers.contains(worker))
              .toList();
          if (matchingWorkers.isEmpty) continue;
          final hours = (minutes / 60) * matchingWorkers.length;
          final paid = hours * factor;
          final day = _dateOnly(log.date);
          actualByDay[day] = (actualByDay[day] ?? 0) + hours;
          paidByDay[day] = (paidByDay[day] ?? 0) + paid;
          projectsByDay.putIfAbsent(day, () => <String>{}).add(project);
          teamProjects.add(project);
          if (day.isAfter(prevMonthStart.subtract(const Duration(days: 1))) &&
              day.isBefore(currentMonthStart)) {
            prevMonthActual += hours;
            prevMonthPaid += paid;
          }
          if (day.isAfter(currentMonthStart.subtract(const Duration(days: 1))) &&
              day.isBefore(nextMonthStart)) {
            currentMonthActual += hours;
            currentMonthPaid += paid;
          }
          if (day.year == _selectedYear) {
            final month = day.month;
            actualByMonth[month] = (actualByMonth[month] ?? 0) + hours;
            paidByMonth[month] = (paidByMonth[month] ?? 0) + paid;
          }
        }
      }

      final maxWeekValue = weekDays.fold<double>(
        0,
        (maxValue, day) {
          final paid = paidByDay[day] ?? 0;
          final actual = actualByDay[day] ?? 0;
          final dayMax = paid > actual ? paid : actual;
          return dayMax > maxValue ? dayMax : maxValue;
        },
      );
      final barMax = maxWeekValue <= 0 ? 1 : maxWeekValue;
      final selectedDay = weekDays.firstWhere(
        (day) =>
            _selectedWeekDay != null &&
            _dateOnly(_selectedWeekDay!) == day,
        orElse: () => weekDays.first,
      );
      final selectedProjects =
          projectsByDay[selectedDay]?.toList() ?? const [];

      DateTime performanceStart;
      DateTime performanceEnd;
      if (_performancePeriodIndex == 0) {
        performanceStart = _performanceDay;
        performanceEnd = _performanceDay;
      } else if (_performancePeriodIndex == 1) {
        performanceStart = _performanceWeekStart;
        performanceEnd =
            _performanceWeekStart.add(const Duration(days: 6));
      } else {
        performanceStart = _performanceMonthStart;
        performanceEnd =
            DateTime(_performanceMonthStart.year, _performanceMonthStart.month + 1, 0);
      }

      final projectsInRange = <String>{};
      for (final entry in ProjectStore.workLogs.entries) {
        final project = entry.key;
        for (final log in entry.value) {
          final day = _dateOnly(log.date);
          if (day.isBefore(performanceStart) || day.isAfter(performanceEnd)) {
            continue;
          }
          if (log.workers.any((worker) => teamMembers.contains(worker))) {
            projectsInRange.add(project);
            break;
          }
        }
      }

      int windows = 0;
      int sliding = 0;
      int doors = 0;
      int gates = 0;
      int finishMdf = 0;
      int finishPvc = 0;
      int finishPleister = 0;
      final windowBreakdown = <String, int>{};
      final slidingBreakdown = <String, int>{};
      final doorBreakdown = <String, int>{};
      final gateBreakdown = <String, int>{};
      final mdfBreakdown = <String, int>{};
      final pvcBreakdown = <String, int>{};
      final pleisterBreakdown = <String, int>{};

      for (final project in projectsInRange) {
        final lines = ProjectStore.offers[project] ?? const <OfferLine>[];
        for (final line in lines) {
          final category = line.category.toLowerCase();
          final item = line.item;
          final qty = line.quantity;
          if (category.contains('schuifraam')) {
            sliding += qty;
            slidingBreakdown[item] = (slidingBreakdown[item] ?? 0) + qty;
            continue;
          }
          if (category.contains('raam montage')) {
            windows += qty;
            windowBreakdown[item] = (windowBreakdown[item] ?? 0) + qty;
            continue;
          }
          if (category.contains('deur montage')) {
            doors += qty;
            doorBreakdown[item] = (doorBreakdown[item] ?? 0) + qty;
            continue;
          }
          if (category.contains('afwerking') &&
              category.contains('mdf')) {
            finishMdf += qty;
            mdfBreakdown[item] = (mdfBreakdown[item] ?? 0) + qty;
            continue;
          }
          if (category.contains('afwerking') &&
              category.contains('pvc')) {
            finishPvc += qty;
            pvcBreakdown[item] = (pvcBreakdown[item] ?? 0) + qty;
            continue;
          }
          if (category.contains('afwerking') &&
              category.contains('pleister')) {
            finishPleister += qty;
            pleisterBreakdown[item] = (pleisterBreakdown[item] ?? 0) + qty;
            continue;
          }
          if (item.toLowerCase().contains('poort')) {
            gates += qty;
            gateBreakdown[item] = (gateBreakdown[item] ?? 0) + qty;
          }
        }
      }

      final workingDaysCount =
          _workingDaysCount(selectedTeam, performanceStart, performanceEnd);
      double avg(double value) =>
          workingDaysCount == 0 ? 0 : value / workingDaysCount;

      return Column(
        key: const ValueKey('stats'),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: _SectionHeader(
                    title: 'Statistieken',
                    subtitle: 'Teamoverzicht',
                  ),
                ),
                _InlineButton(
                  label: 'Payroll',
                  icon: Icons.payments_outlined,
                  onTap: () {
                    Navigator.of(context).push(
                      _appPageRoute(
                        builder: (_) => _PayrollScreen(
                          teams: teams,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              children: [
                _InputCard(
                  title: 'Team',
                  children: [
                    DropdownButtonFormField<String>(
                      key: ValueKey(selectedTeam),
                      initialValue: selectedTeam,
                      items: teams
                          .map(
                            (team) => DropdownMenuItem(
                              value: team,
                              child: Text(team),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setState(() => _selectedTeam = value),
                      decoration: const InputDecoration(
                        labelText: 'Team',
                        filled: true,
                        fillColor: Color(0xFFF4F1EA),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InputCard(
                  title: 'Plaatsingen',
                  children: [
                    _TabToggle(
                      labels: const ['Dag', 'Week', 'Maand'],
                      selectedIndex: _performancePeriodIndex,
                      onSelect: (index) => setState(() {
                        _performancePeriodIndex = index;
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (_performancePeriodIndex == 0)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _formatDate(_performanceDay),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          _InlineButton(
                            label: 'Kies datum',
                            icon: Icons.calendar_today,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _performanceDay,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setState(() =>
                                    _performanceDay = _dateOnly(picked));
                              }
                            },
                          ),
                        ],
                      )
                    else if (_performancePeriodIndex == 1)
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => setState(() {
                              _performanceWeekStart = _performanceWeekStart
                                  .subtract(const Duration(days: 7));
                            }),
                          ),
                          Expanded(
                            child: Text(
                              '${_formatDate(_performanceWeekStart)} - ${_formatDate(_performanceWeekStart.add(const Duration(days: 6)))}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => setState(() {
                              _performanceWeekStart = _performanceWeekStart
                                  .add(const Duration(days: 7));
                            }),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => setState(() {
                              _performanceMonthStart = DateTime(
                                _performanceMonthStart.year,
                                _performanceMonthStart.month - 1,
                                1,
                              );
                            }),
                          ),
                          Expanded(
                            child: Text(
                              '${_monthLabel(_performanceMonthStart.month)} ${_performanceMonthStart.year}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => setState(() {
                              _performanceMonthStart = DateTime(
                                _performanceMonthStart.year,
                                _performanceMonthStart.month + 1,
                                1,
                              );
                            }),
                          ),
                        ],
                      ),
                    const SizedBox(height: 12),
                    _StatRow(label: 'Ramen', value: '$windows'),
                    const SizedBox(height: 6),
                    _StatRow(label: 'Schuiframen', value: '$sliding'),
                    const SizedBox(height: 6),
                    _StatRow(label: 'Deuren', value: '$doors'),
                    const SizedBox(height: 6),
                    _StatRow(label: 'Poorten', value: '$gates'),
                    const SizedBox(height: 6),
                    _StatRow(label: 'Afwerking MDF', value: '$finishMdf'),
                    const SizedBox(height: 6),
                    _StatRow(label: 'Afwerking PVC', value: '$finishPvc'),
                    const SizedBox(height: 6),
                    _StatRow(label: 'Afwerking pleister', value: '$finishPleister'),
                    if (workingDaysCount > 0) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Gemiddeld per werkdag',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      _StatRow(
                        label: 'Ramen',
                        value: avg(windows.toDouble()).toStringAsFixed(1),
                      ),
                      const SizedBox(height: 4),
                      _StatRow(
                        label: 'Schuiframen',
                        value: avg(sliding.toDouble()).toStringAsFixed(1),
                      ),
                      const SizedBox(height: 4),
                      _StatRow(
                        label: 'Deuren',
                        value: avg(doors.toDouble()).toStringAsFixed(1),
                      ),
                    ],
                    if (windowBreakdown.isNotEmpty ||
                        slidingBreakdown.isNotEmpty ||
                        doorBreakdown.isNotEmpty ||
                        gateBreakdown.isNotEmpty ||
                        mdfBreakdown.isNotEmpty ||
                        pvcBreakdown.isNotEmpty ||
                        pleisterBreakdown.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Onderverdeling gewicht/grootte',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      if (windowBreakdown.isNotEmpty) ...[
                        Text(
                          'Ramen',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        ...windowBreakdown.entries.map(
                          (entry) => Text(
                            '${entry.key}: ${entry.value}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6A7C78),
                                ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (slidingBreakdown.isNotEmpty) ...[
                        Text(
                          'Schuiframen',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        ...slidingBreakdown.entries.map(
                          (entry) => Text(
                            '${entry.key}: ${entry.value}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6A7C78),
                                ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (doorBreakdown.isNotEmpty) ...[
                        Text(
                          'Deuren',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        ...doorBreakdown.entries.map(
                          (entry) => Text(
                            '${entry.key}: ${entry.value}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6A7C78),
                                ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (gateBreakdown.isNotEmpty) ...[
                        Text(
                          'Poorten',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        ...gateBreakdown.entries.map(
                          (entry) => Text(
                            '${entry.key}: ${entry.value}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6A7C78),
                                ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (mdfBreakdown.isNotEmpty) ...[
                        Text(
                          'Afwerking MDF',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        ...mdfBreakdown.entries.map(
                          (entry) => Text(
                            '${entry.key}: ${entry.value}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6A7C78),
                                ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (pvcBreakdown.isNotEmpty) ...[
                        Text(
                          'Afwerking PVC',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        ...pvcBreakdown.entries.map(
                          (entry) => Text(
                            '${entry.key}: ${entry.value}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6A7C78),
                                ),
                          ),
                        ),
                        const SizedBox(height: 6),
                      ],
                      if (pleisterBreakdown.isNotEmpty) ...[
                        Text(
                          'Afwerking pleister',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        ...pleisterBreakdown.entries.map(
                          (entry) => Text(
                            '${entry.key}: ${entry.value}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: const Color(0xFF6A7C78),
                                ),
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _InputCard(
                  title: 'Uren per dag (deze week)',
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => setState(() {
                            _weekStart =
                                _weekStart.subtract(const Duration(days: 7));
                          }),
                        ),
                        Expanded(
                          child: Text(
                            '${_formatDate(_weekStart)} - ${_formatDate(_weekStart.add(const Duration(days: 6)))}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => setState(() {
                            _weekStart =
                                _weekStart.add(const Duration(days: 7));
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: weekDays.map((day) {
                        final paid = paidByDay[day] ?? 0;
                        final actual = actualByDay[day] ?? 0;
                        final paidHeight = (paid / barMax) * 80;
                        final actualHeight = (actual / barMax) * 80;
                        final isSelected = selectedDay == day;
                        return Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => setState(() {
                              _selectedWeekDay = day;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                vertical: 6,
                                horizontal: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF0B2E2B)
                                        .withValues(alpha: 0.06)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: [
                                  SizedBox(
                                    height: 90,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          width: 8,
                                          height: actualHeight,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFB8ADA0),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Container(
                                          width: 8,
                                          height: paidHeight,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF0B2E2B),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _weekdayLabel(day),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: isSelected
                                              ? const Color(0xFF0B2E2B)
                                              : const Color(0xFF6A7C78),
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _LegendDot(
                          color: const Color(0xFF0B2E2B),
                          label: 'Gekregen uren',
                        ),
                        const SizedBox(width: 12),
                        _LegendDot(
                          color: const Color(0xFFB8ADA0),
                          label: 'Gepresteerd',
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Projecten op ${_formatDate(selectedDay)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    if (selectedProjects.isEmpty)
                      Text(
                        'Geen projecten.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF6A7C78)),
                      )
                    else
                      ...selectedProjects.map(
                        (project) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            project,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _InputCard(
                  title: 'Vorige maand',
                  children: [
                    _StatRow(
                      label: 'Gekregen uren',
                      value: _formatHours(prevMonthPaid),
                    ),
                    const SizedBox(height: 8),
                    _StatRow(
                      label: 'Gepresteerd',
                      value: _formatHours(prevMonthActual),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InputCard(
                  title: 'Deze maand',
                  children: [
                    _StatRow(
                      label: 'Gekregen uren',
                      value: _formatHours(currentMonthPaid),
                    ),
                    const SizedBox(height: 8),
                    _StatRow(
                      label: 'Gepresteerd',
                      value: _formatHours(currentMonthActual),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InputCard(
                  title: 'Jaaroverzicht',
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => setState(() {
                            _selectedYear -= 1;
                          }),
                        ),
                        Expanded(
                          child: Text(
                            '$_selectedYear',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => setState(() {
                            _selectedYear += 1;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Maand',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFF6A7C78)),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Gekregen',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFF6A7C78)),
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Gepresteerd',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFF6A7C78)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ...List.generate(12, (index) {
                      final month = index + 1;
                      final paid = paidByMonth[month] ?? 0;
                      final actual = actualByMonth[month] ?? 0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                _monthLabel(month),
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _formatHours(paid),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                _formatHours(actual),
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      key: const ValueKey('stats'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: _SectionHeader(
              title: 'Statistieken',
              subtitle: _isAdmin ? 'Bedrijfsoverzicht' : 'Jouw overzicht',
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
        if (_isAdmin) ...[
          const SizedBox(height: 16),
          Builder(
            builder: (context) {
              final performanceStart = _performanceStartDate();
              final performanceEnd = _performanceEndDate();
              _RoleManagementStore.seedIfEmpty();
              final teamNames = _RoleManagementStore.teams.isEmpty
                  ? <String>['Team 1']
                  : _RoleManagementStore.teams
                      .map((team) => team.name)
                      .toList()
                    ..sort();
              final summaries = <_TeamPlacementSummary>[];
              for (final team in teamNames) {
                final projects =
                    _projectsForTeamInRange(team, performanceStart, performanceEnd);
                final stats = _placementStatsForProjects(projects);
                final extra = _extraHoursBreakdownForProjects(projects);
                summaries.add(
                  _TeamPlacementSummary(
                    team: team,
                    contractor: _contractorForTeam(team),
                    stats: stats,
                    extraHours: extra,
                  ),
                );
              }
              final grouped = <String, List<_TeamPlacementSummary>>{};
              for (final summary in summaries) {
                grouped.putIfAbsent(summary.contractor, () => []).add(summary);
              }
              final contractorKeys = grouped.keys.toList()..sort();

              return _InputCard(
                title: 'Plaatsingen per team',
                children: [
                  _TabToggle(
                    labels: const ['Dag', 'Week', 'Maand'],
                    selectedIndex: _performancePeriodIndex,
                    onSelect: (index) => setState(() {
                      _performancePeriodIndex = index;
                    }),
                  ),
                  const SizedBox(height: 12),
                  if (_performancePeriodIndex == 0)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatDate(_performanceDay),
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        _InlineButton(
                          label: 'Kies datum',
                          icon: Icons.calendar_today,
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _performanceDay,
                              firstDate: DateTime(2024),
                              lastDate: DateTime(2030),
                            );
                            if (picked != null) {
                              setState(() =>
                                  _performanceDay = _dateOnly(picked));
                            }
                          },
                        ),
                      ],
                    )
                  else if (_performancePeriodIndex == 1)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => setState(() {
                            _performanceWeekStart = _performanceWeekStart
                                .subtract(const Duration(days: 7));
                          }),
                        ),
                        Expanded(
                          child: Text(
                            '${_formatDate(_performanceWeekStart)} - ${_formatDate(_performanceWeekStart.add(const Duration(days: 6)))}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => setState(() {
                            _performanceWeekStart = _performanceWeekStart
                                .add(const Duration(days: 7));
                          }),
                        ),
                      ],
                    )
                  else
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => setState(() {
                            _performanceMonthStart = DateTime(
                              _performanceMonthStart.year,
                              _performanceMonthStart.month - 1,
                              1,
                            );
                          }),
                        ),
                        Expanded(
                          child: Text(
                            '${_monthLabel(_performanceMonthStart.month)} ${_performanceMonthStart.year}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => setState(() {
                            _performanceMonthStart = DateTime(
                              _performanceMonthStart.year,
                              _performanceMonthStart.month + 1,
                              1,
                            );
                          }),
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  if (summaries.isEmpty)
                    Text(
                      'Nog geen teams beschikbaar.',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF6A7C78)),
                    )
                  else
                    ...contractorKeys.map((contractor) {
                      final teamItems = grouped[contractor] ?? [];
                      int contractorWindows = 0;
                      int contractorSliding = 0;
                      int contractorDoors = 0;
                      int contractorGates = 0;
                      double contractorChargeable = 0;
                      double contractorInternal = 0;
                      for (final item in teamItems) {
                        contractorWindows += item.stats.windows;
                        contractorSliding += item.stats.sliding;
                        contractorDoors += item.stats.doors;
                        contractorGates += item.stats.gates;
                        contractorChargeable += item.extraHours.chargeable;
                        contractorInternal += item.extraHours.internal;
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: const Color(0xFFE1DAD0)),
                          ),
                          child: Theme(
                            data: Theme.of(context)
                                .copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              title: Text(
                                contractor,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              subtitle: Text(
                                'Ramen $contractorWindows · Schuiframen $contractorSliding · Deuren $contractorDoors · Poorten $contractorGates\n'
                                'Extra uren klant ${_formatHours(contractorChargeable)} · intern ${_formatHours(contractorInternal)}',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: const Color(0xFF6A7C78)),
                              ),
                              children: teamItems.map((item) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4F1EA),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE1DAD0),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.team,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color:
                                                    const Color(0xFF243B3A),
                                              ),
                                        ),
                                        const SizedBox(height: 6),
                                        _StatRow(
                                          label: 'Ramen',
                                          value: '${item.stats.windows}',
                                        ),
                                        const SizedBox(height: 4),
                                        _StatRow(
                                          label: 'Schuiframen',
                                          value: '${item.stats.sliding}',
                                        ),
                                        const SizedBox(height: 4),
                                        _StatRow(
                                          label: 'Deuren',
                                          value: '${item.stats.doors}',
                                        ),
                                        const SizedBox(height: 4),
                                        _StatRow(
                                          label: 'Poorten',
                                          value: '${item.stats.gates}',
                                        ),
                                        const SizedBox(height: 4),
                                        _StatRow(
                                          label: 'Afwerking MDF',
                                          value: '${item.stats.finishMdf}',
                                        ),
                                        const SizedBox(height: 4),
                                        _StatRow(
                                          label: 'Afwerking PVC',
                                          value: '${item.stats.finishPvc}',
                                        ),
                                        const SizedBox(height: 4),
                                        _StatRow(
                                          label: 'Afwerking pleister',
                                          value: '${item.stats.finishPleister}',
                                        ),
                                        const SizedBox(height: 6),
                                        _StatRow(
                                          label: 'Extra uren klant',
                                          value:
                                              _formatHours(item.extraHours.chargeable),
                                        ),
                                        const SizedBox(height: 4),
                                        _StatRow(
                                          label: 'Extra uren intern',
                                          value:
                                              _formatHours(item.extraHours.internal),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      );
                    }),
                ],
              );
            },
          ),
        ],
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final weekDays = _weekDays(_weekStart);
            final weekStart = weekDays.first;
            final weekEnd = weekDays.last;
            final projectsByDay = <DateTime, Set<String>>{};
            for (final entry in ProjectStore.workLogs.entries) {
              final project = entry.key;
              for (final log in entry.value) {
                final day = _dateOnly(log.date);
                if (day.isBefore(weekStart) || day.isAfter(weekEnd)) {
                  continue;
                }
                projectsByDay.putIfAbsent(day, () => <String>{}).add(project);
              }
            }
            final statsByDay = <DateTime, _PlacementStats>{};
            final totalsByDay = <DateTime, int>{};
            int maxTotal = 1;
            for (final day in weekDays) {
              final stats =
                  _placementStatsForProjects(projectsByDay[day] ?? {});
              statsByDay[day] = stats;
              final total = stats.windows +
                  stats.sliding +
                  stats.doors +
                  stats.gates +
                  stats.finishMdf +
                  stats.finishPvc +
                  stats.finishPleister;
              totalsByDay[day] = total;
              if (total > maxTotal) {
                maxTotal = total;
              }
            }
            final selectedDay = weekDays.firstWhere(
              (day) =>
                  _selectedWeekDay != null &&
                  _dateOnly(_selectedWeekDay!) == day,
              orElse: () => weekDays.first,
            );
            final selectedStats =
                statsByDay[selectedDay] ?? _placementStatsForProjects({});

            return _InputCard(
              title: 'Weekoverzicht plaatsingen',
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: () => setState(() {
                        _weekStart =
                            _weekStart.subtract(const Duration(days: 7));
                      }),
                    ),
                    Expanded(
                      child: Text(
                        '${_formatDate(_weekStart)} - ${_formatDate(_weekStart.add(const Duration(days: 6)))}',
                        textAlign: TextAlign.center,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: () => setState(() {
                        _weekStart = _weekStart.add(const Duration(days: 7));
                      }),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: weekDays.map((day) {
                    final total = totalsByDay[day] ?? 0;
                    final height = (total / maxTotal) * 90;
                    final isSelected = selectedDay == day;
                    return Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() {
                          _selectedWeekDay = day;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF0B2E2B)
                                    .withValues(alpha: 0.06)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              SizedBox(
                                height: 100,
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: 16,
                                    height: height,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF0B2E2B),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _weekdayLabel(day),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: isSelected
                                          ? const Color(0xFF0B2E2B)
                                          : const Color(0xFF6A7C78),
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Text(
                  'Elementen op ${_formatDate(selectedDay)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                _StatRow(label: 'Ramen', value: '${selectedStats.windows}'),
                const SizedBox(height: 4),
                _StatRow(
                  label: 'Schuiframen',
                  value: '${selectedStats.sliding}',
                ),
                const SizedBox(height: 4),
                _StatRow(label: 'Deuren', value: '${selectedStats.doors}'),
                const SizedBox(height: 4),
                _StatRow(label: 'Poorten', value: '${selectedStats.gates}'),
                const SizedBox(height: 4),
                _StatRow(
                  label: 'Afwerking MDF',
                  value: '${selectedStats.finishMdf}',
                ),
                const SizedBox(height: 4),
                _StatRow(
                  label: 'Afwerking PVC',
                  value: '${selectedStats.finishPvc}',
                ),
                const SizedBox(height: 4),
                _StatRow(
                  label: 'Afwerking pleister',
                  value: '${selectedStats.finishPleister}',
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _InputCard(
          title: 'Prestaties',
          children: [
            _StatRow(
              label: 'Gemiddelde projecten per week',
              value: avgPerWeek.toStringAsFixed(1),
            ),
            if (canSeeHours) ...[
              const SizedBox(height: 8),
              _StatRow(
                label: 'Geschatte uren (offerte)',
                value: _formatPrice(totalOfferHours),
              ),
              const SizedBox(height: 8),
              _StatRow(
                label: 'Extra uren',
                value: _formatPrice(totalExtraHours),
              ),
            ],
            if (canSeePrices) ...[
              const SizedBox(height: 8),
              _StatRow(
                label: 'Gemiddelde kost per plaatsing',
                value: '€${_formatPrice(avgCost)}',
              ),
            ],
          ],
        ),
        if (_isExternal && canSeeHours) ...[
          const SizedBox(height: 16),
          _InputCard(
            title: 'Uren & opbrengst',
            children: [
              TextField(
                controller: _rateController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Uurprijs (optioneel)',
                  filled: true,
                  fillColor: const Color(0xFFF4F1EA),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              _StatRow(
                label: 'Geschatte opbrengst',
                value: rate == 0
                    ? '—'
                    : '€${_formatPrice(estimatedValue)}',
              ),
            ],
          ),
        ],
            ],
          ),
        ),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _PlacementStats {
  const _PlacementStats({
    required this.windows,
    required this.sliding,
    required this.doors,
    required this.gates,
    required this.finishMdf,
    required this.finishPvc,
    required this.finishPleister,
    required this.windowBreakdown,
    required this.slidingBreakdown,
    required this.doorBreakdown,
    required this.gateBreakdown,
    required this.mdfBreakdown,
    required this.pvcBreakdown,
    required this.pleisterBreakdown,
  });

  final int windows;
  final int sliding;
  final int doors;
  final int gates;
  final int finishMdf;
  final int finishPvc;
  final int finishPleister;
  final Map<String, int> windowBreakdown;
  final Map<String, int> slidingBreakdown;
  final Map<String, int> doorBreakdown;
  final Map<String, int> gateBreakdown;
  final Map<String, int> mdfBreakdown;
  final Map<String, int> pvcBreakdown;
  final Map<String, int> pleisterBreakdown;

  int get totalPlacements => windows + sliding + doors + gates;
}

class _ExtraHoursBreakdown {
  const _ExtraHoursBreakdown({
    required this.chargeable,
    required this.internal,
  });

  final double chargeable;
  final double internal;
}

class _TeamPlacementSummary {
  const _TeamPlacementSummary({
    required this.team,
    required this.contractor,
    required this.stats,
    required this.extraHours,
  });

  final String team;
  final String contractor;
  final _PlacementStats stats;
  final _ExtraHoursBreakdown extraHours;
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, this.label});

  final Color color;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final text = label?.trim() ?? '';
    if (text.isEmpty) {
      return Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: const Color(0xFF6A7C78)),
        ),
      ],
    );
  }
}

class _PayrollScreen extends StatefulWidget {
  const _PayrollScreen({
    required this.teams,
  });

  final List<String> teams;

  @override
  State<_PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<_PayrollScreen> {
  int _periodIndex = 1; // 0 dag, 1 week, 2 maand
  late DateTime _selectedDay;
  late DateTime _weekStart;
  late DateTime _monthStart;

  @override
  void initState() {
    super.initState();
    _selectedDay = _dateOnly(DateTime.now());
    _weekStart = _startOfWeek(_selectedDay);
    _monthStart = DateTime(_selectedDay.year, _selectedDay.month, 1);
  }

  @override
  void dispose() {
    super.dispose();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _startOfWeek(DateTime date) {
    final normalized = _dateOnly(date);
    return normalized.subtract(Duration(days: normalized.weekday - 1));
  }

  String _monthLabel(int month) {
    const labels = [
      'Jan',
      'Feb',
      'Mrt',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Dec',
    ];
    return labels[month - 1];
  }

  List<String> _membersForTeam(String team) {
    _RoleManagementStore.seedIfEmpty();
    return _RoleManagementStore.assignments
        .where((assignment) =>
            assignment.role == 'Werknemer' && assignment.team == team)
        .map((assignment) => assignment.name)
        .toList();
  }

  double _offerHoursForProject(String name) {
    final lines = ProjectStore.offers[name] ?? const <OfferLine>[];
    double total = 0;
    for (final line in lines) {
      final item = OfferCatalogStore.findItem(line.category, line.item);
      final hours = item?.hours ?? 0;
      total += hours * line.quantity;
    }
    return total;
  }

  double _extraHoursForProject(String name) {
    final entries = ProjectStore.extraWorks[name] ?? const <ExtraWorkEntry>[];
    double total = 0;
    for (final entry in entries) {
      total += entry.hours;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    DateTime rangeStart;
    DateTime rangeEnd;
    if (_periodIndex == 0) {
      rangeStart = _selectedDay;
      rangeEnd = _selectedDay;
    } else if (_periodIndex == 1) {
      rangeStart = _weekStart;
      rangeEnd = _weekStart.add(const Duration(days: 6));
    } else {
      rangeStart = _monthStart;
      rangeEnd = DateTime(_monthStart.year, _monthStart.month + 1, 0);
    }

    final teamMap = <String, List<String>>{};
    for (final team in widget.teams) {
      teamMap[team] = _membersForTeam(team);
    }
    final allWorkers = teamMap.values.expand((e) => e).toSet();
    final paidByWorker = <String, double>{};
    final actualByWorker = <String, double>{};
    for (final worker in allWorkers) {
      paidByWorker[worker] = 0;
      actualByWorker[worker] = 0;
    }

    for (final entry in ProjectStore.workLogs.entries) {
      final project = entry.key;
      final logs = entry.value;
      if (logs.isEmpty) continue;
      final totalPaid =
          _offerHoursForProject(project) + _extraHoursForProject(project);
      double totalPersonHours = 0;
      for (final log in logs) {
        final minutes = log.endMinutes - log.startMinutes - log.breakMinutes;
        if (minutes <= 0) continue;
        totalPersonHours += (minutes / 60) * log.workers.length;
      }
      if (totalPersonHours <= 0) continue;
      final factor = totalPaid / totalPersonHours;
      for (final log in logs) {
        final minutes = log.endMinutes - log.startMinutes - log.breakMinutes;
        if (minutes <= 0) continue;
        final day = _dateOnly(log.date);
        if (day.isBefore(rangeStart) || day.isAfter(rangeEnd)) continue;
        for (final worker in log.workers) {
          if (!allWorkers.contains(worker)) continue;
          final hours = minutes / 60;
          actualByWorker[worker] = (actualByWorker[worker] ?? 0) + hours;
          paidByWorker[worker] =
              (paidByWorker[worker] ?? 0) + hours * factor;
        }
      }
    }

    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Payroll',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _InputCard(
                  title: 'Periode',
                  children: [
                    _TabToggle(
                      labels: const ['Dag', 'Week', 'Maand'],
                      selectedIndex: _periodIndex,
                      onSelect: (index) => setState(() {
                        _periodIndex = index;
                      }),
                    ),
                    const SizedBox(height: 12),
                    if (_periodIndex == 0)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _formatDate(_selectedDay),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          _InlineButton(
                            label: 'Kies datum',
                            icon: Icons.calendar_today,
                            onTap: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDay,
                                firstDate: DateTime(2024),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setState(() => _selectedDay = _dateOnly(picked));
                              }
                            },
                          ),
                        ],
                      )
                    else if (_periodIndex == 1)
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => setState(() {
                              _weekStart =
                                  _weekStart.subtract(const Duration(days: 7));
                            }),
                          ),
                          Expanded(
                            child: Text(
                              '${_formatDate(_weekStart)} - ${_formatDate(_weekStart.add(const Duration(days: 6)))}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => setState(() {
                              _weekStart =
                                  _weekStart.add(const Duration(days: 7));
                            }),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => setState(() {
                              _monthStart = DateTime(
                                _monthStart.year,
                                _monthStart.month - 1,
                                1,
                              );
                            }),
                          ),
                          Expanded(
                            child: Text(
                              '${_monthLabel(_monthStart.month)} ${_monthStart.year}',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => setState(() {
                              _monthStart = DateTime(
                                _monthStart.year,
                                _monthStart.month + 1,
                                1,
                              );
                            }),
                          ),
                        ],
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                ...widget.teams.map((team) {
                  final workers = teamMap[team] ?? const <String>[];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _InputCard(
                      title: team,
                      children: [
                        if (workers.isEmpty)
                          Text(
                            'Geen werknemers.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: const Color(0xFF6A7C78)),
                          )
                        else ...[
                          Row(
                            children: [
                              Expanded(
                                flex: 4,
                                child: Text(
                                  'Werknemer',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: const Color(0xFF6A7C78)),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'Gekregen',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: const Color(0xFF6A7C78)),
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  'Gepresteerd',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: const Color(0xFF6A7C78)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ...workers.map((worker) {
                            final paid = paidByWorker[worker] ?? 0;
                            final actual = actualByWorker[worker] ?? 0;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 4,
                                    child: Text(
                                      worker,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _formatHours(paid),
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      _formatHours(actual),
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectsTabState extends State<ProjectsTab> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedGroup = _projectGroups.first;
  String _selectedStatus = _statusStages.first;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }


  List<_ProjectResult> _filteredCustomers() {
    final isExternal = _isExternalRole(CurrentUserStore.role);
    final visibleProjects = isExternal ? _visibleProjects() : null;
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) {
      if (isExternal) {
        return visibleProjects ?? const <_ProjectResult>[];
      }
      final customers =
          ProjectStore.projectsByGroup[_selectedGroup]?[_selectedStatus] ?? [];
      return customers
          .map((name) => _ProjectResult(
                name: name,
                group: _selectedGroup,
                status: _selectedStatus,
              ))
          .toList();
    }

    final results = <_ProjectResult>[];
    if (isExternal) {
      for (final item in visibleProjects ?? const <_ProjectResult>[]) {
        if (item.name.toLowerCase().contains(query)) {
          results.add(item);
        }
      }
    } else {
      for (final groupEntry in ProjectStore.projectsByGroup.entries) {
        for (final statusEntry in groupEntry.value.entries) {
          for (final name in statusEntry.value) {
            if (name.toLowerCase().contains(query)) {
              results.add(_ProjectResult(
                name: name,
                group: groupEntry.key,
                status: statusEntry.key,
              ));
            }
          }
        }
      }
    }
    return results;
  }

  List<_ProjectResult> _visibleProjects() {
    final teams = _teamsForCurrentUser();
    final projects = <String>{};
    for (final assignment in widget.scheduled) {
      if (teams.contains(assignment.team)) {
        projects.add(assignment.project);
      }
    }
    for (final entry in ProjectStore.completionTeams.entries) {
      if (teams.contains(entry.value)) {
        projects.add(entry.key);
      }
    }
    return projects
        .map((name) {
          final group = ProjectStore.findGroupForProject(name) ?? 'Klanten';
          final status = ProjectStore.findStatusForProject(name) ?? 'Ingepland';
          return _ProjectResult(name: name, group: group, status: status);
        })
        .where((item) => item.status == 'Afgewerkt')
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  List<_ProjectResult> _visibleByGroup(String group) {
    return _visibleProjects()
        .where((item) => item.group == group)
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _searchController.text.trim().isNotEmpty;
    final isExternal = _isExternalRole(CurrentUserStore.role);
    final isWorker = CurrentUserStore.role == 'Werknemer';
    final isSubcontractor = CurrentUserStore.role == 'Onderaannemer' ||
        CurrentUserStore.role == 'Onderaannemer beheerder';
    final canInvoice = CurrentUserStore.role == 'Onderaannemer' ||
        CurrentUserStore.role == 'Onderaannemer beheerder';
    final hasProjectAction = !isExternal || canInvoice;
    final filteredResults = isSearching ? _filteredCustomers() : const <_ProjectResult>[];
    final groupedResults = !isExternal ? const <_ProjectResult>[] : _visibleByGroup(_selectedGroup);
    return Column(
      key: const ValueKey('projects'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                title: isExternal ? 'Afgewerkte projecten' : 'Projecten',
                subtitle: '',
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SearchField(
                      controller: _searchController,
                      hintText: 'Zoek klant',
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (hasProjectAction) ...[
                    const SizedBox(width: 12),
                    if (!isExternal)
                      _PrimaryButton(
                        label: 'Project +',
                        height: 42,
                        onTap: () async {
                          final result =
                              await Navigator.of(context).push<bool>(
                            _appPageRoute(
                              builder: (_) => AddProjectScreen(
                                initialGroup: _selectedGroup,
                                initialStatus: _selectedStatus,
                              ),
                            ),
                          );
                          if (result == true) {
                            setState(() {});
                          }
                        },
                      ),
                    if (isExternal && canInvoice)
                      _SecondaryButton(
                        label: 'Facturatie',
                        onTap: () => Navigator.of(context).push(
                          _appPageRoute(
                            builder: (_) => _InvoiceScreen(
                              teamNames: _teamsForCurrentUser(),
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              _GroupToggle(
                groups: _projectGroups,
                selected: _selectedGroup,
                onSelect: (group) => setState(() {
                  _selectedGroup = group;
                  _selectedStatus = _statusStages.first;
                }),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
              const SizedBox(height: 12),
              if (isSearching)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredResults.length,
                  itemBuilder: (context, index) {
                    final result = filteredResults[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CustomerRow(
                        name: result.name,
                        phone: isWorker
                            ? ''
                            : ProjectStore.details[result.name]?.phone ?? '—',
                        group: result.group,
                        status: result.status,
                        highlight: !isWorker,
                        compact: isWorker,
                        showStatus: !isSubcontractor,
                        onCenterTap: isExternal
                            ? () async {
                                final changed =
                                    await Navigator.of(context).push<bool>(
                                  _appPageRoute(
                                    builder: (_) => ProjectDetailScreen(
                                      customerName: result.name,
                                      group: result.group,
                                      status: result.status,
                                    ),
                                  ),
                                );
                                if (changed == true) {
                                  setState(() {});
                                }
                              }
                            : null,
                        onIconTap: null,
                        onArrowTap: () async {
                          final changed =
                              await Navigator.of(context).push<bool>(
                            _appPageRoute(
                              builder: (_) => ProjectDetailScreen(
                                customerName: result.name,
                                group: result.group,
                                status: result.status,
                              ),
                            ),
                          );
                          if (changed == true) {
                            setState(() {});
                          }
                        },
                      ),
                    );
                  },
                )
              else if (!isExternal)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _statusStages.length,
                  itemBuilder: (context, index) {
                    final status = _statusStages[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _StatusRow(
                        status: status,
                        count:
                            ProjectStore.projectsByGroup[_selectedGroup]?[status]
                                    ?.length ??
                                0,
                        onTap: () => Navigator.of(context).push(
                          _appPageRoute(
                            builder: (_) => StatusDetailScreen(
                              group: _selectedGroup,
                              status: status,
                            ),
                          ),
                        ).then((_) => setState(() {})),
                      ),
                    );
                  },
                )
              else ...[
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: groupedResults.length,
                  itemBuilder: (context, index) {
                    final result = groupedResults[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _CustomerRow(
                        name: result.name,
                        phone: isWorker
                            ? ''
                            : ProjectStore.details[result.name]?.phone ?? '—',
                        group: result.group,
                        status: result.status,
                        highlight: !isWorker,
                        compact: isWorker,
                        showStatus: !isSubcontractor,
                        onCenterTap: () async {
                          final changed =
                              await Navigator.of(context).push<bool>(
                            _appPageRoute(
                              builder: (_) => ProjectDetailScreen(
                                customerName: result.name,
                                group: result.group,
                                status: result.status,
                              ),
                            ),
                          );
                          if (changed == true) {
                            setState(() {});
                          }
                        },
                        onIconTap: null,
                        onArrowTap: () async {
                          final changed =
                              await Navigator.of(context).push<bool>(
                            _appPageRoute(
                              builder: (_) => ProjectDetailScreen(
                                customerName: result.name,
                                group: result.group,
                                status: result.status,
                              ),
                            ),
                          );
                          if (changed == true) {
                            setState(() {});
                          }
                        },
                      ),
                    );
                  },
                ),
                if (groupedResults.isEmpty)
                  const _EmptyStateCard(
                    title: 'Geen afgewerkte projecten',
                    subtitle:
                        'Er zijn nog geen afgewerkte projecten voor jouw team.',
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _InvoiceScreen extends StatefulWidget {
  const _InvoiceScreen({
    required this.teamNames,
  });

  final List<String> teamNames;

  @override
  State<_InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends State<_InvoiceScreen> {
  double _extraHoursForProject(String name) {
    final entries = ProjectStore.extraWorks[name] ?? const <ExtraWorkEntry>[];
    double total = 0;
    for (final entry in entries) {
      total += entry.hours;
    }
    return total;
  }

  double _offerHoursForProject(List<OfferLine> lines) {
    double total = 0;
    for (final line in lines) {
      final item = OfferCatalogStore.findItem(line.category, line.item);
      final hours = item?.hours;
      if (hours != null) {
        total += hours * line.quantity;
      }
    }
    return total;
  }

  double _offerPriceTotal(List<OfferLine> lines) {
    double total = 0;
    for (final line in lines) {
      final item = OfferCatalogStore.findItem(line.category, line.item);
      if (item == null) continue;
      total += item.price * line.quantity;
    }
    return total;
  }

  List<_InvoiceItem> _buildItems() {
    OfferCatalogStore.seedIfEmpty();
    final projects = <String>{};
    for (final entry in ProjectStore.completionTeams.entries) {
      if (widget.teamNames.contains(entry.value)) {
        projects.add(entry.key);
      }
    }
    final items = <_InvoiceItem>[];
    for (final name in projects) {
      final status = ProjectStore.findStatusForProject(name) ?? '';
      final isBackorder = ProjectStore.isBackorder[name] ?? false;
      if (!isBackorder && status != 'Afgewerkt') {
        continue;
      }
      final record = InvoiceStore.recordFor(name);
      final offerLines = ProjectStore.offers[name] ?? const <OfferLine>[];
      final offerHours = _offerHoursForProject(offerLines);
      final extraHoursTotal = _extraHoursForProject(name);
      final extraHoursDelta = (extraHoursTotal - record.extraHoursBilled)
          .clamp(0, double.infinity)
          .toDouble();
      final includeOffer = !record.offerBilled;
      final invoiceHours = (includeOffer ? offerHours : 0) + extraHoursDelta;
      if (invoiceHours <= 0) {
        continue;
      }
      items.add(
        _InvoiceItem(
          name: name,
          group: ProjectStore.findGroupForProject(name) ?? 'Klanten',
          status: status,
          isBackorder: isBackorder,
          offerLines: offerLines,
          offerHours: offerHours,
          extraHoursTotal: extraHoursTotal,
          extraHoursDelta: extraHoursDelta,
          includeOffer: includeOffer,
        ),
      );
    }
    items.sort((a, b) => a.name.compareTo(b.name));
    return items;
  }

  void _approveInvoice(_InvoiceItem item) {
    final record = InvoiceStore.recordFor(item.name);
    if (item.includeOffer) {
      record.offerBilled = true;
    }
    record.extraHoursBilled = item.extraHoursTotal;
    AppDataStore.scheduleSave();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Facturatie goedgekeurd')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _buildItems();
    final canSeePrices = _canSeeOfferPrices(CurrentUserStore.role);
    final canSeeHours = _canSeeOfferHours(CurrentUserStore.role);
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Facturatie',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const _EmptyStateCard(
                    title: 'Geen facturatie',
                    subtitle: 'Er zijn geen projecten om te factureren.',
                  )
                else
                  ...items.map(
                    (item) {
                      final offerTotal = _offerPriceTotal(item.offerLines);
                      return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE1DAD0)),
                        ),
                        child: Theme(
                          data: Theme.of(context)
                              .copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            childrenPadding:
                                const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.name,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF243B3A),
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${item.group} · ${item.isBackorder ? 'Nabestelling' : item.status}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF6A7C78),
                                      ),
                                ),
                                if (canSeeHours) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Te factureren: ${_formatPrice((item.includeOffer ? item.offerHours : 0) + item.extraHoursDelta)} uur',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF6A7C78),
                                        ),
                                  ),
                                ],
                              ],
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.check_circle,
                                color: Color(0xFF0B2E2B),
                              ),
                              onPressed: () => _approveInvoice(item),
                            ),
                            children: [
                              if (item.includeOffer && item.offerLines.isNotEmpty)
                                ...[
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Offerte',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                              fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...(() {
                                    final grouped =
                                        <String, List<OfferLine>>{};
                                    for (final line in item.offerLines) {
                                      grouped
                                          .putIfAbsent(line.category, () => [])
                                          .add(line);
                                    }
                                    Widget cell(
                                      String value, {
                                      bool header = false,
                                      TextAlign align = TextAlign.left,
                                    }) {
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 6,
                                        ),
                                        child: Text(
                                          value,
                                          textAlign: align,
                                          maxLines: 2,
                                          style: header
                                              ? Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        const Color(0xFF243B3A),
                                                  )
                                              : Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        const Color(0xFF6A7C78),
                                                  ),
                                        ),
                                      );
                                    }

                                    TableRow headerRow() {
                                      return TableRow(
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFF4F1EA),
                                        ),
                                        children: [
                                          cell('Omschrijving', header: true),
                                          cell(
                                            'Aantal',
                                            header: true,
                                            align: TextAlign.right,
                                          ),
                                          cell(
                                            'Eenheid',
                                            header: true,
                                            align: TextAlign.right,
                                          ),
                                          if (canSeePrices)
                                            cell(
                                              'Prijs per eenheid',
                                              header: true,
                                              align: TextAlign.right,
                                            ),
                                        ],
                                      );
                                    }

                                    return grouped.entries.expand((entry) sync* {
                                      yield Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          entry.key,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      );
                                      yield const SizedBox(height: 6);
                                      yield Container(
                                        decoration: BoxDecoration(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          border: Border.all(
                                            color: const Color(0xFFE1DAD0),
                                          ),
                                        ),
                                        child: Table(
                                          columnWidths: {
                                            0: const FlexColumnWidth(2.2),
                                            1: const FlexColumnWidth(1.3),
                                            2: const FlexColumnWidth(1.3),
                                            if (canSeePrices)
                                              3: const FlexColumnWidth(1.6),
                                          },
                                          children: [
                                            headerRow(),
                                            ...entry.value.map((line) {
                                              final offerItem =
                                                  OfferCatalogStore.findItem(
                                                line.category,
                                                line.item,
                                              );
                                              final unit =
                                                  offerItem?.unit ?? '';
                                              final price = offerItem == null ||
                                                      !canSeePrices
                                                  ? ''
                                                  : '€${_formatPrice(offerItem.price)}';
                                              return TableRow(
                                                children: [
                                                  cell(line.item),
                                                  cell(
                                                    '${line.quantity}',
                                                    align: TextAlign.right,
                                                  ),
                                                  cell(unit,
                                                      align: TextAlign.right),
                                                  if (canSeePrices)
                                                    cell(price,
                                                        align: TextAlign.right),
                                                ],
                                              );
                                            }),
                                          ],
                                        ),
                                      );
                                      yield const SizedBox(height: 10);
                                    }).toList();
                                  })(),
                                ],
                              if (item.includeOffer &&
                                  item.offerLines.isNotEmpty &&
                                  canSeePrices) ...[
                                const SizedBox(height: 2),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: Text(
                                    'Totaal prijs: €${_formatPrice(offerTotal)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                const SizedBox(height: 10),
                              ],
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  canSeeHours
                                      ? 'Extra uren: ${_formatPrice(item.extraHoursDelta)}'
                                      : 'Extra uren geregistreerd',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProfileTab extends StatefulWidget {
  const ProfileTab({
    super.key,
    required this.account,
    required this.assignments,
    this.onCalendarSaved,
  });

  final TestAccount account;
  final List<TeamAssignment> assignments;
  final VoidCallback? onCalendarSaved;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  int _tabIndex = 0;
  final List<DocumentEntry> _documents = [];
  bool _showDocumentForm = false;
  String _profileName = 'Liam Vermeulen';
  PlatformFile? _profilePhoto;
  DateTime? _leaveFrom;
  DateTime? _leaveTo;
  final TextEditingController _leaveReasonController = TextEditingController();
  final TextEditingController _docDescriptionController =
      TextEditingController();
  DateTime? _docExpiry;
  PlatformFile? _docFile;

  @override
  void dispose() {
    _leaveReasonController.dispose();
    _docDescriptionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _profileName = widget.account.name;
    _RoleManagementStore.seedIfEmpty();
    _documents.clear();
    _documents.addAll(ProfileDocumentStore.forUser(_profileName));
  }

  Future<void> _pickDocumentFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null) return;
    setState(() {
      _docFile = result.files.first;
    });
  }

  Future<void> _pickDate(BuildContext context, ValueChanged<DateTime> onPick) async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime(2030, 12, 31),
      initialDate: DateTime.now(),
    );
    if (picked != null) onPick(picked);
  }

  void _addDocument() {
    final desc = _docDescriptionController.text.trim();
    if (desc.isEmpty || _docExpiry == null || _docFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul alles in en voeg een bestand toe')),
      );
      return;
    }
    setState(() {
      _documents.add(
        DocumentEntry(
          description: desc,
          expiry: _docExpiry!,
          file: _docFile!,
        ),
      );
      ProfileDocumentStore.setForUser(
        _profileName,
        List<DocumentEntry>.from(_documents),
      );
      _docDescriptionController.clear();
      _docExpiry = null;
      _docFile = null;
      _showDocumentForm = false;
    });
  }

  void _removeDocument(DocumentEntry entry) {
    setState(() {
      _documents.remove(entry);
      ProfileDocumentStore.setForUser(
        _profileName,
        List<DocumentEntry>.from(_documents),
      );
    });
  }

  void _editDocument(DocumentEntry entry) {
    _docDescriptionController.text = entry.description;
    _docExpiry = entry.expiry;
    _docFile = entry.file;
    setState(() {
      _documents.remove(entry);
      ProfileDocumentStore.setForUser(
        _profileName,
        List<DocumentEntry>.from(_documents),
      );
      _showDocumentForm = true;
    });
  }

  String _leaveStatusLabel(String status) {
    switch (status) {
      case 'Goedgekeurd':
        return 'Goedgekeurd';
      case 'Geweigerd':
        return 'Geweigerd';
      default:
        return 'Nog goed te keuren';
    }
  }


  Future<void> _openRolesManagement() async {
    await Navigator.of(context).push<List<_RoleAssignment>>(
      _appPageRoute(
        builder: (_) => _RolesManagementScreen(
          assignments: List<_RoleAssignment>.from(
            _RoleManagementStore.assignments,
          ),
          currentAccount: widget.account,
        ),
      ),
    );
    setState(() {});
  }

  Future<void> _openOfferManagement() async {
    await Navigator.of(context).push(
      _appPageRoute(
        builder: (_) => OfferManagementScreen(account: widget.account),
      ),
    );
    setState(() {});
  }

  Future<void> _editProfile() async {
    final nameController = TextEditingController(text: _profileName);
    PlatformFile? tempPhoto = _profilePhoto;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              Future<void> pickPhoto() async {
                final result = await FilePicker.platform.pickFiles(
                  allowMultiple: false,
                  type: FileType.image,
                  withData: true,
                );
                if (result == null) return;
                setSheetState(() {
                  tempPhoto = result.files.first;
                });
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Profiel aanpassen',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      hintText: 'Naam',
                      filled: true,
                      fillColor: const Color(0xFFF4F1EA),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _FileUploadRow(
                    label: tempPhoto?.name ?? 'Profielfoto kiezen',
                    buttonLabel: 'Kies foto',
                    files: tempPhoto == null ? const [] : [tempPhoto!],
                    onAdd: pickPhoto,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _SecondaryButton(
                          label: 'Annuleer',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PrimaryButton(
                          label: 'Opslaan',
                          onTap: () {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Vul een naam in'),
                                ),
                              );
                              return;
                            }
                            setState(() {
                              _profileName = name;
                              _profilePhoto = tempPhoto;
                            });
                            Navigator.of(context).pop();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  int _countForGroup(String group, List<String> statuses) {
    final groupMap = ProjectStore.projectsByGroup[group];
    if (groupMap == null) return 0;
    var total = 0;
    for (final status in statuses) {
      total += groupMap[status]?.length ?? 0;
    }
    return total;
  }

  int _countForGroupForProjects(
    String group,
    List<String> statuses,
    Set<String> allowedProjects,
  ) {
    final groupMap = ProjectStore.projectsByGroup[group];
    if (groupMap == null) return 0;
    var total = 0;
    for (final status in statuses) {
      final list = groupMap[status] ?? const <String>[];
      total += list.where(allowedProjects.contains).length;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final canManageRoles = widget.account.role == 'Beheerder' ||
        widget.account.role == 'Onderaannemer' ||
        widget.account.role == 'Onderaannemer beheerder';
    final canManageOffers = widget.account.role == 'Beheerder' ||
        widget.account.role == 'Onderaannemer' ||
        widget.account.role == 'Onderaannemer beheerder';
    final isWorkerProfile = widget.account.role == 'Werknemer';
    final workerTeam = widget.account.team ?? CurrentUserStore.team;
    final workerProjects = <String>{};
    if (isWorkerProfile && workerTeam.isNotEmpty) {
      for (final assignment in ScheduleStore.scheduled) {
        if (assignment.team == workerTeam) {
          workerProjects.add(assignment.project);
        }
      }
      for (final entry in ProjectStore.completionTeams.entries) {
        if (entry.value == workerTeam) {
          workerProjects.add(entry.key);
        }
      }
    }
    final openOrders = isWorkerProfile
        ? 0
        : _countForGroup(
            'Klanten',
            const ['In opmaak', 'In bestelling', 'Geleverd'],
          );
    final plannedProjects = isWorkerProfile
        ? _countForGroupForProjects(
              'Klanten',
              const ['Ingepland'],
              workerProjects,
            ) +
            _countForGroupForProjects(
              'Nabestellingen',
              const ['Ingepland'],
              workerProjects,
            )
        : _countForGroup(
              'Klanten',
              const ['Ingepland'],
            ) +
            _countForGroup('Nabestellingen', const ['Ingepland']);
    final backorders = isWorkerProfile
        ? 0
        : _countForGroup(
            'Nabestellingen',
            const ['In opmaak', 'In bestelling', 'Geleverd'],
          );
    final completedProjects = isWorkerProfile
        ? _countForGroupForProjects(
              'Klanten',
              const ['Afgewerkt'],
              workerProjects,
            ) +
            _countForGroupForProjects(
              'Nabestellingen',
              const ['Afgewerkt'],
              workerProjects,
            )
        : _countForGroup(
              'Klanten',
              const ['Afgewerkt'],
            ) +
            _countForGroup('Nabestellingen', const ['Afgewerkt']);
    final myRequests = LeaveRequestStore.requests
        .where((request) => request.requester == _profileName)
        .toList()
      ..sort((a, b) => b.from.compareTo(a.from));

    final content = <Widget>[];
    if (_tabIndex == 0) {
      content.addAll([
        _ProfileCard(
          name: _profileName,
          roleLabel: _profileRoleLabel(widget.account),
          photo: _profilePhoto,
          onEdit: _editProfile,
        ),
        const SizedBox(height: 12),
        _StatsGrid(
          items: [
            _StatTileData(
              label: 'Ingeplande projecten',
              value: plannedProjects,
              icon: Icons.event_available,
            ),
            _StatTileData(
              label: 'Afgewerkte projecten',
              value: completedProjects,
              icon: Icons.check_circle_outline,
            ),
            if (!isWorkerProfile)
              _StatTileData(
                label: 'Openstaande bestellingen',
                value: openOrders,
                icon: Icons.pending_actions,
              ),
            if (!isWorkerProfile)
              _StatTileData(
                label: 'Nabestellingen',
                value: backorders,
                icon: Icons.repeat,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (canManageRoles) ...[
          _PrimaryButton(
            label: 'Rollenbeheer',
            onTap: _openRolesManagement,
          ),
          const SizedBox(height: 12),
        ],
        if (canManageOffers) ...[
          _PrimaryButton(
            label: 'Offertebeheer',
            onTap: _openOfferManagement,
          ),
          const SizedBox(height: 12),
        ],
        _DangerButton(
          label: 'Uitloggen',
          onTap: () => Navigator.of(context).pushAndRemoveUntil(
            _appPageRoute(
              builder: (_) => const LoginScreen(),
            ),
            (route) => false,
          ),
        ),
      ]);
    } else if (_tabIndex == 1) {
      content.addAll([
        _InputCard(
          title: 'Documenten',
          children: [
            _PrimaryButton(
              label: 'Document toevoegen',
              onTap: () => setState(() {
                _showDocumentForm = !_showDocumentForm;
              }),
            ),
            if (_showDocumentForm) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _docDescriptionController,
                decoration: InputDecoration(
                  hintText: 'Beschrijving',
                  filled: true,
                  fillColor: const Color(0xFFF4F1EA),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _DatePickerRow(
                label: 'Vervaldatum',
                value: _docExpiry,
                onPick: () => _pickDate(context, (date) {
                  setState(() => _docExpiry = date);
                }),
              ),
              const SizedBox(height: 10),
              _FileUploadRow(
                label: _docFile?.name ?? 'Bestand toevoegen',
                buttonLabel: 'Kies bestand',
                files: _docFile == null ? const [] : [_docFile!],
                onAdd: _pickDocumentFile,
              ),
              const SizedBox(height: 12),
              _PrimaryButton(
                label: 'Document opslaan',
                onTap: _addDocument,
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        if (_documents.isEmpty)
          Text(
            'Nog geen documenten toegevoegd.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF6A7C78)),
          )
        else
          ..._documents.map(
            (doc) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _DocumentRow(
                entry: doc,
                onEdit: () => _editDocument(doc),
                onDelete: () => _removeDocument(doc),
                onOpen: () => _openProfileDocument(context, doc),
              ),
            ),
          ),
      ]);
    } else {
      content.addAll([
        _InputCard(
          title: 'Verlof aanvragen',
          children: [
            Row(
              children: [
                Expanded(
                  child: _SecondaryButton(
                    label: _leaveFrom == null || _leaveTo == null
                        ? 'Periode kiezen'
                        : '${_formatDate(_leaveFrom!)} - ${_formatDate(_leaveTo!)}',
                    onTap: () async {
                      final range = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(2024, 1, 1),
                        lastDate: DateTime(2030, 12, 31),
                        initialDateRange:
                            _leaveFrom != null && _leaveTo != null
                                ? DateTimeRange(
                                    start: _leaveFrom!,
                                    end: _leaveTo!,
                                  )
                                : null,
                      );
                      if (range == null) return;
                      setState(() {
                        _leaveFrom = range.start;
                        _leaveTo = range.end;
                      });
                    },
                  ),
                ),
                if (_leaveFrom != null || _leaveTo != null) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => setState(() {
                      _leaveFrom = null;
                      _leaveTo = null;
                    }),
                    icon: const Icon(Icons.close),
                    color: const Color(0xFF6A7C78),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _leaveReasonController,
              decoration: InputDecoration(
                hintText: 'Reden (optioneel)',
                filled: true,
                fillColor: const Color(0xFFF4F1EA),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            _PrimaryButton(
              label: 'Aanvraag versturen',
              onTap: () {
                if (_leaveFrom == null || _leaveTo == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Kies een periode voor verlof.'),
                    ),
                  );
                  return;
                }
                final from = _leaveFrom!;
                final to = _leaveTo!;
                LeaveRequestStore.requests.add(
                  LeaveRequest(
                    requester: _profileName,
                    role: widget.account.role,
                    from: from,
                    to: to,
                    reason: _leaveReasonController.text.trim(),
                  ),
                );
                AppDataStore.scheduleSave();
                setState(() {
                  _leaveFrom = null;
                  _leaveTo = null;
                  _leaveReasonController.clear();
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Verlofaanvraag verstuurd')),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        _InputCard(
          title: 'Mijn aanvragen',
          children: [
            if (myRequests.isEmpty)
              Text(
                'Nog geen aanvragen.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: const Color(0xFF6A7C78)),
              )
            else
              ...myRequests.map(
                (request) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F1EA),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE1DAD0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_formatDate(request.from)} - ${_formatDate(request.to)}',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _leaveStatusLabel(request.status),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF6A7C78)),
                        ),
                        if (request.reason.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(request.reason),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ]);
    }

    return Column(
      key: const ValueKey('profile'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                title: 'Persoonlijk',
                subtitle: '',
              ),
              const SizedBox(height: 12),
              _ProfileTabSwitch(
                labels: const [
                  'Gegevens',
                  'Documenten',
                  'Verlof',
                ],
                selectedIndex: _tabIndex,
                onSelect: (index) => setState(() => _tabIndex = index),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            children: [
              const SizedBox(height: 16),
              ...content,
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        if (subtitle.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF5A6F6C)),
          ),
        ],
      ],
    );
  }
}

class _ProfileTabSwitch extends StatelessWidget {
  const _ProfileTabSwitch({
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE6DFD5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final isSelected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFF0B2E2B) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? const Color(0xFFFFE9CC)
                              : const Color(0xFF4B6763),
                        ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}


String _profileRoleLabel(TestAccount account) {
  if (account.team != null && account.team!.isNotEmpty) {
    return '${account.role} · ${account.team}';
  }
  return '${account.role} · ${account.company}';
}

class _RoleAssignment {
  _RoleAssignment({
    required this.name,
    required this.email,
    required this.role,
    this.contractor,
    this.team,
  });

  String name;
  final String email;
  String role;
  String? contractor;
  String? team;
}

class _RoleManagementStore {
  static List<_RoleAssignment> assignments = [];
  static List<_TeamAssignment> teams = [];
  static const Set<int> _defaultWorkingDays = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
  };
  static const Set<int> _saturdayWorkingDays = {
    DateTime.monday,
    DateTime.tuesday,
    DateTime.wednesday,
    DateTime.thursday,
    DateTime.friday,
    DateTime.saturday,
  };

  static void seedIfEmpty() {
    if (assignments.isEmpty) {
      assignments = _testAccounts
          .map(
            (account) => _RoleAssignment(
              name: account.name,
              email: AuthStore._emailFromNameAndCompany(
                account.name,
                account.company,
              ),
              role: account.role,
              contractor: account.role == 'Onderaannemer beheerder'
                  ? (account.name == 'Maksim' ? 'MS Construct' : 'Schijnpoort')
                  : account.role == 'Onderaannemer'
                      ? account.name
                      : account.team != null
                          ? 'Schijnpoort'
                          : 'Schijnpoort',
              team: account.team,
            ),
          )
          .toList();
      if (!assignments.any(
        (assignment) =>
            assignment.role == 'Onderaannemer' &&
            assignment.name == 'Schijnpoort',
      )) {
        assignments.add(
          _RoleAssignment(
            name: 'Schijnpoort',
            email: '',
            role: 'Onderaannemer',
          ),
        );
      }
      teams = [
        _TeamAssignment(
          name: 'Team 1',
          contractor: 'Schijnpoort',
          workingDays: _saturdayWorkingDays,
        ),
        _TeamAssignment(
          name: 'Team 2',
          contractor: 'Schijnpoort',
          workingDays: _defaultWorkingDays,
        ),
        _TeamAssignment(
          name: 'Team 3',
          contractor: 'Schijnpoort',
          workingDays: _saturdayWorkingDays,
        ),
        _TeamAssignment(
          name: 'Team 4',
          contractor: 'MS Construct',
          workingDays: _defaultWorkingDays,
        ),
        _TeamAssignment(
          name: 'Team 5',
          contractor: 'MS Construct',
          workingDays: _defaultWorkingDays,
        ),
      ];
    }
    _normalizeDemoTeams();
  }

  static void _normalizeDemoTeams() {
    const allowedTeams = {'Team 1', 'Team 2', 'Team 3', 'Team 4', 'Team 5'};
    teams.removeWhere((team) => !allowedTeams.contains(team.name));
    assignments.removeWhere(
      (assignment) =>
          assignment.role == 'Werknemer' &&
          (assignment.team == null ||
              !allowedTeams.contains(assignment.team)),
    );
  }

  static Set<int> workingDaysForTeam(String teamName, {String? contractor}) {
    seedIfEmpty();
    final match = teams.firstWhere(
      (team) =>
          team.name == teamName &&
          (contractor == null || team.contractor == contractor),
      orElse: () => _TeamAssignment(
        name: teamName,
        contractor: '',
        workingDays: _defaultWorkingDays,
      ),
    );
    return match.workingDays.isEmpty
        ? _defaultWorkingDays
        : Set<int>.from(match.workingDays);
  }
}

class ProfileDocumentStore {
  static final Map<String, List<DocumentEntry>> documentsByUser = {};

  static List<DocumentEntry> forUser(String name) {
    return documentsByUser[name] ?? <DocumentEntry>[];
  }

  static void setForUser(String name, List<DocumentEntry> docs) {
    documentsByUser[name] = docs;
    AppDataStore.scheduleSave();
  }
}

class _TeamAssignment {
  _TeamAssignment({
    required this.name,
    required this.contractor,
    required this.workingDays,
  });

  String name;
  final String contractor;
  Set<int> workingDays;
}

class _UndoAction {
  _UndoAction({
    required this.assignments,
    required this.teams,
  });

  final List<_RoleAssignment> assignments;
  final List<_TeamAssignment> teams;
}

class _RolesManagementScreen extends StatefulWidget {
  const _RolesManagementScreen({
    // ignore: unused_element_parameter
    super.key,
    required this.assignments,
    required this.currentAccount,
  });

  final List<_RoleAssignment> assignments;
  final TestAccount currentAccount;

  @override
  State<_RolesManagementScreen> createState() => _RolesManagementScreenState();
}

class _RolesManagementScreenState extends State<_RolesManagementScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _contractorController = TextEditingController();
  final TextEditingController _teamController = TextEditingController();
  String? _selectedContractor;
  String _selectedRole = _roleOptions.first;
  int _tabIndex = 0;
  late final bool _isAdminLike;
  late final bool _isContractor;
  bool _showInvite = false;
  _UndoAction? _lastUndo;

  @override
  void dispose() {
    _RoleManagementStore.assignments = widget.assignments;
    _nameController.dispose();
    _emailController.dispose();
    _contractorController.dispose();
    _teamController.dispose();
    super.dispose();
  }

  Future<void> _invite() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    if (_selectedRole != 'Team') {
      if (name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vul een naam in')),
        );
        return;
      }
    }
    if (_selectedRole != 'Team' && _selectedRole != 'Onderaannemer') {
      if (email.isEmpty || !email.contains('@')) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vul een geldig e-mailadres in')),
        );
        return;
      }
    }
    final contractor = _resolvedContractor(name);
    final team = _teamController.text.trim();
    final isAdminRole = _adminRoles.contains(_selectedRole);
    if (!_isAdminLike && isAdminRole) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geen rechten voor administratieve rollen')),
      );
      return;
    }
    if (_practicalRoles.contains(_selectedRole)) {
      if (_selectedRole == 'Onderaannemer' && name.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vul de onderaannemer naam in')),
        );
        return;
      }
      if (_selectedRole == 'Onderaannemer beheerder') {
        if (contractor.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vul de onderaannemer in')),
          );
          return;
        }
      }
      if (_selectedRole == 'Team') {
        if (contractor.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vul de onderaannemer in')),
          );
          return;
        }
        if (team.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vul het team in')),
          );
          return;
        }
      }
      if (_selectedRole == 'Werknemer') {
        if (contractor.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vul de onderaannemer in')),
          );
          return;
        }
        if (team.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Vul het team in')),
          );
          return;
        }
      }
    }
    if (_selectedRole != 'Team' &&
        _selectedRole != 'Onderaannemer' &&
        NetlifyIdentityService.isConfigured) {
      final inviteError = await NetlifyIdentityService.inviteUser(
        email: email,
        name: name,
        role: _selectedRole,
        invitedBy: widget.currentAccount.name,
        company: widget.currentAccount.company,
        contractor: contractor,
        team: team,
      );
      if (inviteError != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(inviteError)),
        );
        return;
      }
    }
    setState(() {
      if (_selectedRole == 'Team') {
        _RoleManagementStore.teams.add(
          _TeamAssignment(
            name: team,
            contractor: contractor,
            workingDays:
                _RoleManagementStore.workingDaysForTeam(team, contractor: contractor),
          ),
        );
      } else {
        widget.assignments.add(
          _RoleAssignment(
            name: _selectedRole == 'Onderaannemer' ? name : name,
            email: email,
            role: _selectedRole,
            contractor: _selectedRole == 'Onderaannemer'
                ? name
                : contractor.isEmpty
                    ? null
                    : contractor,
            team: team.isEmpty ? null : team,
          ),
        );
      }
      _nameController.clear();
      _emailController.clear();
      _contractorController.clear();
      _teamController.clear();
      _selectedContractor = null;
      if (_isContractor) {
        _contractorController.text = _contractorNameForCurrentAccount();
      }
      _selectedRole = _isContractor ? 'Werknemer' : _roleOptions.first;
      _showInvite = false;
    });
    AppDataStore.scheduleSave();
  }

  void _updateTeam(
    String contractor,
    String oldName,
    String newName,
    Set<int> workingDays,
  ) {
    if (newName.isEmpty || workingDays.isEmpty) return;
    setState(() {
      for (final team in _RoleManagementStore.teams) {
        if (team.contractor == contractor && team.name == oldName) {
          team.name = newName;
          team.workingDays = Set<int>.from(workingDays);
        }
      }
      for (final assignment in widget.assignments) {
        if (assignment.role == 'Werknemer' &&
            assignment.contractor == contractor &&
            assignment.team == oldName) {
          assignment.team = newName;
        }
      }
      for (int i = 0; i < ScheduleStore.scheduled.length; i++) {
        final assignment = ScheduleStore.scheduled[i];
        if (assignment.team == oldName) {
          ScheduleStore.scheduled[i] = TeamAssignment(
            project: assignment.project,
            team: newName,
            startDate: assignment.startDate,
            endDate: assignment.endDate,
            estimatedDays: assignment.estimatedDays,
            isBackorder: assignment.isBackorder,
            group: assignment.group,
          );
        }
      }
      final teamAssignments = ScheduleStore.scheduled
          .where((assignment) => assignment.team == newName)
          .toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
      if (teamAssignments.isNotEmpty) {
        DateTime? cursor;
        final recalculated = <TeamAssignment>[];
        for (final item in teamAssignments) {
          final startBase = cursor ?? item.startDate;
          final start = _nextWorkingDayForTeam(startBase, newName);
          final end = _endDateFromTeam(start, item.estimatedDays, newName);
          recalculated.add(
            TeamAssignment(
              project: item.project,
              team: newName,
              startDate: start,
              endDate: end,
              estimatedDays: item.estimatedDays,
              isBackorder: item.isBackorder,
              group: item.group,
            ),
          );
          cursor = end.add(const Duration(days: 1));
        }
        ScheduleStore.scheduled.removeWhere(
          (assignment) => assignment.team == newName,
        );
        ScheduleStore.scheduled.addAll(recalculated);
      }
    });
    AppDataStore.scheduleSave();
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isWorkingDayForTeam(String team, DateTime date) {
    final workingDays = _RoleManagementStore.workingDaysForTeam(team);
    if (!workingDays.contains(date.weekday)) return false;
    return !PlanningCalendarStore.isNonWorkingDay(date);
  }

  DateTime _nextWorkingDayForTeam(DateTime date, String team) {
    var day = _normalizeDate(date);
    for (int i = 0; i < 366; i++) {
      if (_isWorkingDayForTeam(team, day)) return day;
      day = day.add(const Duration(days: 1));
    }
    return _normalizeDate(date);
  }

  DateTime _endDateFromTeam(DateTime start, int days, String team) {
    var current = _normalizeDate(start);
    int counted = 0;
    for (int i = 0; i < 1000; i++) {
      if (_isWorkingDayForTeam(team, current)) {
        counted += 1;
        if (counted == days) {
          return current;
        }
      }
      current = current.add(const Duration(days: 1));
    }
    return current;
  }

  bool _canDeleteAssignment(_RoleAssignment assignment) {
    if (assignment.name == widget.currentAccount.name &&
        assignment.role == widget.currentAccount.role) {
      return false;
    }
    if (_isAdminLike) return true;
    if (_isContractor) {
      final contractor = _contractorNameForCurrentAccount();
      return assignment.contractor == contractor &&
          (assignment.role == 'Werknemer' ||
              assignment.role == 'Onderaannemer beheerder');
    }
    return false;
  }

  int _beheerderCount() {
    return widget.assignments
        .where((assignment) => assignment.role == 'Beheerder')
        .length;
  }

  bool _canChangeRole(_RoleAssignment assignment, String newRole) {
    if (assignment.role != 'Beheerder') {
      return true;
    }
    if (newRole == 'Beheerder') {
      return true;
    }
    return _beheerderCount() > 1;
  }

  void _applyRoleChange(_RoleAssignment assignment, String newRole) {
    if (!_canChangeRole(assignment, newRole)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Er moet altijd minstens 1 beheerder zijn.'),
        ),
      );
      return;
    }
    final contractorOptions = _contractorNames();
    String? contractor = assignment.contractor;
    if (newRole == 'Onderaannemer beheerder' || newRole == 'Werknemer') {
      contractor ??= contractorOptions.isNotEmpty ? contractorOptions.first : null;
      if (contractor == null || contractor.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voeg eerst een onderaannemer toe.'),
          ),
        );
        return;
      }
    }
    if (newRole == 'Werknemer') {
      final teams = _teamNames(contractor ?? '');
      final team = teams.isNotEmpty ? teams.first : null;
      if (team == null || team.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voeg eerst een team toe.'),
          ),
        );
        return;
      }
      setState(() {
        assignment.role = newRole;
        assignment.contractor = contractor;
        assignment.team = team;
      });
      AppDataStore.scheduleSave();
      return;
    }
    if (newRole == 'Onderaannemer beheerder') {
      setState(() {
        assignment.role = newRole;
        assignment.contractor = contractor;
        assignment.team = null;
      });
      AppDataStore.scheduleSave();
      return;
    }
    setState(() {
      assignment.role = newRole;
      if (_adminRoles.contains(newRole) || newRole == 'Onderaannemer') {
        assignment.contractor = null;
        assignment.team = null;
      }
    });
    AppDataStore.scheduleSave();
  }

  bool _canDeleteTeam(String contractor) {
    if (_isAdminLike) return true;
    if (_isContractor) {
      return contractor == _contractorNameForCurrentAccount();
    }
    return false;
  }

  void _deleteAssignment(_RoleAssignment assignment) {
    setState(() {
      if (assignment.role == 'Onderaannemer') {
        final contractor = assignment.name;
        final removedAssignments = widget.assignments
            .where(
              (entry) =>
                  entry.name == contractor ||
                  entry.contractor == contractor ||
                  (entry.role == 'Onderaannemer beheerder' &&
                      entry.contractor == contractor),
            )
            .toList();
        final removedTeams = _RoleManagementStore.teams
            .where((team) => team.contractor == contractor)
            .toList();
        widget.assignments
            .removeWhere((entry) => removedAssignments.contains(entry));
        _RoleManagementStore.teams
            .removeWhere((team) => removedTeams.contains(team));
        _lastUndo = _UndoAction(
          assignments: removedAssignments,
          teams: removedTeams,
        );
      } else {
        widget.assignments.remove(assignment);
        _lastUndo = _UndoAction(assignments: [assignment], teams: const []);
      }
    });
    AppDataStore.scheduleSave();
    _showUndoSnack('Verwijderd');
  }

  void _deleteTeam(String contractor, String team) {
    setState(() {
      final removedTeams = _RoleManagementStore.teams
          .where((entry) => entry.contractor == contractor && entry.name == team)
          .toList();
      final removedAssignments = widget.assignments
          .where(
            (entry) =>
                entry.role == 'Werknemer' &&
                entry.contractor == contractor &&
                entry.team == team,
          )
          .toList();
      _RoleManagementStore.teams
          .removeWhere((entry) => removedTeams.contains(entry));
      widget.assignments
          .removeWhere((entry) => removedAssignments.contains(entry));
      _lastUndo = _UndoAction(
        assignments: removedAssignments,
        teams: removedTeams,
      );
    });
    AppDataStore.scheduleSave();
    _showUndoSnack('Verwijderd');
  }

  void _undoLast() {
    if (!mounted) return;
    final undo = _lastUndo;
    if (undo == null) return;
    setState(() {
      widget.assignments.addAll(undo.assignments);
      _RoleManagementStore.teams.addAll(undo.teams);
      _lastUndo = null;
    });
    AppDataStore.scheduleSave();
  }

  void _showUndoSnack(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        onVisible: () {},
        content: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              color: Colors.white,
              onPressed: () {
                _lastUndo = null;
                messenger.hideCurrentSnackBar();
              },
            ),
            Expanded(child: Text(message)),
            TextButton(
              onPressed: _undoLast,
              child: const Text(
                'Ongedaan maken',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
        dismissDirection: DismissDirection.horizontal,
      ),
    ).closed.then((_) {
      _lastUndo = null;
    });
  }

  List<_RoleAssignment> _adminAssignments() {
    return widget.assignments
        .where((assignment) => _adminRoles.contains(assignment.role))
        .toList();
  }

  String _contractorNameForCurrentAccount() {
    if (widget.currentAccount.role == 'Onderaannemer beheerder') {
      return 'Schijnpoort';
    }
    return widget.currentAccount.name;
  }

  List<String> _contractorNames() {
    return widget.assignments
        .where((assignment) => assignment.role == 'Onderaannemer')
        .map((assignment) => assignment.name)
        .toList();
  }

  List<String> _teamNames(String contractor) {
    return _RoleManagementStore.teams
        .where((team) => team.contractor == contractor)
        .map((team) => team.name)
        .toList();
  }

  String _resolvedContractor(String name) {
    if (_selectedRole == 'Onderaannemer') {
      return name;
    }
    final options = _isContractor
        ? [_contractorNameForCurrentAccount()]
        : _contractorNames();
    if (options.isNotEmpty) {
      return _selectedContractor ?? options.first;
    }
    return _contractorController.text.trim();
  }

  Map<String, Map<String, List<_RoleAssignment>>> _practicalHierarchy() {
    final Map<String, Map<String, List<_RoleAssignment>>> hierarchy = {};
    final contractors = widget.assignments
        .where((assignment) => assignment.role == 'Onderaannemer')
        .toList();
    for (final contractor in contractors) {
      hierarchy[contractor.name] = {};
    }
    for (final team in _RoleManagementStore.teams) {
      hierarchy.putIfAbsent(team.contractor, () => {});
      hierarchy[team.contractor]!.putIfAbsent(team.name, () => []);
    }
    final workers = widget.assignments
        .where((assignment) => assignment.role == 'Werknemer')
        .toList();
    for (final worker in workers) {
      final contractor = worker.contractor?.isNotEmpty == true
          ? worker.contractor!
          : 'Geen onderaannemer';
      hierarchy.putIfAbsent(contractor, () => {});
      final team = worker.team?.isNotEmpty == true ? worker.team! : 'Geen team';
      hierarchy[contractor]!.putIfAbsent(team, () => []);
      hierarchy[contractor]![team]!.add(worker);
    }
    if (_isContractor) {
      final contractorName = _contractorNameForCurrentAccount();
      return hierarchy
          .map((key, value) => MapEntry(key, value))
          .containsKey(contractorName)
          ? {contractorName: hierarchy[contractorName]!}
          : {};
    }
    return hierarchy;
  }

  @override
  void initState() {
    super.initState();
    _isAdminLike = widget.currentAccount.role == 'Beheerder';
    _isContractor = widget.currentAccount.role == 'Onderaannemer' ||
        widget.currentAccount.role == 'Onderaannemer beheerder';
    if (_isContractor) {
      _contractorController.text = _contractorNameForCurrentAccount();
      _selectedRole = 'Werknemer';
      _tabIndex = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableInviteRoles = _isAdminLike
        ? _roleOptions
        : _isContractor
            ? const ['Werknemer', 'Onderaannemer beheerder', 'Team']
            : _practicalRoles;
    final contractorOptions = _isContractor
        ? [_contractorNameForCurrentAccount()]
        : _contractorNames();
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(
                        List<_RoleAssignment>.from(widget.assignments),
                      ),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Rollenbeheer',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          setState(() => _showInvite = !_showInvite),
                      icon: const Icon(Icons.person_add_alt_1),
                    ),
                  ],
                ),
                  const SizedBox(height: 12),
                  if (_showInvite) ...[
                    _InputCard(
                      title: _selectedRole == 'Onderaannemer' ||
                              _selectedRole == 'Team'
                          ? 'Nieuwe toevoegen'
                          : 'Iemand uitnodigen',
                      children: [
                        if (_selectedRole != 'Team') ...[
                          TextField(
                            controller: _nameController,
                            decoration: InputDecoration(
                              hintText: _selectedRole == 'Onderaannemer'
                                  ? 'Bedrijfsnaam'
                                  : 'Naam',
                              filled: true,
                              fillColor: const Color(0xFFF4F1EA),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide:
                                    const BorderSide(color: Color(0xFFE1DAD0)),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(14),
                                borderSide:
                                    const BorderSide(color: Color(0xFF0B2E2B)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (_selectedRole != 'Onderaannemer')
                            TextField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                hintText: 'E-mailadres',
                                filled: true,
                                fillColor: const Color(0xFFF4F1EA),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE1DAD0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF0B2E2B)),
                                ),
                              ),
                              keyboardType: TextInputType.emailAddress,
                            ),
                          if (_selectedRole != 'Onderaannemer')
                            const SizedBox(height: 10),
                        ],
                        DropdownButtonFormField<String>(
                          key: ValueKey('role-$_selectedRole'),
                          initialValue: _selectedRole,
                          items: availableInviteRoles
                              .map(
                                (role) => DropdownMenuItem<String>(
                                  value: role,
                                  child: Text(role),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() {
                              _selectedRole = value;
                              final options = _isContractor
                                  ? [_contractorNameForCurrentAccount()]
                                  : _contractorNames();
                              if (_selectedRole != 'Onderaannemer' &&
                                  options.isNotEmpty) {
                                _selectedContractor ??= options.first;
                              } else {
                                _selectedContractor = null;
                              }
                            });
                          },
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.badge_outlined,
                                color: Color(0xFF6A7C78)),
                            filled: true,
                            fillColor: const Color(0xFFF4F1EA),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: Color(0xFFE1DAD0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide:
                                  const BorderSide(color: Color(0xFF0B2E2B)),
                            ),
                          ),
                        ),
                        if (_practicalRoles.contains(_selectedRole)) ...[
                          if (_selectedRole != 'Onderaannemer') ...[
                            const SizedBox(height: 10),
                            if (contractorOptions.isEmpty)
                            Text(
                              'Voeg eerst een onderaannemer toe.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF6A7C78)),
                            )
                          else
                            DropdownButtonFormField<String>(
                              key: ValueKey(
                                _selectedContractor ?? contractorOptions.first,
                              ),
                              initialValue:
                                  _selectedContractor ?? contractorOptions.first,
                              items: contractorOptions
                                  .map(
                                    (contractor) => DropdownMenuItem<String>(
                                      value: contractor,
                                      child: Text(contractor),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                setState(() => _selectedContractor = value);
                              },
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.apartment_outlined,
                                    color: Color(0xFF6A7C78)),
                                filled: true,
                                fillColor: const Color(0xFFF4F1EA),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE1DAD0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF0B2E2B)),
                                ),
                              ),
                            ),
                          ],
                          if (_selectedRole == 'Team') ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _teamController,
                              decoration: InputDecoration(
                                hintText: 'Team',
                                filled: true,
                                fillColor: const Color(0xFFF4F1EA),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFFE1DAD0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: const BorderSide(
                                      color: Color(0xFF0B2E2B)),
                                ),
                              ),
                            ),
                          ],
                          if (_selectedRole == 'Werknemer') ...[
                            const SizedBox(height: 10),
                            Builder(
                              builder: (context) {
                                final contractor =
                                    _resolvedContractor(_nameController.text.trim());
                                final teams = contractor.isEmpty
                                    ? const <String>[]
                                    : _teamNames(contractor);
                                if (teams.isEmpty) {
                                  return Text(
                                    'Voeg eerst een team toe.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF6A7C78),
                                        ),
                                  );
                                }
                                final selectedTeam =
                                    _teamController.text.isNotEmpty
                                        ? _teamController.text
                                        : teams.first;
                                return DropdownButtonFormField<String>(
                                  key: ValueKey(selectedTeam),
                                  initialValue: selectedTeam,
                                  items: teams
                                      .map(
                                        (team) => DropdownMenuItem<String>(
                                          value: team,
                                          child: Text(team),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    if (value == null) return;
                                    setState(() => _teamController.text = value);
                                  },
                                  decoration: InputDecoration(
                                    prefixIcon: const Icon(Icons.group_outlined,
                                        color: Color(0xFF6A7C78)),
                                    filled: true,
                                    fillColor: const Color(0xFFF4F1EA),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                          color: Color(0xFFE1DAD0)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                          color: Color(0xFF0B2E2B)),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                        const SizedBox(height: 12),
                        _PrimaryButton(
                          label: _selectedRole == 'Onderaannemer' ||
                                  _selectedRole == 'Team'
                              ? 'Aanmaken'
                              : 'Uitnodigen',
                          onTap: () {
                            _invite();
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_isAdminLike) ...[
                    _TabToggle(
                      labels: const ['Administratief', 'Praktisch'],
                      selectedIndex: _tabIndex,
                      onSelect: (index) => setState(() => _tabIndex = index),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (_isAdminLike && _tabIndex == 0) ...[
                    if (_adminAssignments().isEmpty)
                      Text(
                        'Nog geen administratieve rollen.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: const Color(0xFF6A7C78)),
                      )
                    else
                      ..._adminAssignments().map(
                        (assignment) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RoleAssignmentRow(
                            assignment: assignment,
                            onRoleChanged: (value) {
                              _applyRoleChange(assignment, value);
                            },
                            canEditRole: _isAdminLike,
                            allowedRoles: _adminRoles,
                            canDelete: _canDeleteAssignment(assignment),
                            onDelete: () => _deleteAssignment(assignment),
                          ),
                        ),
                      ),
                  ] else ...[
                    if (_practicalHierarchy().isEmpty)
                      Text(
                        'Nog geen praktische teams.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: const Color(0xFF6A7C78)),
                      )
                    else
                      ..._practicalHierarchy().entries.map(
                        (contractorEntry) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _ContractorSection(
                            contractor: contractorEntry.key,
                            teams: contractorEntry.value,
                            assignments: widget.assignments,
                            canEdit: _isAdminLike || _isContractor,
                            canDeleteTeam:
                                _canDeleteTeam(contractorEntry.key),
                            onDeleteTeam: (team) =>
                                _deleteTeam(contractorEntry.key, team),
                            onUpdateTeam: (team, newName, workingDays) =>
                                _updateTeam(
                                  contractorEntry.key,
                                  team,
                                  newName,
                                  workingDays,
                                ),
                            canDeleteWorker: (worker) =>
                                _canDeleteAssignment(worker),
                            onDeleteWorker: (worker) =>
                                _deleteAssignment(worker),
                            canDeleteContractor: _isAdminLike,
                            onDeleteContractor: () {
                              final assignment = widget.assignments.firstWhere(
                                (entry) =>
                                    entry.role == 'Onderaannemer' &&
                                    entry.name == contractorEntry.key,
                                orElse: () => _RoleAssignment(
                                  name: contractorEntry.key,
                                  email: '',
                                  role: 'Onderaannemer',
                                ),
                              );
                              _deleteAssignment(assignment);
                            },
                            onRoleChanged: (assignment, role) {
                              _applyRoleChange(assignment, role);
                            },
                            onTeamChanged: (assignment, team) {
                              setState(() => assignment.team = team);
                              AppDataStore.scheduleSave();
                            },
                            onContractorChanged: (assignment, contractor) {
                              setState(() => assignment.contractor = contractor);
                              AppDataStore.scheduleSave();
                            },
                          ),
                        ),
                      ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class OfferManagementScreen extends StatefulWidget {
  const OfferManagementScreen({super.key, required this.account});

  final TestAccount account;

  @override
  State<OfferManagementScreen> createState() => _OfferManagementScreenState();
}

class _OfferManagementScreenState extends State<OfferManagementScreen> {
  bool get _isAdmin => widget.account.role == 'Beheerder';
  bool get _isContractor =>
      widget.account.role == 'Onderaannemer' ||
      widget.account.role == 'Onderaannemer beheerder';

  @override
  void initState() {
    super.initState();
    OfferCatalogStore.seedIfEmpty();
  }

  Future<void> _addCategory() async {
    final controller = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Nieuwe onderverdeling'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: 'Naam'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Annuleer'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Toevoegen'),
            ),
          ],
        );
      },
    );
    if (saved != true) return;
    final name = controller.text.trim();
    if (name.isEmpty) return;
    setState(() {
      OfferCatalogStore.addCategory(name);
    });
  }

  Future<void> _openItemEditor({
    required OfferCategory category,
    OfferItem? item,
  }) async {
    final nameController = TextEditingController(text: item?.name ?? '');
    final priceController = TextEditingController(
      text: item == null ? '' : _formatPrice(item.price),
    );
    final unitController = TextEditingController(text: item?.unit ?? '');
    final hoursController = TextEditingController(
      text: item?.hours == null ? '' : _formatPrice(item!.hours!),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            20 + MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _isAdmin
                    ? (item == null ? 'Element toevoegen' : 'Element bewerken')
                    : 'Uren toewijzen',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              if (_isAdmin) ...[
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    hintText: 'Naam',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: priceController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Prijs (EUR)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: unitController,
                  decoration: const InputDecoration(
                    hintText: 'Eenheid (bijv. stuk, m)',
                  ),
                ),
              ] else ...[
                Text(
                  item?.name ?? '',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  item == null
                      ? ''
                      : 'EUR ${_formatPrice(item.price)} / ${item.unit}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF6A7C78)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: hoursController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Uren',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _SecondaryButton(
                      label: 'Annuleer',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PrimaryButton(
                      label: 'Opslaan',
                      onTap: () {
                        if (_isAdmin) {
                          final name = nameController.text.trim();
                          final price =
                              double.tryParse(priceController.text.trim()) ?? 0;
                          final unit = unitController.text.trim();
                          if (name.isEmpty || unit.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Vul alle velden in.'),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            if (item == null) {
                              OfferCatalogStore.addItem(
                                category.name,
                                OfferItem(
                                  name: name,
                                  price: price,
                                  unit: unit,
                                ),
                              );
                            } else {
                              item.name = name;
                              item.price = price;
                              item.unit = unit;
                            }
                          });
                          AppDataStore.scheduleSave();
                        } else if (_isContractor && item != null) {
                          final hours =
                              double.tryParse(hoursController.text.trim());
                          setState(() {
                            item.hours = hours;
                          });
                          AppDataStore.scheduleSave();
                        }
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = OfferCatalogStore.categories;
    final canSeePrices = _canSeeOfferPrices(CurrentUserStore.role);
    final canSeeHours = _canSeeOfferHours(CurrentUserStore.role);
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Offertebeheer',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (_isAdmin)
                      IconButton(
                        onPressed: _addCategory,
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (categories.isEmpty)
                  Text(
                    'Nog geen onderverdelingen toegevoegd.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: const Color(0xFF6A7C78)),
                  )
                else
                  ...categories.map(
                    (category) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _InputCard(
                        title: category.name,
                        children: [
                          if (category.items.isEmpty)
                            Text(
                              'Nog geen elementen toegevoegd.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF6A7C78)),
                            )
                          else
                            ...category.items.map(
                              (item) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${canSeePrices ? 'EUR ${_formatPrice(item.price)} / ${item.unit}' : 'Eenheid: ${item.unit}'}'
                                            '${item.hours == null || !canSeeHours ? '' : ' · ${_formatPrice(item.hours!)} uur'}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      const Color(0xFF6A7C78),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon:
                                          const Icon(Icons.edit_outlined, size: 18),
                                      color: const Color(0xFF6A7C78),
                                      onPressed: () =>
                                          _openItemEditor(category: category, item: item),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (_isAdmin) ...[
                            const SizedBox(height: 6),
                            _InlineButton(
                              label: 'Element toevoegen',
                              onTap: () => _openItemEditor(category: category),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleAssignmentRow extends StatelessWidget {
  const _RoleAssignmentRow({
    required this.assignment,
    required this.onRoleChanged,
    this.canEditRole = true,
    this.allowedRoles = _roleOptions,
    this.canDelete = false,
    this.onDelete,
  });

  final _RoleAssignment assignment;
  final ValueChanged<String> onRoleChanged;
  final bool canEditRole;
  final List<String> allowedRoles;
  final bool canDelete;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
            children: [
              Expanded(
                child: Text(
                  '${assignment.name} — ${assignment.role}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (canEditRole)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: const Color(0xFF6A7C78),
                  onPressed: () => _openRoleEditor(
                    context,
                    currentRole: assignment.role,
                    allowedRoles: allowedRoles,
                    onSave: onRoleChanged,
                    onDelete: canDelete ? onDelete : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContractorSection extends StatelessWidget {
  const _ContractorSection({
    required this.contractor,
    required this.teams,
    required this.assignments,
    required this.canEdit,
    required this.canDeleteTeam,
    required this.onDeleteTeam,
    required this.onUpdateTeam,
    required this.canDeleteWorker,
    required this.onDeleteWorker,
    required this.canDeleteContractor,
    required this.onDeleteContractor,
    required this.onRoleChanged,
    required this.onTeamChanged,
    required this.onContractorChanged,
  });

  final String contractor;
  final Map<String, List<_RoleAssignment>> teams;
  final List<_RoleAssignment> assignments;
  final bool canEdit;
  final bool canDeleteTeam;
  final ValueChanged<String> onDeleteTeam;
  final void Function(String team, String newName, Set<int> workingDays)
      onUpdateTeam;
  final bool Function(_RoleAssignment worker) canDeleteWorker;
  final void Function(_RoleAssignment worker) onDeleteWorker;
  final bool canDeleteContractor;
  final VoidCallback onDeleteContractor;
  final void Function(_RoleAssignment assignment, String role) onRoleChanged;
  final void Function(_RoleAssignment assignment, String team) onTeamChanged;
  final void Function(_RoleAssignment assignment, String contractor)
      onContractorChanged;

  _RoleAssignment? _contractorAssignment() {
    return assignments.firstWhere(
      (assignment) =>
          assignment.role == 'Onderaannemer' && assignment.name == contractor,
      orElse: () => _RoleAssignment(
        name: contractor,
        email: '',
        role: 'Onderaannemer',
        contractor: contractor,
      ),
    );
  }

  String _adminLabel() {
    final admins = assignments
        .where(
          (assignment) =>
              assignment.role == 'Onderaannemer beheerder' &&
              assignment.contractor == contractor,
        )
        .map((assignment) => assignment.name)
        .toList();
    if (admins.isEmpty) return 'onderaannemer';
    return 'beheerders: ${admins.join(', ')}';
  }

  @override
  Widget build(BuildContext context) {
    final contractorAssignment = _contractorAssignment();
    final managers = assignments
        .where(
          (assignment) =>
              assignment.role == 'Onderaannemer beheerder' &&
              assignment.contractor == contractor,
        )
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Row(
          children: [
            Expanded(
              child: Text(
                '$contractor — onderaannemer',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (canEdit && contractorAssignment != null)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: const Color(0xFF6A7C78),
                onPressed: () => _openRoleEditor(
                  context,
                  currentRole: contractorAssignment.role,
                  allowedRoles: _practicalRoles,
                  onSave: (role) => onRoleChanged(contractorAssignment, role),
                  onDelete:
                      canDeleteContractor ? onDeleteContractor : null,
                ),
              ),
          ],
        ),
        subtitle: Text(
          _adminLabel(),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: const Color(0xFF6A7C78)),
        ),
        children: [
          if (managers.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F6F1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFEDE5DA)),
                ),
                child: ExpansionTile(
                  tilePadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  title: Text(
                    'Beheerders',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF0B2E2B),
                        ),
                  ),
                  children: managers
                      .map(
                        (manager) => Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                          child: _RoleAssignmentRow(
                            assignment: manager,
                            onRoleChanged: (value) =>
                                onRoleChanged(manager, value),
                            canEditRole: canEdit,
                            allowedRoles: const [
                              'Onderaannemer beheerder',
                              'Werknemer',
                            ],
                            canDelete: canDeleteWorker(manager),
                            onDelete: () => onDeleteWorker(manager),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Text(
                'Geen beheerders toegevoegd.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF6A7C78)),
              ),
            ),
          ...teams.entries.map(
            (teamEntry) => Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _TeamSection(
                contractor: contractor,
                team: teamEntry.key,
                workers: teamEntry.value,
                canEdit: canEdit,
                canDeleteTeam: canDeleteTeam,
                onDeleteTeam: () => onDeleteTeam(teamEntry.key),
                onUpdateTeam: (newName, workingDays) => onUpdateTeam(
                  teamEntry.key,
                  newName,
                  workingDays,
                ),
                canDeleteWorker: canDeleteWorker,
                onDeleteWorker: onDeleteWorker,
                onRoleChanged: onRoleChanged,
                onTeamChanged: onTeamChanged,
                onContractorChanged: onContractorChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({
    required this.contractor,
    required this.team,
    required this.workers,
    required this.canEdit,
    required this.canDeleteTeam,
    required this.onDeleteTeam,
    required this.onUpdateTeam,
    required this.canDeleteWorker,
    required this.onDeleteWorker,
    required this.onRoleChanged,
    required this.onTeamChanged,
    required this.onContractorChanged,
  });

  final String contractor;
  final String team;
  final List<_RoleAssignment> workers;
  final bool canEdit;
  final bool canDeleteTeam;
  final VoidCallback onDeleteTeam;
  final void Function(String newName, Set<int> workingDays) onUpdateTeam;
  final bool Function(_RoleAssignment worker) canDeleteWorker;
  final void Function(_RoleAssignment worker) onDeleteWorker;
  final void Function(_RoleAssignment assignment, String role) onRoleChanged;
  final void Function(_RoleAssignment assignment, String team) onTeamChanged;
  final void Function(_RoleAssignment assignment, String contractor)
      onContractorChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEDE5DA)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        title: Row(
          children: [
            Expanded(
              child: Text(
                team,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF0B2E2B),
                    ),
              ),
            ),
            if (canEdit)
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: const Color(0xFF6A7C78),
                onPressed: () => _openTeamEditor(
                  context,
                  currentName: team,
                  currentWorkdays:
                      _RoleManagementStore.workingDaysForTeam(
                        team,
                        contractor: contractor,
                      ),
                  onSave: onUpdateTeam,
                  onDelete: canDeleteTeam ? onDeleteTeam : null,
                ),
              ),
          ],
        ),
        children: workers
            .map(
              (worker) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: _WorkerRow(
                  worker: worker,
                  canEdit: canEdit,
                  canDelete: canDeleteWorker(worker),
                  onDelete: () => onDeleteWorker(worker),
                  onRoleChanged: onRoleChanged,
                  onTeamChanged: onTeamChanged,
                  onContractorChanged: onContractorChanged,
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _WorkerRow extends StatelessWidget {
  const _WorkerRow({
    required this.worker,
    required this.canEdit,
    required this.canDelete,
    required this.onDelete,
    required this.onRoleChanged,
    required this.onTeamChanged,
    required this.onContractorChanged,
  });

  final _RoleAssignment worker;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onDelete;
  final void Function(_RoleAssignment assignment, String role) onRoleChanged;
  final void Function(_RoleAssignment assignment, String team) onTeamChanged;
  final void Function(_RoleAssignment assignment, String contractor)
      onContractorChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            Row(
            children: [
              Expanded(
                child: Text(
                  '${worker.name} — ${worker.role}',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (canEdit)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  color: const Color(0xFF6A7C78),
                  onPressed: () => _openRoleEditor(
                    context,
                    currentRole: worker.role,
                    allowedRoles: _practicalRoles,
                    onSave: (role) => onRoleChanged(worker, role),
                    onDelete: canDelete ? onDelete : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (canEdit)
            const SizedBox.shrink(),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.items});

  final List<_StatTileData> items;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.15,
      children: items
          .map(
            (item) => _StatTile(data: item),
          )
          .toList(),
    );
  }
}

Future<void> _openRoleEditor(
  BuildContext context, {
  required String currentRole,
  required List<String> allowedRoles,
  required ValueChanged<String> onSave,
  VoidCallback? onDelete,
}) async {
  var selectedRole = currentRole;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setSheetState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Rol aanpassen',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  key: ValueKey('edit-role-$selectedRole'),
                  initialValue: selectedRole,
                  items: allowedRoles
                      .map(
                        (role) => DropdownMenuItem<String>(
                          value: role,
                          child: Text(role),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    setSheetState(() => selectedRole = value);
                  },
                  decoration: InputDecoration(
                    prefixIcon:
                        const Icon(Icons.badge_outlined, color: Color(0xFF6A7C78)),
                    filled: true,
                    fillColor: const Color(0xFFF4F1EA),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _SecondaryButton(
                        label: 'Annuleer',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PrimaryButton(
                        label: 'Opslaan',
                        onTap: () {
                          onSave(selectedRole);
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
                if (onDelete != null) ...[
                  const SizedBox(height: 12),
                  _DangerButton(
                    label: 'Verwijderen',
                    onTap: () {
                      onDelete();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ],
            );
          },
        ),
      );
    },
  );
}

Future<void> _openTeamEditor(
  BuildContext context, {
  required String currentName,
  required Set<int> currentWorkdays,
  required void Function(String name, Set<int> workingDays) onSave,
  VoidCallback? onDelete,
}) async {
  final controller = TextEditingController(text: currentName);
  final selectedDays = Set<int>.from(currentWorkdays);
  final dayOptions = const [
    {'label': 'Ma', 'value': DateTime.monday},
    {'label': 'Di', 'value': DateTime.tuesday},
    {'label': 'Wo', 'value': DateTime.wednesday},
    {'label': 'Do', 'value': DateTime.thursday},
    {'label': 'Vr', 'value': DateTime.friday},
    {'label': 'Za', 'value': DateTime.saturday},
    {'label': 'Zo', 'value': DateTime.sunday},
  ];
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              20,
              20,
              20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team bewerken',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  decoration: InputDecoration(
                    hintText: 'Teamnaam',
                    filled: true,
                    fillColor: const Color(0xFFF4F1EA),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Werkdagen',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: dayOptions
                      .map(
                        (day) => FilterChip(
                          label: Text(day['label'] as String),
                          selected:
                              selectedDays.contains(day['value'] as int),
                          onSelected: (selected) {
                            setModalState(() {
                              final value = day['value'] as int;
                              if (selected) {
                                selectedDays.add(value);
                              } else {
                                selectedDays.remove(value);
                              }
                            });
                          },
                          selectedColor: const Color(0xFF0B2E2B),
                          labelStyle: TextStyle(
                            color: selectedDays.contains(day['value'] as int)
                                ? const Color(0xFFFFE9CC)
                                : const Color(0xFF4B6763),
                          ),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _SecondaryButton(
                        label: 'Annuleer',
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PrimaryButton(
                        label: 'Opslaan',
                        onTap: () {
                          final value = controller.text.trim();
                          if (selectedDays.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Kies minstens één werkdag.'),
                              ),
                            );
                            return;
                          }
                          if (value.isNotEmpty) {
                            onSave(value, selectedDays);
                          }
                          Navigator.of(context).pop();
                        },
                      ),
                    ),
                  ],
                ),
                if (onDelete != null) ...[
                  const SizedBox(height: 12),
                  _DangerButton(
                    label: 'Verwijderen',
                    onTap: () {
                      onDelete();
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ],
            ),
          );
        },
      );
    },
  );
}

class _StatTileData {
  const _StatTileData({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.data});

  final _StatTileData data;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF4F1EA),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              data.icon,
              size: 20,
              color: const Color(0xFF0B2E2B),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${data.value}',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: const Color(0xFF0B2E2B),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            data.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF5A6F6C),
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _DatePickerRow extends StatelessWidget {
  const _DatePickerRow({
    required this.label,
    required this.value,
    required this.onPick,
  });

  final String label;
  final DateTime? value;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF243B3A),
                ),
          ),
        ),
        _InlineButton(
          label: value == null ? 'Kies datum' : _formatDate(value!),
          onTap: onPick,
          icon: Icons.calendar_today,
        ),
      ],
    );
  }
}

class _DangerButton extends StatelessWidget {
  const _DangerButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: const Color(0xFFB42318),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DocumentEntry {
  DocumentEntry({
    required this.description,
    required this.expiry,
    required this.file,
  });

  final String description;
  final DateTime expiry;
  final PlatformFile file;

  bool get isValid => expiry.isAfter(DateTime.now());
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
    this.onOpen,
  });

  final DocumentEntry entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final statusLabel = entry.isValid ? 'Geldig' : 'Ongeldig';
    final statusColor =
        entry.isValid ? const Color(0xFF0B2E2B) : const Color(0xFFB42318);
    final isPreviewable = _isPreviewableFile(entry.file);
    final previewPath = entry.file.path;
    final previewBytes = entry.file.bytes;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1DAD0)),
          ),
          child: Row(
            children: [
              Container(
                height: 38,
                width: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFFFCE6CC),
                  borderRadius: BorderRadius.circular(12),
                  image: isPreviewable && (previewPath != null || previewBytes != null)
                      ? DecorationImage(
                          image: previewPath != null
                              ? FileImage(File(previewPath))
                              : MemoryImage(previewBytes!) as ImageProvider,
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: isPreviewable && (previewPath != null || previewBytes != null)
                    ? null
                    : const Icon(Icons.description_outlined,
                        color: Color(0xFF6A4A2D)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.description,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF243B3A),
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Vervalt op ${_formatDate(entry.expiry)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF6A7C78)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusLabel,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EditableInputField extends StatelessWidget {
  const _EditableInputField({
    required this.label,
    required this.hint,
    required this.icon,
    required this.controller,
    this.obscure = false,
    this.keyboardType,
  });

  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController controller;
  final bool obscure;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF243B3A),
              ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          obscureText: obscure,
          keyboardType: keyboardType,
          autocorrect: !obscure,
          enableSuggestions: !obscure,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF6A7C78)),
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF4F1EA),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
            ),
          ),
        ),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF243B3A),
              ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF4F1EA),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE1DAD0)),
          ),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF6A7C78)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value.isEmpty ? '—' : value,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF6A7C78)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.currentStatus,
    required this.pendingStatus,
    required this.onChanged,
    required this.onSave,
  });

  final String currentStatus;
  final String pendingStatus;
  final ValueChanged<String> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      title: 'Status',
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('status-$pendingStatus'),
          initialValue: pendingStatus,
          items: _editableStatusStages
              .map(
                (status) => DropdownMenuItem<String>(
                  value: status,
                  child: Text(status),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value == null) {
              return;
            }
            onChanged(value);
          },
          decoration: InputDecoration(
            prefixIcon:
                const Icon(Icons.flag_outlined, color: Color(0xFF6A7C78)),
            filled: true,
            fillColor: const Color(0xFFF4F1EA),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerRight,
          child: _PrimaryButton(label: 'Opslaan', onTap: onSave),
        ),
      ],
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({
    required this.title,
    required this.children,
    this.headerTrailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? headerTrailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              ...[headerTrailing].whereType<Widget>(),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  const _InputField({
    required this.label,
    required this.hint,
    required this.icon,
    this.controller,
  });

  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF243B3A),
              ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF6A7C78)),
            hintText: hint,
            filled: true,
            fillColor: const Color(0xFFF4F1EA),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: hintText,
        prefixIcon: const Icon(Icons.search, color: Color(0xFF6A7C78)),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.clear, color: Color(0xFF6A7C78)),
                onPressed: () {
                  controller.clear();
                  onChanged?.call('');
                },
              ),
        filled: false,
        contentPadding: const EdgeInsets.symmetric(vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
        ),
      ),
    );
  }
}

class _MiniCalendarPicker extends StatelessWidget {
  const _MiniCalendarPicker({
    required this.team,
    required this.focusedDay,
    required this.selectedStart,
    required this.selectedEnd,
    required this.enabledDays,
    required this.assignments,
    required this.onFocused,
    required this.onSelect,
  });

  final String team;
  final DateTime focusedDay;
  final DateTime? selectedStart;
  final DateTime? selectedEnd;
  final Set<DateTime> enabledDays;
  final List<TeamAssignment> assignments;
  final ValueChanged<DateTime> onFocused;
  final ValueChanged<DateTime> onSelect;

  bool _isSameDay(DateTime? a, DateTime? b) => isSameDay(a, b);

  static const int _miniMaxLaneShown = 3;

  DateTime _normalize(DateTime day) => DateTime(day.year, day.month, day.day);

  bool _isWorkingDayForTeam(DateTime day) {
    final normalized = _normalize(day);
    final workingDays = _RoleManagementStore.workingDaysForTeam(team);
    if (!workingDays.contains(normalized.weekday)) {
      return false;
    }
    return !PlanningCalendarStore.isNonWorkingDay(normalized);
  }

  bool _isBackorderAssignment(TeamAssignment assignment) {
    if (assignment.group == 'Nabestellingen') return true;
    final group = ProjectStore.findGroupForProject(assignment.project);
    return group == 'Nabestellingen';
  }

  List<TeamAssignment> _assignmentsForDay(DateTime day) {
    final normalized = _normalize(day);
    return assignments.where((assignment) {
      final start = _normalize(assignment.startDate);
      final end = _normalize(assignment.endDate);
      return !normalized.isBefore(start) && !normalized.isAfter(end);
    }).toList();
  }

  Map<TeamAssignment, int> _computeLanes(List<TeamAssignment> items) {
    final laneMap = <TeamAssignment, int>{};
    final laneEnds = <DateTime>[];
    final sorted = List<TeamAssignment>.from(items)
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    for (final assignment in sorted) {
      if (_isBackorderAssignment(assignment)) {
        continue;
      }
      final start = _normalize(assignment.startDate);
      final end = _normalize(assignment.endDate);
      int laneIndex = 0;
      for (; laneIndex < laneEnds.length; laneIndex++) {
        if (start.isAfter(laneEnds[laneIndex])) {
          break;
        }
      }
      if (laneIndex == laneEnds.length) {
        laneEnds.add(end);
      } else {
        laneEnds[laneIndex] = end;
      }
      laneMap[assignment] = laneIndex;
    }
    return laneMap;
  }

  int _previewLane(
    DateTime start,
    DateTime end,
    Map<TeamAssignment, int> laneMap,
  ) {
    final normalizedStart = _normalize(start);
    final normalizedEnd = _normalize(end);
    for (int lane = 0; lane < _miniMaxLaneShown; lane++) {
      final conflict = laneMap.entries.any((entry) {
        if (entry.value != lane) return false;
        final assignment = entry.key;
        final aStart = _normalize(assignment.startDate);
        final aEnd = _normalize(assignment.endDate);
        return !normalizedEnd.isBefore(aStart) &&
            !normalizedStart.isAfter(aEnd);
      });
      if (!conflict) return lane;
    }
    return 0;
  }

  Widget _buildDayCell({
    required BuildContext context,
    required DateTime day,
    required bool isSelected,
    required bool isToday,
    required Map<TeamAssignment, int> laneMap,
    DateTime? previewStart,
    DateTime? previewEnd,
    int? previewLane,
    bool isEnabled = true,
  }) {
    final isWorkingDay = _isWorkingDayForTeam(day);
    final items = isWorkingDay
        ? (_assignmentsForDay(day)
          ..sort((a, b) {
            final laneA = laneMap[a] ?? 0;
            final laneB = laneMap[b] ?? 0;
            return laneA.compareTo(laneB);
          }))
        : <TeamAssignment>[];
    final dotItems = items.where((assignment) {
      return _isBackorderAssignment(assignment);
    }).toList();
    final lineItemsAll =
        items.where((assignment) => !dotItems.contains(assignment)).toList();
    final lineItems = lineItemsAll.where((assignment) {
      final lane = laneMap[assignment] ?? 0;
      return lane < _miniMaxLaneShown;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        const barHeight = 4.0;
        const barGap = 2.0;
        const topStart = 2.0;
        const dateHeight = 12.0;
        final dotRowTop = topStart + dateHeight + 2;
        final linesTop = dotRowTop + 6;
        final normalizedDay = _normalize(day);
        final previewSingleDay =
            previewStart != null &&
            previewEnd != null &&
            previewStart.isAtSameMomentAs(previewEnd);
        final previewCoversDay = isWorkingDay &&
            previewStart != null &&
            previewEnd != null &&
            !previewSingleDay &&
            !normalizedDay.isBefore(previewStart) &&
            !normalizedDay.isAfter(previewEnd);
        final showPreviewDot = isWorkingDay &&
            previewSingleDay &&
            normalizedDay.isAtSameMomentAs(previewStart);
        final hasPreviewRange =
            previewStart != null && previewEnd != null && !previewSingleDay;
        final usedLanes = <int>{};
        final effectiveLaneMap = <TeamAssignment, int>{};
        for (final assignment in lineItems) {
          var candidate = laneMap[assignment] ?? 0;
          if (candidate >= _miniMaxLaneShown) continue;
          if (hasPreviewRange &&
              previewLane != null &&
              candidate == previewLane) {
            final previewStartDay = previewStart;
            final previewEndDay = previewEnd;
            final aStart = _normalize(assignment.startDate);
            final aEnd = _normalize(assignment.endDate);
            final overlapsPreview = !previewEndDay.isBefore(aStart) &&
                !previewStartDay.isAfter(aEnd);
            if (overlapsPreview) {
              final fallback = List.generate(_miniMaxLaneShown, (i) => i)
                  .firstWhere(
                (lane) => lane != previewLane && !usedLanes.contains(lane),
                orElse: () => candidate,
              );
              candidate = fallback;
            }
          }
          if (usedLanes.contains(candidate)) {
            final fallback = List.generate(_miniMaxLaneShown, (i) => i)
                .firstWhere(
              (lane) => !usedLanes.contains(lane),
              orElse: () => candidate,
            );
            candidate = fallback;
          }
          usedLanes.add(candidate);
          effectiveLaneMap[assignment] = candidate;
        }

        return Stack(
          children: [
            if (isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B2E2B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              )
            else if (isToday)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA64D).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isEnabled
                            ? const Color(0xFF243B3A)
                            : const Color(0xFFB0B8B6),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ),
            ...lineItems.map((assignment) {
              final lane =
                  effectiveLaneMap[assignment] ?? (laneMap[assignment] ?? 0);
              final color = const Color(0xFF0B2E2B);
              final start = _normalize(assignment.startDate);
              final end = _normalize(assignment.endDate);
              final singleDay = start.isAtSameMomentAs(end);
              final top = linesTop + lane * (barHeight + barGap);
              final isStart = start.isAtSameMomentAs(normalizedDay);
              final isEnd = end.isAtSameMomentAs(normalizedDay);
              const boundaryInset = 3.0;
              final leftInset = isStart ? boundaryInset : 0.0;
              final rightInset = isEnd ? boundaryInset : 0.0;
              return Positioned(
                left: 0,
                right: 0,
                top: top,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: singleDay ? boundaryInset : leftInset,
                    right: singleDay ? boundaryInset : rightInset,
                  ),
                  child: Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.horizontal(
                        left: isStart || singleDay
                            ? Radius.circular(barHeight / 2)
                            : Radius.zero,
                        right: isEnd || singleDay
                            ? Radius.circular(barHeight / 2)
                            : Radius.zero,
                      ),
                    ),
                  ),
                ),
              );
            }),
            if (dotItems.isNotEmpty || showPreviewDot)
              Positioned(
                left: 2,
                right: 2,
                top: dotRowTop,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ...List.generate(
                      dotItems.length > 5 ? 5 : dotItems.length,
                      (_) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFF0B2E2B),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                    if (showPreviewDot)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Color(0xFF2F6FED),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (previewCoversDay && previewLane != null)
              Positioned(
                left: 0,
                right: 0,
                top: linesTop + previewLane * (barHeight + barGap),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: normalizedDay.isAtSameMomentAs(previewStart)
                        ? 3
                        : 0,
                    right:
                        normalizedDay.isAtSameMomentAs(previewEnd) ? 3 : 0,
                  ),
                  child: Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F6FED),
                      borderRadius: BorderRadius.horizontal(
                        left: normalizedDay.isAtSameMomentAs(previewStart)
                            ? Radius.circular(barHeight / 2)
                            : Radius.zero,
                        right: normalizedDay.isAtSameMomentAs(previewEnd)
                            ? Radius.circular(barHeight / 2)
                            : Radius.zero,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final laneMap = _computeLanes(assignments);
    final hasPreview = selectedStart != null && selectedEnd != null;
    final previewStart =
        hasPreview ? _normalize(selectedStart!) : null;
    final previewEnd =
        hasPreview ? _normalize(selectedEnd!) : null;
    final previewLane = hasPreview && previewStart != null && previewEnd != null
        ? _previewLane(previewStart, previewEnd, laneMap)
        : null;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: TableCalendar(
        firstDay: DateTime.utc(2024, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: focusedDay,
        calendarFormat: CalendarFormat.month,
        startingDayOfWeek: StartingDayOfWeek.monday,
        selectedDayPredicate: (day) => _isSameDay(day, selectedStart),
        enabledDayPredicate: (day) => _isWorkingDayForTeam(day),
        onDaySelected: (selectedDay, focusedDay) {
          onFocused(focusedDay);
          onSelect(selectedDay);
        },
        onPageChanged: onFocused,
        calendarStyle: CalendarStyle(
          cellMargin: const EdgeInsets.all(2),
          outsideTextStyle:
              (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
                  .copyWith(color: const Color(0xFFB0B8B6)),
        ),
        headerStyle: const HeaderStyle(
          titleCentered: true,
          formatButtonVisible: false,
          leftChevronVisible: true,
          rightChevronVisible: true,
        ),
        daysOfWeekStyle: DaysOfWeekStyle(
          weekdayStyle:
              (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
                  .copyWith(color: const Color(0xFF5A6F6C)),
          weekendStyle:
              (Theme.of(context).textTheme.bodySmall ?? const TextStyle())
                  .copyWith(color: const Color(0xFF5A6F6C)),
        ),
        calendarBuilders: CalendarBuilders(
          selectedBuilder: (context, day, focusedDay) => _buildDayCell(
            context: context,
            day: day,
            isSelected: true,
            isToday: isSameDay(DateTime.now(), day),
            laneMap: laneMap,
            previewStart: previewStart,
            previewEnd: previewEnd,
            previewLane: previewLane,
          ),
          todayBuilder: (context, day, focusedDay) => _buildDayCell(
            context: context,
            day: day,
            isSelected: false,
            isToday: true,
            laneMap: laneMap,
            previewStart: previewStart,
            previewEnd: previewEnd,
            previewLane: previewLane,
            isEnabled: true,
          ),
          defaultBuilder: (context, day, focusedDay) =>
              _buildDayCell(
            context: context,
            day: day,
            isSelected: false,
            isToday: false,
            laneMap: laneMap,
            previewStart: previewStart,
            previewEnd: previewEnd,
            previewLane: previewLane,
          ),
          disabledBuilder: (context, day, focusedDay) => _buildDayCell(
            context: context,
            day: day,
            isSelected: false,
            isToday: isSameDay(DateTime.now(), day),
            laneMap: laneMap,
            previewStart: previewStart,
            previewEnd: previewEnd,
            previewLane: previewLane,
            isEnabled: false,
          ),
          outsideBuilder: (context, day, focusedDay) => _buildDayCell(
            context: context,
            day: day,
            isSelected: false,
            isToday: isSameDay(DateTime.now(), day),
            laneMap: laneMap,
            previewStart: previewStart,
            previewEnd: previewEnd,
            previewLane: previewLane,
            isEnabled: false,
          ),
          markerBuilder: (context, day, events) {
            final isHoliday = PlanningCalendarStore.holidays.contains(day);
            final isVacation = PlanningCalendarStore.vacations.contains(day);
            if (!isHoliday && !isVacation) return null;
            return Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isHoliday) const _LegendDot(color: Color(0xFF0B2E2B)),
                if (isHoliday && isVacation) const SizedBox(width: 3),
                if (isVacation) const _LegendDot(color: Color(0xFFFFA64D)),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FileUploadRow extends StatelessWidget {
  const _FileUploadRow({
    required this.label,
    required this.buttonLabel,
    required this.files,
    required this.onAdd,
    this.showFiles = true,
  });

  final String label;
  final String buttonLabel;
  final List<PlatformFile> files;
  final VoidCallback onAdd;
  final bool showFiles;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1EA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.attach_file, color: Color(0xFF6A7C78)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF5A6F6C)),
                ),
                if (showFiles && files.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: files
                        .map(
                          (file) => _FilePill(name: file.name),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
          _InlineButton(label: buttonLabel, onTap: onAdd),
        ],
      ),
    );
  }
}

class _FilePill extends StatelessWidget {
  const _FilePill({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFFCE6CC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        name,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: const Color(0xFF6A4A2D)),
      ),
    );
  }
}

class _ChoiceToggle extends StatelessWidget {
  const _ChoiceToggle({
    required this.label,
    required this.options,
    required this.selectedIndex,
    required this.onSelect,
  });

  final String label;
  final List<String> options;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF243B3A),
              ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: List.generate(options.length, (index) {
            final isSelected = index == selectedIndex;
            return GestureDetector(
              onTap: () => onSelect(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0B2E2B) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0B2E2B)
                        : const Color(0xFFE1DAD0),
                  ),
                ),
                child: Text(
                  options[index],
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: isSelected
                            ? const Color(0xFFFFE9CC)
                            : const Color(0xFF4B6763),
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF243B3A),
              ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: value,
          items: items
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item,
                  child: Text(item),
                ),
              )
              .toList(),
          onChanged: onChanged,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF4F1EA),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
            ),
          ),
        ),
      ],
    );
  }
}

// ignore: unused_element
class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFCE6CC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF6A4A2D)),
                              const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF6A4A2D)),
          ),
        ],
      ),
    );
  }
}

class _StatusPicker extends StatefulWidget {
  const _StatusPicker({
    required this.statuses,
    required this.selected,
  });

  final List<String> statuses;
  final String selected;

  @override
  State<_StatusPicker> createState() => _StatusPickerState();
}

class _StatusPickerState extends State<_StatusPicker> {
  late String _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.selected;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: widget.statuses.map((status) {
        final isSelected = status == _selected;
        return GestureDetector(
          onTap: () => setState(() => _selected = status),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF0B2E2B) : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF0B2E2B)
                    : const Color(0xFFE1DAD0),
              ),
            ),
            child: Text(
              status,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isSelected
                        ? const Color(0xFFFFE9CC)
                        : const Color(0xFF4B6763),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class StatusDetailScreen extends StatefulWidget {
  const StatusDetailScreen({
    super.key,
    required this.group,
    required this.status,
  });

  final String group;
  final String status;

  @override
  State<StatusDetailScreen> createState() => _StatusDetailScreenState();
}

class _StatusDetailScreenState extends State<StatusDetailScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _hasChanges = false;
  bool _selectionMode = false;
  final Set<String> _selectedCustomers = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _filteredCustomers() {
    final query = _searchController.text.trim().toLowerCase();
    final customers =
        ProjectStore.projectsByGroup[widget.group]?[widget.status] ??
            const <String>[];
    if (query.isEmpty) {
      return customers;
    }
    return customers
        .where((name) => name.toLowerCase().contains(query))
        .toList();
  }

  void _toggleSelection(String name) {
    setState(() {
      if (_selectedCustomers.contains(name)) {
        _selectedCustomers.remove(name);
      } else {
        _selectedCustomers.add(name);
      }
      if (_selectedCustomers.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  Future<void> _showBulkStatusPicker() async {
    if (!_editableStatusStages.contains(widget.status)) {
      return;
    }
    if (_selectedCustomers.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status wijzigen',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              ..._editableStatusStages.map(
                (item) => ListTile(
                  title: Text(item),
                  trailing: item == widget.status
                      ? const Icon(Icons.check)
                      : const SizedBox.shrink(),
                  onTap: () => Navigator.of(context).pop(item),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (selected == null || selected == widget.status) return;
    setState(() {
      for (final name in _selectedCustomers) {
        ProjectStore.updateStatus(
          name: name,
          group: widget.group,
          status: selected,
        );
      }
      _selectedCustomers.clear();
      _selectionMode = false;
      _hasChanges = true;
    });
  }

  Future<void> _deleteSelectedProjects() async {
    if (_selectedCustomers.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Projecten verwijderen?'),
        content: Text(
          'Dit verwijdert ${_selectedCustomers.length} projecten definitief.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      for (final name in _selectedCustomers) {
        ProjectStore.deleteProject(name);
      }
      _selectedCustomers.clear();
      _selectionMode = false;
      _hasChanges = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final customers = _filteredCustomers();
    final isExternal = _isExternalRole(CurrentUserStore.role);
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: Stack(
              children: [
                Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(_hasChanges),
                                icon: const Icon(Icons.arrow_back),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: _SearchField(
                                  controller: _searchController,
                                  hintText: 'Zoek klant',
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  widget.status,
                                  style:
                                      Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              if (!isExternal)
                                _PrimaryButton(
                                  label: 'Project +',
                                  height: 42,
                                  onTap: () async {
                                    final result =
                                        await Navigator.of(context)
                                            .push<bool>(
                                      _appPageRoute(
                                        builder: (_) => AddProjectScreen(
                                          initialGroup: widget.group,
                                          initialStatus: widget.status,
                                        ),
                                      ),
                                    );
                                    if (result == true) {
                                      setState(() {});
                                    }
                                  },
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${widget.group} · ${ProjectStore.projectsByGroup[widget.group]?[widget.status]?.length ?? 0} projecten',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: const Color(0xFF6A7C78)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                        children: [
                          const SizedBox(height: 4),
                          if (customers.isEmpty)
                            _EmptyStateCard(
                              title: 'Geen klanten gevonden',
                              subtitle: 'Probeer een andere zoekterm.',
                            )
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: customers.length,
                              itemBuilder: (context, index) {
                                final name = customers[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _CustomerRow(
                                    name: name,
                                    phone: ProjectStore.details[name]?.phone ?? '—',
                                    group: widget.group,
                                    status: widget.status,
                                    highlight: false,
                                      onCenterTap: _selectionMode
                                          ? () => _toggleSelection(name)
                                          : () async {
                                              final changed =
                                                  await Navigator.of(context)
                                                      .push<bool>(
                                                _appPageRoute(
                                                  builder: (_) =>
                                                      ProjectDetailScreen(
                                                    customerName: name,
                                                    group: widget.group,
                                                    status: widget.status,
                                                  ),
                                                ),
                                              );
                                              setState(() {
                                                if (changed == true) {
                                                  _hasChanges = true;
                                                }
                                              });
                                            },
                                    onIconTap: () {
                                      if (!_selectionMode) {
                                        setState(() {
                                          _selectionMode = true;
                                        });
                                      }
                                      _toggleSelection(name);
                                    },
                                      onArrowTap: _selectionMode
                                          ? null
                                          : () async {
                                              final changed =
                                                  await Navigator.of(context)
                                                      .push<bool>(
                                                _appPageRoute(
                                                  builder: (_) =>
                                                      ProjectDetailScreen(
                                                    customerName: name,
                                                    group: widget.group,
                                                    status: widget.status,
                                                  ),
                                                ),
                                              );
                                              setState(() {
                                                if (changed == true) {
                                                  _hasChanges = true;
                                                }
                                              });
                                            },
                                    selected: _selectedCustomers.contains(name),
                                    showSelection: _selectionMode,
                                  ),
                                );
                              },
                            ),
                          if (_selectionMode) const SizedBox(height: 80),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_selectionMode)
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 16,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _PrimaryButton(
                          label:
                              'Status aanpassen (${_selectedCustomers.length})',
                          onTap: _selectedCustomers.isEmpty
                              ? null
                              : _showBulkStatusPicker,
                          fullWidth: true,
                        ),
                        if (!isExternal) ...[
                          const SizedBox(height: 10),
                          _DangerButton(
                            label:
                                'Verwijderen (${_selectedCustomers.length})',
                            onTap: () => _deleteSelectedProjects(),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AddProjectScreen extends StatefulWidget {
  const AddProjectScreen({
    super.key,
    required this.initialGroup,
    required this.initialStatus,
  });

  final String initialGroup;
  final String initialStatus;

  @override
  State<AddProjectScreen> createState() => _AddProjectScreenState();
}

class _AddProjectScreenState extends State<AddProjectScreen> {
  bool _hasFinish = false;
  String _finishType = 'PVC';
  late String _selectedGroup;
  late String _selectedStatus;
  final Map<String, int> _offerQuantities = {};
  final Map<String, TextEditingController> _offerControllers = {};
  final List<ProjectDocument> _documents = [];
  final TextEditingController _docDescriptionController =
      TextEditingController();
  PlatformFile? _docFile;
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _deliveryController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _estimatedDaysController =
      TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedGroup = widget.initialGroup;
    _selectedStatus = widget.initialStatus;
    OfferCatalogStore.seedIfEmpty();
  }

  @override
  void dispose() {
    _customerController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _deliveryController.dispose();
    _notesController.dispose();
    _estimatedDaysController.dispose();
    _docDescriptionController.dispose();
    for (final controller in _offerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null) {
      return;
    }
    setState(() {
      _docFile = result.files.first;
    });
  }

  void _addDocument() {
    final desc = _docDescriptionController.text.trim();
    if (desc.isEmpty || _docFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul een beschrijving in en kies een bestand')),
      );
      return;
    }
    setState(() {
      _documents.add(ProjectDocument(description: desc, file: _docFile!));
      _docDescriptionController.clear();
      _docFile = null;
    });
  }

  String _offerKey(String category, String item) => '$category::$item';

  void _updateOfferQuantity(String key, int delta) {
    setState(() {
      final current = _offerQuantities[key] ?? 0;
      final next = current + delta;
      if (next <= 0) {
        _offerQuantities.remove(key);
      } else {
        _offerQuantities[key] = next;
      }
      if (_offerControllers.containsKey(key)) {
        _offerControllers[key]!.text =
            _offerQuantities[key]?.toString() ?? '';
      }
    });
  }

  List<OfferLine> _buildOfferLines() {
    final lines = <OfferLine>[];
    for (final entry in _offerQuantities.entries) {
      if (entry.value <= 0) continue;
      final parts = entry.key.split('::');
      if (parts.length < 2) continue;
      final category = parts.first;
      final item = parts.sublist(1).join('::');
      lines.add(
        OfferLine(
          category: category,
          item: item,
          quantity: entry.value,
        ),
      );
    }
    return lines;
  }

  TextEditingController _controllerForOffer(String key) {
    return _offerControllers.putIfAbsent(key, () {
      final controller = TextEditingController(
        text: _offerQuantities[key]?.toString() ?? '',
      );
      return controller;
    });
  }

  Widget _offerQtyButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 32,
        width: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F1EA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE1DAD0)),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF243B3A)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: Stack(
              children: [
                ListView(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.arrow_back),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Nieuw project',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InputCard(
                      title: 'Klant & locatie',
                      children: [
                        _InputField(
                          label: 'Klantnaam',
                          hint: 'Bijv. Familie Jacobs',
                          icon: Icons.person_outline,
                          controller: _customerController,
                        ),
                        const SizedBox(height: 12),
                        _InputField(
                          label: 'Telefoonnummer',
                          hint: 'Bijv. 0470 12 34 56',
                          icon: Icons.phone_outlined,
                          controller: _phoneController,
                        ),
                        const SizedBox(height: 12),
                        _InputField(
                          label: 'Adres',
                          hint: 'Straat + nummer, postcode, gemeente',
                          icon: Icons.location_on_outlined,
                          controller: _addressController,
                        ),
                        const SizedBox(height: 12),
                        _InputField(
                          label: 'Leveradres ramen',
                          hint: 'Levering op werf of magazijn',
                          icon: Icons.local_shipping_outlined,
                          controller: _deliveryController,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _InputCard(
                      title: 'Werk & extra info',
                      children: [
                        _InputField(
                          label: 'Geschatte dagen',
                          hint: 'Bijv. 3',
                          icon: Icons.schedule_outlined,
                          controller: _estimatedDaysController,
                        ),
                        const SizedBox(height: 12),
                        _ChoiceToggle(
                          label: 'Afwerking',
                          options: const ['Zonder afwerking', 'Met afwerking'],
                          selectedIndex: _hasFinish ? 1 : 0,
                          onSelect: (index) => setState(() {
                            _hasFinish = index == 1;
                          }),
                        ),
                        if (_hasFinish) ...[
                          const SizedBox(height: 12),
                          _ChoiceToggle(
                            label: 'Type afwerking',
                            options: const ['PVC', 'MDF', 'Pleister'],
                            selectedIndex:
                                ['PVC', 'MDF', 'Pleister'].indexOf(_finishType),
                            onSelect: (index) => setState(() {
                              _finishType = ['PVC', 'MDF', 'Pleister'][index];
                            }),
                          ),
                        ],
                        const SizedBox(height: 12),
                        _InputField(
                          label: 'Extra notes',
                          hint: 'Optioneel',
                          icon: Icons.sticky_note_2_outlined,
                          controller: _notesController,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                _InputCard(
                  title: 'Documenten',
                  children: [
                    TextField(
                      controller: _docDescriptionController,
                      decoration: InputDecoration(
                        hintText: 'Beschrijving',
                        filled: true,
                        fillColor: const Color(0xFFF4F1EA),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _FileUploadRow(
                      label: _docFile?.name ?? 'Bestand toevoegen',
                      buttonLabel: 'Kies bestand',
                      files: _docFile == null ? const [] : [_docFile!],
                      onAdd: _pickFile,
                    ),
                    const SizedBox(height: 10),
                    _PrimaryButton(
                      label: 'Document toevoegen',
                      onTap: _addDocument,
                    ),
                    if (_documents.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      ..._documents.map(
                        (doc) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F1EA),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFE1DAD0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc.description,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 6),
                                _FilePill(name: doc.file.name),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _InputCard(
                  title: 'Offerte',
                  children: [
                    if (OfferCatalogStore.categories.isEmpty)
                      Text(
                        'Nog geen offerte-elementen toegevoegd.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: const Color(0xFF6A7C78)),
                      )
                    else
                      ...OfferCatalogStore.categories.map(
                        (category) => ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: Text(
                            category.name,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          children: [
                            if (category.items.isEmpty)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Nog geen elementen toegevoegd.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF6A7C78),
                                      ),
                                ),
                              )
                            else
                              ...category.items.map(
                                (item) {
                                  final key =
                                      _offerKey(category.name, item.name);
                                  final qty = _offerQuantities[key] ?? 0;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.name,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              if (_canSeeOfferPrices(
                                                CurrentUserStore.role,
                                              )) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  'EUR ${_formatPrice(item.price)} / ${item.unit}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: const Color(
                                                          0xFF6A7C78,
                                                        ),
                                                      ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        _offerQtyButton(
                                          icon: Icons.remove,
                                          onTap: qty == 0
                                              ? null
                                              : () => _updateOfferQuantity(
                                                    key,
                                                    -1,
                                                  ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 44,
                                          child: TextField(
                                            controller:
                                                _controllerForOffer(key),
                                            keyboardType: TextInputType.number,
                                            textAlign: TextAlign.center,
                                            decoration: InputDecoration(
                                              isDense: true,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 6,
                                                horizontal: 6,
                                              ),
                                              filled: true,
                                              fillColor:
                                                  const Color(0xFFF4F1EA),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFFE1DAD0),
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                borderSide: const BorderSide(
                                                  color: Color(0xFF0B2E2B),
                                                ),
                                              ),
                                            ),
                                            onChanged: (value) {
                                              final parsed =
                                                  int.tryParse(value.trim());
                                              setState(() {
                                                if (parsed == null ||
                                                    parsed <= 0) {
                                                  _offerQuantities.remove(key);
                                                } else {
                                                  _offerQuantities[key] = parsed;
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        _offerQtyButton(
                                          icon: Icons.add,
                                          onTap: () =>
                                              _updateOfferQuantity(key, 1),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                _InputCard(
                  title: 'Status',
                  children: [
                        _ChoiceToggle(
                          label: 'Type',
                          options: _projectGroups,
                          selectedIndex: _projectGroups.indexOf(_selectedGroup),
                          onSelect: (index) => setState(() {
                            _selectedGroup = _projectGroups[index];
                            _selectedStatus = _statusStages.first;
                          }),
                        ),
                        const SizedBox(height: 12),
                        _DropdownField(
                          label: 'Status',
                          value: _selectedStatus,
                          items: _statusStages,
                          onChanged: (value) => setState(() {
                            _selectedStatus = value ?? _statusStages.first;
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _PrimaryButton(
                      label: 'Project toevoegen',
                      onTap: () {
                        final name = _customerController.text.trim();
                        if (name.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Vul minstens de klantnaam in'),
                            ),
                          );
                          return;
                        }
                        final phone = _phoneController.text.trim();
                        if (phone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Vul een telefoonnummer in'),
                            ),
                          );
                          return;
                        }
                        final estimatedDays =
                            int.tryParse(_estimatedDaysController.text.trim()) ??
                                1;
                    ProjectStore.addProject(
                      name: name,
                      group: _selectedGroup,
                      status: _selectedStatus,
                      creator: 'Julie',
                      offerLines: _buildOfferLines(),
                      documents: _documents,
                      details: ProjectDetails(
                            address: _addressController.text.trim().isEmpty
                                ? '—'
                                : _addressController.text.trim(),
                            phone: phone,
                            delivery: _deliveryController.text.trim().isEmpty
                                ? '—'
                                : _deliveryController.text.trim(),
                            finish: _hasFinish
                                ? _finishType
                                : 'Zonder afwerking',
                            extraNotes: _notesController.text.trim().isEmpty
                                ? '—'
                                : _notesController.text.trim(),
                            estimatedDays: estimatedDays,
                          ),
                        );
                        Navigator.of(context).pop(true);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({
    super.key,
    required this.customerName,
    required this.group,
    required this.status,
  });

  final String customerName;
  final String group;
  final String status;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class ProjectLogScreen extends StatelessWidget {
  const ProjectLogScreen({super.key, required this.projectName});

  final String projectName;

  @override
  Widget build(BuildContext context) {
    final entries = ProjectLogStore.forProject(projectName);
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Logboek',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              projectName,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: const Color(0xFF6A7C78)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: entries.isEmpty
                      ? Center(
                          child: Text(
                            'Nog geen logs beschikbaar.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: const Color(0xFF6A7C78)),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          itemCount: entries.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return _ProjectLogEntryCard(entry: entries[index]);
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class EstimatedDaysChangeDetailScreen extends StatelessWidget {
  const EstimatedDaysChangeDetailScreen({
    super.key,
    required this.request,
    required this.scheduled,
    this.onUpdated,
  });

  final EstimatedDaysChangeRequest request;
  final List<TeamAssignment> scheduled;
  final VoidCallback? onUpdated;

  TeamAssignment? _assignment() {
    for (final assignment in scheduled) {
      if (assignment.project == request.project &&
          assignment.team == request.team) {
        return assignment;
      }
    }
    return null;
  }

  List<TeamAssignment> _teamAssignments() {
    final list = scheduled
        .where(
          (assignment) =>
              assignment.team == request.team && !assignment.isBackorder,
        )
        .toList();
    list.sort((a, b) => a.startDate.compareTo(b.startDate));
    return list;
  }

  void _approve(BuildContext context, bool shift, TeamAssignment? assignment) {
    final details = ProjectStore.details[request.project];
    if (details != null) {
      ProjectStore.details[request.project] = ProjectDetails(
        address: details.address,
        phone: details.phone,
        delivery: details.delivery,
        finish: details.finish,
        extraNotes: details.extraNotes,
        estimatedDays: request.newDays,
      );
    }
    if (assignment != null) {
      if (shift) {
        _applyEstimatedDaysShift(
          scheduled,
          request.team,
          request.project,
          request.newDays,
        );
      } else {
        _applyEstimatedDaysNoShift(scheduled, assignment, request.newDays);
      }
    }
    request.status = 'Goedgekeurd';
    ProjectLogStore.add(
      request.project,
      'Geschatte dagen goedgekeurd: ${request.oldDays} → ${request.newDays}'
      '${shift ? ' (planning verschoven)' : ''}',
    );
    AppDataStore.scheduleSave();
    onUpdated?.call();
    Navigator.of(context).pop();
  }

  void _deny(BuildContext context) {
    request.status = 'Geweigerd';
    ProjectLogStore.add(
      request.project,
      'Aanvraag geschatte dagen geweigerd',
    );
    AppDataStore.scheduleSave();
    onUpdated?.call();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final assignment = _assignment();
    final teamAssignments = _teamAssignments();
    TeamAssignment? nextAssignment;
    if (assignment != null) {
      final index = teamAssignments.indexWhere(
        (item) => item.project == assignment.project,
      );
      if (index != -1 && index + 1 < teamAssignments.length) {
        nextAssignment = teamAssignments[index + 1];
      }
    }
    final currentStart = assignment?.startDate;
    final currentEnd = assignment?.endDate;
    final newEnd = assignment == null
        ? null
        : _endDateFromWorkingDays(
            assignment.startDate,
            request.newDays,
            request.team,
          );
    final delta = request.newDays - request.oldDays;
    final freeDay = (newEnd == null)
        ? null
        : _nextWorkingDayForTeam(
            newEnd.add(const Duration(days: 1)),
            request.team,
          );
    final overlap = newEnd != null &&
        nextAssignment != null &&
        !_normalizeDateOnly(newEnd)
            .isBefore(_normalizeDateOnly(nextAssignment.startDate));

    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aanvraag geschatte dagen',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            request.project,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: const Color(0xFF6A7C78)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InputCard(
                  title: 'Wijziging',
                  children: [
                    _PlainInfoLine(
                      label: 'Team',
                      value: request.team,
                    ),
                    _PlainInfoLine(
                      label: 'Aangevraagd door',
                      value: request.requester,
                    ),
                    _PlainInfoLine(
                      label: 'Huidig',
                      value: _formatDays(request.oldDays),
                    ),
                    _PlainInfoLine(
                      label: 'Nieuw',
                      value: _formatDays(request.newDays),
                    ),
                    if (currentStart != null && currentEnd != null) ...[
                      const SizedBox(height: 8),
                      _PlainInfoLine(
                        label: 'Huidige planning',
                        value:
                            '${_formatDate(currentStart)} - ${_formatDate(currentEnd)}',
                      ),
                    ],
                    if (newEnd != null && currentStart != null) ...[
                      const SizedBox(height: 8),
                      _PlainInfoLine(
                        label: 'Nieuwe planning',
                        value:
                            '${_formatDate(currentStart)} - ${_formatDate(newEnd)}',
                      ),
                    ],
                    if (delta < 0 && freeDay != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Er komt ${_formatDays(-delta)} vrij vanaf ${_formatDate(freeDay)}.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF6A7C78)),
                      ),
                    ],
                    if (delta > 0 && newEnd != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Er zijn ${_formatDays(delta)} extra nodig tot ${_formatDate(newEnd)}.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF6A7C78)),
                      ),
                    ],
                    if (overlap) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Let op: dit overlapt met de volgende planning '
                        '(${_formatDate(nextAssignment.startDate)} - '
                        '${_formatDate(nextAssignment.endDate)}).',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFFB42318)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                _InputCard(
                  title: 'Planning team ${request.team}',
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 18,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFFD04A4A),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Huidige planning',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF6A7C78)),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          width: 18,
                          height: 6,
                          decoration: BoxDecoration(
                            color: const Color(0xFF2F6FED),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Nieuwe planning',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF6A7C78)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (teamAssignments.isEmpty)
                      Text(
                        'Geen planning gevonden voor dit team.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: const Color(0xFF6A7C78)),
                      )
                    else
                      _TeamMonthlyScheduleCard(
                        team: request.team,
                        assignments: teamAssignments,
                        onOpen: (assignment) {},
                        onCancel: (assignment) async {},
                        canEditPlanning: false,
                        onReschedule: (assignment, date) {},
                        availableStarts: (team, assignment, start) => const [],
                        calculateEndDate:
                            (team, start, days, isBackorder) => null,
                        showHeader: false,
                        initiallyExpanded: true,
                        previewProject: request.project,
                        previewStart: assignment?.startDate,
                        previewEnd: newEnd ?? assignment?.endDate,
                        previewOldStart: assignment?.startDate,
                        previewOldEnd: assignment?.endDate,
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _PrimaryButton(
                        label: 'Goedkeuren',
                        fullWidth: true,
                        onTap: assignment == null
                            ? null
                            : () => _approve(context, false, assignment),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _DangerButton(
                        label: 'Weigeren',
                        onTap: () => _deny(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  int _tabIndex = 0;
  int _siteTabIndex = 0;
  late List<PlatformFile> _beforePhotos;
  late List<PlatformFile> _afterPhotos;
  late List<ExtraWorkEntry> _extraWorks;
  final TextEditingController _extraWorkController = TextEditingController();
  final TextEditingController _extraHoursController = TextEditingController();
  String _extraWorkChargeType = _extraWorkChargeTypes.first;
  List<PlatformFile> _extraWorkFiles = [];
  int? _editingExtraWorkIndex;
  ExtraWorkEntry? _lastDeletedExtraWork;
  int? _lastDeletedExtraWorkIndex;
  final TextEditingController _commentController = TextEditingController();
  bool _isBackorder = false;
  final TextEditingController _backorderController = TextEditingController();
  final TextEditingController _backorderNoteController =
      TextEditingController();
  final List<String> _backorderItems = [];
  late String _currentStatus;
  bool _isEditingInfo = false;
  late String _pendingStatus;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _deliveryController;
  late TextEditingController _finishController;
  late TextEditingController _notesController;
  late TextEditingController _daysController;
  final Map<String, int> _offerQuantities = {};
  final Map<String, TextEditingController> _offerControllers = {};
  final List<ProjectDocument> _editDocuments = [];
  final TextEditingController _docDescriptionController =
      TextEditingController();
  PlatformFile? _docFile;
  final TextEditingController _daysChangeController = TextEditingController();

  String _documentKey(ProjectDocument doc) =>
      '${doc.description}::${doc.file.name}';

  void _logDetailsDiff(ProjectDetails? previous, ProjectDetails next) {
    if (previous == null) {
      ProjectLogStore.add(widget.customerName, 'Projectinformatie toegevoegd');
      return;
    }
    void logChange(String label, String oldValue, String newValue) {
      if (oldValue.trim() == newValue.trim()) return;
      ProjectLogStore.add(
        widget.customerName,
        '$label aangepast van "$oldValue" naar "$newValue"',
      );
    }

    logChange(
      'Telefoonnummer',
      previous.phone.trim().isEmpty ? '—' : previous.phone.trim(),
      next.phone.trim().isEmpty ? '—' : next.phone.trim(),
    );
    logChange(
      'Adres',
      previous.address.trim().isEmpty ? '—' : previous.address.trim(),
      next.address.trim().isEmpty ? '—' : next.address.trim(),
    );
    logChange(
      'Leveradres ramen',
      previous.delivery.trim().isEmpty ? '—' : previous.delivery.trim(),
      next.delivery.trim().isEmpty ? '—' : next.delivery.trim(),
    );
    logChange(
      'Afwerking',
      previous.finish.trim().isEmpty ? '—' : previous.finish.trim(),
      next.finish.trim().isEmpty ? '—' : next.finish.trim(),
    );
    logChange(
      'Extra notes',
      previous.extraNotes.trim().isEmpty ? '—' : previous.extraNotes.trim(),
      next.extraNotes.trim().isEmpty ? '—' : next.extraNotes.trim(),
    );
    if (previous.estimatedDays != next.estimatedDays) {
      ProjectLogStore.add(
        widget.customerName,
        'Geschatte dagen aangepast van '
        '${_formatDays(previous.estimatedDays)} naar '
        '${_formatDays(next.estimatedDays)}',
      );
    }
  }

  void _logOfferDiff(List<OfferLine> previous, List<OfferLine> next) {
    String keyFor(OfferLine line) => '${line.category}::${line.item}';
    final prevMap = <String, int>{};
    for (final line in previous) {
      prevMap[keyFor(line)] = line.quantity;
    }
    final nextMap = <String, int>{};
    for (final line in next) {
      nextMap[keyFor(line)] = line.quantity;
    }
    final keys = {...prevMap.keys, ...nextMap.keys};
    for (final key in keys) {
      final parts = key.split('::');
      final label =
          parts.length >= 2 ? '${parts[0]} - ${parts.sublist(1).join('::')}' : key;
      final prevQty = prevMap[key];
      final nextQty = nextMap[key];
      if (prevQty == null && nextQty != null) {
        ProjectLogStore.add(
          widget.customerName,
          'Offerte toegevoegd: $label (x$nextQty)',
        );
      } else if (prevQty != null && nextQty == null) {
        ProjectLogStore.add(
          widget.customerName,
          'Offerte verwijderd: $label',
        );
      } else if (prevQty != null && nextQty != null && prevQty != nextQty) {
        ProjectLogStore.add(
          widget.customerName,
          'Offerte aangepast: $label ($prevQty -> $nextQty)',
        );
      }
    }
  }

  void _logDocumentDiff(
    List<ProjectDocument> previous,
    List<ProjectDocument> next,
  ) {
    final prevKeys = previous.map(_documentKey).toSet();
    final nextKeys = next.map(_documentKey).toSet();
    final added = next.where((doc) => !prevKeys.contains(_documentKey(doc)));
    final removed = previous.where((doc) => !nextKeys.contains(_documentKey(doc)));
    for (final doc in added) {
      ProjectLogStore.add(
        widget.customerName,
        'Document toegevoegd: ${_truncateText(doc.description, 60)}',
      );
    }
    for (final doc in removed) {
      ProjectLogStore.add(
        widget.customerName,
        'Document verwijderd: ${_truncateText(doc.description, 60)}',
      );
    }
  }

  void _saveInfoChanges() {
    final previousDetails = ProjectStore.details[widget.customerName];
    final previousOffers =
        ProjectStore.offers[widget.customerName] ?? const <OfferLine>[];
    final previousDocs =
        ProjectStore.documents[widget.customerName] ?? const <ProjectDocument>[];
    final parsedDays = int.tryParse(_daysController.text.trim()) ?? 1;
    final currentStatus =
        ProjectStore.findStatusForProject(widget.customerName) ?? _currentStatus;
    final normalizedDays =
        currentStatus == 'Ingepland' ? _clampScheduledDays(parsedDays) : parsedDays;
    final details = ProjectDetails(
      address: _addressController.text.trim(),
      phone: _phoneController.text.trim().isEmpty
          ? '—'
          : _phoneController.text.trim(),
      delivery: _deliveryController.text.trim(),
      finish: _finishController.text.trim(),
      extraNotes: _notesController.text.trim(),
      estimatedDays: normalizedDays,
    );
    final offers = _buildOfferLines();
    final docs = List<ProjectDocument>.from(_editDocuments);
    ProjectStore.details[widget.customerName] = details;
    ProjectStore.offers[widget.customerName] = offers;
    ProjectStore.documents[widget.customerName] = docs;
    if (currentStatus == 'Ingepland' && normalizedDays > 0) {
      final index = ScheduleStore.scheduled.indexWhere(
        (assignment) => assignment.project == widget.customerName,
      );
      if (index != -1) {
        final assignment = ScheduleStore.scheduled[index];
        if (!assignment.isBackorder &&
            assignment.group != 'Nabestellingen') {
          final start = _normalizeDateOnly(assignment.startDate);
          final end = _endDateFromWorkingDays(
            start,
            _clampScheduledDays(normalizedDays),
            assignment.team,
          );
          ScheduleStore.scheduled[index] = TeamAssignment(
            project: assignment.project,
            team: assignment.team,
            startDate: start,
            endDate: end,
            estimatedDays: _clampScheduledDays(normalizedDays),
            isBackorder: assignment.isBackorder,
            group: assignment.group,
          );
        }
      }
    }
    _logDetailsDiff(previousDetails, details);
    _logOfferDiff(previousOffers, offers);
    _logDocumentDiff(previousDocs, docs);
    AppDataStore.scheduleSave();
    setState(() => _isEditingInfo = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Gegevens opgeslagen')),
    );
  }

  @override
  void dispose() {
    _backorderController.dispose();
    _backorderNoteController.dispose();
    _commentController.dispose();
    _extraWorkController.dispose();
    _extraHoursController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _deliveryController.dispose();
    _finishController.dispose();
    _notesController.dispose();
    _daysController.dispose();
    _docDescriptionController.dispose();
    _daysChangeController.dispose();
    for (final controller in _offerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status;
    _pendingStatus = _editableStatusStages.contains(widget.status)
        ? widget.status
        : _editableStatusStages.first;
    final details = ProjectStore.details[widget.customerName];
    OfferCatalogStore.seedIfEmpty();
    _beforePhotos =
        List<PlatformFile>.from(ProjectStore.beforePhotos[widget.customerName] ??
            const []);
    _afterPhotos =
        List<PlatformFile>.from(ProjectStore.afterPhotos[widget.customerName] ??
            const []);
    _extraWorks =
        List<ExtraWorkEntry>.from(ProjectStore.extraWorks[widget.customerName] ??
            const []);
    _isBackorder = ProjectStore.isBackorder[widget.customerName] ?? false;
    _backorderItems
      ..clear()
      ..addAll(ProjectStore.backorderItems[widget.customerName] ?? const []);
    _backorderNoteController.text =
        ProjectStore.backorderNotes[widget.customerName] ?? '';
    _addressController = TextEditingController(text: details?.address ?? '');
    _phoneController = TextEditingController(text: details?.phone ?? '');
    _deliveryController = TextEditingController(text: details?.delivery ?? '');
    _finishController = TextEditingController(text: details?.finish ?? '');
    _notesController = TextEditingController(text: details?.extraNotes ?? '');
    _daysController =
        TextEditingController(text: details?.estimatedDays.toString() ?? '');
    _editDocuments
      ..clear()
      ..addAll(ProjectStore.documents[widget.customerName] ?? const []);
    _loadOfferQuantities();
  }

  Future<void> _pickDocumentFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    if (result == null) return;
    setState(() {
      _docFile = result.files.first;
    });
  }

  void _addDocument() {
    final desc = _docDescriptionController.text.trim();
    if (desc.isEmpty || _docFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vul een beschrijving in en kies een bestand'),
        ),
      );
      return;
    }
    setState(() {
      _editDocuments.add(ProjectDocument(description: desc, file: _docFile!));
      _docDescriptionController.clear();
      _docFile = null;
    });
  }

  void _removeDocument(ProjectDocument doc) {
    setState(() {
      _editDocuments.remove(doc);
    });
  }

  void _loadOfferQuantities() {
    _offerQuantities.clear();
    final lines = ProjectStore.offers[widget.customerName] ?? const <OfferLine>[];
    for (final line in lines) {
      _offerQuantities[_offerKey(line.category, line.item)] = line.quantity;
    }
    for (final controller in _offerControllers.values) {
      controller.dispose();
    }
    _offerControllers.clear();
  }

  String _offerKey(String category, String item) => '$category::$item';

  void _updateOfferQuantity(String key, int delta) {
    setState(() {
      final current = _offerQuantities[key] ?? 0;
      final next = current + delta;
      if (next <= 0) {
        _offerQuantities.remove(key);
      } else {
        _offerQuantities[key] = next;
      }
      if (_offerControllers.containsKey(key)) {
        _offerControllers[key]!.text = _offerQuantities[key]?.toString() ?? '';
      }
    });
  }

  List<OfferLine> _buildOfferLines() {
    final lines = <OfferLine>[];
    for (final entry in _offerQuantities.entries) {
      if (entry.value <= 0) continue;
      final parts = entry.key.split('::');
      if (parts.length < 2) continue;
      final category = parts.first;
      final item = parts.sublist(1).join('::');
      lines.add(
        OfferLine(
          category: category,
          item: item,
          quantity: entry.value,
        ),
      );
    }
    return lines;
  }

  TextEditingController _controllerForOffer(String key) {
    return _offerControllers.putIfAbsent(key, () {
      final controller = TextEditingController(
        text: _offerQuantities[key]?.toString() ?? '',
      );
      return controller;
    });
  }

  Widget _offerQtyButton({
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 32,
        width: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFF4F1EA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE1DAD0)),
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF243B3A)),
      ),
    );
  }

  Future<void> _pickBeforePhotos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;
    setState(() {
      _beforePhotos.addAll(result.files);
      ProjectStore.beforePhotos[widget.customerName] = _beforePhotos;
    });
    ProjectLogStore.add(
      widget.customerName,
      "Foto's voor de werf toegevoegd (${result.files.length})",
    );
  }

  void _removeBeforePhoto(int index) {
    setState(() {
      if (index < 0 || index >= _beforePhotos.length) return;
      _beforePhotos.removeAt(index);
      ProjectStore.beforePhotos[widget.customerName] = _beforePhotos;
    });
    ProjectLogStore.add(widget.customerName, 'Foto voor de werf verwijderd');
  }

  Future<void> _pickAfterPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;
    setState(() {
      _afterPhotos.addAll(result.files);
      ProjectStore.afterPhotos[widget.customerName] = _afterPhotos;
    });
    ProjectLogStore.add(
      widget.customerName,
      "Foto's na de werf toegevoegd (${result.files.length})",
    );
  }

  void _removeAfterPhoto(int index) {
    setState(() {
      if (index < 0 || index >= _afterPhotos.length) return;
      _afterPhotos.removeAt(index);
      ProjectStore.afterPhotos[widget.customerName] = _afterPhotos;
    });
    ProjectLogStore.add(widget.customerName, 'Foto na de werf verwijderd');
  }

  Future<void> _pickExtraWorkPhotos() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
      withData: true,
    );
    if (result == null) return;
    setState(() {
      _extraWorkFiles = result.files;
    });
  }

  void _addExtraWork() {
    final description = _extraWorkController.text.trim();
    if (description.isEmpty || _extraWorkFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voeg een beschrijving en foto’s toe')),
      );
      return;
    }
    final hours = double.tryParse(_extraHoursController.text.trim()) ?? 0;
    final entry = ExtraWorkEntry(
      description: description,
      photos: List<PlatformFile>.from(_extraWorkFiles),
      hours: hours,
      chargeType: _extraWorkChargeType,
    );
    setState(() {
      if (_editingExtraWorkIndex != null &&
          _editingExtraWorkIndex! >= 0 &&
          _editingExtraWorkIndex! < _extraWorks.length) {
        _extraWorks[_editingExtraWorkIndex!] = entry;
        ProjectStore.extraWorks[widget.customerName] =
            List<ExtraWorkEntry>.from(_extraWorks);
        final summary = _truncateText(description, 60);
        ProjectLogStore.add(
          widget.customerName,
          summary.isEmpty
              ? 'Extra werk aangepast'
              : 'Extra werk aangepast: $summary',
        );
      } else {
        _extraWorks.add(entry);
        ProjectStore.addExtraWork(widget.customerName, entry);
      }
      _extraWorkController.clear();
      _extraHoursController.clear();
      _extraWorkChargeType = _extraWorkChargeTypes.first;
      _extraWorkFiles = [];
      _editingExtraWorkIndex = null;
    });
  }

  void _editExtraWork(int index) {
    if (index < 0 || index >= _extraWorks.length) return;
    final entry = _extraWorks[index];
    setState(() {
      _editingExtraWorkIndex = index;
      _extraWorkController.text = entry.description;
      _extraHoursController.text = _formatPrice(entry.hours);
      _extraWorkFiles = List<PlatformFile>.from(entry.photos);
      _extraWorkChargeType = entry.chargeType;
    });
  }

  void _deleteExtraWork(int index) {
    setState(() {
      if (index < 0 || index >= _extraWorks.length) return;
      _lastDeletedExtraWork = _extraWorks.removeAt(index);
      _lastDeletedExtraWorkIndex = index;
      ProjectStore.extraWorks[widget.customerName] =
          List<ExtraWorkEntry>.from(_extraWorks);
      if (_editingExtraWorkIndex == index) {
        _editingExtraWorkIndex = null;
        _extraWorkController.clear();
        _extraHoursController.clear();
        _extraWorkChargeType = _extraWorkChargeTypes.first;
        _extraWorkFiles = [];
      }
      if (_lastDeletedExtraWork != null) {
        final summary = _truncateText(_lastDeletedExtraWork!.description, 60);
        ProjectLogStore.add(
          widget.customerName,
          summary.isEmpty
              ? 'Extra werk verwijderd'
              : 'Extra werk verwijderd: $summary',
        );
      }
    });
    _showExtraWorkUndo();
  }

  void _undoExtraWorkDelete() {
    if (!mounted) return;
    final entry = _lastDeletedExtraWork;
    if (entry == null) return;
    final insertAt = (_lastDeletedExtraWorkIndex ?? _extraWorks.length)
        .clamp(0, _extraWorks.length);
    setState(() {
      _extraWorks.insert(insertAt, entry);
      ProjectStore.extraWorks[widget.customerName] =
          List<ExtraWorkEntry>.from(_extraWorks);
      _lastDeletedExtraWork = null;
      _lastDeletedExtraWorkIndex = null;
    });
    final summary = _truncateText(entry.description, 60);
    ProjectLogStore.add(
      widget.customerName,
      summary.isEmpty
          ? 'Extra werk teruggezet'
          : 'Extra werk teruggezet: $summary',
    );
  }

  void _showExtraWorkUndo() {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
        .showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
            content: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close),
                  color: Colors.white,
                  onPressed: () {
                    _lastDeletedExtraWork = null;
                    _lastDeletedExtraWorkIndex = null;
                    messenger.hideCurrentSnackBar();
                  },
                ),
                const Expanded(child: Text('Extra werk verwijderd')),
                TextButton(
                  onPressed: _undoExtraWorkDelete,
                  child: const Text(
                    'Ongedaan maken',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        )
        .closed
        .then((_) {
          _lastDeletedExtraWork = null;
          _lastDeletedExtraWorkIndex = null;
        });
  }

  void _addBackorderItem() {
    final text = _backorderController.text.trim();
    if (text.isEmpty) {
      return;
    }
    setState(() {
      _backorderItems.add(text);
      _backorderController.clear();
    });
    ProjectStore.setBackorder(
      widget.customerName,
      backorder: true,
      items: _backorderItems,
    );
    ProjectLogStore.add(
      widget.customerName,
      'Nabestelling item toegevoegd: ${_truncateText(text, 60)}',
    );
  }

  bool _hasBeforeAfterPhotos() {
    final before = ProjectStore.beforePhotos[widget.customerName] ?? const [];
    final after = ProjectStore.afterPhotos[widget.customerName] ?? const [];
    return before.isNotEmpty && after.isNotEmpty;
  }

  void _editBackorderItem(int index) {
    if (index < 0 || index >= _backorderItems.length) return;
    final removed = _backorderItems[index];
    _backorderController.text = removed;
    setState(() {
      _backorderItems.removeAt(index);
    });
    ProjectStore.setBackorder(
      widget.customerName,
      backorder: true,
      items: _backorderItems,
    );
    ProjectLogStore.add(
      widget.customerName,
      'Nabestelling item verwijderd: ${_truncateText(removed, 60)}',
    );
  }

  void _deleteBackorderItem(int index) {
    if (index < 0 || index >= _backorderItems.length) return;
    setState(() {
      final removed = _backorderItems.removeAt(index);
      ProjectLogStore.add(
        widget.customerName,
        'Nabestelling item verwijderd: ${_truncateText(removed, 60)}',
      );
    });
    ProjectStore.setBackorder(
      widget.customerName,
      backorder: true,
      items: _backorderItems,
    );
  }

  String _completionTeamForProject() {
    final matches = ScheduleStore.scheduled
        .where((assignment) => assignment.project == widget.customerName)
        .toList();
    if (matches.isEmpty) return '';
    matches.sort((a, b) => b.endDate.compareTo(a.endDate));
    return matches.first.team;
  }

  String _teamForProject() {
    for (final assignment in ScheduleStore.scheduled) {
      if (assignment.project == widget.customerName) {
        return assignment.team;
      }
    }
    return CurrentUserStore.team;
  }

  void _submitEstimatedDaysChange() {
    final details = ProjectStore.details[widget.customerName];
    final currentDays = details?.estimatedDays ?? 1;
    final parsed = int.tryParse(_daysChangeController.text.trim()) ?? 0;
    if (parsed <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vul een geldig aantal dagen in.')),
      );
      return;
    }
    if (parsed == currentDays) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aantal dagen is ongewijzigd.')),
      );
      return;
    }
    EstimatedDaysChangeStore.add(
      EstimatedDaysChangeRequest(
        project: widget.customerName,
        team: _teamForProject(),
        oldDays: currentDays,
        newDays: parsed,
        requester: CurrentUserStore.name,
        requesterRole: CurrentUserStore.role,
        createdAt: DateTime.now(),
      ),
    );
    ProjectLogStore.add(
      widget.customerName,
      'Aanvraag geschatte dagen: $currentDays → $parsed',
    );
    _daysChangeController.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aanvraag verstuurd.')),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isExternal = _isExternalRole(CurrentUserStore.role);
    final canEditStatus =
        !isExternal && _editableStatusStages.contains(_currentStatus);
    final canEditInfo = !isExternal;
    final canEditSite = isExternal && _currentStatus != 'Afgewerkt';
    final canEditCompletion = isExternal && _currentStatus != 'Afgewerkt';
    final canAddComment = CurrentUserStore.role == 'Projectleider';
    final canRequestDaysChange = _isExternalRole(CurrentUserStore.role);
    final pendingDaysRequest =
        EstimatedDaysChangeStore.pendingForProject(widget.customerName);
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.arrow_back),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              widget.customerName,
                              style: Theme.of(context).textTheme.titleLarge,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          _CircleIconButton(
                            icon: Icons.help_outline,
                            onTap: () {
                              Navigator.of(context).push(
                                _appPageRoute(
                                  builder: (_) => ProjectLogScreen(
                                    projectName: widget.customerName,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${widget.group} · ${widget.status}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: const Color(0xFF6A7C78)),
                            ),
                          ),
                          if (canEditInfo && _tabIndex == 0)
                            _InlineButton(
                              label: _isEditingInfo ? 'Opslaan' : 'Bewerken',
                              icon: _isEditingInfo
                                  ? Icons.check_circle_outline
                                  : Icons.edit_outlined,
                              onTap: () {
                                if (_isEditingInfo) {
                                  _saveInfoChanges();
                                } else {
                                  setState(() => _isEditingInfo = true);
                                }
                              },
                            ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _TabToggle(
                        labels: const ['Informatie', 'Werfopvolging'],
                        selectedIndex: _tabIndex,
                        onSelect: (index) => setState(() => _tabIndex = index),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    children: [
                      const SizedBox(height: 16),
                      if (_tabIndex == 0)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                      if (canEditStatus)
                        _StatusCard(
                          currentStatus: _currentStatus,
                          pendingStatus: _pendingStatus,
                          onChanged: (value) =>
                              setState(() => _pendingStatus = value),
                          onSave: () {
                            setState(() => _currentStatus = _pendingStatus);
                            ProjectStore.updateStatus(
                              name: widget.customerName,
                              group: widget.group,
                              status: _currentStatus,
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Status opgeslagen'),
                              ),
                            );
                            Navigator.of(context).pop(true);
                          },
                        )
                      else
                        _InfoTextBlock(
                          title: 'Status',
                          lines: [
                            _PlainInfoLine(
                              label: 'Huidige status',
                              value: _currentStatus,
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                      _ProjectInfoCard(
                        customerName: widget.customerName,
                        creator:
                            ProjectStore.creators[widget.customerName] ?? 'Julie',
                        details: ProjectStore.details[widget.customerName],
                        isEditing: canEditInfo && _isEditingInfo,
                        canEdit: canEditInfo,
                        addressController: _addressController,
                        phoneController: _phoneController,
                        deliveryController: _deliveryController,
                        finishController: _finishController,
                        notesController: _notesController,
                        daysController: _daysController,
                        completionTeam:
                            ProjectStore.completionTeams[widget.customerName],
                        onSave: () {
                          final details = ProjectDetails(
                            address: _addressController.text.trim(),
                            phone: _phoneController.text.trim().isEmpty
                                ? '—'
                                : _phoneController.text.trim(),
                            delivery: _deliveryController.text.trim(),
                            finish: _finishController.text.trim(),
                            extraNotes: _notesController.text.trim(),
                            estimatedDays:
                                int.tryParse(_daysController.text.trim()) ?? 1,
                          );
                          ProjectStore.details[widget.customerName] = details;
                          ProjectStore.offers[widget.customerName] =
                              _buildOfferLines();
                          AppDataStore.scheduleSave();
                          setState(() => _isEditingInfo = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Gegevens opgeslagen')),
                          );
                        },
                      ),
                      if (canRequestDaysChange && !_isBackorder) ...[
                        const SizedBox(height: 16),
                        if (pendingDaysRequest != null)
                          _InfoTextBlock(
                            title: 'Aanvraag geschatte dagen',
                            lines: [
                              _PlainInfoLine(
                                label: 'Aangevraagd',
                                value:
                                    '${pendingDaysRequest.oldDays} → ${pendingDaysRequest.newDays} dagen',
                              ),
                              _PlainInfoLine(
                                label: 'Status',
                                value: pendingDaysRequest.status,
                              ),
                            ],
                          )
                        else
                          _InputCard(
                            title: 'Geschatte dagen aanpassen',
                            children: [
                              _PlainInfoLine(
                                label: 'Huidig',
                                value: _formatDays(
                                  ProjectStore.details[widget.customerName]
                                          ?.estimatedDays ??
                                      1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _daysChangeController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText: 'Nieuw aantal dagen',
                                  filled: true,
                                  fillColor: const Color(0xFFF4F1EA),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide:
                                        const BorderSide(color: Color(0xFFE1DAD0)),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide:
                                        const BorderSide(color: Color(0xFF0B2E2B)),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _PrimaryButton(
                                label: 'Aanvraag versturen',
                                onTap: _submitEstimatedDaysChange,
                              ),
                            ],
                          ),
                      ],
                      if (canEditInfo && _isEditingInfo) ...[
                        const SizedBox(height: 16),
                        _InputCard(
                          title: 'Offerte',
                          children: [
                            if (OfferCatalogStore.categories.isEmpty)
                              Text(
                                'Nog geen offerte-elementen toegevoegd.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: const Color(0xFF6A7C78)),
                              )
                            else
                              ...OfferCatalogStore.categories.map(
                                (category) => ExpansionTile(
                                  tilePadding: EdgeInsets.zero,
                                  childrenPadding: EdgeInsets.zero,
                                  title: Text(
                                    category.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                  children: [
                                    if (category.items.isEmpty)
                                      Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                          'Nog geen elementen toegevoegd.',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF6A7C78),
                                              ),
                                        ),
                                      )
                                    else
                                      ...category.items.map(
                                        (item) {
                                          final key =
                                              _offerKey(category.name, item.name);
                                          final qty = _offerQuantities[key] ?? 0;
                                          return Padding(
                                            padding:
                                                const EdgeInsets.only(bottom: 8),
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        item.name,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodyMedium
                                                            ?.copyWith(
                                                              fontWeight:
                                                                  FontWeight.w600,
                                                            ),
                                                      ),
                                                      if (_canSeeOfferPrices(
                                                        CurrentUserStore.role,
                                                      )) ...[
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          'EUR ${_formatPrice(item.price)} / ${item.unit}',
                                                          style: Theme.of(context)
                                                              .textTheme
                                                              .bodySmall
                                                              ?.copyWith(
                                                                color: const Color(
                                                                  0xFF6A7C78,
                                                                ),
                                                              ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                _offerQtyButton(
                                                  icon: Icons.remove,
                                                  onTap: qty == 0
                                                      ? null
                                                      : () => _updateOfferQuantity(
                                                            key,
                                                            -1,
                                                          ),
                                                ),
                                                const SizedBox(width: 6),
                                                SizedBox(
                                                  width: 44,
                                                  child: TextField(
                                                    controller:
                                                        _controllerForOffer(key),
                                                    keyboardType:
                                                        TextInputType.number,
                                                    textAlign: TextAlign.center,
                                                    decoration: InputDecoration(
                                                      isDense: true,
                                                      contentPadding:
                                                          const EdgeInsets.symmetric(
                                                        vertical: 6,
                                                        horizontal: 6,
                                                      ),
                                                      filled: true,
                                                      fillColor:
                                                          const Color(0xFFF4F1EA),
                                                      enabledBorder:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                10),
                                                        borderSide:
                                                            const BorderSide(
                                                          color: Color(0xFFE1DAD0),
                                                        ),
                                                      ),
                                                      focusedBorder:
                                                          OutlineInputBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                                10),
                                                        borderSide:
                                                            const BorderSide(
                                                          color: Color(0xFF0B2E2B),
                                                        ),
                                                      ),
                                                    ),
                                                    onChanged: (value) {
                                                      final parsed = int.tryParse(
                                                          value.trim());
                                                      setState(() {
                                                        if (parsed == null ||
                                                            parsed <= 0) {
                                                          _offerQuantities
                                                              .remove(key);
                                                        } else {
                                                          _offerQuantities[key] =
                                                              parsed;
                                                        }
                                                      });
                                                    },
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                _offerQtyButton(
                                                  icon: Icons.add,
                                                  onTap: () =>
                                                      _updateOfferQuantity(
                                                    key,
                                                    1,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                                    const SizedBox(height: 8),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ] else if (ProjectStore.offers[widget.customerName]
                              ?.isNotEmpty ==
                          true) ...[
                        const SizedBox(height: 16),
                        _OfferOverviewCard(customerName: widget.customerName),
                      ],
                      const SizedBox(height: 16),
                      if (canEditInfo && _isEditingInfo)
                        _InputCard(
                          title: 'Documenten',
                          children: [
                            TextField(
                              controller: _docDescriptionController,
                              decoration: InputDecoration(
                                hintText: 'Beschrijving',
                                filled: true,
                                fillColor: const Color(0xFFF4F1EA),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide:
                                      const BorderSide(color: Color(0xFFE1DAD0)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide:
                                      const BorderSide(color: Color(0xFF0B2E2B)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _FileUploadRow(
                              label: _docFile?.name ?? 'Bestand toevoegen',
                              buttonLabel: 'Kies bestand',
                              files: _docFile == null ? const [] : [_docFile!],
                              onAdd: _pickDocumentFile,
                            ),
                            const SizedBox(height: 10),
                            _PrimaryButton(
                              label: 'Document toevoegen',
                              onTap: _addDocument,
                            ),
                            if (_editDocuments.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              ..._editDocuments.map(
                                (doc) => Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4F1EA),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: const Color(0xFFE1DAD0),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            doc.description,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                          ),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline,
                                              size: 18),
                                          color: const Color(0xFFB42318),
                                          onPressed: () => _removeDocument(doc),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        )
                      else if (ProjectStore.documents[widget.customerName]
                              ?.isNotEmpty ==
                          true)
                        _ProjectDocumentsCard(
                          customerName: widget.customerName,
                        ),
                      if (canEditInfo && _isEditingInfo) ...[
                        const SizedBox(height: 16),
                        _DangerButton(
                          label: 'Project verwijderen',
                          onTap: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (dialogContext) => AlertDialog(
                                title: const Text('Project verwijderen?'),
                                content: Text(
                                  'Dit verwijdert ${widget.customerName} definitief.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(false),
                                    child: const Text('Annuleren'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(dialogContext).pop(true),
                                    child: const Text('Verwijderen'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            ProjectStore.deleteProject(widget.customerName);
                            if (!context.mounted) return;
                            Navigator.of(context).pop(true);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Project verwijderd'),
                              ),
                            );
                          },
                        ),
                      ],
                          ],
                        )
                      else if (_tabIndex == 1)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                      _ProjectSiteFollowUp(
                        siteTabIndex: _siteTabIndex,
                        onTabChange: (index) =>
                            setState(() => _siteTabIndex = index),
                        beforePhotos: _beforePhotos,
                        afterPhotos: _afterPhotos,
                        canEdit: canEditSite,
                        onAddBefore: _pickBeforePhotos,
                        onAddAfter: _pickAfterPhotos,
                        onRemoveBefore: _removeBeforePhoto,
                        onRemoveAfter: _removeAfterPhoto,
                      ),
                      if ((ProjectStore.comments[widget.customerName]?.isNotEmpty ??
                              false) ||
                          canAddComment) ...[
                        const SizedBox(height: 16),
                        _ProjectCommentsSection(
                          comments: ProjectStore.comments[widget.customerName] ??
                              const [],
                          canAdd: canAddComment,
                          controller: _commentController,
                          onAdd: () {
                            final text = _commentController.text.trim();
                            if (text.isEmpty) return;
                            setState(() {
                              ProjectStore.addComment(widget.customerName, text);
                              _commentController.clear();
                            });
                          },
                        ),
                      ],
                      const SizedBox(height: 16),
                      _ExtraWorkSection(
                        canEdit: canEditSite,
                        isEditingExtraWork: _editingExtraWorkIndex != null,
                        extraWorks: _extraWorks,
                        extraWorkController: _extraWorkController,
                        extraHoursController: _extraHoursController,
                        extraWorkChargeType: _extraWorkChargeType,
                        onChargeTypeChanged: (value) => setState(() {
                          _extraWorkChargeType =
                              value ?? _extraWorkChargeTypes.first;
                        }),
                        extraWorkFiles: _extraWorkFiles,
                        onRemoveExtraPhoto: (index) => setState(() {
                          if (index < 0 || index >= _extraWorkFiles.length) {
                            return;
                          }
                          _extraWorkFiles.removeAt(index);
                        }),
                        onEditExtraWork: _editExtraWork,
                        onDeleteExtraWork: _deleteExtraWork,
                        onPickExtraPhotos: _pickExtraWorkPhotos,
                        onAddExtraWork: _addExtraWork,
                        showExtraWorkSection:
                            _extraWorks.isNotEmpty || canEditSite,
                      ),
                      if (_isBackorder ||
                          ProjectStore.backorderItems[widget.customerName]
                                  ?.isNotEmpty ==
                              true ||
                          canEditCompletion) ...[
                        const SizedBox(height: 16),
                        _InputCard(
                          title: 'Afronding',
                          children: [
                            if (canEditCompletion) ...[
                              _ChoiceToggle(
                                label: 'Status',
                                options: const ['Nabestelling', 'Klaar'],
                                selectedIndex: _isBackorder ? 0 : 1,
                                onSelect: (index) => setState(() {
                                  _isBackorder = index == 0;
                                }),
                              ),
                              if (_isBackorder) ...[
                                const SizedBox(height: 12),
                                TextField(
                                  controller: _backorderNoteController,
                                  maxLines: 3,
                                  decoration: InputDecoration(
                                    hintText: 'Beschrijving nabestelling',
                                    filled: true,
                                    fillColor: const Color(0xFFF4F1EA),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFFE1DAD0),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(14),
                                      borderSide: const BorderSide(
                                        color: Color(0xFF0B2E2B),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                _AddItemRow(
                                  controller: _backorderController,
                                  onAdd: _addBackorderItem,
                                ),
                                const SizedBox(height: 10),
                                if (_backorderItems.isEmpty)
                                  Text(
                                    'Nog geen materialen',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: const Color(0xFF6A7C78),
                                        ),
                                  )
                                else
                                  ..._backorderItems.asMap().entries.map(
                                    (entry) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _EditableBackorderItemRow(
                                        label: entry.value,
                                        onEdit: () =>
                                            _editBackorderItem(entry.key),
                                        onDelete: () =>
                                            _deleteBackorderItem(entry.key),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 8),
                                _PrimaryButton(
                                  label: 'Verzenden',
                                  onTap: () {
                                    if (_backorderItems.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Voeg eerst materialen toe.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    if (!_hasBeforeAfterPhotos()) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Voeg foto’s voor en na de werf toe.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    ProjectStore.setBackorder(
                                      widget.customerName,
                                      backorder: true,
                                      items: _backorderItems,
                                    );
                                    final note =
                                        _backorderNoteController.text.trim();
                                    final previousNote =
                                        ProjectStore.backorderNotes[widget.customerName] ??
                                            '';
                                    if (note.isNotEmpty) {
                                      ProjectStore.backorderNotes[
                                          widget.customerName] = note;
                                    } else {
                                      ProjectStore.backorderNotes
                                          .remove(widget.customerName);
                                    }
                                    if (note.trim() != previousNote.trim()) {
                                      final summary = _truncateText(note, 80);
                                      if (summary.isNotEmpty) {
                                        ProjectLogStore.add(
                                          widget.customerName,
                                          'Beschrijving nabestelling aangepast: $summary',
                                        );
                                      }
                                    }
                                    final team = _completionTeamForProject();
                                    if (team.isNotEmpty) {
                                      ProjectStore.completionTeams[
                                          widget.customerName] = team;
                                    }
                                    ProjectStore.moveToGroupStatus(
                                      name: widget.customerName,
                                      group: 'Nabestellingen',
                                      status: 'In opmaak',
                                    );
                                    ProjectLogStore.add(
                                      widget.customerName,
                                      'Nabestelling verzonden',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Nabestelling verzonden'),
                                      ),
                                    );
                                    Navigator.of(context).pop(true);
                                  },
                                ),
                              ] else ...[
                                const SizedBox(height: 12),
                                _PrimaryButton(
                                  label: 'Verzenden',
                                  onTap: () {
                                    if (!_hasBeforeAfterPhotos()) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Voeg foto’s voor en na de werf toe.',
                                          ),
                                        ),
                                      );
                                      return;
                                    }
                                    ProjectStore.setBackorder(
                                      widget.customerName,
                                      backorder: false,
                                      items: const [],
                                    );
                                    ProjectStore.backorderNotes
                                        .remove(widget.customerName);
                                    final team = _completionTeamForProject();
                                    if (team.isNotEmpty) {
                                      ProjectStore.completionTeams[
                                          widget.customerName] = team;
                                    }
                                    ScheduleStore.scheduled.removeWhere(
                                      (assignment) =>
                                          assignment.project ==
                                          widget.customerName,
                                    );
                                    final targetGroup =
                                        ProjectStore.findGroupForProject(
                                              widget.customerName,
                                            ) ??
                                            widget.group;
                                    ProjectStore.moveToGroupStatus(
                                      name: widget.customerName,
                                      group: targetGroup,
                                      status: 'Afgewerkt',
                                    );
                                    ProjectLogStore.add(
                                      widget.customerName,
                                      'Project afgerond',
                                    );
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('Project afgerond'),
                                      ),
                                    );
                                    Navigator.of(context).pop(true);
                                  },
                                ),
                              ],
                            ] else ...[
                              if (_isBackorder) ...[
                                const SizedBox(height: 12),
                                if ((_backorderNoteController.text.trim())
                                    .isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(
                                      _backorderNoteController.text.trim(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: const Color(0xFF6A7C78),
                                          ),
                                    ),
                                  ),
                                if (_backorderItems.isEmpty)
                                  Text(
                                    'Nog geen materialen',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: const Color(0xFF6A7C78),
                                        ),
                                  )
                                else
                                  ..._backorderItems.map(
                                    (item) => Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _BackorderItemRow(label: item),
                                    ),
                                  ),
                              ],
                            ],
                          ],
                        ),
                      ],
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.status,
    required this.count,
    required this.onTap,
  });

  final String status;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFCE6CC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.folder_open,
                      color: Color(0xFF6A4A2D)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    status,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF243B3A),
                        ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B2E2B),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$count',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFFFE9CC),
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Color(0xFF6A7C78)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HolidayCalendarScreen extends StatefulWidget {
  const HolidayCalendarScreen({
    super.key,
    this.assignments = const [],
    this.onSaved,
    this.readOnly = false,
  });

  final List<TeamAssignment> assignments;
  final VoidCallback? onSaved;
  final bool readOnly;

  @override
  State<HolidayCalendarScreen> createState() => _HolidayCalendarScreenState();
}

class _HolidayCalendarScreenState extends State<HolidayCalendarScreen> {
  final ValueNotifier<DateTime> _focusedDay =
      ValueNotifier<DateTime>(DateTime.now());
  DateTime? _selectedDay;

  int _modeIndex = 0; // 0 = feestdag, 1 = verlof
  bool _isEditing = false;

  @override
  void dispose() {
    _focusedDay.dispose();
    super.dispose();
  }

  void _toggleDay(DateTime day) {
    setState(() {
      final target = _modeIndex == 0
          ? PlanningCalendarStore.holidays
          : PlanningCalendarStore.vacations;
      if (target.contains(day)) {
        target.remove(day);
      } else {
        target.add(day);
      }
    });
    AppDataStore.scheduleSave();
  }

  DateTime _normalizeDate(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  bool _canSeeLeave(LeaveRequest request) {
    if (!widget.readOnly) return true;
    return request.requester == CurrentUserStore.name;
  }

  List<LeaveRequest> _visibleLeaveRequestsForDay(DateTime day) {
    final normalized = _normalizeDate(day);
    return LeaveRequestStore.requests.where((request) {
      if (request.status != 'Goedgekeurd') return false;
      if (!_canSeeLeave(request)) return false;
      final from = _normalizeDate(request.from);
      final to = _normalizeDate(request.to);
      return !normalized.isBefore(from) && !normalized.isAfter(to);
    }).toList();
  }

  void _applyVacationRange(DateTime from, DateTime to) {
    var day = _normalizeDate(from);
    final end = _normalizeDate(to);
    while (!day.isAfter(end)) {
      PlanningCalendarStore.vacations.add(day);
      day = day.add(const Duration(days: 1));
    }
  }

  void _approveRequest(LeaveRequest request) {
    setState(() {
      request.status = 'Goedgekeurd';
      _applyVacationRange(request.from, request.to);
    });
    AppDataStore.scheduleSave();
  }

  void _denyRequest(LeaveRequest request) {
    setState(() {
      request.status = 'Geweigerd';
    });
    AppDataStore.scheduleSave();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.readOnly && _isEditing) {
      _isEditing = false;
    }
    final dayForDetails = _selectedDay ?? _focusedDay.value;
    final visibleLeaveForDay = _visibleLeaveRequestsForDay(dayForDetails);
    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              children: [
                      Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                                        const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Verlof',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    if (!widget.readOnly) ...[
                      _InlineButton(
                        label: _isEditing ? 'Klaar' : 'Bewerken',
                        onTap: () => setState(() => _isEditing = !_isEditing),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                if (_isEditing && !widget.readOnly)
                  _ChoiceToggle(
                    label: 'Type dag',
                    options: const ['Feestdag', 'Verlof'],
                    selectedIndex: _modeIndex,
                    onSelect: (index) => setState(() => _modeIndex = index),
                  ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE1DAD0)),
                  ),
                  child: ValueListenableBuilder<DateTime>(
                    valueListenable: _focusedDay,
                    builder: (context, focusedDay, _) {
                      return TableCalendar(
                        firstDay: DateTime.utc(2024, 1, 1),
                        lastDay: DateTime.utc(2030, 12, 31),
                        focusedDay: focusedDay,
                        calendarFormat: CalendarFormat.month,
                        startingDayOfWeek: StartingDayOfWeek.monday,
                        selectedDayPredicate: (day) =>
                            isSameDay(_selectedDay, day),
                        onDaySelected: (selectedDay, focusedDay) {
                          _focusedDay.value = focusedDay;
                          setState(() => _selectedDay = selectedDay);
                          if (_isEditing && !widget.readOnly) {
                            _toggleDay(selectedDay);
                          }
                        },
                        onPageChanged: (day) => _focusedDay.value = day,
                        calendarBuilders: CalendarBuilders(
                          markerBuilder: (context, day, events) {
                            final normalized = _normalizeDate(day);
                            final isHoliday =
                                PlanningCalendarStore.holidays.contains(
                              normalized,
                            );
                            final isVacation = widget.readOnly
                                ? _visibleLeaveRequestsForDay(day).isNotEmpty
                                : PlanningCalendarStore.vacations
                                    .contains(normalized);
                            if (!isHoliday && !isVacation) {
                              return null;
                            }
                            return Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (isHoliday)
                                  _LegendDot(color: const Color(0xFF0B2E2B)),
                                if (isHoliday && isVacation)
                                  const SizedBox(width: 4),
                                if (isVacation)
                                  _LegendDot(color: const Color(0xFFFFA64D)),
                              ],
                            );
                          },
                        ),
                        calendarStyle: CalendarStyle(
                          todayDecoration: BoxDecoration(
                            color:
                                const Color(0xFFFFA64D).withValues(alpha: 0.3),
                            shape: BoxShape.circle,
                          ),
                          selectedDecoration: const BoxDecoration(
                            color: Color(0xFF0B2E2B),
                            shape: BoxShape.circle,
                          ),
                          weekendTextStyle: (Theme.of(context)
                                  .textTheme
                                  .bodyMedium ??
                              const TextStyle(
                                color: Color(0xFF6A7C78),
                              )).copyWith(
                            color: const Color(0xFF6A7C78),
                          ),
                        ),
                        headerStyle: const HeaderStyle(
                          formatButtonVisible: false,
                          titleCentered: true,
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const _LegendDot(color: Color(0xFF0B2E2B)),
                                        const SizedBox(width: 6),
                    Text(
                      'Feestdag',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF5A6F6C)),
                    ),
                    const SizedBox(width: 16),
                    const _LegendDot(color: Color(0xFFFFA64D)),
                                        const SizedBox(width: 6),
                    Text(
                      'Verlof',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF5A6F6C)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_isEditing && !widget.readOnly) ...[
                  _InputCard(
                    title: 'Verlofaanvragen',
                    children: [
                      if (LeaveRequestStore.requests
                          .where((r) => r.status == 'In afwachting')
                          .isEmpty)
                        Text(
                          'Geen openstaande aanvragen.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: const Color(0xFF6A7C78)),
                        )
                      else
                        ...LeaveRequestStore.requests
                            .where((r) => r.status == 'In afwachting')
                            .map(
                              (request) => Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF4F1EA),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: const Color(0xFFE1DAD0),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        request.requester,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${_formatDate(request.from)} - ${_formatDate(request.to)}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: const Color(0xFF6A7C78),
                                            ),
                                      ),
                                      if (request.reason.trim().isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          request.reason,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color:
                                                    const Color(0xFF6A7C78),
                                              ),
                                        ),
                                      ],
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: _SecondaryButton(
                                              label: 'Weigeren',
                                              onTap: () =>
                                                  _denyRequest(request),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _PrimaryButton(
                                              label: 'Goedkeuren',
                                              onTap: () =>
                                                  _approveRequest(request),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                    ],
                  ),
                ],
                if (!_isEditing)
                  _DayScheduleCard(
                    day: dayForDetails,
                    isHoliday: PlanningCalendarStore.holidays
                        .contains(_normalizeDate(dayForDetails)),
                    isVacation: widget.readOnly
                        ? visibleLeaveForDay.isNotEmpty
                        : PlanningCalendarStore.vacations
                            .contains(_normalizeDate(dayForDetails)),
                    leaveRequests: visibleLeaveForDay,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

int _dayHashCode(DateTime day) => day.year * 10000 + day.month * 100 + day.day;

final Map<int, String> _dateCache = {};

int _dateKey(DateTime date) => date.year * 10000 + date.month * 100 + date.day;

String _formatDate(DateTime date) {
  final key = _dateKey(date);
  final cached = _dateCache[key];
  if (cached != null) return cached;
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  final y = date.year.toString();
  final formatted = '$d/$m/$y';
  _dateCache[key] = formatted;
  return formatted;
}

String _formatDateTime(DateTime date) {
  final dateLabel = _formatDate(date);
  final h = date.hour.toString().padLeft(2, '0');
  final m = date.minute.toString().padLeft(2, '0');
  return '$dateLabel $h:$m';
}

String _truncateText(String value, int maxLength) {
  if (maxLength <= 0) return '';
  final trimmed = value.trim();
  if (trimmed.length <= maxLength) return trimmed;
  return '${trimmed.substring(0, maxLength)}...';
}

Future<void> _launchPhone(BuildContext context, String phone) async {
  final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
  if (cleaned.isEmpty) return;
  final uri = Uri(scheme: 'tel', path: cleaned);
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kan telefoonnummer niet openen.')),
    );
  }
}

Future<void> _launchMaps(BuildContext context, String address) async {
  final trimmed = address.trim();
  if (trimmed.isEmpty) return;
  final uri = Uri.parse(
    'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(trimmed)}',
  );
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kan adres niet openen in maps.')),
    );
  }
}

String _formatPrice(double value) {
  if (value % 1 == 0) {
    return value.toStringAsFixed(0);
  }
  return value.toStringAsFixed(2);
}

String _formatDays(int days) {
  if (days == 1) {
    return '1 dag';
  }
  return '$days dagen';
}

int _clampScheduledDays(int days) {
  if (days < 3) return 3;
  if (days > 7) return 7;
  return days;
}

String _formatHours(double hours) {
  if (hours == 1) {
    return '1 uur';
  }
  return '${_formatPrice(hours)} uur';
}

bool _canApproveEstimatedDaysChanges(String role) {
  return role == 'Planner' ||
      role == 'Administratie' ||
      role == 'Boekhouding' ||
      role == 'Projectleider' ||
      role == 'Beheerder';
}

DateTime _normalizeDateOnly(DateTime date) =>
    DateTime(date.year, date.month, date.day);

bool _isWorkingDayForTeam(DateTime date, String team) {
  final weekday = date.weekday;
  final workingDays = _RoleManagementStore.workingDaysForTeam(team);
  if (!workingDays.contains(weekday)) {
    return false;
  }
  return !PlanningCalendarStore.isNonWorkingDay(date);
}

DateTime _nextWorkingDayForTeam(DateTime date, String team) {
  var day = _normalizeDateOnly(date);
  while (!_isWorkingDayForTeam(day, team)) {
    day = day.add(const Duration(days: 1));
  }
  return day;
}

DateTime _endDateFromWorkingDays(DateTime start, int days, String team) {
  var current = _normalizeDateOnly(start);
  int counted = 0;
  while (true) {
    if (_isWorkingDayForTeam(current, team)) {
      counted += 1;
      if (counted == days) {
        return current;
      }
    }
    current = current.add(const Duration(days: 1));
  }
}

TeamAssignment _copyAssignment(
  TeamAssignment base, {
  required DateTime start,
  required DateTime end,
  required int estimatedDays,
}) {
  return TeamAssignment(
    project: base.project,
    team: base.team,
    startDate: start,
    endDate: end,
    estimatedDays: estimatedDays,
    isBackorder: base.isBackorder,
    group: base.group,
  );
}

void _applyEstimatedDaysNoShift(
  List<TeamAssignment> scheduled,
  TeamAssignment target,
  int newDays,
) {
  final start = _normalizeDateOnly(target.startDate);
  final end = _endDateFromWorkingDays(start, newDays, target.team);
  final updated = _copyAssignment(
    target,
    start: start,
    end: end,
    estimatedDays: newDays,
  );
  final index = scheduled.indexOf(target);
  if (index == -1) return;
  scheduled[index] = updated;
}

void _applyEstimatedDaysShift(
  List<TeamAssignment> scheduled,
  String team,
  String project,
  int newDays,
) {
  final teamAssignments =
      scheduled.where((assignment) => assignment.team == team).toList();
  final regularItems =
      teamAssignments.where((item) => !item.isBackorder).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));
  final backorderItems =
      teamAssignments.where((item) => item.isBackorder).toList();
  final targetIndex =
      regularItems.indexWhere((item) => item.project == project);
  if (targetIndex == -1) return;

  final updatedRegular = <TeamAssignment>[];
  for (int i = 0; i < regularItems.length; i++) {
    final item = regularItems[i];
    DateTime baseStart = item.startDate;
    if (i > 0) {
      final prevEnd = updatedRegular.last.endDate;
      if (!_normalizeDateOnly(baseStart).isAfter(prevEnd)) {
        baseStart = prevEnd.add(const Duration(days: 1));
      }
    }
    if (i > targetIndex) {
      baseStart = updatedRegular.last.endDate.add(const Duration(days: 1));
    }
    final start = _nextWorkingDayForTeam(baseStart, team);
    final days = i == targetIndex ? newDays : item.estimatedDays;
    final end = _endDateFromWorkingDays(start, days, team);
    updatedRegular.add(
      _copyAssignment(
        item,
        start: start,
        end: end,
        estimatedDays: days,
      ),
    );
  }

  final updated = <TeamAssignment>[
    ...scheduled.where((assignment) => assignment.team != team),
    ...updatedRegular,
    ...backorderItems,
  ];
  scheduled
    ..clear()
    ..addAll(updated);
}

class _DayScheduleCard extends StatelessWidget {
  const _DayScheduleCard({
    required this.day,
    required this.isHoliday,
    required this.isVacation,
    required this.leaveRequests,
  });

  final DateTime day;
  final bool isHoliday;
  final bool isVacation;
  final List<LeaveRequest> leaveRequests;

  @override
  Widget build(BuildContext context) {
    final title = _formatDate(day);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verlof op $title',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (!isHoliday && !isVacation && leaveRequests.isEmpty)
            Text(
              'Geen feestdag of verlof.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF6A7C78)),
            ),
          if (isHoliday) ...[
            Text(
              'Feestdag',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
          ],
          if (isVacation && leaveRequests.isEmpty) ...[
            Text(
              'Verlof',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 4),
          ],
          if (leaveRequests.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Verlof',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            ...leaveRequests.map(
              (request) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  request.requester,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF5A6F6C)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class PlanningCalendarStore {
  static final LinkedHashSet<DateTime> holidays = LinkedHashSet<DateTime>(
    equals: isSameDay,
    hashCode: _dayHashCode,
  );
  static final LinkedHashSet<DateTime> vacations = LinkedHashSet<DateTime>(
    equals: isSameDay,
    hashCode: _dayHashCode,
  );

  static bool isNonWorkingDay(DateTime day) =>
      holidays.contains(day) || vacations.contains(day);
}

class LeaveRequest {
  LeaveRequest({
    required this.requester,
    required this.role,
    required this.from,
    required this.to,
    required this.reason,
    this.status = 'In afwachting',
  });

  final String requester;
  final String role;
  final DateTime from;
  final DateTime to;
  final String reason;
  String status;
}

class LeaveRequestStore {
  static final List<LeaveRequest> requests = [];
}

class InvoiceRecord {
  InvoiceRecord({
    this.offerBilled = false,
    this.extraHoursBilled = 0,
  });

  bool offerBilled;
  double extraHoursBilled;
}

class InvoiceStore {
  static final Map<String, InvoiceRecord> records = {};

  static InvoiceRecord recordFor(String project) {
    return records.putIfAbsent(project, () => InvoiceRecord());
  }
}

class _PlanningAssignCard extends StatefulWidget {
  const _PlanningAssignCard({
    super.key,
    required this.item,
    required this.teams,
    required this.onAssign,
    required this.availableStarts,
    required this.calculateEndDate,
    required this.scheduled,
  });

  final _PlanningItem item;
  final List<String> teams;
  final void Function(
    _PlanningItem item,
    String team,
    DateTime startDate, {
    double? backorderHours,
  }) onAssign;
  final List<DateTime> Function(String team, int days, bool isBackorder)
      availableStarts;
  final DateTime? Function(
    String team,
    DateTime start,
    int days,
    bool isBackorder,
  ) calculateEndDate;
  final List<TeamAssignment> scheduled;

  @override
  State<_PlanningAssignCard> createState() => _PlanningAssignCardState();
}

class _PlanningAssignCardState extends State<_PlanningAssignCard> {
  late String _team;
  late DateTime? _startDate;
  late DateTime _focusedDay;
  bool _autoSuggested = true;
  final TextEditingController _hoursController = TextEditingController();

  bool _isSameDay(DateTime? a, DateTime? b) => isSameDay(a, b);

  int get _effectiveDays =>
      widget.item.group == 'Nabestellingen' ? 1 : widget.item.estimatedDays;
  bool get _isBackorder => widget.item.group == 'Nabestellingen';

  @override
  void initState() {
    super.initState();
    _team = widget.teams.first;
    _startDate = _suggestedStartForTeam(_team);
    _focusedDay = _startDate ?? DateTime.now();
    _autoSuggested = true;
    if (_isBackorder) {
      final hours = ProjectStore.backorderHours[widget.item.name] ?? 0;
      _hoursController.text = hours > 0 ? _formatPrice(hours) : '';
    }
  }

  @override
  void didUpdateWidget(covariant _PlanningAssignCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scheduled.length != widget.scheduled.length) {
      setState(() {});
    }
    final suggested = _suggestedStartForTeam(_team);
    if (_autoSuggested &&
        (_startDate == null || !_isSameDay(_startDate, suggested))) {
      setState(() {
        _startDate = suggested;
        _focusedDay = suggested;
      });
    }
  }

  @override
  void dispose() {
    _hoursController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _startDate ??= _suggestedStartForTeam(_team);
    final endDate = _startDate == null
        ? null
        : widget.calculateEndDate(
            _team,
            _startDate!,
            _effectiveDays,
            _isBackorder,
          );
    final hasRange = endDate != null;
    final enabledDays = widget
        .availableStarts(_team, _effectiveDays, _isBackorder)
        .toSet();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item.name,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF243B3A),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Geschat: ${_formatDays(_effectiveDays)}'
                '${_isBackorder ? ' · Nabestelling' : ''}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: const Color(0xFF6A7C78)),
              ),
              const SizedBox(height: 4),
              Text(
                'Tel: ${widget.item.phone}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF6A7C78)),
              ),
              const SizedBox(height: 4),
              Text(
                'Adres: ${widget.item.address}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF6A7C78)),
              ),
            ],
          ),
          children: [
            _DropdownField(
              label: 'Team',
              value: _team,
              items: widget.teams,
              onChanged: (value) => setState(() {
                _team = value ?? widget.teams.first;
                _startDate = _suggestedStartForTeam(_team);
                _focusedDay = _startDate ?? DateTime.now();
                _autoSuggested = true;
              }),
            ),
            if (_isBackorder) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _hoursController,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'Duur (uren)',
                  filled: true,
                  fillColor: const Color(0xFFF4F1EA),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            _MiniCalendarPicker(
              team: _team,
              focusedDay: _focusedDay,
              selectedStart: _startDate,
              selectedEnd: endDate,
              enabledDays: enabledDays,
              assignments: widget.scheduled
                  .where((assignment) => assignment.team == _team)
                  .toList(),
              onFocused: (day) => setState(() => _focusedDay = day),
              onSelect: (day) => setState(() {
                _startDate = day;
                _autoSuggested = false;
              }),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: _PrimaryButton(
                label: 'Inplannen',
                onTap: hasRange && _startDate != null
                    ? () {
                        final hours =
                            double.tryParse(_hoursController.text.trim()) ?? 0;
                        widget.onAssign(
                          widget.item,
                          _team,
                          _startDate!,
                          backorderHours: _isBackorder ? hours : null,
                        );
                      }
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _isWorkingDayForTeam(String team, DateTime date) {
    final workingDays = _RoleManagementStore.workingDaysForTeam(team);
    if (!workingDays.contains(date.weekday)) return false;
    return !PlanningCalendarStore.isNonWorkingDay(date);
  }

  DateTime _nextWorkingDayForTeam(String team, DateTime date) {
    var day = _normalizeDate(date);
    for (int i = 0; i < 366; i++) {
      if (_isWorkingDayForTeam(team, day)) return day;
      day = day.add(const Duration(days: 1));
    }
    return _normalizeDate(date);
  }

  DateTime _suggestedStartForTeam(String team) {
    final today = _normalizeDate(DateTime.now());
    final teamAssignments =
        widget.scheduled.where((assignment) => assignment.team == team).toList();
    if (teamAssignments.isEmpty) {
      return _nextWorkingDayForTeam(team, today);
    }
    teamAssignments.sort((a, b) => a.endDate.compareTo(b.endDate));
    final lastEnd = teamAssignments.last.endDate;
    var candidate = lastEnd.add(const Duration(days: 1));
    if (candidate.isBefore(today)) {
      candidate = today;
    }
    return _nextWorkingDayForTeam(team, candidate);
  }

}

class _ExternalPlanningProjectCard extends StatelessWidget {
  const _ExternalPlanningProjectCard({
    required this.assignment,
    required this.details,
    required this.onOpen,
  });

  final TeamAssignment assignment;
  final ProjectDetails? details;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final canSeeHours = _canSeeOfferHours(CurrentUserStore.role);
    final isBackorder =
        assignment.isBackorder || assignment.group == 'Nabestellingen';
    final backorderHours = isBackorder
        ? (ProjectStore.backorderHours[assignment.project] ?? 0).toDouble()
        : 0.0;
    double totalHours = 0;
    if (canSeeHours) {
      final lines =
          ProjectStore.offers[assignment.project] ?? const <OfferLine>[];
      for (final line in lines) {
        final item = OfferCatalogStore.findItem(line.category, line.item);
        final hours = item?.hours;
        if (hours != null) {
          totalHours += hours * line.quantity;
        }
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assignment.project,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF243B3A),
                    ),
              ),
              if (isBackorder) ...[
                const SizedBox(height: 4),
                Text(
                  backorderHours > 0
                      ? 'Nabestelling · ${_formatHours(backorderHours)}'
                      : 'Nabestelling',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF6A7C78)),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                '${assignment.team} · ${_formatDate(assignment.startDate)} - '
                '${_formatDate(assignment.endDate)}',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: const Color(0xFF6A7C78)),
              ),
              if (canSeeHours && totalHours > 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Totaal uren: ${_formatPrice(totalHours)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF6A7C78)),
                ),
              ],
            ],
          ),
          children: [
            if (details != null) ...[
              _InfoLine(
                label: 'Adres',
                value: details!.address,
                icon: Icons.location_on_outlined,
              ),
              const SizedBox(height: 6),
              _InfoLine(
                label: 'Levering',
                value: details!.delivery,
                icon: Icons.local_shipping_outlined,
              ),
              const SizedBox(height: 6),
              _InfoLine(
                label: 'Afwerking',
                value: details!.finish,
                icon: Icons.layers_outlined,
              ),
              const SizedBox(height: 6),
              _InfoLine(
                label: 'Geschatte dagen',
                value: _formatDays(isBackorder ? 1 : details!.estimatedDays),
                icon: Icons.schedule_outlined,
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: _InlineButton(
                label: 'Openen',
                onTap: onOpen,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF6A7C78)),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: const Color(0xFF6A7C78)),
        ),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _InfoTextBlock extends StatelessWidget {
  const _InfoTextBlock({
    required this.title,
    required this.lines,
  });

  final String title;
  final List<Widget> lines;

  @override
  Widget build(BuildContext context) {
    if (lines.isEmpty) {
      return const SizedBox.shrink();
    }
    return _InputCard(
      title: title,
      children: [
        ...lines.map(
          (line) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: line,
          ),
        ),
      ],
    );
  }
}

class _PlainInfoLine extends StatelessWidget {
  const _PlainInfoLine({
    required this.label,
    required this.value,
    this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: const Color(0xFF6A7C78)),
        ),
        Expanded(
          child: onTap == null
              ? Text(
                  value,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : InkWell(
                  onTap: onTap,
                  child: Text(
                    value,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF0B2E2B),
                          decoration: TextDecoration.underline,
                        ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _PlanningOverviewScreen extends StatefulWidget {
  const _PlanningOverviewScreen({
    required this.assignments,
    required this.onCancel,
    required this.canEditPlanning,
    required this.onReschedule,
    required this.availableStarts,
    required this.calculateEndDate,
  });

  final List<TeamAssignment> assignments;
  final void Function(TeamAssignment assignment) onCancel;
  final bool canEditPlanning;
  final void Function(TeamAssignment assignment, DateTime newStart) onReschedule;
  final List<DateTime> Function(
    String team,
    int days,
    bool isBackorder,
  ) availableStarts;
  final DateTime? Function(
    String team,
    DateTime start,
    int days,
    bool isBackorder,
  ) calculateEndDate;

  @override
  State<_PlanningOverviewScreen> createState() =>
      _PlanningOverviewScreenState();
}

class _PlanningOverviewScreenState extends State<_PlanningOverviewScreen> {
  Future<void> _confirmCancel(TeamAssignment assignment) async {
    if (!widget.canEditPlanning) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Planning verwijderen'),
        content: Text(
          'Ben je zeker dat je ${assignment.project} uit de planning wil halen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annuleren'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onCancel(assignment);
      setState(() {});
    }
  }

  void _openProject(TeamAssignment assignment) {
    Navigator.of(context).push(
      _appPageRoute(
        builder: (_) => ProjectDetailScreen(
          customerName: assignment.project,
          group: assignment.group,
          status:
              ProjectStore.findStatusForProject(assignment.project) ??
                  'Ingepland',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final grouped = <String, List<TeamAssignment>>{};
    for (final item in widget.assignments) {
      grouped.putIfAbsent(item.team, () => []).add(item);
    }
    final teams = grouped.keys.toList()..sort();

    return Scaffold(
      body: Stack(
        children: [
          const _SoftGradientBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Overzicht planning',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                    children: [
                      if (widget.assignments.isEmpty)
                        const _EmptyStateCard(
                          title: 'Geen planning',
                          subtitle: 'Er zijn nog geen teams ingepland.',
                        )
                      else
                        ...teams.map(
                          (team) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                      child: _TeamMonthlyScheduleCard(
                        team: team,
                        assignments: grouped[team] ?? const [],
                        onOpen: _openProject,
                        onCancel: _confirmCancel,
                        canEditPlanning: widget.canEditPlanning,
                        showHeader: true,
                        initiallyExpanded: false,
                        onReschedule: (assignment, newStart) {
                          widget.onReschedule(assignment, newStart);
                          if (mounted) {
                            setState(() {});
                          }
                        },
                        availableStarts: widget.availableStarts,
                        calculateEndDate: widget.calculateEndDate,
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
    );
  }
}

class _TeamMonthlyScheduleCard extends StatefulWidget {
  const _TeamMonthlyScheduleCard({
    required this.team,
    required this.assignments,
    required this.onOpen,
    required this.onCancel,
    required this.canEditPlanning,
    required this.onReschedule,
    required this.availableStarts,
    required this.calculateEndDate,
    this.showHeader = true,
    this.initiallyExpanded = false,
    this.previewProject,
    this.previewStart,
    this.previewEnd,
    this.previewOldStart,
    this.previewOldEnd,
  });

  final String team;
  final List<TeamAssignment> assignments;
  final void Function(TeamAssignment assignment) onOpen;
  final Future<void> Function(TeamAssignment assignment) onCancel;
  final bool canEditPlanning;
  final void Function(TeamAssignment assignment, DateTime newStart) onReschedule;
  final List<DateTime> Function(
    String team,
    int days,
    bool isBackorder,
  ) availableStarts;
  final DateTime? Function(
    String team,
    DateTime start,
    int days,
    bool isBackorder,
  ) calculateEndDate;
  final bool showHeader;
  final bool initiallyExpanded;
  final String? previewProject;
  final DateTime? previewStart;
  final DateTime? previewEnd;
  final DateTime? previewOldStart;
  final DateTime? previewOldEnd;

  @override
  State<_TeamMonthlyScheduleCard> createState() =>
      _TeamMonthlyScheduleCardState();
}

class _TeamMonthlyScheduleCardState extends State<_TeamMonthlyScheduleCard> {
  late DateTime _focusedDay;
  DateTime? _selectedDay;
  static const int _maxLaneShown = 3;
  static const Color _backorderDotColor = Color(0xFFD04A4A);

  @override
  void initState() {
    super.initState();
    _focusedDay = DateTime.now();
    _selectedDay = _focusedDay;
  }

  DateTime _normalizeDate(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  DateTime _monthStart(DateTime date) => DateTime(date.year, date.month, 1);

  DateTime _monthEnd(DateTime date) => DateTime(date.year, date.month + 1, 0);

  Future<void> _showRescheduleDialog(
    BuildContext context,
    TeamAssignment assignment,
  ) async {
    final isBackorder = _isBackorderAssignment(assignment);
    final days = isBackorder ? 1 : assignment.estimatedDays;
    DateTime startDate = assignment.startDate;
    DateTime focused = startDate;
    final enabledDays =
        widget.availableStarts(assignment.team, days, isBackorder).toSet();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final endDate = widget.calculateEndDate(
              assignment.team,
              startDate,
              days,
              isBackorder,
            );
            return AlertDialog(
              title: const Text('Startdatum aanpassen'),
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 300,
                  child: _MiniCalendarPicker(
                    team: assignment.team,
                    focusedDay: focused,
                    selectedStart: startDate,
                    selectedEnd: endDate,
                    enabledDays: enabledDays,
                    assignments: widget.assignments
                        .where((a) => a.team == assignment.team)
                        .toList(),
                    onFocused: (day) => setState(() => focused = day),
                    onSelect: (day) => setState(() => startDate = day),
                  ),
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annuleren'),
                ),
                TextButton(
                  onPressed: () {
                    widget.onReschedule(assignment, startDate);
                    if (mounted) {
                      setState(() {});
                    }
                    Navigator.of(context).pop();
                  },
                  child: const Text('Opslaan'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<TeamAssignment> _monthAssignments() {
    final start = _monthStart(_focusedDay);
    final end = _monthEnd(_focusedDay);
    final list = widget.assignments
        .where(
          (assignment) =>
              !assignment.endDate.isBefore(start) &&
              !assignment.startDate.isAfter(end),
        )
        .toList();
    list.sort((a, b) => a.startDate.compareTo(b.startDate));
    return list;
  }

  Map<TeamAssignment, int> _computeLanes(List<TeamAssignment> assignments) {
    final laneEnds = <int, DateTime>{};
    final laneMap = <TeamAssignment, int>{};
    for (final assignment in assignments) {
      final group =
          ProjectStore.findGroupForProject(assignment.project) ??
          assignment.group;
      if (group == 'Nabestellingen') {
        continue;
      }
      final start = _normalizeDate(assignment.startDate);
      final end = _normalizeDate(assignment.endDate);
      int laneIndex = 0;
      while (true) {
        final lastEnd = laneEnds[laneIndex];
        if (lastEnd == null || start.isAfter(lastEnd)) {
          laneEnds[laneIndex] = end;
          laneMap[assignment] = laneIndex;
          break;
        }
        laneIndex += 1;
      }
    }
    return laneMap;
  }

  @override
  Widget build(BuildContext context) {
    final selectedDay = _selectedDay ?? _focusedDay;
    final monthAssignments = _monthAssignments();
    final laneMap = _computeLanes(monthAssignments);
    final dayAssignments = _orderedAssignmentsForDay(selectedDay, laneMap);
    final hasSelection = _selectedDay != null;
    int? previewLane;
    if (widget.previewProject != null) {
      final match = monthAssignments.firstWhere(
        (assignment) => assignment.project == widget.previewProject,
        orElse: () => monthAssignments.isEmpty
            ? TeamAssignment(
                project: '',
                team: '',
                startDate: DateTime.now(),
                endDate: DateTime.now(),
                estimatedDays: 1,
                isBackorder: false,
                group: 'Klanten',
              )
            : monthAssignments.first,
      );
      if (match.project == widget.previewProject) {
        previewLane = laneMap[match];
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: widget.showHeader
            ? ExpansionTile(
                initiallyExpanded: widget.initiallyExpanded,
                tilePadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                title: Text(
                  widget.team,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                children: [
                  _buildScheduleBody(
                    context,
                    laneMap,
                    dayAssignments,
                    hasSelection,
                    previewLane,
                  ),
                ],
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: _buildScheduleBody(
                  context,
                  laneMap,
                  dayAssignments,
                  hasSelection,
                  previewLane,
                ),
              ),
      ),
    );
  }

  Widget _buildScheduleBody(
    BuildContext context,
    Map<TeamAssignment, int> laneMap,
    List<TeamAssignment> dayAssignments,
    bool hasSelection,
    int? previewLane,
  ) {
    final selectedDay = _selectedDay ?? _focusedDay;
    final workingDays = _RoleManagementStore.workingDaysForTeam(widget.team);
    final isWeekendOff = !workingDays.contains(selectedDay.weekday);
    final isNonWorkingDay = !_isWorkingDayForTeam(selectedDay, widget.team);
    final isHoliday = _isHoliday(selectedDay);
    final isVacation = _isVacation(selectedDay);
    return Column(
      children: [
        TableCalendar(
              firstDay: DateTime.utc(2024, 1, 1),
              lastDay: DateTime.utc(2030, 12, 31),
              focusedDay: _focusedDay,
              calendarFormat: CalendarFormat.month,
              startingDayOfWeek: StartingDayOfWeek.monday,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
              },
              onPageChanged: (day) => setState(() => _focusedDay = day),
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              calendarStyle: CalendarStyle(
                cellMargin: EdgeInsets.zero,
                todayDecoration: BoxDecoration(
                  color: const Color(0xFFFFA64D).withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: const BoxDecoration(
                  color: Color(0xFF0B2E2B),
                  shape: BoxShape.circle,
                ),
                weekendTextStyle: (Theme.of(context).textTheme.bodyMedium ??
                        const TextStyle(color: Color(0xFF6A7C78)))
                    .copyWith(color: const Color(0xFF6A7C78)),
              ),
              calendarBuilders: CalendarBuilders(
                dowBuilder: (context, day) {
                  const labels = ['Ma', 'Di', 'Wo', 'Do', 'Vr', 'Za', 'Zo'];
                  return Center(
                    child: Text(
                      labels[day.weekday - 1],
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF6A7C78),
                          ),
                    ),
                  );
                },
                defaultBuilder: (context, day, focusedDay) {
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: isSameDay(_selectedDay, day),
                    isToday: isSameDay(DateTime.now(), day),
                    laneMap: laneMap,
                    previewStart: widget.previewStart,
                    previewEnd: widget.previewEnd,
                    previewLane: previewLane,
                    previewOldStart: widget.previewOldStart,
                    previewOldEnd: widget.previewOldEnd,
                  );
                },
                todayBuilder: (context, day, focusedDay) {
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: isSameDay(_selectedDay, day),
                    isToday: true,
                    laneMap: laneMap,
                    previewStart: widget.previewStart,
                    previewEnd: widget.previewEnd,
                    previewLane: previewLane,
                    previewOldStart: widget.previewOldStart,
                    previewOldEnd: widget.previewOldEnd,
                  );
                },
                selectedBuilder: (context, day, focusedDay) {
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: true,
                    isToday: isSameDay(DateTime.now(), day),
                    laneMap: laneMap,
                    previewStart: widget.previewStart,
                    previewEnd: widget.previewEnd,
                    previewLane: previewLane,
                    previewOldStart: widget.previewOldStart,
                    previewOldEnd: widget.previewOldEnd,
                  );
                },
                outsideBuilder: (context, day, focusedDay) {
                  return _buildDayCell(
                    context: context,
                    day: day,
                    isSelected: false,
                    isToday: false,
                    laneMap: laneMap,
                    previewStart: widget.previewStart,
                    previewEnd: widget.previewEnd,
                    previewLane: previewLane,
                    previewOldStart: widget.previewOldStart,
                    previewOldEnd: widget.previewOldEnd,
                  );
                },
              ),
            ),
        const SizedBox(height: 12),
        if (hasSelection)
          _InputCard(
            title: isNonWorkingDay ? 'Niet-werkdag' : 'Klanten',
            children: [
              if (isNonWorkingDay)
                Text(
                  isHoliday
                      ? 'Feestdag'
                      : (isVacation
                          ? 'Verlofdag'
                          : (isWeekendOff ? 'Weekend' : 'Niet-werkdag')),
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF6A7C78)),
                )
              else if (dayAssignments.isEmpty)
                Text(
                  'Geen klanten ingepland.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF6A7C78)),
                )
              else if (widget.canEditPlanning)
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  onReorder: (oldIndex, newIndex) {
                    if (oldIndex < newIndex) {
                      newIndex -= 1;
                    }
                    final updated = List<TeamAssignment>.from(dayAssignments);
                    final item = updated.removeAt(oldIndex);
                    updated.insert(newIndex, item);
                    setState(() {});
                    _saveDayOrder(selectedDay, updated);
                  },
                  children: [
                    for (int index = 0; index < dayAssignments.length; index++)
                      Padding(
                        key: ValueKey('order_${dayAssignments[index].project}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => widget.onOpen(dayAssignments[index]),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 0,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4F1EA),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFE1DAD0)),
                            ),
                            child: Row(
                              children: [
                                _LegendDot(
                                  color: _isBackorderAssignment(
                                          dayAssignments[index])
                                      ? _backorderDotColor
                                      : _dotColorForLane(
                                          laneMap[dayAssignments[index]] ?? 0,
                                        ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        dayAssignments[index].project,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: const Color(0xFF5A6F6C),
                                            ),
                                      ),
                                      if (CurrentUserStore.role ==
                                          'Onderaannemer')
                                        Text(
                                          ProjectStore
                                                  .details[
                                                      dayAssignments[index]
                                                          .project]
                                                  ?.phone ??
                                              '—',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: const Color(0xFF6A7C78),
                                              ),
                                        ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, size: 18),
                                  color: const Color(0xFF6A7C78),
                                  visualDensity: VisualDensity.compact,
                                  constraints:
                                      const BoxConstraints(minWidth: 32),
                                  onPressed: () => _showRescheduleDialog(
                                    context,
                                    dayAssignments[index],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  color: const Color(0xFF6A7C78),
                                  visualDensity: VisualDensity.compact,
                                  constraints:
                                      const BoxConstraints(minWidth: 32),
                                  onPressed: () =>
                                      widget.onCancel(dayAssignments[index]),
                                ),
                                const SizedBox(width: 4),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Icon(
                                    Icons.drag_handle,
                                    size: 18,
                                    color: Color(0xFF6A7C78),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              else
                ...dayAssignments.map(
                  (assignment) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => widget.onOpen(assignment),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F1EA),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE1DAD0)),
                        ),
                        child: Row(
                          children: [
                            _LegendDot(
                              color: _isBackorderAssignment(assignment)
                                  ? _backorderDotColor
                                  : _dotColorForLane(
                                      laneMap[assignment] ?? 0,
                                    ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    assignment.project,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: const Color(0xFF5A6F6C),
                                        ),
                                  ),
                                  if (CurrentUserStore.role ==
                                      'Onderaannemer')
                                    Text(
                                      ProjectStore
                                              .details[assignment.project]
                                              ?.phone ??
                                          '—',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF6A7C78),
                                          ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          )
        else
          Text(
            'Selecteer een dag om klanten te zien.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF6A7C78)),
          ),
      ],
    );
  }

  List<TeamAssignment> _assignmentsForDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    return widget.assignments.where((assignment) {
      final start = DateTime(
        assignment.startDate.year,
        assignment.startDate.month,
        assignment.startDate.day,
      );
      final end = DateTime(
        assignment.endDate.year,
        assignment.endDate.month,
        assignment.endDate.day,
      );
      return !normalized.isBefore(start) && !normalized.isAfter(end);
    }).toList();
  }

  List<TeamAssignment> _orderedAssignmentsForDay(
    DateTime day,
    Map<TeamAssignment, int> laneMap,
  ) {
    final base = _assignmentsForDay(day)
        .where((assignment) => _isWorkingDayForTeam(day, assignment.team))
        .toList()
      ..sort((a, b) {
        final laneA = laneMap[a] ?? 0;
        final laneB = laneMap[b] ?? 0;
        if (laneA != laneB) return laneA.compareTo(laneB);
        return a.startDate.compareTo(b.startDate);
      });
    final order = PlanningOrderStore.orderFor(widget.team, day);
    if (order.isEmpty) return base;
    final remaining = List<TeamAssignment>.from(base);
    final ordered = <TeamAssignment>[];
    for (final name in order) {
      final index =
          remaining.indexWhere((assignment) => assignment.project == name);
      if (index != -1) {
        ordered.add(remaining.removeAt(index));
      }
    }
    ordered.addAll(remaining);
    return ordered;
  }

  void _saveDayOrder(DateTime day, List<TeamAssignment> ordered) {
    PlanningOrderStore.setOrder(
      widget.team,
      day,
      ordered.map((item) => item.project).toList(),
    );
    AppDataStore.scheduleSave();
  }

  bool _isWorkingDayForTeam(DateTime day, String team) {
    final normalized = DateTime(day.year, day.month, day.day);
    final workingDays = _RoleManagementStore.workingDaysForTeam(team);
    if (!workingDays.contains(normalized.weekday)) {
      return false;
    }
    return !PlanningCalendarStore.isNonWorkingDay(normalized);
  }

  bool _isHoliday(DateTime day) =>
      PlanningCalendarStore.holidays.contains(_normalizeDate(day));

  bool _isVacation(DateTime day) =>
      PlanningCalendarStore.vacations.contains(_normalizeDate(day));

  bool _isBackorderAssignment(TeamAssignment assignment) {
    if (assignment.group == 'Nabestellingen') {
      return true;
    }
    final group = ProjectStore.findGroupForProject(assignment.project);
    return group == 'Nabestellingen';
  }

  Color _dotColorForLane(int lane) {
    final palette = [
      const Color(0xFF0B2E2B),
      const Color(0xFFFFA64D),
      const Color(0xFF2F6FED),
    ];
    return palette[lane % palette.length];
  }

  Widget _buildDayCell({
    required BuildContext context,
    required DateTime day,
    required bool isSelected,
    required bool isToday,
    required Map<TeamAssignment, int> laneMap,
    DateTime? previewStart,
    DateTime? previewEnd,
    int? previewLane,
    DateTime? previewOldStart,
    DateTime? previewOldEnd,
  }) {
    final assignments = _assignmentsForDay(day)
      ..sort((a, b) {
        final laneA = laneMap[a] ?? 0;
        final laneB = laneMap[b] ?? 0;
        return laneA.compareTo(laneB);
      });
    final isHoliday = _isHoliday(day);
    final isVacation = _isVacation(day);
    final displayAssignments = assignments
        .where((assignment) => _isWorkingDayForTeam(day, assignment.team))
        .toList();
    final dotAssignments = displayAssignments
        .where((assignment) => _isBackorderAssignment(assignment))
        .toList();
    final lineAssignmentsAll =
        displayAssignments
            .where((assignment) => !dotAssignments.contains(assignment))
            .toList();
    final lineAssignments = lineAssignmentsAll.where((assignment) {
      final lane = laneMap[assignment] ?? 0;
      return lane < _maxLaneShown;
    }).toList();
    final hiddenCount = lineAssignmentsAll.length - lineAssignments.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cellHeight = constraints.maxHeight;
        const barHeight = 5.0;
        const barGap = 2.0;
        const topStart = 2.0;
        const dateHeight = 12.0;
        final dotRowTop = topStart + dateHeight + 2;
        final linesTop = dotRowTop + 7;
        final normalizedDay = _normalizeDate(day);
        final previewSingleDay = previewStart != null &&
            previewEnd != null &&
            isSameDay(previewStart, previewEnd);
        final previewCoversDay = previewStart != null &&
            previewEnd != null &&
            !previewSingleDay &&
            !normalizedDay.isBefore(_normalizeDate(previewStart)) &&
            !normalizedDay.isAfter(_normalizeDate(previewEnd));
        final oldSingleDay = previewOldStart != null &&
            previewOldEnd != null &&
            isSameDay(previewOldStart, previewOldEnd);
        final oldCoversDay = previewOldStart != null &&
            previewOldEnd != null &&
            !oldSingleDay &&
            !normalizedDay.isBefore(_normalizeDate(previewOldStart)) &&
            !normalizedDay.isAfter(_normalizeDate(previewOldEnd));
        return Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: const Color(0xFFE1DAD0),
                    width: 0.5,
                  ),
                ),
              ),
            ),
            if (isHoliday || isVacation)
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CustomPaint(
                    painter: _HatchPainter(
                      color: const Color(0xFFDED7CC).withValues(alpha: 0.6),
                      strokeWidth: 0.8,
                      spacing: 8,
                    ),
                  ),
                ),
              ),
            if (isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B2E2B).withValues(alpha: 0.08),
                  ),
                ),
              )
            else if (isToday)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFA64D).withValues(alpha: 0.16),
                  ),
                ),
              ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${day.day}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF243B3A),
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w500,
                        height: 1.0,
                      ),
                ),
              ),
            ),
            ...lineAssignments.map((assignment) {
              final lane = laneMap[assignment] ?? 0;
              final color = _dotColorForLane(lane);
              final start = _normalizeDate(assignment.startDate);
              final end = _normalizeDate(assignment.endDate);
              final singleDay = start.isAtSameMomentAs(end);
              final isBackorder = _isBackorderAssignment(assignment);
              final showSingleDot = singleDay && isBackorder;
              final top = linesTop + lane * (barHeight + barGap);
              final isStart = start.isAtSameMomentAs(
                DateTime(day.year, day.month, day.day),
              );
              final isEnd = end.isAtSameMomentAs(
                DateTime(day.year, day.month, day.day),
              );
              const boundaryInset = 3.0;
              final leftInset = isStart ? boundaryInset : 0.0;
              final rightInset = isEnd ? boundaryInset : 0.0;
              return Positioned(
                left: 0,
                right: 0,
                top: top,
                child: showSingleDot
                    ? Align(
                        alignment: Alignment.center,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      )
                    : Padding(
                        padding: EdgeInsets.only(
                          left: leftInset,
                          right: rightInset,
                        ),
                        child: Container(
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.horizontal(
                              left: isStart
                                  ? Radius.circular(barHeight / 2)
                                  : Radius.zero,
                              right: isEnd
                                  ? Radius.circular(barHeight / 2)
                                  : Radius.zero,
                            ),
                          ),
                        ),
                      ),
              );
            }),
            if (previewLane != null &&
                previewOldStart != null &&
                previewOldEnd != null &&
                _isWorkingDayForTeam(day, widget.team) &&
                (oldSingleDay || oldCoversDay))
              Positioned(
                left: 0,
                right: 0,
                top: linesTop + previewLane * (barHeight + barGap),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: isSameDay(previewOldStart, day) ? 3 : 0,
                    right: isSameDay(previewOldEnd, day) ? 3 : 0,
                  ),
                  child: Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD04A4A),
                      borderRadius: BorderRadius.horizontal(
                        left: isSameDay(previewOldStart, day)
                            ? Radius.circular(barHeight / 2)
                            : Radius.zero,
                        right: isSameDay(previewOldEnd, day)
                            ? Radius.circular(barHeight / 2)
                            : Radius.zero,
                      ),
                    ),
                  ),
                ),
              ),
            if (previewLane != null &&
                previewStart != null &&
                previewEnd != null &&
                _isWorkingDayForTeam(day, widget.team) &&
                (previewSingleDay || previewCoversDay))
              Positioned(
                left: 0,
                right: 0,
                top: linesTop + previewLane * (barHeight + barGap) + 6,
                child: Padding(
                  padding: EdgeInsets.only(
                    left: isSameDay(previewStart, day) ? 3 : 0,
                    right: isSameDay(previewEnd, day) ? 3 : 0,
                  ),
                  child: Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: const Color(0xFF2F6FED),
                      borderRadius: BorderRadius.horizontal(
                        left: isSameDay(previewStart, day)
                            ? Radius.circular(barHeight / 2)
                            : Radius.zero,
                        right: isSameDay(previewEnd, day)
                            ? Radius.circular(barHeight / 2)
                            : Radius.zero,
                      ),
                    ),
                  ),
                ),
              ),
            if (dotAssignments.isNotEmpty)
              Positioned(
                left: 4,
                right: 4,
                top: dotRowTop,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ...List.generate(
                        dotAssignments.length > 5 ? 5 : dotAssignments.length,
                        (index) {
                          final assignment = dotAssignments[index];
                          final isBackorder = assignment.isBackorder ||
                              assignment.group == 'Nabestellingen';
                          final dotColor = isBackorder
                              ? _backorderDotColor
                              : const Color(0xFF0B2E2B);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1.5),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: dotColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            if (hiddenCount > 0)
              Positioned(
                top: 2,
                right: 2,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B2E2B),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '+$hiddenCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            if (cellHeight < 32) const SizedBox.shrink(),
          ],
        );
      },
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter({
    required this.color,
    this.strokeWidth = 1,
    this.spacing = 6,
  });

  final Color color;
  final double strokeWidth;
  final double spacing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth;
    for (double x = -size.height; x < size.width + size.height; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HatchPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.spacing != spacing;
  }
}

class _TabToggle extends StatelessWidget {
  const _TabToggle({
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE6DFD5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final isSelected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color:
                      isSelected ? const Color(0xFF0B2E2B) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    labels[index],
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? const Color(0xFFFFE9CC)
                              : const Color(0xFF4B6763),
                        ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _ProjectInfoCard extends StatelessWidget {
  const _ProjectInfoCard({
    required this.customerName,
    required this.creator,
    required this.details,
    required this.isEditing,
    required this.canEdit,
    required this.addressController,
    required this.phoneController,
    required this.deliveryController,
    required this.finishController,
    required this.notesController,
    required this.daysController,
    this.completionTeam,
    required this.onSave,
  });

  final String customerName;
  final String creator;
  final ProjectDetails? details;
  final bool isEditing;
  final bool canEdit;
  final TextEditingController addressController;
  final TextEditingController phoneController;
  final TextEditingController deliveryController;
  final TextEditingController finishController;
  final TextEditingController notesController;
  final TextEditingController daysController;
  final String? completionTeam;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final hasCompletionTeam =
        completionTeam != null && completionTeam!.trim().isNotEmpty;
    final hasDetails = details != null &&
        (details!.address.trim().isNotEmpty ||
            details!.phone.trim().isNotEmpty ||
            details!.delivery.trim().isNotEmpty ||
            details!.finish.trim().isNotEmpty ||
            details!.extraNotes.trim().isNotEmpty ||
            details!.estimatedDays > 0);
    if (!canEdit && !isEditing && !hasCompletionTeam && !hasDetails) {
      return const SizedBox.shrink();
    }

    if (!canEdit && !isEditing) {
      final lines = <Widget>[
        _PlainInfoLine(label: 'Aangemaakt door', value: creator),
        _PlainInfoLine(label: 'Klantnaam', value: customerName),
        if (hasCompletionTeam)
          _PlainInfoLine(label: 'Afronding door team', value: completionTeam!),
      ];
      if (details != null) {
        if (details!.phone.trim().isNotEmpty) {
          lines.add(
            _PlainInfoLine(
              label: 'Telefoonnummer',
              value: details!.phone,
              onTap: () => _launchPhone(context, details!.phone),
            ),
          );
        }
        if (details!.address.trim().isNotEmpty) {
          lines.add(
            _PlainInfoLine(
              label: 'Adres',
              value: details!.address,
              onTap: () => _launchMaps(context, details!.address),
            ),
          );
        }
        if (details!.delivery.trim().isNotEmpty) {
          lines.add(
            _PlainInfoLine(label: 'Leveradres ramen', value: details!.delivery),
          );
        }
        if (details!.finish.trim().isNotEmpty) {
          lines.add(
            _PlainInfoLine(label: 'Afwerking', value: details!.finish),
          );
        }
        if (details!.extraNotes.trim().isNotEmpty) {
          lines.add(
            _PlainInfoLine(label: 'Extra notes', value: details!.extraNotes),
          );
        }
        if (details!.estimatedDays > 0) {
          lines.add(
            _PlainInfoLine(
              label: 'Geschatte dagen',
              value: _formatDays(details!.estimatedDays),
            ),
          );
        }
      }
      return _InfoTextBlock(
        title: 'Huidige informatie',
        lines: lines,
      );
    }

    final phoneValue = isEditing && canEdit
        ? phoneController.text.trim()
        : (details?.phone ?? '');
    final canCall = (CurrentUserStore.role == 'Planner' ||
            CurrentUserStore.role == 'Beheerder') &&
        phoneValue.trim().isNotEmpty;
    return _InputCard(
      title: 'Huidige informatie',
      headerTrailing: canCall
          ? IconButton(
              icon: const Icon(Icons.phone_outlined),
              color: const Color(0xFF0B2E2B),
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32),
              onPressed: () => _launchPhone(context, phoneValue),
            )
          : null,
      children: [
        Text(
          'Aangemaakt door: $creator',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: const Color(0xFF6A7C78)),
        ),
        const SizedBox(height: 12),
        _ReadOnlyField(
          label: 'Klantnaam',
          value: customerName,
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 12),
        if (isEditing && canEdit)
          _InputField(
            label: 'Telefoonnummer',
            hint: 'Telefoonnummer',
            icon: Icons.phone_outlined,
            controller: phoneController,
          )
        else
          _ReadOnlyField(
            label: 'Telefoonnummer',
            value: details?.phone ?? '—',
            icon: Icons.phone_outlined,
          ),
        if (completionTeam != null && completionTeam!.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ReadOnlyField(
            label: 'Afronding door team',
            value: completionTeam!,
            icon: Icons.group_outlined,
          ),
        ],
        const SizedBox(height: 12),
        if (isEditing && canEdit)
          _InputField(
            label: 'Adres',
            hint: 'Adres',
            icon: Icons.location_on_outlined,
            controller: addressController,
          )
        else
          _ReadOnlyField(
            label: 'Adres',
            value: details?.address ?? '—',
            icon: Icons.location_on_outlined,
          ),
        const SizedBox(height: 12),
        if (isEditing && canEdit)
          _InputField(
            label: 'Leveradres ramen',
            hint: 'Leveradres',
            icon: Icons.local_shipping_outlined,
            controller: deliveryController,
          )
        else
          _ReadOnlyField(
            label: 'Leveradres ramen',
            value: details?.delivery ?? '—',
            icon: Icons.local_shipping_outlined,
          ),
        const SizedBox(height: 12),
        if (isEditing && canEdit)
          _InputField(
            label: 'Afwerking',
            hint: 'Afwerking',
            icon: Icons.layers_outlined,
            controller: finishController,
          )
        else
          _ReadOnlyField(
            label: 'Afwerking',
            value: details?.finish ?? '—',
            icon: Icons.layers_outlined,
          ),
        const SizedBox(height: 12),
        if (isEditing && canEdit)
          _InputField(
            label: 'Extra notes',
            hint: 'Notities',
            icon: Icons.sticky_note_2_outlined,
            controller: notesController,
          )
        else
          _ReadOnlyField(
            label: 'Extra notes',
            value: details?.extraNotes ?? '—',
            icon: Icons.sticky_note_2_outlined,
          ),
        const SizedBox(height: 12),
        if (isEditing && canEdit)
          _InputField(
            label: 'Geschatte dagen',
            hint: 'Aantal dagen',
            icon: Icons.schedule_outlined,
            controller: daysController,
          )
        else
          _ReadOnlyField(
            label: 'Geschatte dagen',
            value: details == null ? '—' : _formatDays(details!.estimatedDays),
            icon: Icons.schedule_outlined,
          ),
        if (isEditing && canEdit) const SizedBox(height: 12),
      ],
    );
  }
}

class _ProjectLogEntryCard extends StatelessWidget {
  const _ProjectLogEntryCard({required this.entry});

  final ProjectLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.message,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            '${entry.user} · ${entry.role}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF6A7C78)),
          ),
          const SizedBox(height: 4),
          Text(
            _formatDateTime(entry.timestamp),
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF6A7C78)),
          ),
        ],
      ),
    );
  }
}

class _OfferOverviewCard extends StatelessWidget {
  const _OfferOverviewCard({required this.customerName});

  final String customerName;

  @override
  Widget build(BuildContext context) {
    final lines = ProjectStore.offers[customerName] ?? const <OfferLine>[];
    final canSeeHours = _canSeeOfferHours(CurrentUserStore.role);
    double totalHours = 0;
    if (canSeeHours) {
      for (final line in lines) {
        final item = OfferCatalogStore.findItem(line.category, line.item);
        final hours = item?.hours;
        if (hours != null) {
          totalHours += hours * line.quantity;
        }
      }
    }
    if (lines.isEmpty) {
      return _InputCard(
        title: 'Offerte',
        children: [
          Text(
            'Geen offerte-elementen toegevoegd.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF6A7C78)),
          ),
        ],
      );
    }
    final Map<String, List<OfferLine>> grouped = {};
    for (final line in lines) {
      grouped.putIfAbsent(line.category, () => []).add(line);
    }
    return _InputCard(
      title: 'Offerte',
      children: [
        ...grouped.entries.expand((entry) sync* {
          double categoryHours = 0;
          yield Text(
            entry.key,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          );
          yield const SizedBox(height: 6);
          yield Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE1DAD0)),
            ),
            child: Table(
              columnWidths: const {
                0: FlexColumnWidth(2.4),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
                3: FlexColumnWidth(1.2),
              },
              children: [
                TableRow(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF4F1EA),
                  ),
                  children: [
                    _offerCell(context, 'Beschrijving', header: true),
                    _offerCell(context, 'Aantal', header: true, alignRight: true),
                    _offerCell(context, 'Uur / aantal', header: true, alignRight: true),
                    _offerCell(context, 'Totaal', header: true, alignRight: true),
                  ],
                ),
                ...entry.value.map((line) {
                  final item = OfferCatalogStore.findItem(line.category, line.item);
                  final unitHours = item?.hours ?? 0;
                  final lineTotal = unitHours * line.quantity;
                  if (canSeeHours && item?.hours != null) {
                    categoryHours += lineTotal;
                  }
                  return TableRow(
                    children: [
                      _offerCell(context, line.item),
                      _offerCell(context, '${line.quantity}', alignRight: true),
                      _offerCell(
                        context,
                        canSeeHours ? _formatPrice(unitHours) : '—',
                        alignRight: true,
                      ),
                      _offerCell(
                        context,
                        canSeeHours ? _formatPrice(lineTotal) : '—',
                        alignRight: true,
                      ),
                    ],
                  );
                }),
              ],
            ),
          );
          if (canSeeHours) {
            yield const SizedBox(height: 6);
            yield Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Totaal: ${_formatPrice(categoryHours)} uur',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF243B3A),
                    ),
              ),
            );
          }
          yield const SizedBox(height: 8);
        }),
        if (canSeeHours) ...[
          const Divider(height: 24),
          Text(
            'Totaal uren: ${_formatPrice(totalHours)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ],
    );
  }
}

Widget _offerCell(
  BuildContext context,
  String value, {
  bool header = false,
  bool alignRight = false,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: Text(
      value,
      textAlign: alignRight ? TextAlign.right : TextAlign.left,
      maxLines: 2,
      style: header
          ? Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF243B3A),
              )
          : Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF6A7C78),
              ),
    ),
  );
}

class _ProjectDocumentsCard extends StatelessWidget {
  const _ProjectDocumentsCard({required this.customerName});

  final String customerName;

  @override
  Widget build(BuildContext context) {
    final documents =
        ProjectStore.documents[customerName] ?? const <ProjectDocument>[];
    return _InputCard(
      title: 'Documenten',
      children: [
        if (documents.isEmpty)
          Text(
            'Geen documenten toegevoegd.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF6A7C78)),
          )
        else
          ...documents.map(
            (doc) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await _openDocument(context, doc);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F1EA),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE1DAD0)),
                  ),
                  child: Text(
                    doc.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

Future<void> _openDocument(BuildContext context, ProjectDocument doc) async {
  final path = await _ensureLocalPath(doc);
  if (path == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bestand kan niet geopend worden.')),
    );
    return;
  }
  final result = await OpenFilex.open(path);
  if (!context.mounted) return;
  if (result.type != ResultType.done) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.message.isNotEmpty
              ? result.message
              : 'Bestand kon niet geopend worden.',
        ),
      ),
    );
  }
}

Future<String?> _ensureLocalPath(ProjectDocument doc) async {
  if (doc.file.path != null) {
    return doc.file.path!;
  }
  final bytes = doc.file.bytes;
  if (bytes == null) return null;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/${doc.file.name}');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

Future<String?> _ensureLocalPathForFile(PlatformFile file) async {
  if (file.path != null) {
    return file.path!;
  }
  final bytes = file.bytes;
  if (bytes == null) return null;
  final dir = await getTemporaryDirectory();
  final out = File('${dir.path}/${file.name}');
  await out.writeAsBytes(bytes, flush: true);
  return out.path;
}

bool _isPreviewableFile(PlatformFile file) {
  final ext = (file.extension ?? '').toLowerCase();
  if (ext.isEmpty) return false;
  if (ext == 'pdf') return true;
  return ['png', 'jpg', 'jpeg', 'heic', 'webp'].contains(ext);
}

Future<void> _openProfileDocument(
  BuildContext context,
  DocumentEntry entry,
) async {
  if (!_isPreviewableFile(entry.file)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Geen preview beschikbaar voor dit bestand.')),
    );
    return;
  }
  final path = await _ensureLocalPathForFile(entry.file);
  if (path == null) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bestand kan niet geopend worden.')),
    );
    return;
  }
  final result = await OpenFilex.open(path);
  if (!context.mounted) return;
  if (result.type != ResultType.done) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.message.isNotEmpty
              ? result.message
              : 'Bestand kon niet geopend worden.',
        ),
      ),
    );
  }
}

class _ProjectSiteFollowUp extends StatelessWidget {
  const _ProjectSiteFollowUp({
    required this.siteTabIndex,
    required this.onTabChange,
    required this.beforePhotos,
    required this.afterPhotos,
    required this.canEdit,
    required this.onAddBefore,
    required this.onAddAfter,
    required this.onRemoveBefore,
    required this.onRemoveAfter,
  });

  final int siteTabIndex;
  final ValueChanged<int> onTabChange;
  final List<PlatformFile> beforePhotos;
  final List<PlatformFile> afterPhotos;
  final bool canEdit;
  final VoidCallback onAddBefore;
  final VoidCallback onAddAfter;
  final void Function(int index) onRemoveBefore;
  final void Function(int index) onRemoveAfter;

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      title: 'Werfopvolging',
      children: [
        _TabToggle(
          labels: const ['Voor de werf', 'Na de werf'],
          selectedIndex: siteTabIndex,
          onSelect: onTabChange,
        ),
        const SizedBox(height: 12),
        if (siteTabIndex == 0)
          _PhotoGridSection(
            title: 'Foto’s voor de werf',
            photos: beforePhotos,
            onAdd: canEdit ? onAddBefore : null,
            onRemove: canEdit ? onRemoveBefore : null,
          )
        else
          _PhotoGridSection(
            title: 'Foto’s na de werf',
            photos: afterPhotos,
            onAdd: canEdit ? onAddAfter : null,
            onRemove: canEdit ? onRemoveAfter : null,
          ),
      ],
    );
  }
}

class _ExtraWorkSection extends StatelessWidget {
  const _ExtraWorkSection({
    required this.canEdit,
    required this.isEditingExtraWork,
    required this.extraWorks,
    required this.extraWorkController,
    required this.extraHoursController,
    required this.extraWorkChargeType,
    required this.onChargeTypeChanged,
    required this.extraWorkFiles,
    required this.onRemoveExtraPhoto,
    required this.onEditExtraWork,
    required this.onDeleteExtraWork,
    required this.onPickExtraPhotos,
    required this.onAddExtraWork,
    required this.showExtraWorkSection,
  });

  final bool canEdit;
  final bool isEditingExtraWork;
  final List<ExtraWorkEntry> extraWorks;
  final TextEditingController extraWorkController;
  final TextEditingController extraHoursController;
  final String extraWorkChargeType;
  final void Function(String?) onChargeTypeChanged;
  final List<PlatformFile> extraWorkFiles;
  final void Function(int index) onRemoveExtraPhoto;
  final void Function(int index) onEditExtraWork;
  final void Function(int index) onDeleteExtraWork;
  final VoidCallback onPickExtraPhotos;
  final VoidCallback onAddExtraWork;
  final bool showExtraWorkSection;

  @override
  Widget build(BuildContext context) {
    if (!showExtraWorkSection) {
      return const SizedBox.shrink();
    }
    return _InputCard(
      title: 'Extra werk',
      children: [
        if (extraWorks.isEmpty)
          SizedBox(
            width: double.infinity,
            child: Text(
              'Nog geen extra werk toegevoegd.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF6A7C78)),
            ),
          )
        else
          ...extraWorks.asMap().entries.map(
            (entryPair) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1EA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE1DAD0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entryPair.value.description,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                        if (canEdit) ...[
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18),
                            color: const Color(0xFF6A7C78),
                            onPressed: () => onEditExtraWork(entryPair.key),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: const Color(0xFFB42318),
                            onPressed: () => onDeleteExtraWork(entryPair.key),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Extra uren: ${_formatPrice(entryPair.value.hours)}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: const Color(0xFF6A7C78)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Type: ${entryPair.value.chargeType}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: const Color(0xFF6A7C78)),
                    ),
                    if (entryPair.value.photos.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _CollapsiblePhotoWrap(
                        photos: entryPair.value.photos,
                        onOpen: (index) => _openPhotoViewer(
                          context,
                          entryPair.value.photos,
                          index,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (canEdit) ...[
          const SizedBox(height: 8),
          TextField(
            controller: extraWorkController,
            decoration: InputDecoration(
              hintText: 'Extra werk beschrijving',
              filled: true,
              fillColor: const Color(0xFFF4F1EA),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: extraHoursController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Extra uren',
              filled: true,
              fillColor: const Color(0xFFF4F1EA),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey(extraWorkChargeType),
            initialValue: extraWorkChargeType,
            items: _extraWorkChargeTypes
                .map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(type),
                  ),
                )
                .toList(),
            onChanged: onChargeTypeChanged,
            decoration: InputDecoration(
              labelText: 'Doorrekening',
              filled: true,
              fillColor: const Color(0xFFF4F1EA),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _FileUploadRow(
            label: 'Foto’s toevoegen',
            buttonLabel: 'Kies foto’s',
            files: extraWorkFiles,
            onAdd: onPickExtraPhotos,
            showFiles: false,
          ),
          if (extraWorkFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            _CollapsiblePhotoWrap(
              photos: extraWorkFiles,
              onOpen: (index) => _openPhotoViewer(
                context,
                extraWorkFiles,
                index,
              ),
              onRemove: (index) => onRemoveExtraPhoto(index),
            ),
          ],
          const SizedBox(height: 8),
          _PrimaryButton(
            label:
                isEditingExtraWork ? 'Extra werk bijwerken' : 'Extra werk opslaan',
            onTap: onAddExtraWork,
          ),
        ],
      ],
    );
  }
}

class _ProjectCommentsSection extends StatelessWidget {
  const _ProjectCommentsSection({
    required this.comments,
    required this.canAdd,
    required this.controller,
    required this.onAdd,
  });

  final List<String> comments;
  final bool canAdd;
  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return _InputCard(
      title: 'Opmerkingen',
      children: [
        if (comments.isEmpty)
          Text(
            'Nog geen opmerkingen.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF6A7C78)),
          )
        else
          ...comments.map(
            (comment) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4F1EA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE1DAD0)),
                ),
                child: Text(
                  comment,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ),
          ),
        if (canAdd) ...[
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Opmerking toevoegen',
              filled: true,
              fillColor: const Color(0xFFF4F1EA),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _PrimaryButton(label: 'Opmerking toevoegen', onTap: onAdd),
        ] else ...[
          const SizedBox(height: 6),
        ],
      ],
    );
  }
}

class _AddItemRow extends StatelessWidget {
  const _AddItemRow({
    required this.controller,
    required this.onAdd,
  });

  final TextEditingController controller;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Stuk toevoegen',
              filled: true,
              fillColor: const Color(0xFFF4F1EA),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFE1DAD0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFF0B2E2B)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        _InlineButton(label: 'Toevoegen', onTap: onAdd),
      ],
    );
  }
}

class _BackorderItemRow extends StatelessWidget {
  const _BackorderItemRow({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.build_outlined, color: Color(0xFF6A7C78)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF243B3A)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditableBackorderItemRow extends StatelessWidget {
  const _EditableBackorderItemRow({
    required this.label,
    required this.onEdit,
    required this.onDelete,
  });

  final String label;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1EA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18),
            color: const Color(0xFF6A7C78),
            onPressed: onEdit,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            color: const Color(0xFFB42318),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}

class _PhotoGridSection extends StatefulWidget {
  const _PhotoGridSection({
    required this.title,
    required this.photos,
    this.onAdd,
    this.onRemove,
  });

  final String title;
  final List<PlatformFile> photos;
  final VoidCallback? onAdd;
  final void Function(int index)? onRemove;

  @override
  State<_PhotoGridSection> createState() => _PhotoGridSectionState();
}

class _PhotoGridSectionState extends State<_PhotoGridSection> {
  bool _isEditing = false;

  @override
  Widget build(BuildContext context) {
    final canEdit = widget.onRemove != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (canEdit || widget.onAdd != null)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF243B3A),
                      ),
                ),
              ),
              if (canEdit)
                IconButton(
                  onPressed: () => setState(() => _isEditing = !_isEditing),
                  icon: Icon(
                    _isEditing ? Icons.check : Icons.edit_outlined,
                  ),
                  color: const Color(0xFF6A7C78),
                ),
              if (widget.onAdd != null)
                IconButton(
                  onPressed: widget.onAdd,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  color: const Color(0xFF6A7C78),
                ),
            ],
          )
        else
          Text(
            widget.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF243B3A),
                ),
          ),
        const SizedBox(height: 8),
        if (widget.photos.isEmpty)
          Text(
            'Nog geen foto’s toegevoegd.',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF6A7C78)),
          )
        else
          _CollapsiblePhotoWrap(
            photos: widget.photos,
            onOpen: (index) => _openPhotoViewer(context, widget.photos, index),
            onRemove: _isEditing ? widget.onRemove : null,
          ),
      ],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.file,
    required this.onTap,
    this.onRemove,
  });

  final PlatformFile file;
  final VoidCallback onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final path = file.path;
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Stack(
          children: [
            Container(
              height: 64,
              width: 64,
              color: const Color(0xFFE6DFD5),
              child: path == null
                  ? const Icon(Icons.image_outlined,
                      color: Color(0xFF6A7C78))
                  : Image.file(
                      File(path),
                      fit: BoxFit.cover,
                    ),
            ),
            if (onRemove != null)
              Positioned(
                top: 2,
                right: 2,
                child: GestureDetector(
                  onTap: onRemove,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB42318),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.close,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CollapsiblePhotoWrap extends StatefulWidget {
  const _CollapsiblePhotoWrap({
    required this.photos,
    required this.onOpen,
    this.onRemove,
  });

  final List<PlatformFile> photos;
  final void Function(int index) onOpen;
  final void Function(int index)? onRemove;

  @override
  State<_CollapsiblePhotoWrap> createState() => _CollapsiblePhotoWrapState();
}

class _CollapsiblePhotoWrapState extends State<_CollapsiblePhotoWrap> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.photos.length;
    final showCollapsed = count > 4 && !_expanded;
    final visibleCount = showCollapsed ? 3 : count;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < visibleCount; i++)
              _PhotoThumb(
                file: widget.photos[i],
                onTap: () => widget.onOpen(i),
                onRemove:
                    widget.onRemove == null ? null : () => widget.onRemove!(i),
              ),
            if (showCollapsed)
              _MorePhotosTile(
                remaining: count - 3,
                onTap: () => setState(() => _expanded = true),
              ),
          ],
        ),
        if (count > 4 && _expanded) ...[
          const SizedBox(height: 8),
          _InlineButton(
            label: 'Toon minder',
            onTap: () => setState(() => _expanded = false),
            icon: Icons.expand_less,
          ),
        ],
      ],
    );
  }
}

class _MorePhotosTile extends StatelessWidget {
  const _MorePhotosTile({required this.remaining, required this.onTap});

  final int remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 64,
          width: 64,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F1EA),
            border: Border.all(color: const Color(0xFFE1DAD0)),
          ),
          child: Center(
            child: Text(
              '+$remaining',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF243B3A),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

void _openPhotoViewer(
  BuildContext context,
  List<PlatformFile> photos,
  int initialIndex,
) {
  if (photos.isEmpty) return;
  showDialog<void>(
    context: context,
    builder: (context) {
      final controller = PageController(initialPage: initialIndex);
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            PageView.builder(
              controller: controller,
              itemCount: photos.length,
              itemBuilder: (context, index) {
                final path = photos[index].path;
                if (path == null) {
                  return const Center(
                    child: Icon(Icons.image_outlined, color: Colors.white),
                  );
                }
                return InteractiveViewer(
                  child: Image.file(
                    File(path),
                    fit: BoxFit.contain,
                  ),
                );
              },
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// ignore: unused_element
class _ReadOnlyNote extends StatelessWidget {
  const _ReadOnlyNote({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F1EA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_outline, color: Color(0xFF6A7C78)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF243B3A),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF6A7C78)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupToggle extends StatelessWidget {
  const _GroupToggle({
    required this.groups,
    required this.selected,
    required this.onSelect,
    this.labelBuilder,
  });

  final List<String> groups;
  final String selected;
  final ValueChanged<String> onSelect;
  final String Function(String group)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFE6DFD5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: groups
            .map(
              (group) => Expanded(
                child: GestureDetector(
                  onTap: () => onSelect(group),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: group == selected
                          ? const Color(0xFF0B2E2B)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        labelBuilder?.call(group) ?? group,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: group == selected
                                      ? const Color(0xFFFFE9CC)
                                      : const Color(0xFF4B6763),
                                ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _CustomerRow extends StatelessWidget {
  const _CustomerRow({
    required this.name,
    required this.phone,
    required this.group,
    required this.status,
    required this.highlight,
    this.compact = false,
    this.onCenterTap,
    this.onArrowTap,
    this.onIconTap,
    this.showSelection = false,
    this.selected = false,
    this.showStatus = true,
  });

  final String name;
  final String phone;
  final String group;
  final String status;
  final bool highlight;
  final bool compact;
  final VoidCallback? onCenterTap;
  final VoidCallback? onArrowTap;
  final VoidCallback? onIconTap;
  final bool showSelection;
  final bool selected;
  final bool showStatus;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onCenterTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                GestureDetector(
                  onTap: onIconTap,
                  child: Container(
                    height: 38,
                    width: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFCE6CC),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.home_work_outlined,
                        color: Color(0xFF6A4A2D)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: compact
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF243B3A),
                                ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF243B3A),
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              phone,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF6A7C78)),
                            ),
                            if (highlight && showStatus) ...[
                              const SizedBox(height: 4),
                              Text(
                                '$group · $status',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: const Color(0xFF6A7C78)),
                              ),
                            ],
                          ],
                        ),
                ),
                const SizedBox(width: 6),
                if (showSelection)
                  Container(
                    height: 22,
                    width: 22,
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF0B2E2B)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF0B2E2B)
                            : const Color(0xFFB8ADA0),
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  )
                else
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    color: const Color(0xFF6A7C78),
                    onPressed: onArrowTap,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  const _EmptyStateCard({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF6A7C78)),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _OverviewCard extends StatelessWidget {
  const _OverviewCard({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2E2B),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFFFFE9CC),
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: const Color(0xFFFFE9CC),
                    ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFA64D),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.timer, color: Color(0xFF0B2E2B)),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _RoleSection extends StatelessWidget {
  const _RoleSection({
    required this.title,
    required this.subtitle,
    required this.items,
  });

  final String title;
  final String subtitle;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF6A7C78)),
          ),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      size: 16, color: Color(0xFF0B2E2B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF5A6F6C)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _ShiftCard extends StatelessWidget {
  const _ShiftCard({
    required this.time,
    required this.project,
    required this.details,
    required this.status,
  });

  final String time;
  final String project;
  final String details;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: const Color(0xFFF4F1EA),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.work_outline, color: Color(0xFF0B2E2B)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  project,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  details,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF6A7C78)),
                ),
                const SizedBox(height: 10),
                _InlineButton(label: status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.title,
    required this.subtitle,
    required this.status,
  });

  final String title;
  final String subtitle;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF6A7C78)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0B2E2B),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              status,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFFFE9CC),
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.roleLabel,
    this.photo,
    this.onEdit,
  });

  final String name;
  final String roleLabel;
  final PlatformFile? photo;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Row(
        children: [
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: const Color(0xFF0B2E2B),
              borderRadius: BorderRadius.circular(18),
            ),
            child: photo?.path != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.file(
                      File(photo!.path!),
                      fit: BoxFit.cover,
                    ),
                  )
                : const Icon(Icons.person, color: Color(0xFFFFE9CC)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: onEdit,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            name,
                            style: Theme.of(context).textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                                            const SizedBox(width: 6),
                        Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: const Color(0xFF6A7C78),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  roleLabel,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF6A7C78)),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFCE6CC),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Actief',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF6A4A2D)),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _SimpleListCard extends StatelessWidget {
  const _SimpleListCard({required this.title, required this.items});

  final String title;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE1DAD0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 8, color: Color(0xFF0B2E2B)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: const Color(0xFF5A6F6C)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ignore: unused_element
class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.title,
    required this.subtitle,
    required this.buttonLabel,
    // ignore: unused_element_parameter
    this.onTap,
  });

  final String title;
  final String subtitle;
  final String buttonLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0B2E2B),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(color: const Color(0xFFFFE9CC)),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFFD9C3A0)),
          ),
          const SizedBox(height: 12),
          _PrimaryButton(label: buttonLabel, onTap: onTap),
        ],
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    this.onTap,
    this.fullWidth = false,
    this.height,
  });

  final String label;
  final VoidCallback? onTap;
  final bool fullWidth;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        color: const Color(0xFFFFA64D),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              label,
              textAlign: fullWidth ? TextAlign.center : TextAlign.start,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0B2E2B),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  const _SecondaryButton({required this.label, this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF0B2E2B)),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0B2E2B),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InlineButton extends StatelessWidget {
  const _InlineButton({required this.label, this.onTap, this.icon});

  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFFCE6CC),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: const Color(0xFF6A4A2D)),
                                    const SizedBox(width: 6),
              ],
              Text(
                label,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: const Color(0xFF6A4A2D)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        height: 36,
        width: 36,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE1DAD0)),
        ),
        child: Icon(
          icon,
          size: 20,
          color: const Color(0xFF243B3A),
        ),
      ),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 22),
      decoration: const BoxDecoration(
        color: Color(0xFFF4F1EA),
        boxShadow: [
          BoxShadow(
            color: Color(0x220B2E2B),
            blurRadius: 16,
            offset: Offset(0, -6),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _NavItem(
              icon: Icons.today,
              label: 'Vandaag',
              selected: currentIndex == 0,
              onTap: () => onTap(0),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.calendar_today,
              label: 'Planning',
              selected: currentIndex == 1,
              onTap: () => onTap(1),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.folder_open,
              label: 'Projecten',
              selected: currentIndex == 2,
              onTap: () => onTap(2),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.bar_chart,
              label: 'Stats',
              selected: currentIndex == 3,
              onTap: () => onTap(3),
            ),
          ),
          Expanded(
            child: _NavItem(
              icon: Icons.person_outline,
              label: 'Profiel',
              selected: currentIndex == 4,
              onTap: () => onTap(4),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0B2E2B) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: selected
                  ? const Color(0xFFFFE9CC)
                  : const Color(0xFF6A7C78),
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? const Color(0xFFFFE9CC)
                        : const Color(0xFF6A7C78),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SoftGradientBackground extends StatelessWidget {
  const _SoftGradientBackground();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFF4F1EA),
    );
  }
}
