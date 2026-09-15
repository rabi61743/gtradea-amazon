package com.gtradea.gtradea_amazon

import android.content.res.Configuration
import android.graphics.drawable.ColorDrawable
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // The window shows through until Flutter paints its first frame. Left
        // to the manifest theme it follows only the device's dark mode, so a
        // shopper on a dark phone who is using the app in Light -- the default,
        // and so everyone who never opened the setting -- watched a dark window
        // for the whole engine and Dart start-up and then got a light app. That
        // is the "black screen" being reported.
        val saved = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
            .getString("flutter.gtradea_theme_mode", null)
        val deviceDark = (resources.configuration.uiMode and
            Configuration.UI_MODE_NIGHT_MASK) == Configuration.UI_MODE_NIGHT_YES
        val dark = when (saved) {
            "dark" -> true
            "system" -> deviceDark
            else -> false
        }

        // After `super`, not before. FlutterActivity swaps LaunchTheme for the
        // NormalTheme named in the manifest *inside* onCreate, and that swap
        // re-applies the theme's own windowBackground -- so a drawable set
        // ahead of it is overwritten and the window stayed dark anyway. This is
        // the last word on the colour, which is the point: it is the only one
        // of the three that knows what the app itself will paint.
        super.onCreate(savedInstanceState)

        // AppColors.backgroundDark and AppColors.backgroundLight.
        window.setBackgroundDrawable(
            ColorDrawable(if (dark) 0xFF1B2229.toInt() else 0xFFF3F2F2.toInt())
        )
    }
}
