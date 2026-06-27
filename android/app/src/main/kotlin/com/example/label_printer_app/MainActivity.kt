package com.example.label_printer_app

import android.Manifest
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val mainHandler = Handler(Looper.getMainLooper())
    private var activeScanCallback: ScanCallback? = null
    private var activeFinishCallback: Runnable? = null
    private var printerGatt: BluetoothGatt? = null
    private var printerWriteCharacteristic: BluetoothGattCharacteristic? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "label_printer_app/ble_scanner"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanBle" -> {
                    val timeoutMs = call.argument<Number>("timeoutMs")?.toLong() ?: 6000L
                    scanBleDevices(timeoutMs, result)
                }
                "pairBle" -> {
                    val address = call.argument<String>("address")
                    val pin = call.argument<String>("pin")
                    pairBleDevice(address, pin, result)
                }
                "connectBlePrinter" -> {
                    val address = call.argument<String>("address")
                    connectBlePrinter(address, result)
                }
                "disconnectBlePrinter" -> {
                    disconnectBlePrinter()
                    result.success(mapOf("success" to true, "logs" to listOf("Conexao BLE nativa encerrada")))
                }
                "writeBlePrinter" -> {
                    val bytes = call.argument<Any>("bytes")
                    writeBlePrinter(bytes, result)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun scanBleDevices(timeoutMs: Long, result: MethodChannel.Result) {
        stopActiveBleScan()
        val logs = mutableListOf<String>()

        fun finishEmpty(message: String) {
            logs.add(message)
            result.success(mapOf("devices" to emptyList<Map<String, Any?>>(), "logs" to logs))
        }

        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter: BluetoothAdapter? = bluetoothManager.adapter
        logs.add("Fallback nativo: adapter=${adapter != null}, enabled=${adapter?.isEnabled == true}")

        if (adapter?.isEnabled != true) {
            finishEmpty("Fallback nativo cancelado: Bluetooth desligado ou indisponivel")
            return
        }

        if (!hasBleScanPermissions()) {
            finishEmpty("Fallback nativo cancelado: permissoes BLE ausentes")
            return
        }

        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            finishEmpty("Fallback nativo cancelado: bluetoothLeScanner nulo")
            return
        }

        val devices = linkedMapOf<String, MutableMap<String, Any?>>()
        var finished = false

        fun finish() {
            mainHandler.post {
                if (finished) return@post
                finished = true

                try {
                    activeScanCallback?.let { scanner.stopScan(it) }
                } catch (_: SecurityException) {
                }

                activeFinishCallback?.let { mainHandler.removeCallbacks(it) }
                activeScanCallback = null
                activeFinishCallback = null

                logs.add("Fallback nativo finalizado: ${devices.size} dispositivo(s)")
                result.success(
                    mapOf(
                        "devices" to devices.values.sortedByDescending { it["rssi"] as Int },
                        "logs" to logs
                    )
                )
            }
        }

        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, scanResult: ScanResult) {
                mainHandler.post { addScanResult(scanResult, devices, logs) }
            }

            override fun onBatchScanResults(results: MutableList<ScanResult>) {
                mainHandler.post {
                    results.forEach { addScanResult(it, devices, logs) }
                }
            }

            override fun onScanFailed(errorCode: Int) {
                logs.add("Fallback nativo falhou: erro $errorCode")
                finish()
            }
        }

        val finishCallback = Runnable { finish() }
        activeScanCallback = callback
        activeFinishCallback = finishCallback

        try {
            val settings = ScanSettings.Builder()
                .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
                .build()
            scanner.startScan(null, settings, callback)
            logs.add("Fallback nativo iniciou startScan por ${timeoutMs.coerceIn(1000, 12000)}ms")
            mainHandler.postDelayed(finishCallback, timeoutMs.coerceIn(1000, 12000))
        } catch (e: SecurityException) {
            logs.add("Fallback nativo exception SecurityException: ${e.message}")
            finish()
        } catch (e: IllegalStateException) {
            logs.add("Fallback nativo exception IllegalStateException: ${e.message}")
            finish()
        }
    }

    private fun addScanResult(
        scanResult: ScanResult,
        devices: LinkedHashMap<String, MutableMap<String, Any?>>,
        logs: MutableList<String>
    ) {
        val address = scanResult.device?.address ?: return
        val advertisedName = scanResult.scanRecord?.deviceName
        val deviceName = try {
            scanResult.device?.name
        } catch (_: SecurityException) {
            null
        }

        val name = firstNotBlank(advertisedName, deviceName, address)
        val existing = devices[address]

        if (existing == null) {
            logs.add("BLE visto: $name | $address | rssi=${scanResult.rssi}")
            devices[address] = mutableMapOf(
                "name" to name,
                "address" to address,
                "rssi" to scanResult.rssi
            )
        } else {
            existing["rssi"] = maxOf(existing["rssi"] as Int, scanResult.rssi)
            if ((existing["name"] as String).isBlank() || existing["name"] == address) {
                existing["name"] = name
            }
        }
    }

    private fun firstNotBlank(vararg values: String?): String {
        return values.firstOrNull { !it.isNullOrBlank() } ?: "Unknown BLE"
    }

    private fun pairBleDevice(address: String?, pin: String?, result: MethodChannel.Result) {
        val logs = mutableListOf<String>()
        var completed = false
        var receiver: BroadcastReceiver? = null
        lateinit var timeoutRunnable: Runnable

        fun finish(success: Boolean, message: String) {
            if (completed) return
            completed = true
            receiver?.let { cleanupPairReceiver(it, timeoutRunnable) }
            logs.add(message)
            result.success(mapOf("success" to success, "logs" to logs))
        }

        if (address.isNullOrBlank()) {
            finish(false, "Pareamento cancelado: endereco vazio")
            return
        }

        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter

        if (adapter?.isEnabled != true) {
            finish(false, "Pareamento cancelado: Bluetooth desligado ou indisponivel")
            return
        }

        if (!hasPermissionForConnect()) {
            finish(false, "Pareamento cancelado: permissao BLUETOOTH_CONNECT ausente")
            return
        }

        val device = try {
            adapter.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            finish(false, "Pareamento cancelado: endereco invalido $address")
            return
        }

        logs.add("Pareamento: dispositivo ${device.name ?: address}, bondState=${device.bondState}")

        if (device.bondState == BluetoothDevice.BOND_BONDED) {
            finish(true, "Pareamento ignorado: dispositivo ja pareado")
            return
        }

        val cleanPin = pin?.trim().orEmpty()
        timeoutRunnable = Runnable {
            finish(false, "Pareamento falhou: tempo limite aguardando Android")
        }

        receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (completed) return

                val action = intent.action
                val receivedDevice: BluetoothDevice? =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE, BluetoothDevice::class.java)
                    } else {
                        @Suppress("DEPRECATION")
                        intent.getParcelableExtra(BluetoothDevice.EXTRA_DEVICE)
                    }

                if (receivedDevice?.address != address) return

                if (BluetoothDevice.ACTION_PAIRING_REQUEST == action && cleanPin.isNotEmpty()) {
                    try {
                        receivedDevice.setPin(cleanPin.toByteArray(Charsets.UTF_8))
                        receivedDevice.setPairingConfirmation(true)
                        abortBroadcast()
                        logs.add("Pareamento: PIN enviado automaticamente")
                    } catch (e: Exception) {
                        logs.add("Pareamento: erro ao enviar PIN automaticamente: ${e.message}")
                    }
                }

                if (BluetoothDevice.ACTION_BOND_STATE_CHANGED == action) {
                    val bondState = intent.getIntExtra(BluetoothDevice.EXTRA_BOND_STATE, BluetoothDevice.ERROR)
                    val previousBondState = intent.getIntExtra(
                        BluetoothDevice.EXTRA_PREVIOUS_BOND_STATE,
                        BluetoothDevice.ERROR
                    )
                    logs.add("Pareamento: bondState $previousBondState -> $bondState")

                    when (bondState) {
                        BluetoothDevice.BOND_BONDED -> {
                            finish(true, "Pareamento bem-sucedido")
                        }
                        BluetoothDevice.BOND_NONE -> {
                            if (previousBondState == BluetoothDevice.BOND_BONDING) {
                                finish(false, "Pareamento falhou ou foi recusado")
                            }
                        }
                    }
                }
            }
        }

        try {
            val filter = IntentFilter().apply {
                addAction(BluetoothDevice.ACTION_PAIRING_REQUEST)
                addAction(BluetoothDevice.ACTION_BOND_STATE_CHANGED)
                priority = IntentFilter.SYSTEM_HIGH_PRIORITY
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                registerReceiver(receiver!!, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("DEPRECATION")
                registerReceiver(receiver!!, filter)
            }

            if (cleanPin.isNotEmpty()) {
                try {
                    device.setPin(cleanPin.toByteArray(Charsets.UTF_8))
                    logs.add("Pareamento: PIN preconfigurado")
                } catch (e: Exception) {
                    logs.add("Pareamento: setPin antes do createBond falhou: ${e.message}")
                }
            }

            val started = device.createBond()
            logs.add("Pareamento: createBond retornou $started")

            if (!started) {
                finish(false, "Pareamento falhou: createBond retornou false")
                return
            }

            mainHandler.postDelayed(timeoutRunnable, 20000)
        } catch (e: SecurityException) {
            finish(false, "Pareamento exception SecurityException: ${e.message}")
        } catch (e: Exception) {
            finish(false, "Pareamento exception: ${e.message}")
        }
    }

    private fun cleanupPairReceiver(receiver: BroadcastReceiver, timeoutRunnable: Runnable) {
        mainHandler.removeCallbacks(timeoutRunnable)
        try {
            unregisterReceiver(receiver)
        } catch (_: Exception) {
        }
    }

    private fun connectBlePrinter(address: String?, result: MethodChannel.Result) {
        val logs = mutableListOf<String>()
        var completed = false
        lateinit var timeoutRunnable: Runnable

        fun finish(success: Boolean, message: String) {
            mainHandler.post {
                if (completed) return@post
                completed = true
                mainHandler.removeCallbacks(timeoutRunnable)
                logs.add(message)
                result.success(mapOf("success" to success, "logs" to logs))
            }
        }

        if (address.isNullOrBlank()) {
            result.success(mapOf("success" to false, "logs" to listOf("Conexao BLE nativa cancelada: endereco vazio")))
            return
        }

        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val adapter = bluetoothManager.adapter

        if (adapter?.isEnabled != true) {
            result.success(
                mapOf(
                    "success" to false,
                    "logs" to listOf("Conexao BLE nativa cancelada: Bluetooth desligado ou indisponivel")
                )
            )
            return
        }

        if (!hasPermissionForConnect()) {
            result.success(
                mapOf(
                    "success" to false,
                    "logs" to listOf("Conexao BLE nativa cancelada: permissao BLUETOOTH_CONNECT ausente")
                )
            )
            return
        }

        val device = try {
            adapter.getRemoteDevice(address)
        } catch (e: IllegalArgumentException) {
            result.success(
                mapOf(
                    "success" to false,
                    "logs" to listOf("Conexao BLE nativa cancelada: endereco invalido $address")
                )
            )
            return
        }

        disconnectBlePrinter()
        logs.add("Conexao BLE nativa: conectando em ${device.name ?: address}, bondState=${device.bondState}")

        timeoutRunnable = Runnable {
            disconnectBlePrinter()
            finish(false, "Conexao BLE nativa falhou: tempo limite")
        }

        val callback = object : BluetoothGattCallback() {
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                mainHandler.post {
                    logs.add("Conexao BLE nativa: state=$newState status=$status")

                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        disconnectBlePrinter()
                        finish(false, "Conexao BLE nativa falhou: status GATT $status")
                        return@post
                    }

                    when (newState) {
                        BluetoothProfile.STATE_CONNECTED -> {
                            printerGatt = gatt
                            logs.add("Conexao BLE nativa: conectado, descobrindo servicos")
                            gatt.discoverServices()
                        }
                        BluetoothProfile.STATE_DISCONNECTED -> {
                            disconnectBlePrinter()
                            finish(false, "Conexao BLE nativa desconectou antes de ficar pronta")
                        }
                    }
                }
            }

            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                mainHandler.post {
                    if (status != BluetoothGatt.GATT_SUCCESS) {
                        disconnectBlePrinter()
                        finish(false, "Conexao BLE nativa falhou ao descobrir servicos: $status")
                        return@post
                    }

                    val writable = findWritableCharacteristic(gatt, logs)
                    if (writable == null) {
                        disconnectBlePrinter()
                        finish(false, "Conexao BLE nativa falhou: nenhuma characteristic de escrita")
                        return@post
                    }

                    printerGatt = gatt
                    printerWriteCharacteristic = writable
                    logs.add("Conexao BLE nativa pronta: write=${writable.uuid}")
                    finish(true, "Conexao BLE nativa bem-sucedida")
                }
            }
        }

        try {
            timeoutRunnable = Runnable {
                disconnectBlePrinter()
                finish(false, "Conexao BLE nativa falhou: tempo limite")
            }

            printerGatt = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                device.connectGatt(this, false, callback, BluetoothDevice.TRANSPORT_LE)
            } else {
                @Suppress("DEPRECATION")
                device.connectGatt(this, false, callback)
            }
            mainHandler.postDelayed(timeoutRunnable, 20000)
        } catch (e: SecurityException) {
            disconnectBlePrinter()
            finish(false, "Conexao BLE nativa exception SecurityException: ${e.message}")
        } catch (e: Exception) {
            disconnectBlePrinter()
            finish(false, "Conexao BLE nativa exception: ${e.message}")
        }
    }

    private fun findWritableCharacteristic(
        gatt: BluetoothGatt,
        logs: MutableList<String>
    ): BluetoothGattCharacteristic? {
        var fallback: BluetoothGattCharacteristic? = null

        gatt.services.forEach { service ->
            logs.add("Servico BLE: ${service.uuid}")

            service.characteristics.forEach { characteristic ->
                val properties = characteristic.properties
                val canWrite =
                    properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0
                val canWriteNoResponse =
                    properties and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE != 0

                logs.add(
                    "Characteristic BLE: ${characteristic.uuid} props=$properties " +
                        "write=$canWrite writeNoResp=$canWriteNoResponse"
                )

                if (canWriteNoResponse) return characteristic
                if (canWrite && fallback == null) fallback = characteristic
            }
        }

        return fallback
    }

    private fun disconnectBlePrinter() {
        try {
            printerGatt?.disconnect()
            printerGatt?.close()
        } catch (_: SecurityException) {
        } catch (_: Exception) {
        }

        printerGatt = null
        printerWriteCharacteristic = null
    }

    private fun writeBlePrinter(bytes: Any?, result: MethodChannel.Result) {
        val logs = mutableListOf<String>()
        val gatt = printerGatt
        val characteristic = printerWriteCharacteristic

        if (gatt == null || characteristic == null) {
            result.success(
                mapOf(
                    "success" to false,
                    "logs" to listOf("Escrita BLE cancelada: impressora nativa nao conectada")
                )
            )
            return
        }

        if (!hasPermissionForConnect()) {
            result.success(
                mapOf(
                    "success" to false,
                    "logs" to listOf("Escrita BLE cancelada: permissao BLUETOOTH_CONNECT ausente")
                )
            )
            return
        }

        val data = when (bytes) {
            is ByteArray -> bytes
            is ArrayList<*> -> bytes.mapNotNull { (it as? Number)?.toByte() }.toByteArray()
            is List<*> -> bytes.mapNotNull { (it as? Number)?.toByte() }.toByteArray()
            else -> ByteArray(0)
        }
        if (data.isEmpty()) {
            result.success(
                mapOf(
                    "success" to false,
                    "logs" to listOf("Escrita BLE cancelada: bytes vazios")
                )
            )
            return
        }

        val chunkSize = 20
        val chunks = data.toList().chunked(chunkSize)
        var completed = false
        logs.add("Escrita BLE iniciada: ${data.size} bytes em ${chunks.size} chunk(s)")

        fun finish(success: Boolean, extraLog: String? = null) {
            if (completed) return
            completed = true
            val finalLogs = if (extraLog == null) logs else logs + extraLog
            result.success(mapOf("success" to success, "logs" to finalLogs))
        }

        try {
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE

            chunks.forEachIndexed { index, chunk ->
                mainHandler.postDelayed({
                    if (completed) return@postDelayed

                    try {
                        @Suppress("DEPRECATION")
                        characteristic.value = chunk.toByteArray()
                        @Suppress("DEPRECATION")
                        val started = gatt.writeCharacteristic(characteristic)
                        logs.add("Escrita BLE chunk ${index + 1}/${chunks.size}: ${chunk.size} bytes started=$started")

                        if (index == chunks.lastIndex) {
                            finish(started)
                        }
                    } catch (e: SecurityException) {
                        finish(false, "Escrita BLE SecurityException: ${e.message}")
                    } catch (e: Exception) {
                        finish(false, "Escrita BLE exception: ${e.message}")
                    }
                }, index * 35L)
            }
        } catch (e: Exception) {
            finish(false, "Escrita BLE exception inicial: ${e.message}")
        }
    }

    private fun hasBleScanPermissions(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            hasPermission(Manifest.permission.BLUETOOTH_SCAN) && hasPermissionForConnect()
        } else {
            hasPermission(Manifest.permission.ACCESS_FINE_LOCATION)
        }
    }

    private fun hasPermissionForConnect(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
    }

    private fun hasPermission(permission: String): Boolean {
        return ActivityCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun stopActiveBleScan() {
        val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
        val scanner = bluetoothManager.adapter?.bluetoothLeScanner

        try {
            activeScanCallback?.let { scanner?.stopScan(it) }
        } catch (_: SecurityException) {
        }

        activeFinishCallback?.let { mainHandler.removeCallbacks(it) }
        activeScanCallback = null
        activeFinishCallback = null
    }
}
