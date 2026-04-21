package com.localmesh.localmesh

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private lateinit var bleGattServer: LocalMeshBleGattServer

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bleGattServer = LocalMeshBleGattServer(applicationContext)
        bleGattServer.attach(flutterEngine.dartExecutor.binaryMessenger)
    }
}
