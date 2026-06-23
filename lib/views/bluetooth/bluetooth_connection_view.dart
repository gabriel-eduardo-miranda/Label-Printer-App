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
    // Inicia o escaneamento de dispositivos automaticamente ao entrar na tela
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BluetoothPrinterService>().startScan();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Escuta as alterações que acontecem dentro do serviço de bluetooth
    final bluetoothService = context.watch<BluetoothPrinterService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Printer'),
        actions: [
          // Botão no topo para atualizar a busca manual
          if (bluetoothService.isScanning)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => bluetoothService.startScan(),
            ),
        ],
      ),
      body: bluetoothService.discoveredDevices.isEmpty
          ? Center(
              child: Text(
                bluetoothService.isScanning
                    ? 'Scanning for devices...'
                    : 'No devices found.',
              ),
            )
          : ListView.builder(
              itemCount: bluetoothService.discoveredDevices.length,
              itemBuilder: (context, index) {
                final device = bluetoothService.discoveredDevices[index];
                final isCurrentConnected =
                    bluetoothService.connectedDevice?.address == device.address;

                return ListTile(
                  leading: const Icon(Icons.print),
                  title: Text(device.name ?? 'Unknown Device'),
                  subtitle: Text(device.address ?? ''),
                  trailing: isCurrentConnected
                      ? const Text(
                          'Connected',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : const Icon(Icons.chevron_right),
                  onTap: () async {
                    if (isCurrentConnected) return;

                    // Mostra um feedback de carregamento rápido
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Connecting to ${device.name}...'),
                      ),
                    );

                    bool success = await bluetoothService.connectToDevice(
                      device,
                    );

                    if (mounted) {
                      if (success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Printer connected successfully!'),
                          ),
                        );
                        // Volta para a tela inicial
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Failed to connect. Try again.'),
                          ),
                        );
                      }
                    }
                  },
                );
              },
            ),
    );
  }
}
