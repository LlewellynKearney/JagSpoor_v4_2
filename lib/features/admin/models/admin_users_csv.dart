import 'admin_subscription_metrics.dart';
import 'admin_user_metrics.dart';

/// Builds the Admin Portal V2 **Users CSV** exports.
///
/// Pure + synchronous so the CSV content, the row count shown next to each
/// button, and the downloaded file are guaranteed to agree — the count IS the
/// CSV row count.
///
/// Columns (per the brief):
/// `Email, First Name, Surname, Role, Created Date (YYYY-MM-DD),
/// Last Active (YYYY-MM-DD), Subscription Status, Subscription Provider`.
///
/// Empty fields are emitted as an empty cell (never `—`, never `null`) so the
/// file imports cleanly into a spreadsheet and no cell can crash the export.
class AdminUsersCsv {
  AdminUsersCsv._();

  /// The CSV header row, in the exact column order above.
  static const List<String> headers = <String>[
    'Email',
    'First Name',
    'Surname',
    'Role',
    'Created Date',
    'Last Active',
    'Subscription Status',
    'Subscription Provider',
  ];

  /// The role cell value: the stored role verbatim (trimmed), or blank when the
  /// account has none.
  static String roleCell(AdminUserRecord r) => r.role.trim();

  /// The subscription-status cell: `Active` / `Trial` / `Cancelled` /
  /// `Expired` when the account is on a subscription path, else blank.
  static String subscriptionStatusCell(AdminUserRecord r, DateTime now) {
    final premiumNow = r.isPremiumActive(now);
    if (premiumNow) return 'Active';
    if (r.isTrialActive(now)) return 'Trial';
    if (r.subscriptionStatus == 'cancelled' || r.cancelledAt != null) {
      return 'Cancelled';
    }
    final expiry = r.premiumExpiry;
    final trialEnd = r.trialEnd;
    if ((expiry != null && !expiry.isAfter(now)) ||
        (trialEnd != null && !trialEnd.isAfter(now))) {
      return 'Expired';
    }
    return '';
  }

  /// The subscription-provider cell: `Google` / `PayFast`, or blank when the
  /// account has no known billing provider (the brief's "None" — left blank so
  /// a no-role / never-subscribed row is unambiguous in a spreadsheet).
  static String subscriptionProviderCell(AdminUserRecord r) {
    final provider = resolveAdminSubscriptionProvider(r.provider);
    return provider.isKnown ? provider.label : '';
  }

  /// One CSV data row for [r].
  static List<String> rowFor(AdminUserRecord r, DateTime now) => <String>[
        r.email,
        r.firstName,
        r.lastName,
        roleCell(r),
        _dateCell(r.createdAt),
        _dateCell(r.lastActive),
        subscriptionStatusCell(r, now),
        subscriptionProviderCell(r),
      ];

  /// The users the "Export Users With No Role (CSV)" button exports: every
  /// account whose role is blank / missing / `none` / `unassigned`.
  static List<AdminUserRecord> noRoleUsers(Iterable<AdminUserRecord> records) =>
      records.where((r) => r.hasNoRoleForExport).toList(growable: false);

  /// The full CSV document (header + one row per record) as a single string.
  ///
  /// [records] order is preserved; a caller wanting a stable order should sort
  /// first. Values are escaped by the shared [csvEscape] so a comma, quote or
  /// newline inside an email / name never breaks the row.
  static String build(Iterable<AdminUserRecord> records, {DateTime? now}) {
    final ref = now ?? DateTime.now();
    final buffer = StringBuffer()..write(_line(headers));
    for (final r in records) {
      buffer.write(_line(rowFor(r, ref)));
    }
    return buffer.toString();
  }

  /// The number of DATA rows [build] would produce (the header is excluded).
  /// This is the count rendered next to each export button, so the label and
  /// the file always agree.
  static int rowCount(Iterable<AdminUserRecord> records) => records.length;

  /// `jagspoor-users-YYYY-MM-DD.csv`.
  static String allUsersFileName([DateTime? now]) =>
      'jagspoor-users-${_fileDate(now)}.csv';

  /// `jagspoor-users-no-role-YYYY-MM-DD.csv`.
  static String noRoleFileName([DateTime? now]) =>
      'jagspoor-users-no-role-${_fileDate(now)}.csv';

  static String _line(List<String> cells) =>
      '${cells.map(csvEscape).join(',')}\r\n';

  /// A `YYYY-MM-DD` cell, or an empty string when the date is unknown.
  static String _dateCell(DateTime? date) {
    if (date == null) return '';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  static String _fileDate(DateTime? now) {
    final ref = now ?? DateTime.now();
    final month = ref.month.toString().padLeft(2, '0');
    final day = ref.day.toString().padLeft(2, '0');
    return '${ref.year}-$month-$day';
  }
}

/// RFC 4180 CSV escaping: wraps a value in double quotes and doubles any
/// embedded quote when it contains a comma, quote, CR or LF. A plain value is
/// returned verbatim. Null-safe (an empty string passes through).
String csvEscape(String value) {
  final needsQuoting = value.contains(',') ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuoting) return value;
  return '"${value.replaceAll('"', '""')}"';
}
