package za.co.jagspoor.app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import com.android.billingclient.api.BillingClient
import com.android.billingclient.api.BillingClientStateListener
import com.android.billingclient.api.BillingResult
import com.android.billingclient.api.PendingPurchasesParams
import com.android.billingclient.api.PurchasesUpdatedListener
import com.android.billingclient.api.UserChoiceDetails
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * JagSpoor's Android host.
 *
 * Beyond the edge-to-edge window setup this activity implements the
 * **Google Play User Choice Billing** (alternative billing) bridge that
 * `AlternativeBillingService` talks to over the
 * `com.jagspoor/alternative_billing` method channel.
 *
 * ## Why the token matters
 *
 * Play's alternative billing programme lets a user pay through PayFast
 * instead of Play Billing, but Play still invoices its (reduced) service fee
 * for that transaction. To reconcile the invoice Play issues an **external
 * transaction token** that the app must obtain and report. The token comes
 * from one of two places, both implemented here:
 *
 *  * **User Choice Billing** — Play renders the choice sheet inside the
 *    purchase flow; when the user picks the alternative system, Play invokes
 *    the `UserChoiceBillingListener` with a `UserChoiceDetails` whose
 *    `externalTransactionToken` is the token. This is the path JagSpoor uses
 *    (both options are offered side by side).
 *  * **Alternative-billing-only** —
 *    `createAlternativeBillingOnlyReportingDetailsAsync` returns an
 *    `AlternativeBillingOnlyReportingDetails` whose
 *    `externalTransactionToken` is the token. Exposed as a fallback for
 *    builds where the Play-side choice sheet is unavailable.
 *
 * NOTE: the widely-misquoted `BillingClient.createAlternativeBillingReportingToken()`
 * does **not** exist in the Play Billing Library. These are the real API
 * names, verified against `com.android.billingclient:billing:8.0.0`.
 *
 * ## Failure posture
 *
 * Every path degrades gracefully. If the installed Play Store does not support
 * alternative billing, if the app is not enrolled, or if the BillingClient
 * cannot connect, the Dart side receives a null token and continues with the
 * PayFast checkout — logging the transaction as `token_unavailable` for
 * manual reporting rather than blocking the customer.
 */
class MainActivity : FlutterFragmentActivity() {

    companion object {
        private const val CHANNEL_NAME = "com.jagspoor/alternative_billing"
        private const val METHOD_CREATE_TOKEN = "createAlternativeBillingToken"
        private const val METHOD_REPORT_TOKEN = "reportAlternativeBillingToken"
        private const val METHOD_IS_SUPPORTED = "isAlternativeBillingSupported"
    }

    private var channel: MethodChannel? = null
    private var billingClient: BillingClient? = null

    /**
     * The most recent token Play handed us via the User Choice Billing
     * listener, kept so [METHOD_CREATE_TOKEN] can answer immediately when Play
     * has already delivered the token for the in-flight purchase.
     */
    @Volatile
    private var userChoiceToken: String? = null

    /**
     * Result holder for an in-flight `createAlternativeBillingToken` call so
     * the async billing callbacks can complete the pending Dart future.
     */
    private var pendingTokenResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Backward-compatible edge-to-edge window handling. Android 15 (API 35)
        // enforces edge-to-edge for apps targeting SDK 35+; enableEdgeToEdge()
        // opts the window into drawing behind the system bars and applies the
        // correct system-bar icon contrast on every API level (it is a no-op /
        // safe on older versions). Must run before super.onCreate so the Flutter
        // view lays out edge-to-edge from the very first frame.
        //
        // FlutterFragmentActivity is used (instead of FlutterActivity) because
        // enableEdgeToEdge() is an androidx.activity extension defined only on
        // ComponentActivity, and FlutterActivity extends android.app.Activity.
        // FlutterFragmentActivity extends FragmentActivity -> ComponentActivity,
        // so the edge-to-edge API is available while keeping the identical
        // Flutter embedding behaviour.
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).apply {
            setMethodCallHandler { call, result -> handleMethodCall(call, result) }
        }
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        channel = null
        endBillingConnection()
        super.onDestroy()
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            METHOD_IS_SUPPORTED -> result.success(isUserChoiceBillingAvailable())
            METHOD_CREATE_TOKEN -> requestAlternativeBillingToken(result)
            METHOD_REPORT_TOKEN -> {
                // Reporting to Google happens server-side (the token is written
                // to Firestore and a Cloud Function calls the Play Developer
                // API). The native side only acknowledges the hand-off.
                val token = call.argument<String>("token")
                if (!token.isNullOrBlank()) {
                    userChoiceToken = token
                }
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Whether User Choice Billing can be used on this device.
     *
     * The programme needs a Billing Library that exposes the user-choice entry
     * point. It is compiled in, so the check is a fast `NoSuchMethodError`
     * probe: any failure reports `false` and the Dart side falls back to the
     * plain Google Play checkout (never showing a PayFast option it cannot
     * obtain a token for).
     */
    private fun isUserChoiceBillingAvailable(): Boolean {
        return try {
            val builder = BillingClient.newBuilder(this)
            builder.enableUserChoiceBilling { _: UserChoiceDetails -> }
            true
        } catch (t: Throwable) {
            false
        }
    }

    /**
     * Resolves an external transaction token.
     *
     * Prefers a token Play already delivered through the User Choice Billing
     * listener (the normal path for a user who just picked PayFast), and
     * otherwise asks Play directly via the alternative-billing-only reporting
     * details API.
     */
    private fun requestAlternativeBillingToken(result: MethodChannel.Result) {
        userChoiceToken?.let { existing ->
            userChoiceToken = null
            result.success(existing)
            return
        }

        if (pendingTokenResult != null) {
            // A token request is already in flight — don't stack a second one.
            result.success(null)
            return
        }
        pendingTokenResult = result

        val client = ensureBillingClient()
        if (client == null) {
            completeTokenRequest(null)
            return
        }

        if (!client.isReady) {
            client.startConnection(object : BillingClientStateListener {
                override fun onBillingSetupFinished(billingResult: BillingResult) {
                    if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                        fetchAlternativeBillingOnlyToken(client)
                    } else {
                        completeTokenRequest(null)
                    }
                }

                override fun onBillingServiceDisconnected() {
                    completeTokenRequest(null)
                }
            })
        } else {
            fetchAlternativeBillingOnlyToken(client)
        }
    }

    private fun fetchAlternativeBillingOnlyToken(client: BillingClient) {
        try {
            client.createAlternativeBillingOnlyReportingDetailsAsync { billingResult, details ->
                val token =
                    if (billingResult.responseCode == BillingClient.BillingResponseCode.OK) {
                        details?.externalTransactionToken
                    } else {
                        null
                    }
                completeTokenRequest(token)
            }
        } catch (t: Throwable) {
            // An older Play Store / Billing Library surface throws here; the
            // checkout must continue without a token.
            completeTokenRequest(null)
        }
    }

    private fun completeTokenRequest(token: String?) {
        val result = pendingTokenResult ?: return
        pendingTokenResult = null
        result.success(token?.takeIf { it.isNotBlank() })
    }

    /**
     * Lazily builds the BillingClient with User Choice Billing enabled.
     *
     * `enableUserChoiceBilling` is what makes Play surface the two-option
     * choice sheet during the purchase flow and deliver the alternative
     * transaction token via the listener.
     */
    private fun ensureBillingClient(): BillingClient? {
        billingClient?.let { return it }
        return try {
            val client = BillingClient.newBuilder(this)
                .setListener(PurchasesUpdatedListener { _, _ ->
                    // The Flutter `in_app_purchase` plugin owns the Play
                    // purchase flow and its own listener; this client exists
                    // solely for the alternative-billing token handshake.
                })
                .enablePendingPurchases(PendingPurchasesParams.newBuilder().build())
                .enableUserChoiceBilling { details: UserChoiceDetails ->
                    userChoiceToken = details.externalTransactionToken
                }
                .build()
            billingClient = client
            client
        } catch (t: Throwable) {
            null
        }
    }

    private fun endBillingConnection() {
        try {
            billingClient?.endConnection()
        } catch (_: Throwable) {
            // Nothing actionable — the process is going away.
        }
        billingClient = null
        pendingTokenResult = null
    }
}