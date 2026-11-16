import 'admin_user_metrics.dart';

/// Builds the Admin Portal V2 **Users CSV** exports.
///
/// Pure + synchronous so the CSV content, the row count shown next to each
/// button, and the downloaded file are guaranteed to agree — the count IS the
/// CSV row count.
///
/// Columns mirror the Admin V2 Users **table** exactly, in the same order:
/// `Email, Name, Surname, Role, Trial, Trial Start Date, Trial End Date,
/// Plan, Provider`. There is NO `Created` column (it was removed from both the
/// table and the CSV). Dates are `YYYY-MM-DD`; empty fields are emitted as an
/// empty cell (never `—`, never `null`) so the file imports cleanly into a
/// spreadsheet and no cell can crash the export.
class AdminUsersCsv {
  AdminUsersCsv._();

  /// The CSV header row, in the exact column order the Users table renders.
  static const List<String> headers = <String>[
    'Email',
    'Name',
    'Surname',
    'Role',
    'Trial',
    'Trial Start Date',
    'Trial End Date',
    'Plan',
    'Provider',
  ];

  /// The role cell value: the stored role verbatim (trimmed), or blank when the
  /// account has none.
  static String roleCell(AdminUserRecord r) => r.role.trim();

  /// One CSV data row for [r], matching the Users table cells exactly.
  ///
  /// Dates use `YYYY-MM-DD` and render blank when unknown (never `—`); `Trial`
  /// is the same computed label the table shows (`Active` / `Expired` /
  /// `Converted` / `None`).
  static List<String> rowFor(AdminUserRecord r, DateTime now) => <String>[
        r.email,
        r.firstName,
        r.lastName,
        roleCell(r),
        r.trialLabel(now),
        _dateCell(r.trialStart),
        _dateCell(r.trialEnd),
        r.plan,
        r.provider,
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
