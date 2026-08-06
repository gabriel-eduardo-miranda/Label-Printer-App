abstract class LabelListItem {
  const LabelListItem();

  String get id;

  Map<String, dynamic> toJson();

  static LabelListItem fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String?;
    if (type == LabelGroupData.jsonType) {
      return LabelGroupData.fromJson(json);
    }

    return LabelData.fromJson(json);
  }
}

class LabelData extends LabelListItem {
  LabelData({
    required this.id,
    required this.text,
    required this.lengthText,
    required this.widthText,
    required this.quantityText,
    this.isSelected = true,
    this.isEditing = true,
  });

  factory LabelData.empty() {
    return LabelData(
      id: _newId('label'),
      text: '',
      lengthText: '',
      widthText: '',
      quantityText: '',
    );
  }

  factory LabelData.fromJson(Map<String, dynamic> json) {
    return LabelData(
      id: (json['id'] as String?) ?? _newId('label'),
      text: (json['text'] as String?) ?? '',
      lengthText: (json['lengthText'] as String?) ?? '',
      widthText: (json['widthText'] as String?) ?? '',
      quantityText: (json['quantityText'] as String?) ?? '',
      isSelected: (json['isSelected'] as bool?) ?? true,
      isEditing: (json['isEditing'] as bool?) ?? true,
    );
  }

  static const String jsonType = 'label';

  @override
  final String id;
  String text;
  String lengthText;
  String widthText;
  String quantityText;
  bool isSelected;
  bool isEditing;

  int get quantity => int.tryParse(quantityText.trim()) ?? 0;

  bool get isReadyToPrint {
    return text.trim().isNotEmpty &&
        lengthText.trim().isNotEmpty &&
        widthText.trim().isNotEmpty &&
        quantity > 0;
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': jsonType,
      'id': id,
      'text': text,
      'lengthText': lengthText,
      'widthText': widthText,
      'quantityText': quantityText,
      'isSelected': isSelected,
      'isEditing': isEditing,
    };
  }
}

class LabelGroupData extends LabelListItem {
  LabelGroupData({
    required this.id,
    required this.name,
    required this.labels,
    this.isEditing = true,
    this.isExpanded = true,
  });

  factory LabelGroupData.empty() {
    return LabelGroupData(id: _newId('group'), name: '', labels: []);
  }

  factory LabelGroupData.fromJson(Map<String, dynamic> json) {
    final labelsJson = json['labels'];
    final labels = labelsJson is List
        ? labelsJson
              .whereType<Map>()
              .map(
                (item) => LabelData.fromJson(Map<String, dynamic>.from(item)),
              )
              .toList()
        : <LabelData>[];

    return LabelGroupData(
      id: (json['id'] as String?) ?? _newId('group'),
      name: (json['name'] as String?) ?? '',
      labels: labels,
      isEditing: (json['isEditing'] as bool?) ?? true,
      isExpanded: (json['isExpanded'] as bool?) ?? true,
    );
  }

  static const String jsonType = 'group';

  @override
  final String id;
  String name;
  List<LabelData> labels;
  bool isEditing;
  bool isExpanded;

  @override
  Map<String, dynamic> toJson() {
    return {
      'type': jsonType,
      'id': id,
      'name': name,
      'labels': labels.map((label) => label.toJson()).toList(),
      'isEditing': isEditing,
      'isExpanded': isExpanded,
    };
  }
}

int _idSequence = 0;

String _newId(String prefix) {
  _idSequence = (_idSequence + 1) % 0x3fffffff;
  return '${prefix}_${DateTime.now().microsecondsSinceEpoch}_$_idSequence';
}
