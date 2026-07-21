import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'training_curriculum.dart';
import 'training_http_client.dart';
import 'training_http_overrides.dart';
import 'training_sandbox_store.dart';

/// Training Mode (Admin-only) — curriculum modules only (POS, Logistics,
/// History & DP, Warranty, Finance, Master Data). Not wired into Karyawan APK.
///
/// **Live vs training:**
/// - **Live:** online; cabang ↔ pusat sync real-time.
/// - **Training:** fresh sandbox world each enter; modules sync **with each
///   other inside the sandbox only**; exit wipes everything; re-enter = zero.
///
/// **Zero leak rule:** while [isActive], [TrainingHttpClient] intercepts all
/// REST/Storage/RPC into [TrainingSandboxStore] (reads isolated — no prod
/// read-through). Mutations that would escape fail closed.
class TrainingMode extends ChangeNotifier {
  TrainingMode._();

  static final TrainingMode instance = TrainingMode._();

  static const _prefsActiveKey = 'training_mode_active';
  static const _prefsSessionKey = 'training_mode_session_id';
  static const _prefsTokoKey = 'training_mode_toko_id';
  static const _prefsRoleKey = 'training_mode_role';

  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  bool _isActive = false;
  String? _sessionId;
  String? _tokoId;
  String? _role;
  Map<String, dynamic>? _lockedProfile;

  bool get isActive => _isActive;
  String? get sessionId => _sessionId;
  String? get tokoId => _tokoId;
  String? get role => _role;

  /// Snapshot of admin profile at enter (scope lock source of truth).
  Map<String, dynamic>? get lockedProfile =>
      _lockedProfile == null ? null : Map.unmodifiable(_lockedProfile!);

  /// Enter training (Admin): lock scope from current profile, init sandbox,
  /// persist crash-recovery flag so orphan dirs are wiped on next launch.
  Future<void> enter(Map<String, dynamic> profile) async {
    if (_isActive) {
      throw StateError('Training mode already active (session $_sessionId).');
    }

    final tokoId = (profile['toko_id'] ?? '').toString().trim();
    if (tokoId.isEmpty) {
      throw ArgumentError(
        'Training mode requires toko_id on profile — cannot enter without store scope.',
      );
    }

    // Role = jabatan (karyawan) or explicit role field; never elevate privileges.
    final role = (profile['jabatan'] ?? profile['role'] ?? '').toString().trim();
    if (role.isEmpty) {
      throw ArgumentError(
        'Training mode requires jabatan/role on profile — scope must match live access.',
      );
    }

    final sessionId =
        'tr_${DateTime.now().millisecondsSinceEpoch}_${tokoId.hashCode.abs()}';

    await TrainingSandboxStore.instance.init(sessionId);

    _isActive = true;
    _sessionId = sessionId;
    _tokoId = tokoId;
    _role = role;
    _lockedProfile = Map<String, dynamic>.from(profile);
    TrainingHttpClient.debugBlockedMutations = 0;

    // Image.network / CachedNetworkImage → loopback sandbox files.
    await TrainingLocalFileServer.instance.start();
    TrainingHttpOverrides.install();

    // Fresh curriculum world (products, kasir, settings). No prod data mixed in.
    try {
      await TrainingCurriculum.seedFreshWorld(
        tokoId: tokoId,
        profile: profile,
      );
    } catch (e) {
      debugPrint('[TrainingMode] seedFreshWorld: $e');
      rethrow;
    }

    await _persistRecoveryFlag(
      active: true,
      sessionId: sessionId,
      tokoId: tokoId,
      role: role,
    );

    notifyListeners();
    debugPrint(
      '[TrainingMode] ENTER session=$sessionId toko=$tokoId role=$role '
      '(curriculum sandbox; isolated reads; wipe on exit)',
    );
  }

  /// Exit training: wipe ALL sandbox data/files, clear flags, back to live.
  ///
  /// **Critical order:** keep [isActive] true until the sandbox is fully wiped.
  /// Deactivating first would let in-flight mutations fall through to production.
  Future<void> exit() async {
    if (!_isActive && _sessionId == null) {
      await wipeOrphanSessions();
      return;
    }

    final sid = _sessionId;
    debugPrint(
      '[TrainingMode] EXIT wipe session=$sid '
      'blockedMutations=${TrainingHttpClient.debugBlockedMutations}',
    );

    // Stop image URL rewriting; Supabase mutations stay fail-closed while
    // isActive remains true through the wipe below.
    TrainingHttpOverrides.uninstall();
    await TrainingLocalFileServer.instance.stop();

    try {
      await TrainingSandboxStore.instance.wipe();
    } catch (e) {
      debugPrint('[TrainingMode] sandbox wipe error: $e');
    }

    // Also remove any leftover training_* dirs (crash / partial wipe).
    await wipeOrphanSessions();

    // Only after wipe: allow live network mutations again.
    _isActive = false;
    _sessionId = null;
    _tokoId = null;
    _role = null;
    _lockedProfile = null;

    try {
      await _clearRecoveryFlag();
    } catch (e) {
      debugPrint('[TrainingMode] clear recovery flag: $e');
    }
    notifyListeners();
  }

  /// On app start: if recovery flag or orphan `training_*` dirs exist, wipe them.
  /// Ensures crash mid-training never leaves sandbox residue or a sticky flag.
  Future<void> recoverOnLaunch() async {
    try {
      TrainingHttpOverrides.uninstall();
      await TrainingLocalFileServer.instance.stop();

      final flagged = await _secure.read(key: _prefsActiveKey);
      if (flagged == '1') {
        final orphanSid = await _secure.read(key: _prefsSessionKey);
        debugPrint(
          '[TrainingMode] orphan recovery flag — wiping session=$orphanSid',
        );
        if (orphanSid != null && orphanSid.isNotEmpty) {
          await TrainingSandboxStore.wipeSessionDir(orphanSid);
        }
        await wipeOrphanSessions();
        await _clearRecoveryFlag();
      } else {
        // Flag clear but leftover dirs (e.g. killed during wipe) → still clean.
        await wipeOrphanSessions();
      }
    } catch (e) {
      debugPrint('[TrainingMode] recoverOnLaunch: $e');
      try {
        await wipeOrphanSessions();
        await _clearRecoveryFlag();
      } catch (_) {}
    }

    // Memory must start inactive after launch recovery.
    if (_isActive) {
      _isActive = false;
      _sessionId = null;
      _tokoId = null;
      _role = null;
      _lockedProfile = null;
      notifyListeners();
    }
  }

  /// Delete every `training_*` directory under temp.
  Future<void> wipeOrphanSessions() =>
      TrainingSandboxStore.wipeAllTrainingDirs();

  /// Throws if [tokoId] does not match the locked training store.
  void assertSameToko(String tokoId) {
    if (!_isActive) return;
    final locked = _tokoId ?? '';
    if (tokoId.trim() != locked) {
      throw StateError(
        'Training scope violation: attempted toko=$tokoId, locked=$locked',
      );
    }
  }

  /// Call before any production mutation. Throws when training is ON.
  /// Prefer relying on [TrainingHttpClient] fail-closed; this is an extra assert.
  static void guardProductionWrite(String op) {
    if (instance.isActive) {
      throw StateError(
        'PRODUCTION WRITE BLOCKED during Training Mode: $op. '
        'TrainingHttpClient should intercept Supabase mutations into the sandbox. '
        'Zero leak — not one row/file to production while training is active.',
      );
    }
  }

  /// Convenience: returns a failed Future when training is active.
  static Future<T> forbidProdMutation<T>(String op) {
    guardProductionWrite(op);
    return Future.error(
      StateError('forbidProdMutation unreachable for $op'),
    );
  }

  /// Test helper: activate sandbox without secure-storage / image server.
  @visibleForTesting
  Future<void> debugActivateForTest({
    String sessionId = 'tr_test',
    String tokoId = 'toko_test',
    String role = 'Staff',
  }) async {
    await TrainingSandboxStore.instance.init(sessionId);
    _isActive = true;
    _sessionId = sessionId;
    _tokoId = tokoId;
    _role = role;
    _lockedProfile = {
      'toko_id': tokoId,
      'jabatan': role,
      'id': 'karyawan_test',
    };
    TrainingHttpClient.debugBlockedMutations = 0;
  }

  /// Test helper: wipe sandbox first (same order as [exit]), then deactivate.
  @visibleForTesting
  Future<void> debugDeactivateForTest() async {
    try {
      await TrainingSandboxStore.instance.wipe();
    } catch (_) {}
    _isActive = false;
    _sessionId = null;
    _tokoId = null;
    _role = null;
    _lockedProfile = null;
  }

  Future<void> _persistRecoveryFlag({
    required bool active,
    required String sessionId,
    required String tokoId,
    required String role,
  }) async {
    await _secure.write(key: _prefsActiveKey, value: active ? '1' : '0');
    await _secure.write(key: _prefsSessionKey, value: sessionId);
    await _secure.write(key: _prefsTokoKey, value: tokoId);
    await _secure.write(key: _prefsRoleKey, value: role);
  }

  Future<void> _clearRecoveryFlag() async {
    await _secure.delete(key: _prefsActiveKey);
    await _secure.delete(key: _prefsSessionKey);
    await _secure.delete(key: _prefsTokoKey);
    await _secure.delete(key: _prefsRoleKey);
  }
}
