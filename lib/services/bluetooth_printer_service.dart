import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothPrinterService extends ChangeNotifier {
  final PrinterManager _printerManager = PrinterManager.instance;

  // Alterado para usar o PrinterDevice diretamente da biblioteca
  List<PrinterDevice> _discoveredDevices = [];
  PrinterDevice? _connectedDevice;
  bool _isScanning = false;
  bool _isConnected = false;

  List<PrinterDevice> get discoveredDevices => _discoveredDevices;
  PrinterDevice? get connectedDevice => _connectedDevice;
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;

  StreamSubscription<PrinterDevice>? _scanSubscription;

  Future<bool> requestBluetoothPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location,
    ].request();

    return statuses[Permission.bluetoothScan]?.isGranted == true &&
        statuses[Permission.bluetoothConnect]?.isGranted == true;
  }

  void startScan() async {
    bool hasPermission = await requestBluetoothPermissions();
    if (!hasPermission) return;

    _discoveredDevices.clear();
    _isScanning = true;
    notifyListeners();

    await _scanSubscription?.cancel();

    _scanSubscription = _printerManager
        .discovery(type: PrinterType.bluetooth)
        .listen((device) {
          final isAlreadyAdded = _discoveredDevices.any(
            (d) => d.address == device.address,
          );
          if (!isAlreadyAdded &&
              device.name != null &&
              device.name!.isNotEmpty) {
            _discoveredDevices.add(device);
            notifyListeners();
          }
        });

    Future.delayed(const Duration(seconds: 10), () {
      stopScan();
    });
  }

  void stopScan() {
    _scanSubscription?.cancel();
    _isScanning = false;
    notifyListeners();
  }

  Future<bool> connectToDevice(PrinterDevice device) async {
    try {
      bool result = await _printerManager.connect(
        type: PrinterType.bluetooth,
        model: BluetoothPrinterInput(
          name: device.name ?? '',
          address: device.address ?? '',
          isBle: true,
        ),
      );

      if (result) {
        _connectedDevice = device;
        _isConnected = true;
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      if (kDebugMode) print("Connection error: $e");
      return false;
    }
  }

  Future<void> disconnectDevice() async {
    if (_connectedDevice != null) {
      await _printerManager.disconnect(type: PrinterType.bluetooth);
      _connectedDevice = null;
      _isConnected = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _scanSubscription?.cancel();
    super.dispose();
  }
}
