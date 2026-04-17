import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

/// Wraps flutter_ble_peripheral to advertise the LocalMesh GATT service.
/// Must be started on every device that wants to be discoverable as a peripheral.
class BlePeripheralAdvertiser {
  static const String serviceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';

  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();
  bool _advertising = false;

  bool get isAdvertising => _advertising;

  Future<bool> start({required String localName}) async {
    if (_advertising) return true;

    final data = AdvertiseData(
      serviceUuid: serviceUuid,
      localName: localName,
      includeDeviceName: true,
    );

    final settings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeLowLatency,
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerMedium,
      connectable: true,
    );

    try {
      await _peripheral.start(advertiseData: data, advertiseSettings: settings);
      _advertising = true;
      return true;
    } catch (_) {
      _advertising = false;
      return false;
    }
  }

  Future<void> stop() async {
    if (!_advertising) return;
    await _peripheral.stop();
    _advertising = false;
  }
}
