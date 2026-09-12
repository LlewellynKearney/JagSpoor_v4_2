package za.co.jagspoor.app

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
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
}