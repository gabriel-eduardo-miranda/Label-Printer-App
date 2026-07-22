import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/label_data.dart';

class LabelStorageService {
  const LabelStorageService();

  static const MethodChannel _channel = MethodChannel(
    'label_printer_app/label_storage',
  );

  Future<List<LabelData>> loadLabels() async {
    try {
      final labelsJson = await _channel.invokeMethod<String>('loadLabels');
      if (labelsJson == null || labelsJson.trim().isEmpty) return [];

      final decoded = jsonDecode(labelsJson);
      if (decoded is! List) return [];

      return decoded
          .whereType<Map>()
          .map((item) => LabelData.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    } on MissingPluginException {
      return [];
    } on FormatException {
      return [];
    }
  }

  Future<void> saveLabels(List<LabelData> labels) async {
    final labelsJson = jsonEncode(
      labels.map((label) => label.toJson()).toList(),
    );

    try {
      await _channel.invokeMethod<void>('saveLabels', {
        'labelsJson': labelsJson,
      });
    } on MissingPluginException {
      return;
    }
  }
}
