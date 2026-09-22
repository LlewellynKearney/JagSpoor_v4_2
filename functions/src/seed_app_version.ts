/**
 * One-time seed for the v9 forced-update control-plane doc.
 *
 * Writes `admin_config/app_version`:
 *   {
 *     min_required_version: 9,
 *     latest_version: 9,
 *     force_update: true,
 *     force_update_message: "New JagSpoor update required - billing fix for
 *                            Hunters & Outfitters (v9). Please update to
 *                            continue.",
 *     updated_at: <server timestamp>
 *   }
 *
 * The read side is `lib/services/app_version_check.dart`, which blocks the
 * splash screen and routes the user to the Play listing when the installed
 * Android `versionCode` is below `min_required_version` and `force_update` is
 * true.
 *
 * This module is intentionally NOT exported from `src/index.ts`: it is a
 * standalone operator script, not a deployed Cloud Function.
 *
 * Run it (requires a credentialed environment — Application Default
 * Credentials or GOOGLE_APPLICATION_CREDENTIALS pointing at a service account
 * with the `clouddatastore.user` / Firebase Admin role):
 *
 *   cd functions
 *   npm run build
 *   SEED_CONFIRM=yes node lib/seed_app_version.js
 *
 * The SEED_CONFIRM guard is deliberate: writing `admin_config/app_version`
 * with `force_update: true` blocks every installed build below the floor, so
 * it must never run implicitly (e.g. as part of a deploy).
 */

import { initializeApp, getApps } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";

/** Version floor written by this seed (the v9 build / versionCode 9). */
export const APP_VERSION_MIN_REQUIRED = 9;

/** Human-readable latest version. */
export const APP_VERSION_LATEST = 9;

/** Message shown in the non-dismissible "Update Required" dialog. */
export const APP_VERSION_FORCE_MESSAGE =
  "New JagSpoor update required - billing fix for Hunters & Outfitters (v9). " +
  "Please update to continue.";

/** Control-plane doc path read by the app. */
export const APP_VERSION_DOC_PATH = "admin_config/app_version";

/** The document payload (without the server timestamp). */
export function appVersionSeedPayload(): Record<string, unknown> {
  return {
    min_required_version: APP_VERSION_MIN_REQUIRED,
    latest_version: APP_VERSION_LATEST,
    force_update: true,
    force_update_message: APP_VERSION_FORCE_MESSAGE,
  };
}

/**
 * Writes the control-plane doc. Returns the path that was written.
 * Exported so an operator can also call it from a REPL / another script.
 */
export async function seedAppVersionDoc(): Promise<string> {
  if (getApps().length === 0) {
    initializeApp();
  }
  await getFirestore()
    .doc(APP_VERSION_DOC_PATH)
    .set(
      {
        ...appVersionSeedPayload(),
        updated_at: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  return APP_VERSION_DOC_PATH;
}

/**
 * CLI entry point. Guarded by SEED_CONFIRM so an accidental
 * `node lib/seed_app_version.js` (or a build hook) cannot flip the kill switch
 * on for every user.
 */
async function main(): Promise<void> {
  if (process.env.SEED_CONFIRM !== "yes") {
    console.log(
      "Refusing to write. Re-run with SEED_CONFIRM=yes to arm the " +
        "forced-update kill switch for builds below versionCode " +
        `${APP_VERSION_MIN_REQUIRED}.`,
    );
    console.log("Payload that WOULD be written:");
    console.log(JSON.stringify(appVersionSeedPayload(), null, 2));
    return;
  }
  const path = await seedAppVersionDoc();
  console.log(`Wrote ${path}`);
}

if (require.main === module) {
  main().catch((err) => {
    console.error("seed_app_version failed:", err);
    process.exitCode = 1;
  });
}
