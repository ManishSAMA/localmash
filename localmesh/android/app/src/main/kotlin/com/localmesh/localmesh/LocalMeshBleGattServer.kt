package com.localmesh.localmesh

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothGattServer
import android.bluetooth.BluetoothGattServerCallback
import android.bluetooth.BluetoothGattService
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.CompletableFuture
import java.util.concurrent.TimeUnit

class LocalMeshBleGattServer(private val context: Context) :
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val METHOD_CHANNEL = "localmesh/ble_gatt_server/methods"
        private const val EVENT_CHANNEL = "localmesh/ble_gatt_server/events"

        private const val SERVICE_UUID = "6e400001-b5a3-f393-e0a9-e50e24dcca9e"
        private const val TX_CHAR_UUID = "6e400002-b5a3-f393-e0a9-e50e24dcca9e"
        private const val RX_CHAR_UUID = "6e400003-b5a3-f393-e0a9-e50e24dcca9e"
        private const val CCC_DESCRIPTOR_UUID = "00002902-0000-1000-8000-00805f9b34fb"
    }

    private val bluetoothManager =
        context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
    private val adapter: BluetoothAdapter? = bluetoothManager.adapter
    private val advertiser: BluetoothLeAdvertiser?
        get() = adapter?.bluetoothLeAdvertiser

    // All EventSink.success() calls must run on the Android main thread;
    // BluetoothGattServerCallback fires on the Binder thread pool.
    private val mainHandler = Handler(Looper.getMainLooper())

    private var gattServer: BluetoothGattServer? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var rxCharacteristic: BluetoothGattCharacteristic? = null
    private val connectedDevices = linkedMapOf<String, BluetoothDevice>()
    private val subscribedDevices = linkedSetOf<String>()
    private var eventSink: EventChannel.EventSink? = null

    // Stores the human-readable reason for the last start() failure.
    private var lastStartError: String? = null

    // Bridges the async onServiceAdded() callback into openGattServer().
    private var serviceAddedFuture: CompletableFuture<Boolean>? = null

    fun attach(binaryMessenger: BinaryMessenger) {
        MethodChannel(binaryMessenger, METHOD_CHANNEL).setMethodCallHandler(this)
        EventChannel(binaryMessenger, EVENT_CHANNEL).setStreamHandler(this)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val localName = call.argument<String>("localName") ?: "LocalMesh"
                result.success(start(localName))
            }

            "stop" -> {
                stop()
                result.success(null)
            }

            "notifyPeer" -> {
                val peerId = call.argument<String>("peerId")
                val data = call.argument<ByteArray>("data")
                if (peerId == null || data == null) {
                    result.success(false)
                } else {
                    result.success(notifyPeer(peerId, data))
                }
            }

            else -> result.notImplemented()
        }
    }

    // Returns a Map<String, Any?> so the Dart side can show a specific failure reason.
    // {"success": true, "error": null} on success.
    // {"success": false, "error": "<reason>"} on failure.
    private fun start(localName: String): Map<String, Any?> {
        lastStartError = null

        if (!hasRequiredPermissions()) {
            val msg = "Missing Bluetooth permissions (BLUETOOTH_CONNECT or BLUETOOTH_ADVERTISE)"
            emitLog("cannot start GATT server: $msg")
            return mapOf("success" to false, "error" to msg)
        }
        if (adapter == null || adapter?.isEnabled != true) {
            val msg = "Bluetooth is disabled — please enable Bluetooth and try again"
            emitLog("cannot start GATT server: $msg")
            return mapOf("success" to false, "error" to msg)
        }
        if (advertiser == null) {
            val msg = "BLE advertising not supported on this device"
            emitLog("cannot start GATT server: $msg")
            return mapOf("success" to false, "error" to msg)
        }

        stop()

        if (!openGattServer()) {
            return mapOf("success" to false, "error" to (lastStartError ?: "Failed to open GATT server"))
        }
        if (!startAdvertising(localName)) {
            return mapOf("success" to false, "error" to (lastStartError ?: "Failed to start BLE advertising"))
        }
        return mapOf("success" to true, "error" to null)
    }

    private fun stop() {
        advertiseCallback?.let { advertiser?.stopAdvertising(it) }
        advertiseCallback = null
        serviceAddedFuture?.cancel(true)
        serviceAddedFuture = null
        gattServer?.close()
        gattServer = null
        rxCharacteristic = null
        connectedDevices.clear()
        subscribedDevices.clear()
    }

    @SuppressLint("MissingPermission")
    private fun openGattServer(): Boolean {
        val txCharacteristic = BluetoothGattCharacteristic(
            UUID.fromString(TX_CHAR_UUID),
            BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE,
            BluetoothGattCharacteristic.PERMISSION_WRITE
        )

        val rx = BluetoothGattCharacteristic(
            UUID.fromString(RX_CHAR_UUID),
            BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_READ,
            BluetoothGattCharacteristic.PERMISSION_READ
        )
        rx.addDescriptor(
            BluetoothGattDescriptor(
                UUID.fromString(CCC_DESCRIPTOR_UUID),
                BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE
            )
        )
        rxCharacteristic = rx

        val service = BluetoothGattService(
            UUID.fromString(SERVICE_UUID),
            BluetoothGattService.SERVICE_TYPE_PRIMARY
        )
        service.addCharacteristic(txCharacteristic)
        service.addCharacteristic(rx)

        val server = bluetoothManager.openGattServer(context, gattServerCallback)
        if (server == null) {
            lastStartError = "bluetoothManager.openGattServer() returned null"
            emitLog("failed to open Android BluetoothGattServer")
            return false
        }

        // Prepare the future BEFORE addService() to avoid a race where onServiceAdded
        // fires before the field is assigned.
        val future = CompletableFuture<Boolean>()
        serviceAddedFuture = future

        val queued = server.addService(service)
        if (!queued) {
            lastStartError = "server.addService() returned false for $SERVICE_UUID"
            emitLog("failed to enqueue GATT service $SERVICE_UUID")
            server.close()
            serviceAddedFuture = null
            return false
        }

        // Block until onServiceAdded() confirms (or 3s timeout as safety valve).
        // This runs on the Flutter method-channel background thread — safe to block.
        val added = try {
            future.get(3, TimeUnit.SECONDS)
        } catch (e: Exception) {
            lastStartError = "onServiceAdded timed out or threw: ${e.message}"
            emitLog("onServiceAdded timed out: ${e.message}")
            false
        } finally {
            serviceAddedFuture = null
        }

        if (!added) {
            lastStartError = lastStartError ?: "GATT service registration failed in onServiceAdded"
            server.close()
            return false
        }

        gattServer = server
        emitLog("GATT service $SERVICE_UUID registered")
        return true
    }

    @SuppressLint("MissingPermission")
    private fun startAdvertising(localName: String): Boolean {
        adapter?.name = localName

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setConnectable(true)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .build()

        // Primary ad packet: service UUID only (device name in scan response to stay under 31B).
        val primaryData = AdvertiseData.Builder()
            .addServiceUuid(ParcelUuid(UUID.fromString(SERVICE_UUID)))
            .setIncludeTxPowerLevel(false)
            .build()

        val scanResponse = AdvertiseData.Builder()
            .setIncludeDeviceName(true)
            .build()

        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings) {
                emitLog("BLE advertising started for $SERVICE_UUID")
                emitAdvertiseResult(success = true)
            }

            override fun onStartFailure(errorCode: Int) {
                lastStartError = "BLE advertising failed with errorCode=$errorCode"
                emitLog("BLE advertising failed with code=$errorCode")
                emitAdvertiseResult(success = false, errorCode = errorCode)
            }
        }

        return try {
            advertiser?.startAdvertising(settings, primaryData, scanResponse, callback)
            advertiseCallback = callback
            true
        } catch (t: Throwable) {
            lastStartError = "startAdvertising threw: ${t.message}"
            emitLog("BLE advertising threw ${t.message}")
            false
        }
    }

    private fun emitAdvertiseResult(success: Boolean, errorCode: Int = 0) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to if (success) "advertiseStarted" else "advertiseError",
                    "peerId" to "",
                    "message" to "errorCode=$errorCode",
                )
            )
        }
    }

    @SuppressLint("MissingPermission")
    private fun notifyPeer(peerId: String, data: ByteArray): Boolean {
        val server = gattServer ?: return false
        val characteristic = rxCharacteristic ?: return false
        val device = connectedDevices[peerId] ?: return false
        if (!subscribedDevices.contains(peerId)) {
            emitLog("notify skipped for $peerId: notifications not enabled")
            return false
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            server.notifyCharacteristicChanged(device, characteristic, false, data) == BluetoothStatusCodes.SUCCESS
        } else {
            characteristic.value = data
            server.notifyCharacteristicChanged(device, characteristic, false)
        }
    }

    private val gattServerCallback = object : BluetoothGattServerCallback() {
        override fun onServiceAdded(status: Int, service: BluetoothGattService?) {
            val success = (status == BluetoothGatt.GATT_SUCCESS)
            emitLog("onServiceAdded status=$status success=$success")
            serviceAddedFuture?.complete(success)
        }

        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            val peerId = device.address
            when (newState) {
                BluetoothGatt.STATE_CONNECTED -> {
                    connectedDevices[peerId] = device
                    emitPeerEvent("peerConnected", device)
                }

                BluetoothGatt.STATE_DISCONNECTED -> {
                    connectedDevices.remove(peerId)
                    subscribedDevices.remove(peerId)
                    emitPeerEvent("peerDisconnected", device)
                }
            }
        }

        override fun onCharacteristicWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            characteristic: BluetoothGattCharacteristic,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (characteristic.uuid == UUID.fromString(TX_CHAR_UUID)) {
                emitDataEvent(device, value)
            }
            if (responseNeeded && hasRequiredPermissions()) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, null)
            }
        }

        override fun onDescriptorWriteRequest(
            device: BluetoothDevice,
            requestId: Int,
            descriptor: BluetoothGattDescriptor,
            preparedWrite: Boolean,
            responseNeeded: Boolean,
            offset: Int,
            value: ByteArray
        ) {
            if (descriptor.uuid == UUID.fromString(CCC_DESCRIPTOR_UUID)) {
                val peerId = device.address
                if (value.contentEquals(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE)) {
                    subscribedDevices.add(peerId)
                    emitLog("notifications enabled for $peerId")
                } else if (value.contentEquals(BluetoothGattDescriptor.DISABLE_NOTIFICATION_VALUE)) {
                    subscribedDevices.remove(peerId)
                    emitLog("notifications disabled for $peerId")
                }
            }
            if (responseNeeded && hasRequiredPermissions()) {
                gattServer?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
            }
        }
    }

    private fun emitPeerEvent(type: String, device: BluetoothDevice) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to type,
                    "peerId" to device.address,
                    "displayName" to device.name
                )
            )
        }
    }

    private fun emitDataEvent(device: BluetoothDevice, value: ByteArray) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "dataReceived",
                    "peerId" to device.address,
                    "displayName" to device.name,
                    "data" to value
                )
            )
        }
    }

    private fun emitLog(message: String) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to "log",
                    "peerId" to "",
                    "message" to message
                )
            )
        }
    }

    private fun hasRequiredPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasPermission(Manifest.permission.BLUETOOTH_CONNECT) &&
                hasPermission(Manifest.permission.BLUETOOTH_ADVERTISE)
        } else {
            true
        }
    }

    private fun hasPermission(permission: String): Boolean {
        return ContextCompat.checkSelfPermission(context, permission) ==
            PackageManager.PERMISSION_GRANTED
    }
}
