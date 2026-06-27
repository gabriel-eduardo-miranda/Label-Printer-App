import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/bluetooth_printer_service.dart';

class BluetoothConnectionView extends StatefulWidget {
  const BluetoothConnectionView({super.key});

  @override
  State<BluetoothConnectionView> createState() =>
      _BluetoothConnectionViewState();
}

class _BluetoothConnectionViewState extends State<BluetoothConnectionView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothPrinterService>().startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    final bluetoothService = context.watch<BluetoothPrinterService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Conectar impressora'),
        actions: [
          IconButton(
            tooltip: 'Limpar log',
            icon: const Icon(Icons.delete_outline),
            onPressed: bluetoothService.clearDebugLogs,
          ),
          if (bluetoothService.isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              tooltip: 'Buscar novamente',
              icon: const Icon(Icons.refresh),
              onPressed: bluetoothService.startScan,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _buildDeviceList(bluetoothService)),
          const Divider(height: 1),
          SizedBox(
            height: 220,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Log de depuracao',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: SingleChildScrollView(
                  reverse: true,
                  child: SelectableText(
                    bluetoothService.debugLogText.isEmpty
                        ? 'Nenhum log ainda.'
                        : bluetoothService.debugLogText,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceList(BluetoothPrinterService bluetoothService) {
    if (bluetoothService.discoveredDevices.isEmpty) {
      return Center(
        child: Text(
          bluetoothService.isScanning
              ? 'Buscando dispositivos...'
              : 'Nenhum dispositivo encontrado.',
        ),
      );
    }

    return ListView.builder(
      itemCount: bluetoothService.discoveredDevices.length,
      itemBuilder: (context, index) {
        final device = bluetoothService.discoveredDevices[index];
        final isCurrentConnected =
            bluetoothService.connectedDevice?.address == device.address;

        return ListTile(
          leading: const Icon(Icons.print),
          title: Text(
            device.name.isNotEmpty ? device.name : 'Dispositivo desconhecido',
          ),
          subtitle: Text(device.address ?? ''),
          trailing: isCurrentConnected
              ? const Text(
                  'Conectada',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                )
              : const Icon(Icons.chevron_right),
          onTap: () async {
            if (isCurrentConnected) return;

            final pin = await _askForPin(device.name);
            if (!context.mounted || pin == null) return;

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Conectando em ${device.name}...')),
            );

            final success = await bluetoothService.connectToDevice(
              device,
              pin: pin,
            );

            if (!context.mounted) return;

            if (success) {
              Navigator.of(context).pop();
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Falha ao conectar. Verifique o log.'),
                ),
              );
            }
          },
        );
      },
    );
  }

  Future<String?> _askForPin(String deviceName) async {
    final controller = TextEditingController(text: '0000');

    try {
      return await showDialog<String>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('PIN da impressora'),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: deviceName.isNotEmpty ? deviceName : 'Impressora',
                hintText: '0000',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, ''),
                child: const Text('Sem PIN'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: const Text('Conectar'),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }
}
