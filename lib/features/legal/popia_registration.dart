/// POPIA / PAIA registration details + contact channels for JagSpoor.
///
/// This is the single source of truth for the organisation's Information
/// Officer, registration numbers and complaint channels. The privacy policy
/// screen, the in-app "request my data / object" flows and the contract tests
/// all read from here so the published policy can never drift from the
/// registered particulars.
///
/// Source: Information Regulator (South Africa) POPIA registration
/// certificate, dated 2026-09-05.
class PopiaRegistration {
  PopiaRegistration._();

  /// Registered organisation name (the POPIA certificate holder).
  static const String organisationName = 'JAGSPOOR VELD AND VENTURES';

  /// POPIA registration number issued by the Information Regulator.
  static const String registrationNumber = '2026-066026';

  /// Date the POPIA registration was issued.
  static const String registrationDate = '2026-09-05';

  /// CIPC private company registration number.
  static const String companyRegistrationNumber = '2026/675772/07';

  /// Appointed Information Officer (POPIA s.55 / PAIA s.17).
  static const String informationOfficerName = 'Donald Llewelyn Kearney';

  /// Date the Information Officer was appointed.
  static const String informationOfficerAppointed = '2026-09-01';

  /// Regulator that issued the registration.
  static const String issuingAuthority = 'Information Regulator (South Africa)';

  /// Primary data-protection / Information Officer contact address.
  static const String privacyEmail = 'privacy@jag-spoor.co.za';

  /// General support address (app help + account queries).
  static const String supportEmail = 'support@jag-spoor.co.za';

  /// Information Regulator complaint channels.
  static const String regulatorWebsite = 'https://inforegulator.org.za';
  static const String regulatorComplaintsEmail =
      'complaints@inforegulator.org.za';
  static const String regulatorPhone = '+27 (0)10 023 5200';
  static const String regulatorAddress =
      'JD House, 27 Stiemens Street, Braamfontein, Johannesburg, 2001';

  /// Human-readable "last updated" date shown at the foot of the policy.
  static const String lastUpdated = '23 September 2026';

  /// Marketing/version label for the policy document.
  static const String policyVersion = '3.0';

  /// Combined display line used in the policy header + settings.
  static String get registrationSummary =>
      '$organisationName · POPIA Reg $registrationNumber '
      '(issued $registrationDate) · Company $companyRegistrationNumber';
}
