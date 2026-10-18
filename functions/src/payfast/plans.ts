/**
 * PayFast plan catalog for the web (non-Play) subscription checkout.
 *
 * The amounts here are the authoritative server-side charges — the client
 * NEVER sends an amount; it sends only `{role, planId, billingCycle}` and the
 * function resolves the price from this table. That prevents a client from
 * tampering with the amount it is charged.
 *
 * Prices are ZAR and VAT-inclusive (Option A: the listed price is the final
 * charge; 15% SA VAT is absorbed out of it).
 */

export type BillingCycle = "monthly" | "yearly";
export type BillingRole = "hunter" | "outfitter";

export interface PayFastPlan {
  /** Stable plan id, e.g. `hunter_monthly`. */
  planId: string;
  role: BillingRole;
  billingCycle: BillingCycle;
  /** ZAR amount (VAT inclusive) the customer is charged. */
  amountZar: number;
  /** Human-readable item name shown on the PayFast checkout. */
  itemName: string;
  /** How many months of entitlement a completed payment grants. */
  months: number;
}

/** The full plan catalog, keyed by plan id. */
export const PAYFAST_PLAN_CATALOG: Record<string, PayFastPlan> = {
  hunter_monthly: {
    planId: "hunter_monthly",
    role: "hunter",
    billingCycle: "monthly",
    amountZar: 34.99,
    itemName: "JagSpoor Hunter — Monthly",
    months: 1,
  },
  hunter_yearly: {
    planId: "hunter_yearly",
    role: "hunter",
    billingCycle: "yearly",
    amountZar: 349.99,
    itemName: "JagSpoor Hunter — Yearly",
    months: 12,
  },
  outfitter_monthly: {
    planId: "outfitter_monthly",
    role: "outfitter",
    billingCycle: "monthly",
    amountZar: 299.99,
    itemName: "JagSpoor Outfitter — Monthly",
    months: 1,
  },
  outfitter_yearly: {
    planId: "outfitter_yearly",
    role: "outfitter",
    billingCycle: "yearly",
    amountZar: 2999.99,
    itemName: "JagSpoor Outfitter — Yearly",
    months: 12,
  },
};

/**
 * Resolves a plan from the client's `{role, planId, billingCycle}` request.
 *
 * Precedence:
 *   1. an explicit, known `planId`;
 *   2. otherwise the plan for the `role` + `billingCycle` pair (defaulting the
 *      cycle to monthly).
 *
 * Returns null when the request cannot be resolved to a real plan, so the
 * caller rejects it instead of inventing a price.
 */
export function resolvePlan(input: {
  role?: string;
  planId?: string;
  billingCycle?: string;
}): PayFastPlan | null {
  const planId = (input.planId ?? "").toString().trim().toLowerCase();
  if (planId && PAYFAST_PLAN_CATALOG[planId]) {
    return PAYFAST_PLAN_CATALOG[planId];
  }
  const role = (input.role ?? "").toString().trim().toLowerCase();
  if (role !== "hunter" && role !== "outfitter") return null;
  const cycle: BillingCycle =
    (input.billingCycle ?? "").toString().trim().toLowerCase() === "yearly"
      ? "yearly"
      : "monthly";
  return PAYFAST_PLAN_CATALOG[`${role}_${cycle}`] ?? null;
}

/** All plans for a role (drives the role-filtered subscription UI). */
export function plansForRole(role: string): PayFastPlan[] {
  const normalized = (role ?? "").toString().trim().toLowerCase();
  return Object.values(PAYFAST_PLAN_CATALOG).filter(
    (p) => p.role === normalized
  );
}
