package com.resiclasia.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.net.wifi.WifiManager
import android.content.Context
import android.os.Build
import android.os.SystemClock
import android.os.Handler
import android.os.Looper
import android.net.wifi.WifiNetworkSpecifier
import android.view.WindowManager

class MainActivity : FlutterActivity() {
    private var callback: ConnectivityManager.NetworkCallback? = null
    private var lock: WifiManager.WifiLock? = null
    private var retained: Network? = null
    private var ssid: String? = null
    private var connectionRequest: ConnectivityManager.NetworkCallback? = null
    private var requestedCredentials: Pair<String, String>? = null
    private var requestedNetwork: Network? = null
    private var requestStarted = 0L
    private var automaticBlocked = false
    private val connectivity get() = getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "resiclasia/wifi").setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "conectar" -> {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) result.success(null)
                        else result.success(connectWifi(
                            call.argument<String>("ssid") ?: "",
                            call.argument<String>("password") ?: "",
                            call.argument<Boolean>("automatico") ?: false))
                    }
                    "retener" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        val requestedSsid = call.argument<String>("ssid")
                        if (!enabled) releaseRetention()
                        else if (callback == null || ssid != requestedSsid) {
                            releaseRetention()
                            ssid = requestedSsid
                            retainWifi()
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) { result.error("WIFI", e.message, null) }
        }
    }

    // Keep one local-only request alive. Recreating it on every heartbeat tears
    // down the AP connection and can repeatedly show Android's consent dialog.
    private fun connectWifi(name: String, password: String, automatic: Boolean): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return false
        val credentials = Pair(name, password)
        if (connectionRequest != null && requestedCredentials == credentials) {
            requestedNetwork?.let {
                connectivity.bindProcessToNetwork(it)
                return true
            }
            if (SystemClock.elapsedRealtime() - requestStarted < 45000L) return true
        }
        // First association needs the user's explicit action/Android consent.
        val preferences = getSharedPreferences("esp-wifi", Context.MODE_PRIVATE)
        if (automatic && (automaticBlocked || preferences.getString("approvedSsid", null) != name)) return false
        if (!automatic) automaticBlocked = false
        connectionRequest?.let { connectivity.unregisterNetworkCallback(it) }
        connectionRequest = null
        requestedNetwork = null
        requestedCredentials = credentials
        requestStarted = SystemClock.elapsedRealtime()
        val specifier = WifiNetworkSpecifier.Builder().setSsid(name)
            .setWpa2Passphrase(password).build()
        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            .setNetworkSpecifier(specifier).build()
        val observer = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (connectionRequest !== this) return
                requestedNetwork = network
                retained = network
                preferences.edit().putString("approvedSsid", name).apply()
                connectivity.bindProcessToNetwork(network)
            }
            override fun onLost(network: Network) {
                if (connectionRequest !== this) return
                if (requestedNetwork == network) requestedNetwork = null
                requestStarted = SystemClock.elapsedRealtime()
                if (connectivity.boundNetworkForProcess == network) connectivity.bindProcessToNetwork(null)
                // Do not unregister: Android can satisfy this request again
                // when the same ESP32 AP returns after a power interruption.
            }
            override fun onUnavailable() {
                if (connectionRequest !== this) return
                connectionRequest = null
                requestedNetwork = null
                requestedCredentials = null
                // A denial/unavailable response must not cause a dialog loop.
                automaticBlocked = true
            }
        }
        connectionRequest = observer
        try { connectivity.requestNetwork(request, observer, Handler(Looper.getMainLooper())) }
        catch (e: Exception) {
            connectionRequest = null
            requestedCredentials = null
            throw e
        }
        return true
    }

    override fun onResume() {
        super.onResume()
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }

    override fun onPause() {
        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        super.onPause()
    }

    @Suppress("DEPRECATION")
    private fun retainWifi() {
        val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        lock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "resiclasia:esp").apply {
            setReferenceCounted(false)
            acquire()
        }
        retained = connectivity.boundNetworkForProcess
        val observer = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                if (callback !== this) return
                // Never bind an unrelated Wi-Fi network. The connection plugin
                // owns its local-only NetworkRequest; we do not unregister it.
                val currentSsid = wifi.connectionInfo?.ssid?.trim('"')
                if (network == retained || network == connectivity.boundNetworkForProcess || (network == connectivity.activeNetwork && currentSsid == ssid)) {
                    retained = network
                    connectivity.bindProcessToNetwork(network)
                }
            }
            override fun onLost(network: Network) {
                if (callback !== this) return
                if (network == retained) {
                    if (connectivity.boundNetworkForProcess == network) connectivity.bindProcessToNetwork(null)
                    retained = null
                }
            }
        }
        callback = observer
        connectivity.registerNetworkCallback(NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .removeCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), observer, Handler(Looper.getMainLooper()))
    }

    private fun releaseRetention() {
        callback?.let {
            try { connectivity.unregisterNetworkCallback(it) }
            catch (_: IllegalArgumentException) { /* Registration may have failed. */ }
        }
        callback = null
        lock?.let { if (it.isHeld) it.release() }
        lock = null
        retained = null
        ssid = null
        // Keep the user's existing connection: turning off retention is not disconnect.
    }

    override fun onDestroy() {
        connectionRequest?.let {
            try { connectivity.unregisterNetworkCallback(it) }
            catch (_: IllegalArgumentException) { }
        }
        connectionRequest = null
        releaseRetention()
        super.onDestroy()
    }
}
