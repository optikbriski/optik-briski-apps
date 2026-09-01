/// Logika murni badge navigasi Admin — dipakai service + unit test.
class AdminNavBadgeLogic {
  AdminNavBadgeLogic._();

  static const reminderToken = '__reminder__';

  static Set<String> unreadEntityIds({
    required Set<String>? live,
    required Set<String> seen,
    required Set<String> pinned,
  }) {
    if (live == null || live.isEmpty) return const {};
    return {
      for (final id in live)
        if (pinned.contains(id) || !seen.contains(id)) id,
    };
  }

  static int displayCount({
    required Set<String>? live,
    required Set<String> seen,
    required Set<String> pinned,
  }) {
    final n = unreadEntityIds(live: live, seen: seen, pinned: pinned).length;
    if (n > 0) return n;
    if (pinned.contains(reminderToken)) return 1;
    return 0;
  }

  static Set<String> pruneSeen({
    required Set<String>? live,
    required Set<String> seen,
  }) {
    if (live == null) return {};
    return seen.intersection(live);
  }

  static Set<String> prunePinned({
    required Set<String> live,
    required Set<String> pinned,
  }) {
    return pinned.where((id) => id == reminderToken || live.contains(id)).toSet();
  }
}
