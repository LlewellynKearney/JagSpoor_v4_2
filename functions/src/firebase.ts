import * as admin from "firebase-admin";

/**
 * Singleton Firebase Admin SDK initialization.
 *
 * In the Cloud Functions runtime the SDK is auto-initialized via the
 * service-account-impersonation provided by the functions environment, so
 * `applicationDefault()` resolves correctly. For local emulator testing,
 * set GOOGLE_APPLICATION_CREDENTIALS to a service account JSON.
 */
let app: admin.app.App | null = null;

export function getAdmin(): admin.app.App {
  if (app) return app;
  if (admin.apps.length > 0) {
    app = admin.app();
  } else {
    app = admin.initializeApp({ credential: admin.credential.applicationDefault() });
  }
  return app;
}

export const firestore = (): admin.firestore.Firestore =>
  getAdmin().firestore();

export const auth = (): admin.auth.Auth => getAdmin().auth();
