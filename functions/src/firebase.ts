import * as admin from "firebase-admin";

/**
 * Singleton Firebase Admin SDK initialization.
 *
 * ## Do NOT pass an explicit credential
 *
 * `admin.initializeApp()` with NO arguments uses Application Default
 * Credentials, which inside the Cloud Functions runtime resolve to the
 * function's own **runtime service account** (the identity Cloud Run runs the
 * container as). That is the account that must hold
 * `roles/firebaseauth.admin` ("Firebase Authentication Admin").
 *
 * Passing `{ credential: admin.credential.applicationDefault() }` looks
 * equivalent but is NOT:
 *
 *   1. It materialises the credential eagerly, and
 *   2. `applicationDefault()` honours a stray `GOOGLE_APPLICATION_CREDENTIALS`
 *      (e.g. a limited service-account key left on the deploy machine / CI
 *      runner). That key — not the runtime service account — then becomes the
 *      identity, and every Auth Admin call fails with:
 *
 *        "Credential implementation provided to initializeApp() via the
 *         'credential' property has insufficient permission to access the
 *         requested resource."
 *
 * The runtime service account already carries the needed roles (see the IAM
 * audit in `docs/fix-email-verification/`), so the explicit credential is pure
 * downside. For local emulator runs, ADC still picks up
 * `GOOGLE_APPLICATION_CREDENTIALS` automatically — no code path needs the
 * explicit form.
 */
let app: admin.app.App | null = null;

export function getAdmin(): admin.app.App {
  if (app) return app;
  if (admin.apps.length > 0) {
    app = admin.app();
  } else {
    // No explicit credential: use Application Default Credentials, which in
    // the runtime are the function's own service account.
    app = admin.initializeApp();
  }
  return app;
}

export const firestore = (): admin.firestore.Firestore =>
  getAdmin().firestore();

export const auth = (): admin.auth.Auth => getAdmin().auth();

/**
 * Non-secret descriptor of the credential the Admin SDK is actually using.
 *
 * Used to surface an actionable error when an Auth Admin call fails with
 * "insufficient permission": instead of a bare "0 of 12", the UI can show
 * WHICH service account the function ran as and WHICH role it is missing.
 * Nothing here is a secret — the service-account email and project id are
 * identifiers, not credentials.
 */
export interface CredentialDiagnostic {
  /** True when an explicit credential was passed to initializeApp (the bug). */
  explicitCredential: boolean;
  /** The credential implementation class, e.g. "ServiceAccountCredential". */
  credentialClass: string;
  /** Coarse source: serviceAccountKey | computeMetadata | ... | unknown. */
  source: string;
  /** The GCP project id the credential belongs to (non-secret). */
  projectId: string | null;
  /** The service-account email the credential acts as, when determinable. */
  serviceAccount: string | null;
}

/** Reads a non-empty trimmed string, else null. */
function asText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * Describes the credential the Admin SDK will use. Best-effort + never throws:
 * an unresolvable piece is reported as null rather than failing the caller.
 */
export function describeCredential(): CredentialDiagnostic {
  try {
    const options = getAdmin().options;
    const explicit = options.credential;
    // Constructing applicationDefault() does not make a network call; it only
    // resolves which source (env key / metadata / default file) applies.
    const cred = (explicit ?? admin.credential.applicationDefault()) as unknown;
    const asRecord = cred as Record<string, unknown>;
    const credentialClass = String(
      (cred as { constructor?: { name?: string } })?.constructor?.name ??
        "unknown"
    );

    let source = "unknown";
    if (/ServiceAccountCredential/.test(credentialClass)) {
      source = "serviceAccountKey";
    } else if (/ComputeEngineCredential/.test(credentialClass)) {
      source = "computeMetadata";
    } else if (/RefreshTokenCredential/.test(credentialClass)) {
      source = "refreshToken";
    } else if (/Impersonated/.test(credentialClass)) {
      source = "impersonatedServiceAccount";
    } else if (/ApplicationDefault/.test(credentialClass)) {
      source = "applicationDefault";
    }

    return {
      explicitCredential: explicit != null,
      credentialClass,
      source,
      projectId: asText(asRecord.projectId) ?? asText(options.projectId),
      serviceAccount:
        asText(asRecord.clientEmail) ??
        asText(asRecord.serviceAccountId) ??
        // The runtime exports the identity for 1st-gen functions; for 2nd-gen
        // the class above (computeMetadata) is the decisive signal.
        asText(process.env.FUNCTION_IDENTITY) ??
        null,
    };
  } catch (err) {
    return {
      explicitCredential: false,
      credentialClass: "unresolved",
      source: "unknown",
      projectId: null,
      serviceAccount: null,
    };
  }
}
