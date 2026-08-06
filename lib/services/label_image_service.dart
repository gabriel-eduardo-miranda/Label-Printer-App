import 'package:flutter/services.dart';

class LabelImageService {
  const LabelImageService();

  static const MethodChannel _channel = MethodChannel(
    'label_printer_app/label_image',
  );

  Future<Uint8List?> loadImageBytes() async {
    try {
      return _channel.invokeMethod<Uint8List>('loadImage');
    } on MissingPluginException {
      return null;
    }
  }

  Future<Uint8List?> pickImage() async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'pickImage',
      );

      if (response == null) return null;
      if (response['success'] != true) {
        if (response['canceled'] == true) return null;

        final error = response['error'] as String?;
        throw StateError(
          error ?? 'N\u00e3o foi poss\u00edvel importar a imagem',
        );
      }

      return response['bytes'] as Uint8List?;
    } on MissingPluginException {
      throw StateError(
        'Importa\u00e7\u00e3o de imagem dispon\u00edvel apenas no Android',
      );
    }
  }

  Future<void> removeImage() async {
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'removeImage',
      );
      if (response == null || response['success'] == true) return;

      final error = response['error'] as String?;
      throw StateError(error ?? 'N\u00e3o foi poss\u00edvel remover a imagem');
    } on MissingPluginException {
      return;
    }
  }
}
