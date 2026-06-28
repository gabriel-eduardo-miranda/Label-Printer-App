import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pos_printer_platform/flutter_pos_printer_platform.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';

class BluetoothPrinterService extends ChangeNotifier {
  final PrinterManager _printerManager = PrinterManager.instance;
  static const MethodChannel _bleScannerChannel = MethodChannel(
    'label_printer_app/ble_scanner',
  );
  static const String _labelImageAsset =
      'assets/images/Game-of-Thrones-Stark-Family-Logo-Tv-show-transparent-PNG-image.png';
  static const int _dpi = 203;
  static const int _labelWidthMm = 50;
  static const int _labelHeightMm = 60;

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
    required String lengthText,
    required String widthText,
  }) async {
    _log(
      'Impressao solicitada: texto="$text", comprimento="$lengthText", '
      'largura="$widthText"',
    );

    if (!_isConnected || _connectedDevice == null) {
      _log('Impressao cancelada: nenhuma impressora conectada');
      return false;
    }

    final bytes = await _buildRasterLabelBytes(
      text: text,
      lengthText: lengthText,
      widthText: widthText,
    );

    _log('Impressao: raster ESC/POS gerado com ${bytes.length} bytes');
    return _sendNativePrintBytes(bytes);
  }

  Future<List<int>> _buildRasterLabelBytes({
    required String text,
    required String lengthText,
    required String widthText,
  }) async {
    final labelHeightPx = _mmToDots(_labelHeightMm);
    // CONFIGURAÇÃO DA LARGURA: Transforma os 50mm em pontos (~400px) dinamicamente
    final canvasWidth = _mmToDots(_labelWidthMm);

    final imageSizePx = _mmToDots(15);
    const textLineHeight = 28;
    final imageTextGapPx = _mmToDots(5);
    final imageBytes = await rootBundle.load(_labelImageAsset);
    final decodedImage = img.decodeImage(imageBytes.buffer.asUint8List());

    if (decodedImage == null) {
      throw StateError('Nao foi possivel carregar a imagem da etiqueta');
    }

    final lines = [
      _singleLine(text),
      '',
      'Comprimento: ${_singleLine(lengthText)}',
      '',
      'Largura: ${_singleLine(widthText)}',
    ];
    final textBlockHeight = ((lines.length - 1) * textLineHeight) + 24;
    final contentHeight = imageSizePx + imageTextGapPx + textBlockHeight;

    // MARGEM ESQUERDA: Define 20 pontos de distância da borda esquerda para imagem e texto
    final imageX = 20;
    final textX = 20;

    // Inicializa a imagem em memória (canvas) com a largura real calculada
    final canvas = img.Image(canvasWidth, labelHeightPx)..fill(0xffffffff);

    final imageY = ((labelHeightPx - contentHeight) / 2).round().clamp(
      0,
      labelHeightPx - imageSizePx,
    );
    final textY = imageY + imageSizePx + imageTextGapPx;

    final resizedImage = img.copyResize(
      decodedImage,
      width: imageSizePx,
      height: imageSizePx,
    );
    img.grayscale(resizedImage);
    img.drawImage(
      canvas,
      resizedImage,
      dstX: imageX,
      dstY: imageY,
      blend: true,
    );

    var currentY = textY;
    for (final line in lines) {
      if (line.isNotEmpty) {
        img.drawString(
          canvas,
          img.arial_24,
          textX,
          currentY,
          line,
          color: 0xff000000,
        );
      }
      currentY += 28;
    }

    _log(
      'Impressao raster: etiqueta $_labelWidthMm x $_labelHeightMm mm '
      '($canvasWidth x $labelHeightPx dots), alinhada a esquerda, '
      'conteudo centralizado verticalmente',
    );

    return _buildEscPosRasterBytes(canvas);
  }

  int _mmToDots(num mm) => (mm / 25.4 * _dpi).round();

  String _singleLine(String value) {
    return value.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
  }

  List<int> _buildEscPosRasterBytes(img.Image image) {
    final widthBytes = (image.width + 7) ~/ 8;
    final raster = <int>[];

    for (var y = 0; y < image.height; y++) {
      for (var byteX = 0; byteX < widthBytes; byteX++) {
        var byte = 0;
        for (var bit = 0; bit < 8; bit++) {
          final x = byteX * 8 + bit;
          if (x >= image.width) continue;

          final pixel = image.getPixel(x, y);
          final luminance = img.getLuminance(pixel);
          final alpha = img.getAlpha(pixel);
          if (alpha > 32 && luminance < 180) {
            byte |= 0x80 >> bit;
          }
        }
        raster.add(byte);
      }
    }

    return [
      0x1b,
      0x40,
      0x1b,
      0x33,
      0x00,
      0x1d,
      0x76,
      0x30,
      0x00,
      widthBytes & 0xff,
      (widthBytes >> 8) & 0xff,
      image.height & 0xff,
      (image.height >> 8) & 0xff,
      ...raster,
      0x0a,
      0x0a,
    ];
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
      _log('Erro na xaxis de impressao BLE nativa: $e');
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
