import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/label_data.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../services/label_storage_service.dart';
import '../bluetooth/bluetooth_connection_view.dart';

enum _LabelMenuAction { addGroup, addLabel, importCsv, clearAll }

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  static const String _defaultLabelImageAsset = 'assets/images/editar.png';

  final LabelStorageService _storageService = const LabelStorageService();
  final Map<String, GlobalKey<FormState>> _formKeys = {};

  List<LabelData> _labels = [];
  bool _isLoadingLabels = true;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadLabels());
  }

  Future<void> _loadLabels() async {
    final labels = await _storageService.loadLabels();

    if (!mounted) return;

    setState(() {
      _labels = labels;
      _isLoadingLabels = false;
    });
  }

  Future<void> _persistLabels() {
    return _storageService.saveLabels(_labels);
  }

  GlobalKey<FormState> _formKeyFor(String labelId) {
    return _formKeys.putIfAbsent(labelId, () => GlobalKey<FormState>());
  }

  void _handleMenuAction(_LabelMenuAction action) {
    switch (action) {
      case _LabelMenuAction.addGroup:
        _showMessage('Adicionar grupo sera configurado depois');
      case _LabelMenuAction.addLabel:
        _addLabel();
      case _LabelMenuAction.importCsv:
        _showMessage('Importar csv sera configurado depois');
      case _LabelMenuAction.clearAll:
        unawaited(_clearAllLabels());
    }
  }

  void _addLabel() {
    setState(() {
      _labels.add(LabelData.empty());
    });

    unawaited(_persistLabels());
  }

  Future<void> _clearAllLabels() async {
    if (_labels.isEmpty) return;

    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Limpar tudo?'),
          content: const Text(
            'Todas as etiquetas cadastradas ser\u00e3o removidas.',
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
      _labels = [];
      _formKeys.clear();
    });

    unawaited(_persistLabels());
  }

  void _updateLabel(String labelId, void Function(LabelData label) update) {
    final index = _labels.indexWhere((label) => label.id == labelId);
    if (index == -1) return;

    update(_labels[index]);
    unawaited(_persistLabels());
  }

  void _deleteLabel(String labelId) {
    setState(() {
      _labels.removeWhere((label) => label.id == labelId);
      _formKeys.remove(labelId);
    });

    unawaited(_persistLabels());
  }

  void _includeLabel(String labelId) {
    final formState = _formKeyFor(labelId).currentState;
    if (formState?.validate() != true) return;

    setState(() {
      final label = _labels.firstWhere((label) => label.id == labelId);
      label.isEditing = false;
      label.isSelected = false;
    });

    unawaited(_persistLabels());
  }

  void _editLabel(String labelId) {
    setState(() {
      final label = _labels.firstWhere((label) => label.id == labelId);
      label.isEditing = true;
    });

    unawaited(_persistLabels());
  }

  void _setLabelSelected(String labelId, bool isSelected) {
    setState(() {
      final label = _labels.firstWhere((label) => label.id == labelId);
      label.isSelected = isSelected;
    });

    unawaited(_persistLabels());
  }

  void _reorderLabels(int oldIndex, int newIndex) {
    setState(() {
      final label = _labels.removeAt(oldIndex);
      _labels.insert(newIndex, label);
    });

    unawaited(_persistLabels());
  }

  void _unselectAllLabels() {
    setState(() {
      for (final label in _labels) {
        label.isSelected = false;
      }
    });

    unawaited(_persistLabels());
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

    final selectedLabels = _labels
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

  void _showImageImportPending() {
    _showMessage('Importar imagem sera configurado depois');
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
        title: const Text('Menta e hortel\u00e3'),
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
                  : _buildLabelList(),
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
            child: Image.asset(_defaultLabelImageAsset, fit: BoxFit.contain),
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
                onPressed: _showImageImportPending,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabelList() {
    if (_labels.isEmpty) return const SizedBox.expand();

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: _labels.length,
      onReorderItem: _reorderLabels,
      itemBuilder: (context, index) {
        final label = _labels[index];

        return Padding(
          key: ValueKey(label.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: label.isEditing
              ? _buildEditableLabel(label)
              : _buildCompactLabel(label, index),
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
          key: _formKeyFor(label.id),
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
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: () => _deleteLabel(label.id),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          'X',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SizedBox(
                      height: 56,
                      child: FilledButton(
                        onPressed: () => _includeLabel(label.id),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text(
                          '✓',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
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

  Widget _buildCompactLabel(LabelData label, int index) {
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
            ReorderableDragStartListener(
              index: index,
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
    final hasSelectedLabels = _labels.any(
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
