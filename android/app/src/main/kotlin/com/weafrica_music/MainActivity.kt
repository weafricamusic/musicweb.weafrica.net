package com.weafrica_music

import android.app.Notification.AUDIO_ATTRIBUTES_DEFAULT
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.Bundle
import android.telephony.TelephonyManager
import android.view.LayoutInflater
import android.widget.Button
import android.widget.ImageView
import android.widget.TextView
import com.ryanheise.audioservice.AudioServiceActivity
import com.google.android.gms.ads.nativead.NativeAd
import com.google.android.gms.ads.nativead.NativeAdView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : AudioServiceActivity() {
	private var nativeAdFactory: WeAfricaNativeAdFactory? = null

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		createDefaultNotificationChannel()
	}

	override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
		// Some Activity base classes override configureFlutterEngine without
		// calling the FlutterActivity implementation that performs plugin
		// registration. Register explicitly to avoid MissingPluginException.
		super.configureFlutterEngine(flutterEngine)
		GeneratedPluginRegistrant.registerWith(flutterEngine)

		// Register a NativeAdFactory so Flutter NativeAd(factoryId: 'weafricaNative') can render.
		nativeAdFactory = WeAfricaNativeAdFactory(this)
		GoogleMobileAdsPlugin.registerNativeAdFactory(flutterEngine, "weafricaNative", nativeAdFactory)

		MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "weafrica/country").setMethodCallHandler { call, result ->
			if (call.method == "getCountryCode") {
				try {
					val tm = getSystemService(Context.TELEPHONY_SERVICE) as? TelephonyManager
					val sim = tm?.simCountryIso?.trim()?.uppercase()
					val net = tm?.networkCountryIso?.trim()?.uppercase()
					val out = when {
						!sim.isNullOrEmpty() -> sim
						!net.isNullOrEmpty() -> net
						else -> null
					}
					result.success(out)
				} catch (e: Exception) {
					result.success(null)
				}
			} else {
				result.notImplemented()
			}
		}
	}

	override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
		GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "weafricaNative")
		nativeAdFactory = null
		super.cleanUpFlutterEngine(flutterEngine)
	}

	private fun createDefaultNotificationChannel() {
		if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

		val manager = getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager ?: return
		val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
		val channel = NotificationChannel(
			"battle_challenges",
			"Battle Challenges",
			NotificationManager.IMPORTANCE_HIGH,
		).apply {
			description = "Battle invites and live challenge updates"
			enableVibration(true)
			vibrationPattern = longArrayOf(0, 300, 180, 300)
			enableLights(true)
			lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
			setSound(
				soundUri,
				AudioAttributes.Builder()
					.setUsage(AudioAttributes.USAGE_NOTIFICATION)
					.setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
					.build(),
			)
			setShowBadge(true)
		}

		manager.createNotificationChannel(channel)
	}
}

private class WeAfricaNativeAdFactory(private val context: Context) : GoogleMobileAdsPlugin.NativeAdFactory {
	override fun createNativeAd(nativeAd: NativeAd, customOptions: MutableMap<String, Any>?): NativeAdView {
		val inflater = LayoutInflater.from(context)
		val adView = inflater.inflate(R.layout.weafrica_native_ad, null) as NativeAdView

		val headlineView = adView.findViewById<TextView>(R.id.ad_headline)
		val bodyView = adView.findViewById<TextView>(R.id.ad_body)
		val iconView = adView.findViewById<ImageView>(R.id.ad_app_icon)
		val ctaView = adView.findViewById<Button>(R.id.ad_call_to_action)

		headlineView.text = nativeAd.headline
		adView.headlineView = headlineView

		val body = nativeAd.body
		if (body.isNullOrBlank()) {
			bodyView.visibility = android.view.View.GONE
		} else {
			bodyView.visibility = android.view.View.VISIBLE
			bodyView.text = body
			adView.bodyView = bodyView
		}

		val icon = nativeAd.icon
		if (icon?.drawable == null) {
			iconView.visibility = android.view.View.GONE
		} else {
			iconView.visibility = android.view.View.VISIBLE
			iconView.setImageDrawable(icon.drawable)
			adView.iconView = iconView
		}

		val cta = nativeAd.callToAction
		if (cta.isNullOrBlank()) {
			ctaView.visibility = android.view.View.GONE
		} else {
			ctaView.visibility = android.view.View.VISIBLE
			ctaView.text = cta
			ctaView.isClickable = false
			ctaView.isFocusable = false
			adView.callToActionView = ctaView
		}

		adView.setNativeAd(nativeAd)
		return adView
	}
}
