class LabelData {
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
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      text: '',
      lengthText: '',
      widthText: '',
      quantityText: '',
    );
  }

  factory LabelData.fromJson(Map<String, dynamic> json) {
    return LabelData(
      id:
          (json['id'] as String?) ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      text: (json['text'] as String?) ?? '',
      lengthText: (json['lengthText'] as String?) ?? '',
      widthText: (json['widthText'] as String?) ?? '',
      quantityText: (json['quantityText'] as String?) ?? '',
      isSelected: (json['isSelected'] as bool?) ?? true,
      isEditing: (json['isEditing'] as bool?) ?? true,
    );
  }

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

  Map<String, dynamic> toJson() {
    return {
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
