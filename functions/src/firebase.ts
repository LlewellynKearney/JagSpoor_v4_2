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
  /** The Cloud Run service name (`K_SERVICE`), when running in the runtime. */
  cloudRunService?: string | null;
}

/** Reads a non-empty trimmed string, else null. */
function asText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

/**
 * The GCE/Cloud-Run metadata server host. `GCE_METADATA_HOST` is honoured (the
 * same env var `google-auth-library` reads) so an emulator / test can point it
 * elsewhere; otherwise the production metadata host is used.
 */
export function metadataHost(): string {
  return asText(process.env.GCE_METADATA_HOST) ?? "metadata.google.internal";
}

/** The metadata path that returns the runtime service account's email. */
export const METADATA_SA_EMAIL_PATH =
  "/computeMetadata/v1/instance/service-accounts/default/email";

/** How long to wait for the metadata server before giving up (ms). */
export const METADATA_TIMEOUT_MS = 800;

/**
 * Resolves the RUNTIME service account's email from the environment / metadata
 * server, so a credential diagnostic can name the exact identity instead of
 * "(runtime service account — resolve via Cloud Run console)".
 *
 * Resolution order:
 *   1. `FUNCTION_IDENTITY` — 1st-gen functions export the identity directly.
 *   2. The metadata server (`/computeMetadata/v1/instance/service-accounts/
 *      default/email`) — the authoritative source for 2nd-gen Cloud Run
 *      functions, which run as a service account with no email in the env.
 *   3. `SERVICE_ACCOUNT_EMAIL` / `FIREBASE_SERVICE_ACCOUNT_EMAIL` env aliases,
 *      when an operator sets one explicitly.
 *
 * Best-effort + bounded: never throws, times out fast, and returns null when
 * the identity cannot be determined (e.g. local emulator). The result is
 * NON-SECRET — a service-account email is an identifier, not a credential.
 */
export async function resolveRuntimeServiceAccountEmail(): Promise<
  string | null
> {
  const fromEnv =
    asText(process.env.FUNCTION_IDENTITY) ??
    asText(process.env.SERVICE_ACCOUNT_EMAIL) ??
    asText(process.env.FIREBASE_SERVICE_ACCOUNT_EMAIL);
  if (fromEnv) return fromEnv;

  const url = `http://${metadataHost()}${METADATA_SA_EMAIL_PATH}`;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), METADATA_TIMEOUT_MS);
  try {
    const res = await fetch(url, {
      headers: { "Metadata-Flavor": "Google" },
      signal: controller.signal,
    });
    if (!res.ok) return null;
    const text = (await res.text()).trim();
    return text.length > 0 ? text : null;
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
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
      cloudRunService: asText(process.env.K_SERVICE),
    };
  } catch (err) {
    return {
      explicitCredential: false,
      credentialClass: "unresolved",
      source: "unknown",
      projectId: null,
      serviceAccount: null,
      cloudRunService: asText(process.env.K_SERVICE),
    };
  }
}
