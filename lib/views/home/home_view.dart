import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/label_data.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../services/label_image_service.dart';
import '../../services/label_storage_service.dart';
import '../bluetooth/bluetooth_connection_view.dart';

enum _LabelMenuAction { addGroup, addLabel, importCsv, csvRules, clearAll }

enum _GroupMenuAction { rename, addLabel, selectAll, unselectAll, delete }

enum _LabelImageAction { remove, add }

enum _CsvImportTarget { root, newGroup, existingGroup }

class _CsvImportDestination {
  const _CsvImportDestination.root()
    : target = _CsvImportTarget.root,
      groupId = null,
      groupName = null;

  const _CsvImportDestination.newGroup(this.groupName)
    : target = _CsvImportTarget.newGroup,
      groupId = null;

  const _CsvImportDestination.existingGroup(this.groupId)
    : target = _CsvImportTarget.existingGroup,
      groupName = null;

  final _CsvImportTarget target;
  final String? groupId;
  final String? groupName;
}

class _DragPayload {
  const _DragPayload.label(this.id, {this.sourceGroupId}) : isGroup = false;

  const _DragPayload.group(this.id) : isGroup = true, sourceGroupId = null;

  final String id;
  final String? sourceGroupId;
  final bool isGroup;

  bool get isLabel => !isGroup;
}

class _CsvImportDestinationDialog extends StatefulWidget {
  const _CsvImportDestinationDialog({
    required this.labelCount,
    required this.groups,
    required this.pendingMessage,
  });

  final int labelCount;
  final List<LabelGroupData> groups;
  final String pendingMessage;

  @override
  State<_CsvImportDestinationDialog> createState() =>
      _CsvImportDestinationDialogState();
}

class _CsvImportDestinationDialogState
    extends State<_CsvImportDestinationDialog> {
  final TextEditingController _newGroupController = TextEditingController();
  bool _isNewGroupExpanded = false;
  bool _isExistingGroupExpanded = false;
  bool _showNewGroupError = false;

  @override
  void dispose() {
    _newGroupController.dispose();
    super.dispose();
  }

  void _finishWithNewGroup() {
    final groupName = _newGroupController.text.trim();
    if (groupName.isEmpty) {
      setState(() => _showNewGroupError = true);
      return;
    }

    Navigator.pop(context, _CsvImportDestination.newGroup(groupName));
  }

  void _toggleNewGroup() {
    setState(() {
      _isNewGroupExpanded = !_isNewGroupExpanded;
      if (_isNewGroupExpanded) {
        _isExistingGroupExpanded = false;
      }
    });
  }

  void _toggleExistingGroup() {
    setState(() {
      _isExistingGroupExpanded = !_isExistingGroupExpanded;
      if (_isExistingGroupExpanded) {
        _isNewGroupExpanded = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Deseja associar a um grupo?'),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.pendingMessage,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('N\u00e3o associar'),
                onTap: () {
                  Navigator.pop(context, const _CsvImportDestination.root());
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AnimatedRotation(
                  turns: _isNewGroupExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: const Icon(Icons.chevron_right, size: 26),
                ),
                title: const Text('Adicionar grupo'),
                onTap: _toggleNewGroup,
              ),
              if (_isNewGroupExpanded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newGroupController,
                          autofocus: true,
                          textInputAction: TextInputAction.done,
                          decoration: InputDecoration(
                            labelText: 'Nome do grupo',
                            border: const OutlineInputBorder(),
                            errorText: _showNewGroupError
                                ? 'Digite o nome do grupo'
                                : null,
                          ),
                          onChanged: (value) {
                            if (_showNewGroupError && value.trim().isNotEmpty) {
                              setState(() => _showNewGroupError = false);
                            }
                          },
                          onSubmitted: (_) => _finishWithNewGroup(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 48,
                        height: 56,
                        child: FilledButton(
                          onPressed: _finishWithNewGroup,
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Icon(Icons.check),
                        ),
                      ),
                    ],
                  ),
                ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: AnimatedRotation(
                  turns: _isExistingGroupExpanded ? 0.25 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: const Icon(Icons.chevron_right, size: 26),
                ),
                title: const Text('Selecionar grupo'),
                onTap: _toggleExistingGroup,
              ),
              if (_isExistingGroupExpanded)
                if (widget.groups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Nenhum grupo criado'),
                    ),
                  )
                else
                  ...widget.groups.map((group) {
                    final groupName = group.name.trim().isEmpty
                        ? 'Grupo sem nome'
                        : group.name.trim();

                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 34),
                      title: Text(
                        groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        Navigator.pop(
                          context,
                          _CsvImportDestination.existingGroup(group.id),
                        );
                      },
                    );
                  }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
      ],
    );
  }
}

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  static const String _defaultLabelImageAsset = 'assets/images/editar.png';
  static const MethodChannel _csvImportChannel = MethodChannel(
    'label_printer_app/csv_import',
  );

  final LabelStorageService _storageService = const LabelStorageService();
  final LabelImageService _labelImageService = const LabelImageService();
  final Map<String, GlobalKey<FormState>> _labelFormKeys = {};
  final Map<String, GlobalKey<FormState>> _groupFormKeys = {};

  List<LabelListItem> _items = [];
  Uint8List? _customLabelImageBytes;
  bool _isLoadingLabels = true;
  bool _isLoadingLabelImage = true;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadItems());
    unawaited(_loadLabelImage());
  }

  Future<void> _loadItems() async {
    final items = await _storageService.loadItems();

    if (!mounted) return;

    setState(() {
      _items = items;
      _isLoadingLabels = false;
    });
  }

  Future<void> _persistItems() {
    return _storageService.saveItems(_items);
  }

  Future<void> _loadLabelImage() async {
    final bytes = await _labelImageService.loadImageBytes();

    if (!mounted) return;

    setState(() {
      _customLabelImageBytes = bytes;
      _isLoadingLabelImage = false;
    });
  }

  GlobalKey<FormState> _labelFormKeyFor(String labelId) {
    return _labelFormKeys.putIfAbsent(labelId, () => GlobalKey<FormState>());
  }

  GlobalKey<FormState> _groupFormKeyFor(String groupId) {
    return _groupFormKeys.putIfAbsent(groupId, () => GlobalKey<FormState>());
  }

  void _handleMenuAction(_LabelMenuAction action) {
    switch (action) {
      case _LabelMenuAction.addGroup:
        _addGroup();
      case _LabelMenuAction.addLabel:
        _addRootLabel();
      case _LabelMenuAction.importCsv:
        unawaited(_importCsv());
      case _LabelMenuAction.csvRules:
        _showCsvRulesDialog();
      case _LabelMenuAction.clearAll:
        unawaited(_clearAllItems());
    }
  }

  void _handleGroupMenuAction(LabelGroupData group, _GroupMenuAction action) {
    switch (action) {
      case _GroupMenuAction.rename:
        _editGroup(group.id);
      case _GroupMenuAction.addLabel:
        _addLabelToGroup(group.id);
      case _GroupMenuAction.selectAll:
        _setGroupLabelsSelected(group.id, true);
      case _GroupMenuAction.unselectAll:
        _setGroupLabelsSelected(group.id, false);
      case _GroupMenuAction.delete:
        unawaited(_deleteGroup(group.id));
    }
  }

  void _addGroup() {
    setState(() {
      _items.add(LabelGroupData.empty());
    });

    unawaited(_persistItems());
  }

  void _addRootLabel() {
    setState(() {
      _items.add(LabelData.empty());
    });

    unawaited(_persistItems());
  }

  void _addLabelToGroup(String groupId) {
    setState(() {
      final group = _findGroup(groupId);
      if (group == null) return;

      group.isExpanded = true;
      group.labels.add(LabelData.empty());
    });

    unawaited(_persistItems());
  }

  void _showCsvRulesDialog() {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Regras csv'),
          content: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'O arquivo precisa estar no formato .csv e ter a primeira linha com os nomes das colunas.',
                  ),
                  const SizedBox(height: 12),
                  _buildCsvRuleLine('Lenght: preenche o Comprimento.'),
                  _buildCsvRuleLine('Width: preenche a Largura.'),
                  _buildCsvRuleLine(
                    'Qty: preenche a Quantidade e precisa ser um numero inteiro maior que zero.',
                  ),
                  _buildCsvRuleLine('Label: preenche o Texto da etiqueta.'),
                  _buildCsvRuleLine(
                    'Enabled: pode existir no arquivo, mas sera ignorado.',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Exemplo:',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.black12),
                    ),
                    child: const SelectableText(
                      'Lenght,Width,Qty,Label,Enabled\n'
                      '350,740,22,Interna,true\n'
                      '760,1050,1,Lat maior,true',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Cada linha depois do cabecalho cria uma etiqueta. Depois de escolher o arquivo, é possível importar livremente ou associar a um grupo.',
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCsvRuleLine(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('- '),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Future<void> _importCsv() async {
    try {
      final response = await _csvImportChannel.invokeMapMethod<String, Object?>(
        'pickCsv',
      );

      if (!mounted) return;

      if (response == null) {
        _showMessage('N\u00e3o foi poss\u00edvel importar o CSV');
        return;
      }

      if (response['success'] != true) {
        if (response['canceled'] == true) return;

        final error = response['error'] as String?;
        _showMessage(error ?? 'N\u00e3o foi poss\u00edvel importar o CSV');
        return;
      }

      final content = response['content'] as String? ?? '';
      final labels = _parseCsvLabels(content);

      if (labels.isEmpty) {
        _showMessage('Nenhuma etiqueta encontrada no CSV');
        return;
      }

      final destination = await _showCsvImportDestinationDialog(labels.length);
      if (destination == null || !mounted) return;

      setState(() {
        _addImportedLabels(labels, destination);
      });

      unawaited(_persistItems());
      _showMessage(_importSuccessMessage(labels.length));
    } on MissingPluginException {
      _showMessage(
        'Importa\u00e7\u00e3o de CSV dispon\u00edvel apenas no Android',
      );
    } on FormatException catch (error) {
      final message = error.message;
      _showMessage(message.isEmpty ? 'CSV inv\u00e1lido' : message);
    } catch (error) {
      _showMessage('Falha ao importar CSV: $error');
    }
  }

  List<LabelData> _parseCsvLabels(String content) {
    final rows = _parseCsvRows(content);
    if (rows.isEmpty) {
      throw const FormatException('CSV vazio');
    }

    final header = rows.first;
    final lengthIndex = _csvHeaderIndex(header, [
      'lenght',
      'length',
      'comprimento',
    ]);
    final widthIndex = _csvHeaderIndex(header, ['width', 'largura']);
    final quantityIndex = _csvHeaderIndex(header, ['qty', 'wty', 'quantidade']);
    final labelIndex = _csvHeaderIndex(header, ['label', 'texto', 'text']);

    if (lengthIndex == null ||
        widthIndex == null ||
        quantityIndex == null ||
        labelIndex == null) {
      throw const FormatException(
        'O CSV precisa conter as colunas Lenght, Width, Qty e Label',
      );
    }

    final labels = <LabelData>[];
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final lengthText = _csvCell(row, lengthIndex).trim();
      final widthText = _csvCell(row, widthIndex).trim();
      final quantityText = _csvCell(row, quantityIndex).trim();
      final labelText = _csvCell(row, labelIndex).trim();

      if (lengthText.isEmpty &&
          widthText.isEmpty &&
          quantityText.isEmpty &&
          labelText.isEmpty) {
        continue;
      }

      if (lengthText.isEmpty ||
          widthText.isEmpty ||
          quantityText.isEmpty ||
          labelText.isEmpty) {
        throw FormatException(
          'Linha ${rowIndex + 1}: preencha Lenght, Width, Qty e Label',
        );
      }

      final quantity = int.tryParse(quantityText);
      if (quantity == null || quantity <= 0) {
        throw FormatException(
          'Linha ${rowIndex + 1}: Qty precisa ser um n\u00famero inteiro maior que zero',
        );
      }

      final label = LabelData.empty()
        ..text = labelText
        ..lengthText = lengthText
        ..widthText = widthText
        ..quantityText = quantity.toString()
        ..isSelected = false
        ..isEditing = false;

      labels.add(label);
    }

    return labels;
  }

  List<List<String>> _parseCsvRows(String content) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;

    for (var index = 0; index < content.length; index++) {
      final char = content[index];

      if (char == '"') {
        final hasEscapedQuote =
            inQuotes && index + 1 < content.length && content[index + 1] == '"';

        if (hasEscapedQuote) {
          cell.write('"');
          index++;
        } else {
          inQuotes = !inQuotes;
        }
        continue;
      }

      if (char == ',' && !inQuotes) {
        row.add(cell.toString().trim());
        cell.clear();
        continue;
      }

      final isLineBreak = char == '\n' || char == '\r';
      if (isLineBreak && !inQuotes) {
        if (char == '\r' &&
            index + 1 < content.length &&
            content[index + 1] == '\n') {
          index++;
        }

        row.add(cell.toString().trim());
        cell.clear();
        if (row.any((field) => field.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
        continue;
      }

      cell.write(char);
    }

    row.add(cell.toString().trim());
    if (row.any((field) => field.trim().isNotEmpty)) rows.add(row);

    if (inQuotes) {
      throw const FormatException('CSV inv\u00e1lido: aspas n\u00e3o fechadas');
    }

    return rows;
  }

  int? _csvHeaderIndex(List<String> header, List<String> aliases) {
    for (var index = 0; index < header.length; index++) {
      final normalized = _normalizeCsvHeader(header[index]);
      if (aliases.contains(normalized)) return index;
    }

    return null;
  }

  String _normalizeCsvHeader(String value) {
    return value.replaceFirst('\ufeff', '').trim().toLowerCase();
  }

  String _csvCell(List<String> row, int index) {
    return index < row.length ? row[index] : '';
  }

  Future<_CsvImportDestination?> _showCsvImportDestinationDialog(
    int labelCount,
  ) async {
    final groups = _items.whereType<LabelGroupData>().toList(growable: false);

    return showDialog<_CsvImportDestination>(
      context: context,
      builder: (context) {
        return _CsvImportDestinationDialog(
          labelCount: labelCount,
          groups: groups,
          pendingMessage: _pendingImportMessage(labelCount),
        );
      },
    );
  }

  void _addImportedLabels(
    List<LabelData> labels,
    _CsvImportDestination destination,
  ) {
    switch (destination.target) {
      case _CsvImportTarget.root:
        _items.addAll(labels);
      case _CsvImportTarget.newGroup:
        final group = LabelGroupData.empty()
          ..name = destination.groupName?.trim() ?? ''
          ..labels = labels
          ..isEditing = false
          ..isExpanded = true;
        _items.add(group);
      case _CsvImportTarget.existingGroup:
        final groupId = destination.groupId;
        final group = groupId == null ? null : _findGroup(groupId);
        if (group == null) {
          _items.addAll(labels);
          return;
        }

        group.isExpanded = true;
        group.labels.addAll(labels);
    }
  }

  String _pendingImportMessage(int labelCount) {
    return labelCount == 1
        ? '1 etiqueta pronta para importar'
        : '$labelCount etiquetas prontas para importar';
  }

  String _importSuccessMessage(int labelCount) {
    return labelCount == 1
        ? '1 etiqueta importada'
        : '$labelCount etiquetas importadas';
  }

  Future<void> _clearAllItems() async {
    if (_items.isEmpty) return;

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Limpar tudo?'),
          content: const Text(
            'Todas as etiquetas e grupos cadastrados ser\u00e3o removidos.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Limpar'),
            ),
          ],
        );
      },
    );

    if (shouldClear != true || !mounted) return;

    setState(() {
      _items = [];
      _labelFormKeys.clear();
      _groupFormKeys.clear();
    });

    unawaited(_persistItems());
  }

  void _updateLabel(String labelId, void Function(LabelData label) update) {
    final label = _findLabel(labelId);
    if (label == null) return;

    update(label);
    unawaited(_persistItems());
  }

  void _updateGroup(
    String groupId,
    void Function(LabelGroupData group) update,
  ) {
    final group = _findGroup(groupId);
    if (group == null) return;

    update(group);
    unawaited(_persistItems());
  }

  void _deleteLabel(String labelId) {
    setState(() {
      _removeLabel(labelId);
      _labelFormKeys.remove(labelId);
    });

    unawaited(_persistItems());
  }

  Future<void> _deleteGroup(String groupId) async {
    final group = _findGroup(groupId);
    if (group == null) return;

    final groupName = group.name.trim().isEmpty
        ? 'este grupo'
        : 'o grupo "${group.name.trim()}"';
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Excluir grupo?'),
          content: Text(
            group.labels.isEmpty
                ? 'Deseja excluir $groupName?'
                : 'Todas as etiquetas de $groupName ser\u00e3o exclu\u00eddas junto com ele.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Confirmar'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) return;

    setState(() {
      for (final label in group.labels) {
        _labelFormKeys.remove(label.id);
      }

      _items.removeWhere(
        (item) => item is LabelGroupData && item.id == groupId,
      );
      _groupFormKeys.remove(groupId);
    });

    unawaited(_persistItems());
  }

  void _includeLabel(String labelId) {
    final formState = _labelFormKeyFor(labelId).currentState;
    if (formState?.validate() != true) return;

    setState(() {
      final label = _findLabel(labelId);
      if (label == null) return;

      label.isEditing = false;
      label.isSelected = false;
    });

    unawaited(_persistItems());
  }

  void _includeGroup(String groupId) {
    final formState = _groupFormKeyFor(groupId).currentState;
    if (formState?.validate() != true) return;

    setState(() {
      final group = _findGroup(groupId);
      if (group == null) return;

      group.isEditing = false;
      group.isExpanded = false;
    });

    unawaited(_persistItems());
  }

  void _editLabel(String labelId) {
    setState(() {
      final label = _findLabel(labelId);
      if (label == null) return;

      label.isEditing = true;
    });

    unawaited(_persistItems());
  }

  void _editGroup(String groupId) {
    setState(() {
      final group = _findGroup(groupId);
      if (group == null) return;

      group.isEditing = true;
    });

    unawaited(_persistItems());
  }

  void _toggleGroup(String groupId) {
    setState(() {
      final group = _findGroup(groupId);
      if (group == null) return;

      group.isExpanded = !group.isExpanded;
    });

    unawaited(_persistItems());
  }

  void _setLabelSelected(String labelId, bool isSelected) {
    setState(() {
      final label = _findLabel(labelId);
      if (label == null) return;

      label.isSelected = isSelected;
    });

    unawaited(_persistItems());
  }

  void _setGroupLabelsSelected(String groupId, bool isSelected) {
    setState(() {
      final group = _findGroup(groupId);
      if (group == null) return;

      for (final label in group.labels) {
        label.isSelected = isSelected;
      }
    });

    unawaited(_persistItems());
  }

  void _unselectAllLabels() {
    setState(() {
      for (final label in _allLabels()) {
        label.isSelected = false;
      }
    });

    unawaited(_persistItems());
  }

  void _moveToRoot(_DragPayload payload, int index) {
    setState(() {
      final targetIndex = index.clamp(0, _items.length);

      if (payload.isGroup) {
        final oldIndex = _items.indexWhere(
          (item) => item is LabelGroupData && item.id == payload.id,
        );
        if (oldIndex == -1) return;

        final item = _items.removeAt(oldIndex);
        final adjustedIndex = oldIndex < targetIndex
            ? targetIndex - 1
            : targetIndex;
        _items.insert(adjustedIndex.clamp(0, _items.length), item);
        return;
      }

      final oldRootIndex = payload.sourceGroupId == null
          ? _items.indexWhere(
              (item) => item is LabelData && item.id == payload.id,
            )
          : -1;
      final label = _removeLabel(payload.id);
      if (label == null) return;

      final adjustedIndex = oldRootIndex != -1 && oldRootIndex < targetIndex
          ? targetIndex - 1
          : targetIndex;
      _items.insert(adjustedIndex.clamp(0, _items.length), label);
    });

    unawaited(_persistItems());
  }

  void _moveLabelToGroup(_DragPayload payload, String groupId, int index) {
    if (!payload.isLabel) return;

    setState(() {
      final groupBeforeRemove = _findGroup(groupId);
      final oldIndexInSameGroup = payload.sourceGroupId == groupId
          ? groupBeforeRemove?.labels.indexWhere(
                  (label) => label.id == payload.id,
                ) ??
                -1
          : -1;

      final label = _removeLabel(payload.id);
      final group = _findGroup(groupId);
      if (label == null || group == null) return;

      var targetIndex = index.clamp(0, group.labels.length);
      if (oldIndexInSameGroup != -1 && oldIndexInSameGroup < targetIndex) {
        targetIndex -= 1;
      }

      group.isExpanded = true;
      group.labels.insert(targetIndex.clamp(0, group.labels.length), label);
    });

    unawaited(_persistItems());
  }

  void _moveLabelOutOfGroup(_DragPayload payload, String groupId) {
    if (!payload.isLabel || payload.sourceGroupId != groupId) return;

    _moveToRoot(payload, _rootIndexAfterGroup(groupId));
  }

  int _rootIndexAfterGroup(String groupId) {
    final groupIndex = _items.indexWhere(
      (item) => item is LabelGroupData && item.id == groupId,
    );

    return groupIndex == -1 ? _items.length : groupIndex + 1;
  }

  Future<void> _printSelectedLabels(
    BuildContext context,
    BluetoothPrinterService bluetoothService,
  ) async {
    if (_isPrinting) return;

    if (!bluetoothService.isConnected) {
      _showMessage('Conecte uma impressora primeiro');
      return;
    }

    final selectedLabels = _allLabels()
        .where((label) => label.isSelected && !label.isEditing)
        .toList();

    if (selectedLabels.isEmpty) {
      _showMessage('Selecione pelo menos uma etiqueta');
      return;
    }

    final hasInvalidLabel = selectedLabels.any(
      (label) => !label.isReadyToPrint,
    );
    if (hasInvalidLabel) {
      _showMessage('Revise as informacoes da etiqueta antes de imprimir');
      return;
    }

    setState(() => _isPrinting = true);
    _showMessage('Enviando etiquetas para a impressora...');

    var success = true;
    for (final label in selectedLabels) {
      success = await bluetoothService.printLabel(
        text: label.text,
        lengthText: label.lengthText,
        widthText: label.widthText,
        quantity: label.quantity,
      );

      if (!success) break;
    }

    if (!context.mounted) return;

    setState(() => _isPrinting = false);
    _showMessage(
      success
          ? 'Etiquetas enviadas para a impressora'
          : 'Falha ao enviar. Verifique o log do Bluetooth',
    );
  }

  Iterable<LabelData> _allLabels() sync* {
    for (final item in _items) {
      if (item is LabelData) {
        yield item;
      } else if (item is LabelGroupData) {
        yield* item.labels;
      }
    }
  }

  LabelData? _findLabel(String labelId) {
    for (final item in _items) {
      if (item is LabelData && item.id == labelId) {
        return item;
      }

      if (item is LabelGroupData) {
        for (final label in item.labels) {
          if (label.id == labelId) return label;
        }
      }
    }

    return null;
  }

  LabelGroupData? _findGroup(String groupId) {
    for (final item in _items) {
      if (item is LabelGroupData && item.id == groupId) return item;
    }

    return null;
  }

  LabelData? _removeLabel(String labelId) {
    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      if (item is LabelData && item.id == labelId) {
        return _items.removeAt(index) as LabelData;
      }

      if (item is LabelGroupData) {
        final labelIndex = item.labels.indexWhere(
          (label) => label.id == labelId,
        );
        if (labelIndex != -1) {
          return item.labels.removeAt(labelIndex);
        }
      }
    }

    return null;
  }

  Future<void> _showLabelImageOptions() async {
    final action = await showDialog<_LabelImageAction>(
      context: context,
      builder: (context) {
        final canRemove = _customLabelImageBytes != null;

        return AlertDialog(
          title: const Text('Imagem da etiqueta'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: canRemove,
                leading: Icon(
                  Icons.delete_outline,
                  color: canRemove ? Colors.red : Colors.black26,
                ),
                title: Text(
                  'Remover',
                  style: TextStyle(
                    color: canRemove ? Colors.black : Colors.black38,
                  ),
                ),
                onTap: canRemove
                    ? () => Navigator.pop(context, _LabelImageAction.remove)
                    : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Adicionar imagem'),
                onTap: () => Navigator.pop(context, _LabelImageAction.add),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
          ],
        );
      },
    );

    if (action == null || !mounted) return;

    switch (action) {
      case _LabelImageAction.remove:
        await _removeCustomLabelImage();
      case _LabelImageAction.add:
        await _pickCustomLabelImage();
    }
  }

  Future<void> _pickCustomLabelImage() async {
    try {
      final bytes = await _labelImageService.pickImage();
      if (bytes == null || !mounted) return;

      setState(() => _customLabelImageBytes = bytes);
      _showMessage('Imagem importada');
    } catch (error) {
      _showMessage(_cleanStateError(error));
    }
  }

  Future<void> _removeCustomLabelImage() async {
    if (_customLabelImageBytes == null) return;

    try {
      await _labelImageService.removeImage();
      if (!mounted) return;

      setState(() => _customLabelImageBytes = null);
      _showMessage('Imagem padrao restaurada');
    } catch (error) {
      _showMessage(_cleanStateError(error));
    }
  }

  String _cleanStateError(Object error) {
    final message = error.toString();
    return message.startsWith('Bad state: ')
        ? message.substring('Bad state: '.length)
        : message;
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothService = context.watch<BluetoothPrinterService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Print Cuts'),
        actions: [
          IconButton(
            tooltip: 'Bluetooth',
            icon: Icon(
              bluetoothService.isConnected
                  ? Icons.bluetooth_connected
                  : Icons.bluetooth,
              color: bluetoothService.isConnected ? Colors.green : Colors.black,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BluetoothConnectionView(),
                ),
              );
            },
          ),
          PopupMenuButton<_LabelMenuAction>(
            tooltip: 'Adicionar',
            icon: const Icon(Icons.add, color: Colors.black),
            onSelected: _handleMenuAction,
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _LabelMenuAction.addGroup,
                child: Text('Adicionar grupo'),
              ),
              PopupMenuItem(
                value: _LabelMenuAction.addLabel,
                child: Text('Adicionar etiqueta'),
              ),
              PopupMenuItem(
                value: _LabelMenuAction.importCsv,
                child: Text('Importar csv'),
              ),
              PopupMenuItem(
                value: _LabelMenuAction.csvRules,
                child: Text('Regras csv'),
              ),
              PopupMenuItem(
                value: _LabelMenuAction.clearAll,
                child: Text('Limpar tudo'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            _buildImagePreview(),
            const SizedBox(height: 12),
            Expanded(
              child: _isLoadingLabels
                  ? const Center(child: CircularProgressIndicator())
                  : _buildItemList(),
            ),
            _buildBottomActions(bluetoothService),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Center(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 150,
            height: 130,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildLabelImage(),
          ),
          Positioned(
            right: -6,
            bottom: -6,
            child: Material(
              color: Colors.black,
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: 'Galeria',
                icon: const Icon(
                  Icons.photo_library_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: () => unawaited(_showLabelImageOptions()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelImage() {
    if (_isLoadingLabelImage) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final customBytes = _customLabelImageBytes;
    if (customBytes != null) {
      return Image.memory(
        customBytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (context, error, stackTrace) {
          return Image.asset(_defaultLabelImageAsset, fit: BoxFit.contain);
        },
      );
    }

    return Image.asset(_defaultLabelImageAsset, fit: BoxFit.contain);
  }

  Widget _buildItemList() {
    if (_items.isEmpty) return const SizedBox.expand();

    final children = <Widget>[];
    children.add(_buildRootDropTarget(0));

    for (var index = 0; index < _items.length; index++) {
      final item = _items[index];
      if (item is LabelData) {
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: item.isEditing
                ? _buildEditableLabel(item)
                : _buildCompactLabel(item, sourceGroupId: null),
          ),
        );
      } else if (item is LabelGroupData) {
        children.add(_buildGroup(item));
      }

      children.add(_buildRootDropTarget(index + 1));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      children: children,
    );
  }

  Widget _buildRootDropTarget(int index) {
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) => _moveToRoot(details.data, index),
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.isNotEmpty;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: isActive ? 18 : 8,
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: isActive ? 3 : 0,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isActive ? Colors.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroup(LabelGroupData group) {
    if (group.isEditing) return _buildEditableGroup(group);

    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (details) {
        return details.data.isLabel && details.data.sourceGroupId != group.id;
      },
      onAcceptWithDetails: (details) {
        _moveLabelToGroup(details.data, group.id, group.labels.length);
      },
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.any(
          (payload) =>
              payload?.isLabel == true && payload?.sourceGroupId != group.id,
        );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            border: isActive
                ? const Border(
                    top: BorderSide(color: Colors.blue, width: 3),
                    left: BorderSide(color: Colors.blue, width: 3),
                  )
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildGroupHeader(group),
              if (group.isExpanded) _buildExpandedGroupBody(group),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEditableGroup(LabelGroupData group) {
    return Card(
      elevation: 0,
      color: Colors.blueGrey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.blueGrey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _groupFormKeyFor(group.id),
          child: Row(
            children: [
              Expanded(
                flex: 4,
                child: TextFormField(
                  initialValue: group.name,
                  decoration: const InputDecoration(
                    labelText: 'Nome do grupo',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Digite o nome do grupo';
                    }
                    return null;
                  },
                  onChanged: (value) {
                    _updateGroup(group.id, (group) => group.name = value);
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 56,
                child: FilledButton(
                  onPressed: () => unawaited(_deleteGroup(group.id)),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                  ),
                  child: const Icon(Icons.close),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                height: 56,
                child: FilledButton(
                  onPressed: () => _includeGroup(group.id),
                  style: FilledButton.styleFrom(
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Icon(Icons.check),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGroupHeader(LabelGroupData group) {
    return Card(
      elevation: 0,
      color: Colors.blueGrey.shade100,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.blueGrey.shade200),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(8),
                ),
                onTap: () => _toggleGroup(group.id),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 14, 8, 14),
                  child: Row(
                    children: [
                      AnimatedRotation(
                        turns: group.isExpanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: const Icon(Icons.chevron_right, size: 26),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          group.name.trim().isEmpty
                              ? 'Grupo sem nome'
                              : group.name.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            PopupMenuButton<_GroupMenuAction>(
              tooltip: 'Opcoes do grupo',
              icon: const Icon(Icons.more_horiz),
              onSelected: (action) => _handleGroupMenuAction(group, action),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _GroupMenuAction.rename,
                  child: Text('Renomear'),
                ),
                PopupMenuItem(
                  value: _GroupMenuAction.addLabel,
                  child: Text('Adicionar etiqueta'),
                ),
                PopupMenuItem(
                  value: _GroupMenuAction.selectAll,
                  child: Text('Marcar tudo'),
                ),
                PopupMenuItem(
                  value: _GroupMenuAction.unselectAll,
                  child: Text('Desmarcar tudo'),
                ),
                PopupMenuItem(
                  value: _GroupMenuAction.delete,
                  child: Text('Excluir'),
                ),
              ],
            ),
            _buildDragHandle(
              payload: _DragPayload.group(group.id),
              feedback: _buildDragFeedback(
                group.name.trim().isEmpty ? 'Grupo' : group.name.trim(),
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.pan_tool_alt_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedGroupBody(LabelGroupData group) {
    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.only(left: 18, right: 4),
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: Colors.blueGrey.shade300, width: 2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: _buildExpandedGroupLabels(group),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 32,
          child: DragTarget<_DragPayload>(
            onWillAcceptWithDetails: (details) {
              return details.data.isLabel &&
                  details.data.sourceGroupId == group.id;
            },
            onAcceptWithDetails: (details) {
              _moveLabelOutOfGroup(details.data, group.id);
            },
            builder: (context, candidateData, rejectedData) {
              final isActive = candidateData.any(
                (payload) =>
                    payload?.isLabel == true &&
                    payload?.sourceGroupId == group.id,
              );

              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 8),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: isActive ? 4 : 0,
                  decoration: BoxDecoration(
                    color: isActive ? Colors.blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  List<Widget> _buildExpandedGroupLabels(LabelGroupData group) {
    final children = <Widget>[];
    children.add(_buildGroupDropTarget(group.id, 0));

    for (var index = 0; index < group.labels.length; index++) {
      final label = group.labels[index];
      children.add(
        Padding(
          padding: const EdgeInsets.only(left: 16, right: 4),
          child: label.isEditing
              ? _buildEditableLabel(label)
              : _buildCompactLabel(label, sourceGroupId: group.id),
        ),
      );
      children.add(_buildGroupDropTarget(group.id, index + 1));
    }

    return children;
  }

  Widget _buildGroupDropTarget(String groupId, int index) {
    return DragTarget<_DragPayload>(
      onWillAcceptWithDetails: (details) => details.data.isLabel,
      onAcceptWithDetails: (details) {
        _moveLabelToGroup(details.data, groupId, index);
      },
      builder: (context, candidateData, rejectedData) {
        final isActive = candidateData.any(
          (payload) => payload?.isLabel == true,
        );

        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          height: isActive ? 18 : 8,
          margin: const EdgeInsets.only(left: 16, right: 4),
          alignment: Alignment.center,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: isActive ? 3 : 0,
            decoration: BoxDecoration(
              color: isActive ? Colors.blue : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEditableLabel(LabelData label) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Form(
          key: _labelFormKeyFor(label.id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                initialValue: label.text,
                decoration: const InputDecoration(
                  labelText: 'Texto',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Digite um texto';
                  }
                  return null;
                },
                onChanged: (value) {
                  _updateLabel(label.id, (label) => label.text = value);
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: label.lengthText,
                      decoration: const InputDecoration(
                        labelText: 'Comprimento',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Digite o comprimento';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        _updateLabel(
                          label.id,
                          (label) => label.lengthText = value,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      initialValue: label.widthText,
                      decoration: const InputDecoration(
                        labelText: 'Largura',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Digite a largura';
                        }
                        return null;
                      },
                      onChanged: (value) {
                        _updateLabel(
                          label.id,
                          (label) => label.widthText = value,
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      initialValue: label.quantityText,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Quantidade',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        final quantity = int.tryParse(value?.trim() ?? '');

                        if (quantity == null) {
                          return 'Digite a quantidade';
                        }

                        if (quantity <= 0) {
                          return 'Maior que zero';
                        }

                        return null;
                      },
                      onChanged: (value) {
                        _updateLabel(
                          label.id,
                          (label) => label.quantityText = value,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 56,
                    child: FilledButton(
                      onPressed: () => _deleteLabel(label.id),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                      child: const Icon(Icons.close),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 56,
                    child: FilledButton(
                      onPressed: () => _includeLabel(label.id),
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Icon(Icons.check),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactLabel(LabelData label, {required String? sourceGroupId}) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Colors.black12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            Checkbox(
              value: label.isSelected,
              onChanged: (value) {
                _setLabelSelected(label.id, value ?? false);
              },
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildCompactLine('Texto: ${label.text.trim()}'),
                  _buildCompactLine('Comprimento: ${label.lengthText.trim()}'),
                  _buildCompactLine('Largura: ${label.widthText.trim()}'),
                  _buildCompactLine('Quantidade: ${label.quantityText.trim()}'),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Editar',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editLabel(label.id),
            ),
            _buildDragHandle(
              payload: _DragPayload.label(
                label.id,
                sourceGroupId: sourceGroupId,
              ),
              feedback: _buildDragFeedback(
                label.text.trim().isEmpty ? 'Etiqueta' : label.text.trim(),
              ),
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Icon(Icons.pan_tool_alt_outlined),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDragHandle({
    required _DragPayload payload,
    required Widget feedback,
    required Widget child,
  }) {
    return LongPressDraggable<_DragPayload>(
      data: payload,
      feedback: feedback,
      childWhenDragging: Opacity(opacity: 0.35, child: child),
      child: child,
    );
  }

  Widget _buildDragFeedback(String title) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: Card(
          elevation: 8,
          color: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactLine(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, height: 1.2),
    );
  }

  Widget _buildBottomActions(BluetoothPrinterService bluetoothService) {
    final hasSelectedLabels = _allLabels().any(
      (label) => label.isSelected && !label.isEditing,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: hasSelectedLabels ? _unselectAllLabels : null,
              icon: const Icon(Icons.check_box_outline_blank),
              label: const Text('Desmarcar tudo'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              onPressed: _isPrinting
                  ? null
                  : () => _printSelectedLabels(context, bluetoothService),
              icon: _isPrinting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.print),
              label: const Text('Imprimir'),
            ),
          ),
        ],
      ),
    );
  }
}
