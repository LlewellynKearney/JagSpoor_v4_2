import { logger } from "firebase-functions/v2";
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { firestore } from "../firebase";

// ────────────────────────────────────────────────────────────────────────────
// Admin Portal KPIs (server-side)
//
// The Admin Portal's headline metrics are aggregated here rather than on the
// client. Two reasons:
//
//   1. Correctness. Several metrics span collections the client can only read
//      with party-scoped rules (`bookings`), and some (Auth user count,
//      distinct install devices) are not client-readable at all. Computing
//      them server-side with the Admin SDK removes the "shows 0 because the
//      query was denied" failure mode entirely.
//   2. Future-proofing. As the user base grows, a client that reads whole
//      collections to count them does not scale; the aggregate lives on the
//      server and is returned as one small payload.
//
// Authorization mirrors `isAdmin()` in firestore.rules: the `admin == true`
// custom claim, the bootstrap admin email allow-list, or `users/{uid}.role ==
// 'admin'`.
// ────────────────────────────────────────────────────────────────────────────

/** The bootstrap admin email allow-list (mirrors firestore.rules). */
export const ADMIN_EMAIL_ALLOW_LIST = ["admin@jag-spoor.co.za"];

/** Collection names the aggregation reads. */
export const USERS_COLLECTION = "users";
export const OUTFITTERS_COLLECTION = "outfitters";
export const PACKAGES_COLLECTION = "packages";
export const BOOKINGS_COLLECTION = "bookings";
export const TROPHY_STOCK_COLLECTION = "trophy_stock";
export const INSTALLS_COLLECTION = "installs";

/** Where the admin-configured subscription amounts live. */
export const ADMIN_PRICING_COLLECTION = "admin_config";
export const ADMIN_PRICING_DOC_ID = "pricing";

/** Booking statuses that count as an in-flight (active) booking. */
export const ACTIVE_BOOKING_STATUSES = [
  "pending approval",
  "awaiting payment",
  "confirmed",
];

/** Booking statuses that count as delivered / completed. */
export const COMPLETED_BOOKING_STATUSES = ["completed"];

/** Booking statuses that represent realized revenue (payment verified). */
export const EARNED_BOOKING_STATUSES = ["confirmed", "completed"];

/** Billing platform vocabulary shared with the entitlement module. */
export const PLATFORM_GOOGLE_PLAY = "google_play";
export const PLATFORM_PAYFAST = "payfast";
export const PLATFORM_PAYFAST_ALTERNATIVE = "payfast_alternative";

/** Page size for the bounded collection scans. */
export const SCAN_PAGE_SIZE = 500;

/** Hard cap on scanned documents per collection (keeps the function bounded). */
export const SCAN_MAX_DOCUMENTS = 20000;

export interface AdminKpis {
  totalInstalls: number;
  installsSource: "installs" | "authUsers";
  registeredUsers: number;
  totalSubscribers: number;
  payfastSubscribers: number;
  googleSubscribers: number;
  totalHunters: number;
  totalOutfitters: number;
  totalPackages: number;
  listedPackages: number;
  activeBookings: number;
  completedBookings: number;
  totalTrophies: number;
  financial: {
    daily: number;
    weekly: number;
    monthly: number;
    yearly: number;
    mrr: number;
    arr: number;
    hunterSubscribers: number;
    outfitterSubscribers: number;
    hunterPrice: number;
    outfitterPrice: number;
  };
  generatedAt: string;
}

// ── Pure helpers (unit-tested without Firestore) ─────────────────────────────

/** Normalizes a raw platform / source string to the canonical platform. */
export function platformOf(
  data: Record<string, unknown> | undefined | null
): string | null {
  if (!data) return null;
  const raw = (data["subscriptionPlatform"] ?? data["subscriptionSource"] ?? "")
    .toString()
    .trim()
    .toLowerCase();
  if (!raw) return null;
  if (raw === PLATFORM_GOOGLE_PLAY || raw.startsWith("google_play")) {
    return PLATFORM_GOOGLE_PLAY;
  }
  if (
    raw === PLATFORM_PAYFAST_ALTERNATIVE ||
    raw.startsWith("payfast_alternative")
  ) {
    return PLATFORM_PAYFAST_ALTERNATIVE;
  }
  if (raw === PLATFORM_PAYFAST || raw.startsWith("payfast")) {
    return PLATFORM_PAYFAST;
  }
  return null;
}

/** Converts a Firestore timestamp-ish value to a `Date`, else null. */
export function toDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof Date) return value;
  const maybe = value as { toDate?: () => Date };
  if (typeof maybe.toDate === "function") {
    try {
      return maybe.toDate();
    } catch {
      return null;
    }
  }
  if (typeof value === "string" || typeof value === "number") {
    const parsed = new Date(value as string | number);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

/**
 * Whether a `users/{uid}` document represents an ACTIVE subscriber.
 *
 * A subscription is active when the canonical `subscriptionStatus` reads
 * `active`, or the nested `subscription` mirror says `isActive`, or the
 * legacy `isPremium` flag is set with a future `premiumExpiry`. A trial is
 * deliberately NOT a subscription — a trialing account has not been charged.
 */
export function isActiveSubscription(
  data: Record<string, unknown> | undefined | null,
  now: Date = new Date()
): boolean {
  if (!data) return false;

  const status = (data["subscriptionStatus"] ?? "").toString().trim().toLowerCase();
  if (status === "active" || status === "subscribed" || status === "premium") {
    return true;
  }

  const nested = data["subscription"];
  if (nested && typeof nested === "object") {
    const map = nested as Record<string, unknown>;
    if (map["isActive"] === true) return true;
    const nestedStatus = (map["status"] ?? "").toString().trim().toLowerCase();
    if (nestedStatus === "active") return true;
  }

  const expiry = toDate(data["premiumExpiry"]);
  if (
    data["isPremium"] === true &&
    expiry !== null &&
    expiry.getTime() > now.getTime()
  ) {
    return true;
  }

  return false;
}

/** The billing tier of a subscriber (`hunter` / `outfitter`), default hunter. */
export function tierOf(data: Record<string, unknown> | undefined | null): string {
  const raw = (data?.["subscriptionTier"] ?? data?.["subscriptionProduct"] ?? "")
    .toString()
    .trim()
    .toLowerCase();
  if (raw.includes("outfitter")) return "outfitter";
  return "hunter";
}

/** Booking revenue in ZAR, tolerating the historical field spellings. */
export function bookingRevenueOf(
  data: Record<string, unknown> | undefined | null
): number {
  if (!data) return 0;
  const candidates = [
    data["totalHunterPriceRands"],
    data["totalPriceZAR"],
    data["basePriceRands"],
  ];
  for (const value of candidates) {
    const num = typeof value === "number" ? value : Number(value);
    if (Number.isFinite(num)) return num;
  }
  return 0;
}

/** Booking timestamp used for the financial windows. */
export function bookingDateOf(
  data: Record<string, unknown> | undefined | null
): Date | null {
  if (!data) return null;
  return toDate(data["bookingTimestamp"]) ?? toDate(data["createdAt"]);
}

export interface UserKpiAggregate {
  registeredUsers: number;
  totalHunters: number;
  totalOutfitters: number;
  totalSubscribers: number;
  payfastSubscribers: number;
  googleSubscribers: number;
  hunterSubscribers: number;
  outfitterSubscribers: number;
  distinctDevices: number;
}

/**
 * Aggregates the per-user KPIs from a list of `users/{uid}` documents.
 *
 * Hunters and outfitters are counted from the stored `role` (the same field
 * role selection writes). Subscribers are counted from the entitlement fields,
 * split by billing platform so the Play-vs-PayFast mix is visible.
 */
export function aggregateUserKpis(
  users: Array<Record<string, unknown>>,
  now: Date = new Date()
): UserKpiAggregate {
  let totalHunters = 0;
  let totalOutfitters = 0;
  let totalSubscribers = 0;
  let payfastSubscribers = 0;
  let googleSubscribers = 0;
  let hunterSubscribers = 0;
  let outfitterSubscribers = 0;
  const devices = new Set<string>();

  for (const user of users) {
    const role = (user["role"] ?? "").toString().trim().toLowerCase();
    if (role === "hunter") totalHunters += 1;
    if (role === "outfitter") totalOutfitters += 1;

    const fingerprint = (user["deviceFingerprint"] ?? "").toString().trim();
    if (fingerprint) devices.add(fingerprint);

    if (isActiveSubscription(user, now)) {
      totalSubscribers += 1;
      const platform = platformOf(user);
      if (platform === PLATFORM_GOOGLE_PLAY) {
        googleSubscribers += 1;
      } else if (
        platform === PLATFORM_PAYFAST ||
        platform === PLATFORM_PAYFAST_ALTERNATIVE
      ) {
        payfastSubscribers += 1;
      }
      if (tierOf(user) === "outfitter") {
        outfitterSubscribers += 1;
      } else {
        hunterSubscribers += 1;
      }
    }
  }

  return {
    registeredUsers: users.length,
    totalHunters,
    totalOutfitters,
    totalSubscribers,
    payfastSubscribers,
    googleSubscribers,
    hunterSubscribers,
    outfitterSubscribers,
    distinctDevices: devices.size,
  };
}

export interface BookingKpiAggregate {
  activeBookings: number;
  completedBookings: number;
  daily: number;
  weekly: number;
  monthly: number;
  yearly: number;
}

/**
 * Aggregates booking counts + the revenue windows from a list of booking
 * documents. Revenue counts ONLY realized (earned) bookings — a booking whose
 * payment has not been verified is not revenue.
 */
export function aggregateBookingKpis(
  bookings: Array<Record<string, unknown>>,
  now: Date = new Date()
): BookingKpiAggregate {
  let activeBookings = 0;
  let completedBookings = 0;
  let daily = 0;
  let weekly = 0;
  let monthly = 0;
  let yearly = 0;

  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const weekStart = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000);
  const monthStart = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000);
  const yearStart = new Date(now.getTime() - 365 * 24 * 60 * 60 * 1000);

  for (const booking of bookings) {
    const status = (booking["status"] ?? "").toString().trim().toLowerCase();

    if (ACTIVE_BOOKING_STATUSES.includes(status)) activeBookings += 1;
    if (COMPLETED_BOOKING_STATUSES.includes(status)) completedBookings += 1;

    if (!EARNED_BOOKING_STATUSES.includes(status)) continue;
    const date = bookingDateOf(booking);
    if (date === null) continue;
    const revenue = bookingRevenueOf(booking);
    if (revenue === 0) continue;

    if (date >= startOfToday && date <= now) daily += revenue;
    if (date >= weekStart && date <= now) weekly += revenue;
    if (date >= monthStart && date <= now) monthly += revenue;
    if (date >= yearStart && date <= now) yearly += revenue;
  }

  return {
    activeBookings,
    completedBookings,
    // Round to cents — money must not carry binary floating-point noise.
    daily: Math.round(daily * 100) / 100,
    weekly: Math.round(weekly * 100) / 100,
    monthly: Math.round(monthly * 100) / 100,
    yearly: Math.round(yearly * 100) / 100,
  };
}

/** Monthly recurring revenue from the active subscriber mix. */
export function computeMrr(
  hunterSubscribers: number,
  outfitterSubscribers: number,
  hunterPrice: number,
  outfitterPrice: number
): number {
  const h = Number.isFinite(hunterPrice) ? Math.max(0, hunterPrice) : 0;
  const o = Number.isFinite(outfitterPrice) ? Math.max(0, outfitterPrice) : 0;
  const total = hunterSubscribers * h + outfitterSubscribers * o;
  // Round to cents — money must not carry binary floating-point noise
  // (14 × 34.99 + 2 × 299.99 is 1089.8400000000001 unrounded).
  return Math.round(total * 100) / 100;
}

/** The configured hunter / outfitter monthly amounts from `admin_config/pricing`. */
export function pricingFromConfig(
  data: Record<string, unknown> | undefined | null
): { hunterPrice: number; outfitterPrice: number } {
  const read = (keys: string[]): number => {
    if (!data) return 0;
    for (const key of keys) {
      const num = Number(data[key]);
      if (Number.isFinite(num) && num > 0) return num;
    }
    return 0;
  };
  return {
    hunterPrice: read([
      "hunter_monthly",
      "hunter_price_incl",
      "hunterSubscriptionZAR",
    ]),
    outfitterPrice: read([
      "outfitter_monthly",
      "outfitter_price_incl",
      "outfitterSubscriptionZAR",
    ]),
  };
}

/**
 * Resolves the "total installs" figure.
 *
 * A dedicated `installs` collection is the authoritative source when it has
 * rows (a future client-side install beacon writes there). Until then the
 * count of registered accounts is the honest proxy — an account is created by
 * an install — and the payload records which source was used so the UI can
 * label it.
 */
export function resolveInstalls(
  installCount: number,
  authUserCount: number
): { totalInstalls: number; installsSource: "installs" | "authUsers" } {
  if (installCount > 0) {
    return { totalInstalls: installCount, installsSource: "installs" };
  }
  return { totalInstalls: authUserCount, installsSource: "authUsers" };
}

/** Whether a callable request's auth context is a platform admin. */
export function isAdminRequest(
  auth: { token?: Record<string, unknown>; uid?: string } | undefined | null,
  usersDocRole?: string | null
): boolean {
  if (!auth || !auth.uid) return false;
  const token = auth.token ?? {};
  if (token["admin"] === true) return true;
  const email = (token["email"] ?? "").toString().trim().toLowerCase();
  if (ADMIN_EMAIL_ALLOW_LIST.includes(email)) return true;
  if ((usersDocRole ?? "").toString().trim().toLowerCase() === "admin") return true;
  return false;
}

// ── Firestore reads ─────────────────────────────────────────────────────────

/**
 * Reads every document of a collection in bounded pages. Never throws for a
 * single page failure — it returns whatever was collected so far, so one
 * unreadable page degrades the metric rather than failing the whole call.
 */
async function scanCollection(
  path: string
): Promise<Array<Record<string, unknown>>> {
  const docs: Array<Record<string, unknown>> = [];
  let lastId: string | null = null;
  try {
    for (;;) {
      let query = firestore()
        .collection(path)
        .orderBy("__name__")
        .limit(SCAN_PAGE_SIZE);
      if (lastId !== null) query = query.startAfter(lastId);
      const snap = await query.get();
      if (snap.empty) break;
      for (const doc of snap.docs) {
        docs.push(doc.data() as Record<string, unknown>);
      }
      lastId = snap.docs[snap.docs.length - 1].id;
      if (snap.size < SCAN_PAGE_SIZE) break;
      if (docs.length >= SCAN_MAX_DOCUMENTS) {
        logger.warn("scanCollection: document cap reached", {
          path,
          docs: docs.length,
        });
        break;
      }
    }
  } catch (err) {
    logger.warn("scanCollection failed (partial result returned)", {
      path,
      collected: docs.length,
      error: err instanceof Error ? err.message : String(err),
    });
  }
  return docs;
}

/** Total number of Firebase Auth users, bounded to avoid a runaway listing. */
export async function countAuthUsers(maxPages = 40): Promise<number> {
  try {
    const { auth } = await import("../firebase");
    let total = 0;
    let pageToken: string | undefined;
    for (let page = 0; page < maxPages; page += 1) {
      const result = await auth().listUsers(1000, pageToken);
      total += result.users.length;
      pageToken = result.pageToken;
      if (!pageToken) break;
    }
    return total;
  } catch (err) {
    logger.warn("countAuthUsers failed", {
      error: err instanceof Error ? err.message : String(err),
    });
    return 0;
  }
}

// ── Callable ────────────────────────────────────────────────────────────────

/**
 * getAdminPortalKpis
 *
 * Callable Cloud Function (us-central1). Admin-only. Returns the Admin Portal
 * headline KPIs (installs, subscribers by platform, hunters, outfitters,
 * packages, bookings, trophies, revenue windows + MRR) as one payload.
 */
export const getAdminPortalKpis = onCall(
  { region: "us-central1", maxInstances: 10 },
  async (req: CallableRequest): Promise<AdminKpis> => {
    const auth = req.auth;
    if (!auth || !auth.uid) {
      throw new HttpsError("unauthenticated", "Login required.");
    }

    // Admin check — the claim / allow-list paths first, then the users doc
    // fallback (mirrors `isAdmin()` in firestore.rules).
    let usersDocRole: string | null = null;
    try {
      const callerDoc = await firestore()
        .collection(USERS_COLLECTION)
        .doc(auth.uid)
        .get();
      usersDocRole = ((callerDoc.data() ?? {})["role"] ?? "").toString();
    } catch {
      // The users doc may be unreadable; the token paths still decide.
    }
    if (!isAdminRequest(auth, usersDocRole)) {
      throw new HttpsError(
        "permission-denied",
        "Admin privileges are required to read the portal KPIs."
      );
    }

    const now = new Date();

    const [users, outfitters, packages, bookings, trophies, installs] =
      await Promise.all([
        scanCollection(USERS_COLLECTION),
        scanCollection(OUTFITTERS_COLLECTION),
        scanCollection(PACKAGES_COLLECTION),
        scanCollection(BOOKINGS_COLLECTION),
        scanCollection(TROPHY_STOCK_COLLECTION),
        scanCollection(INSTALLS_COLLECTION),
      ]);

    const userAgg = aggregateUserKpis(users, now);

    // Outfitters are the union of `users.role == 'outfitter'` (self-registered)
    // and the `outfitters` collection (admin-provisioned). Both are keyed by
    // uid so the two sets union without double-counting.
    const outfitterIds = new Set<string>();
    for (const user of users) {
      if ((user["role"] ?? "").toString().trim().toLowerCase() === "outfitter") {
        const uid = (user["uid"] ?? "").toString();
        if (uid) outfitterIds.add(uid);
      }
    }
    for (const outfitter of outfitters) {
      const uid = (outfitter["uid"] ?? "").toString();
      if (uid) outfitterIds.add(uid);
    }
    const totalOutfitters = Math.max(userAgg.totalOutfitters, outfitterIds.size);

    const bookingAgg = aggregateBookingKpis(bookings, now);

    const listedPackages = packages.filter(
      (p) => (p["status"] ?? "").toString().trim().toLowerCase() === "active"
    ).length;

    let pricing: { hunterPrice: number; outfitterPrice: number } = {
      hunterPrice: 0,
      outfitterPrice: 0,
    };
    try {
      const pricingSnap = await firestore()
        .collection(ADMIN_PRICING_COLLECTION)
        .doc(ADMIN_PRICING_DOC_ID)
        .get();
      pricing = pricingFromConfig(pricingSnap.data());
    } catch (err) {
      logger.warn("getAdminPortalKpis: pricing config unreadable", {
        error: err instanceof Error ? err.message : String(err),
      });
    }

    const authUserCount = await countAuthUsers();
    const installsResolved = resolveInstalls(
      installs.length,
      Math.max(authUserCount, users.length)
    );

    const mrr = computeMrr(
      userAgg.hunterSubscribers,
      userAgg.outfitterSubscribers,
      pricing.hunterPrice,
      pricing.outfitterPrice
    );

    const kpis: AdminKpis = {
      totalInstalls: installsResolved.totalInstalls,
      installsSource: installsResolved.installsSource,
      registeredUsers: userAgg.registeredUsers,
      totalSubscribers: userAgg.totalSubscribers,
      payfastSubscribers: userAgg.payfastSubscribers,
      googleSubscribers: userAgg.googleSubscribers,
      totalHunters: userAgg.totalHunters,
      totalOutfitters,
      totalPackages: packages.length,
      listedPackages,
      activeBookings: bookingAgg.activeBookings,
      completedBookings: bookingAgg.completedBookings,
      totalTrophies: trophies.length,
      financial: {
        daily: bookingAgg.daily,
        weekly: bookingAgg.weekly,
        monthly: bookingAgg.monthly,
        yearly: bookingAgg.yearly,
        mrr,
        arr: mrr * 12,
        hunterSubscribers: userAgg.hunterSubscribers,
        outfitterSubscribers: userAgg.outfitterSubscribers,
        hunterPrice: pricing.hunterPrice,
        outfitterPrice: pricing.outfitterPrice,
      },
      generatedAt: now.toISOString(),
    };

    logger.info("getAdminPortalKpis served", {
      uid: auth.uid,
      registeredUsers: kpis.registeredUsers,
      totalSubscribers: kpis.totalSubscribers,
    });

    return kpis;
  }
);
