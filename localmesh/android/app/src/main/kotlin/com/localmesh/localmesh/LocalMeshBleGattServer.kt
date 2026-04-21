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
import android.os.Handler   // Bug 2: needed for main-thread dispatch
import android.os.Looper   // Bug 2: needed for main-thread dispatch
import android.os.ParcelUuid
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

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

    // Bug 2: all EventSink.success() calls must run on the Android main thread;
    // BluetoothGattServerCallback fires on the Binder thread pool.
    private val mainHandler = Handler(Looper.getMainLooper())

    private var gattServer: BluetoothGattServer? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var rxCharacteristic: BluetoothGattCharacteristic? = null
    private val connectedDevices = linkedMapOf<String, BluetoothDevice>()
    private val subscribedDevices = linkedSetOf<String>()
    private var eventSink: EventChannel.EventSink? = null

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

    private fun start(localName: String): Boolean {
        if (!hasRequiredPermissions()) {
            emitLog("cannot start GATT server: missing Bluetooth permissions")
            return false
        }
        if (adapter == null || adapter?.isEnabled != true) {
            emitLog("cannot start GATT server: Bluetooth is disabled")
            return false
        }
        if (advertiser == null) {
            emitLog("cannot start GATT server: BLE advertiser unavailable")
            return false
        }

        stop()
        if (!openGattServer()) {
            return false
        }
        return startAdvertising(localName)
    }

    private fun stop() {
        advertiseCallback?.let { advertiser?.stopAdvertising(it) }
        advertiseCallback = null
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
            emitLog("failed to open Android BluetoothGattServer")
            return false
        }
        val added = server.addService(service)
        if (!added) {
            emitLog("failed to add GATT service $SERVICE_UUID")
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
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM)
            .build()

        // Bug 1: primary ad packet was 32 B (flags 3 + UUID 18 + name 11) > 31 B limit,
        // causing ADVERTISE_FAILED_DATA_TOO_LARGE.  Move device name to scan response so
        // each packet stays within the 31-byte budget.
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
                // Bug 3: emit dedicated event so Dart side knows advertising truly started.
                emitAdvertiseResult(success = true)
            }

            override fun onStartFailure(errorCode: Int) {
                emitLog("BLE advertising failed with code=$errorCode")
                // Bug 3: propagate failure to Dart so BleTransport can set state = error.
                emitAdvertiseResult(success = false, errorCode = errorCode)
            }
        }

        return try {
            // Bug 1: use 4-arg overload with separate scan-response packet.
            advertiser?.startAdvertising(settings, primaryData, scanResponse, callback)
            advertiseCallback = callback
            true
        } catch (t: Throwable) {
            emitLog("BLE advertising threw ${t.message}")
            false
        }
    }

    // Bug 3: emit advertiseStarted / advertiseError through the event channel so Dart
    // can react to the real async outcome of startAdvertising().
    private fun emitAdvertiseResult(success: Boolean, errorCode: Int = 0) {
        mainHandler.post {
            eventSink?.success(
                mapOf(
                    "type" to if (success) "advertiseStarted" else "advertiseError",
                    "peerId" to "",
                    // Reuse the "message" field so BleGattServerEvent.fromMap needs no changes.
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

    // Bug 2: EventSink.success() must be called from the Android main thread.
    // BluetoothGattServerCallback fires on the Binder thread pool, so all eventSink
    // calls are posted via mainHandler.  gattServer.sendResponse() stays on Binder thread.
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
