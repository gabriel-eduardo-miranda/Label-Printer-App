import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:permission_handler/permission_handler.dart';

class BluetoothPrinterService extends ChangeNotifier {
  final PrinterManager _printerManager = PrinterManager.instance;
  static const MethodChannel _bleScannerChannel = MethodChannel(
    'label_printer_app/ble_scanner',
  );

  final List<PrinterDevice> _discoveredDevices = [];
  final List<String> _debugLogs = [];
  PrinterDevice? _connectedDevice;
  bool _isScanning = false;
  bool _isConnected = false;

  List<PrinterDevice> get discoveredDevices => _discoveredDevices;
  List<String> get debugLogs => List.unmodifiable(_debugLogs);
  String get debugLogText => _debugLogs.join('\n');
  PrinterDevice? get connectedDevice => _connectedDevice;
  bool get isScanning => _isScanning;
  bool get isConnected => _isConnected;

  StreamSubscription<PrinterDevice>? _scanSubscription;
  Timer? _scanTimeout;

  void clearDebugLogs() {
    _debugLogs.clear();
    _log('Log limpo');
  }

  void _log(String message) {
    final now = DateTime.now();
    final time =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    final line = '[$time] $message';

    _debugLogs.add(line);
    if (_debugLogs.length > 300) {
      _debugLogs.removeRange(0, _debugLogs.length - 300);
    }

    if (kDebugMode) print(line);
    notifyListeners();
  }

  Future<bool> requestBluetoothPermissions() async {
    _log('Solicitando permissoes Bluetooth/Localizacao...');

    final statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final scanGranted = statuses[Permission.bluetoothScan]?.isGranted == true;
    final connectGranted =
        statuses[Permission.bluetoothConnect]?.isGranted == true;
    final locationGranted =
        statuses[Permission.locationWhenInUse]?.isGranted == true;

    _log(
      'Permissoes: scan=$scanGranted, connect=$connectGranted, '
      'location=$locationGranted',
    );

    return (scanGranted && connectGranted) || locationGranted;
  }

  void startScan() async {
    _log('Reload/scan solicitado');

    final hasPermission = await requestBluetoothPermissions();
    if (!hasPermission) {
      _log('Busca cancelada: permissoes ausentes');
      return;
    }

    await _scanSubscription?.cancel();
    _scanTimeout?.cancel();
    _log('Scan anterior cancelado e lista reiniciada');

    _discoveredDevices.clear();
    _isScanning = true;
    notifyListeners();

    _scanSubscription = _printerManager
        .discovery(type: PrinterType.bluetooth, isBle: true)
        .listen(
          (device) => _addDeviceToList(device, source: 'plugin BLE'),
          onError: _handleScanError,
          onDone: _handlePrimaryScanDone,
        );
    _log('Scan BLE pelo plugin iniciado');

    _scanTimeout = Timer(const Duration(seconds: 20), () {
      if (_isScanning) {
        _log('Tempo limite do scan atingido');
        stopScan();
      }
    });
  }

  void _addDeviceToList(PrinterDevice device, {String source = 'scan'}) {
    final hasName = device.name.trim().isNotEmpty;
    final hasAddress = device.address?.trim().isNotEmpty == true;

    if (!hasName && !hasAddress) {
      _log('Dispositivo ignorado ($source): sem nome e sem endereco');
      return;
    }

    final isAlreadyAdded = _discoveredDevices.any(
      (d) =>
          (hasAddress && d.address == device.address) ||
          (hasName && d.name == device.name),
    );

    final label = device.name.isNotEmpty ? device.name : 'sem nome';
    final address = device.address ?? 'sem endereco';

    if (!isAlreadyAdded) {
      _discoveredDevices.add(device);
      _log('Dispositivo encontrado ($source): $label | $address');
      notifyListeners();
    } else {
      _log('Dispositivo duplicado ignorado ($source): $label | $address');
    }
  }

  void _handleScanError(Object error) {
    _log('Erro durante escaneamento: $error');
    stopScan();
  }

  Future<void> _handlePrimaryScanDone() async {
    _log(
      'Scan do plugin finalizado; encontrados ate agora: '
      '${_discoveredDevices.length}',
    );

    if (_isScanning) {
      await _scanWithNativeBleFallback();
    }

    stopScan();
  }

  Future<void> _scanWithNativeBleFallback() async {
    if (!Platform.isAndroid) {
      _log('Fallback BLE nativo ignorado: plataforma nao Android');
      return;
    }

    try {
      _log('Fallback BLE nativo iniciado');

      final response = await _bleScannerChannel.invokeMethod<dynamic>(
        'scanBle',
        {'timeoutMs': 7000},
      );

      final nativeLogs = response is Map ? response['logs'] : null;
      if (nativeLogs is List) {
        for (final entry in nativeLogs) {
          _log('Android: $entry');
        }
      }

      final results = response is Map ? response['devices'] : response;
      final devices = results is List ? results : <dynamic>[];
      _log('Fallback BLE nativo retornou ${devices.length} dispositivo(s)');

      for (final item in devices) {
        if (item is! Map) continue;

        final name = (item['name'] as String? ?? '').trim();
        final address = (item['address'] as String? ?? '').trim();
        if (address.isEmpty) {
          _log('Fallback ignorou item sem endereco: $item');
          continue;
        }

        _addDeviceToList(
          PrinterDevice(
            name: name.isNotEmpty ? name : address,
            address: address,
          ),
          source: 'fallback nativo',
        );
      }
    } catch (e) {
      _log('Erro no fallback BLE nativo: $e');
    }
  }

  void stopScan() {
    _scanTimeout?.cancel();
    _scanTimeout = null;
    _scanSubscription?.cancel();
    _scanSubscription = null;

    if (!_isScanning) return;

    _isScanning = false;
    _log('Scan finalizado. Total listado: ${_discoveredDevices.length}');
    notifyListeners();
  }

  Future<bool> connectToDevice(PrinterDevice device, {String? pin}) async {
    final label = device.name.isNotEmpty ? device.name : 'sem nome';
    final address = device.address ?? 'sem endereco';
    _log('Tentando conectar: $label | $address');

    final cleanPin = pin?.trim() ?? '';
    if (cleanPin.isNotEmpty) {
      final paired = await _pairBleDevice(address, cleanPin);
      if (!paired) {
        _log('Conexao cancelada: pareamento com PIN falhou');
        return false;
      }
    } else {
      _log('Conexao sem PIN/pareamento previo');
    }

    try {
      final result = await _printerManager.connect(
        type: PrinterType.bluetooth,
        model: BluetoothPrinterInput(
          name: device.name,
          address: device.address ?? '',
          isBle: true,
        ),
      );

      if (result) {
        _connectedDevice = device;
        _isConnected = true;
        _log('Conexao bem-sucedida');
        notifyListeners();
        return true;
      }

      _log('Conexao falhou: plugin retornou false');
      return _connectWithNativeBleFallback(device);
    } catch (e) {
      _log('Erro de conexao: $e');
      return _connectWithNativeBleFallback(device);
    }
  }

  Future<bool> _connectWithNativeBleFallback(PrinterDevice device) async {
    if (!Platform.isAndroid) {
      _log('Conexao BLE nativa ignorada: plataforma nao Android');
      return false;
    }

    final address = device.address?.trim() ?? '';
    if (address.isEmpty) {
      _log('Conexao BLE nativa cancelada: endereco vazio');
      return false;
    }

    try {
      _log('Conexao BLE nativa iniciada');
      final response = await _bleScannerChannel.invokeMethod<dynamic>(
        'connectBlePrinter',
        {'address': address},
      );

      if (response is Map) {
        final nativeLogs = response['logs'];
        if (nativeLogs is List) {
          for (final entry in nativeLogs) {
            _log('Android: $entry');
          }
        }

        final success = response['success'] == true;
        _log('Conexao BLE nativa retornou success=$success');

        if (success) {
          _connectedDevice = device;
          _isConnected = true;
          notifyListeners();
          return true;
        }
      } else {
        _log('Conexao BLE nativa retornou resposta inesperada: $response');
      }
    } catch (e) {
      _log('Erro na conexao BLE nativa: $e');
    }

    return false;
  }

  Future<bool> _pairBleDevice(String address, String pin) async {
    if (!Platform.isAndroid) {
      _log('Pareamento com PIN ignorado: plataforma nao Android');
      return true;
    }

    try {
      _log('Pareamento BLE iniciado com PIN informado');
      final response = await _bleScannerChannel.invokeMethod<dynamic>(
        'pairBle',
        {'address': address, 'pin': pin},
      );

      if (response is Map) {
        final nativeLogs = response['logs'];
        if (nativeLogs is List) {
          for (final entry in nativeLogs) {
            _log('Android: $entry');
          }
        }

        final success = response['success'] == true;
        _log('Pareamento BLE retornou success=$success');
        return success;
      }

      _log('Pareamento BLE retornou resposta inesperada: $response');
      return false;
    } catch (e) {
      _log('Erro no pareamento BLE: $e');
      return false;
    }
  }

  Future<bool> printLabel({
    required String text,
    required double widthMm,
    required double heightMm,
  }) async {
    _log(
      'Impressao solicitada: texto="$text", largura=${widthMm}mm, '
      'altura=${heightMm}mm',
    );

    if (!_isConnected || _connectedDevice == null) {
      _log('Impressao cancelada: nenhuma impressora conectada');
      return false;
    }

    final bytes = _buildTsplLabelBytes(
      text: text,
      widthMm: widthMm,
      heightMm: heightMm,
    );

    _log('Impressao: TSPL gerado com ${bytes.length} bytes');
    return _sendNativePrintBytes(bytes);
  }

  List<int> _buildTsplLabelBytes({
    required String text,
    required double widthMm,
    required double heightMm,
  }) {
    final safeText = text
        .replaceAll('"', "'")
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .trim();

    final width = widthMm.clamp(10, 100).toStringAsFixed(0);
    final height = heightMm.clamp(10, 150).toStringAsFixed(0);
    final commands = [
      'SIZE $width mm,$height mm',
      'GAP 2 mm,0 mm',
      'DENSITY 8',
      'SPEED 4',
      'DIRECTION 1',
      'REFERENCE 0,0',
      'CLS',
      'TEXT 30,30,"3",0,1,1,"$safeText"',
      'PRINT 1,1',
      '',
    ].join('\r\n');

    _log('Impressao TSPL:\n$commands');
    return ascii.encode(commands);
  }

  Future<bool> _sendNativePrintBytes(List<int> bytes) async {
    if (!Platform.isAndroid) {
      _log('Impressao nativa cancelada: plataforma nao Android');
      return false;
    }

    try {
      _log('Impressao BLE nativa iniciada');
      final response = await _bleScannerChannel.invokeMethod<dynamic>(
        'writeBlePrinter',
        {'bytes': bytes},
      );

      if (response is Map) {
        final nativeLogs = response['logs'];
        if (nativeLogs is List) {
          for (final entry in nativeLogs) {
            _log('Android: $entry');
          }
        }

        final success = response['success'] == true;
        _log('Impressao BLE nativa retornou success=$success');
        return success;
      }

      _log('Impressao BLE nativa retornou resposta inesperada: $response');
      return false;
    } catch (e) {
      _log('Erro na impressao BLE nativa: $e');
      return false;
    }
  }

  Future<void> disconnectDevice() async {
    if (_connectedDevice != null) {
      _log('Desconectando dispositivo atual');
      await _printerManager.disconnect(type: PrinterType.bluetooth);
      if (Platform.isAndroid) {
        try {
          await _bleScannerChannel.invokeMethod<dynamic>(
            'disconnectBlePrinter',
          );
        } catch (e) {
          _log('Erro ao desconectar BLE nativo: $e');
        }
      }
      _connectedDevice = null;
      _isConnected = false;
      _log('Dispositivo desconectado');
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _scanTimeout?.cancel();
    _scanSubscription?.cancel();
    super.dispose();
  }
}
