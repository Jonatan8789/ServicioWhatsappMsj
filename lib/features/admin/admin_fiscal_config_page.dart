import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

class ConfiguracionFiscalPage extends StatefulWidget {
  const ConfiguracionFiscalPage({Key? key}) : super(key: key);

  @override
  State<ConfiguracionFiscalPage> createState() =>
      _ConfiguracionFiscalPageState();
}

class _ConfiguracionFiscalPageState extends State<ConfiguracionFiscalPage>
    with SingleTickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  late TabController _tabController;

  // 🏛️ CONTROLES AFIP / ARCA
  final _cuitArcaCtrl = TextEditingController();
  final _ptoVentaArcaCtrl = TextEditingController();
  int _comprobanteTipoArca = 11; // 11 = C, 1 = A, 6 = B
  bool _modoProduccionArca = false;
  bool _cargandoArca = true;
  bool _probandoArca = false;

  // 💳 CONTROLES MERCADO PAGO
  final _accessTokenMpCtrl = TextEditingController();
  final _publicKeyMpCtrl = TextEditingController();
  bool _modoProduccionMp = false;
  bool _cargandoMp = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarConfiguracionArca();
    _cargarConfiguracionMP();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cuitArcaCtrl.dispose();
    _ptoVentaArcaCtrl.dispose();
    _accessTokenMpCtrl.dispose();
    _publicKeyMpCtrl.dispose();
    super.dispose();
  }

  // =========================================================================
  // 🏛️ LÓGICA ARCA / AFIP
  // =========================================================================
  Future<void> _cargarConfiguracionArca() async {
    try {
      final doc = await _firestore
          .collection('configuraciones_fiscales')
          .doc('arca_reglas')
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _cuitArcaCtrl.text = (data['cuit'] ?? '').toString();
        _ptoVentaArcaCtrl.text = (data['puntoVenta'] ?? '1').toString();
        _comprobanteTipoArca = data['comprobanteTipo'] ?? 11;
        _modoProduccionArca = data['modoProduccion'] ?? false;
      }
    } catch (e) {
      print("Error cargando ARCA: $e");
    } finally {
      setState(() => _cargandoArca = false);
    }
  }

  Future<void> _guardarConfiguracionArca() async {
    try {
      await _firestore
          .collection('configuraciones_fiscales')
          .doc('arca_reglas')
          .set({
            'cuit': int.tryParse(_cuitArcaCtrl.text.trim()) ?? 0,
            'puntoVenta': int.tryParse(_ptoVentaArcaCtrl.text.trim()) ?? 1,
            'comprobanteTipo': _comprobanteTipoArca,
            'modoProduccion': _modoProduccionArca,
            'ultimaActualizacion': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('✅ Parámetros de ARCA guardados correctamente.'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('❌ Error al guardar ARCA: $e'),
        ),
      );
    }
  }

  Future<void> _probarConexionArca() async {
    setState(() => _probandoArca = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'probarConexionArca',
      );
      final resp = await callable.call({
        'cuit': _cuitArcaCtrl.text.trim(),
        'puntoVenta': _ptoVentaArcaCtrl.text.trim(),
        'modoProduccion': _modoProduccionArca,
      });

      if (resp.data['success'] == true) {
        showDialog(
          context: context,
          builder: (c) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green),
                SizedBox(width: 8),
                Text('Handshake Exitoso'),
              ],
            ),
            content: Text(
              'Conexión con los servidores de ARCA establecida.\n\nServidor App: ${resp.data['status']}\nBase de Datos: ${resp.data['dbServer']}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        throw Exception(resp.data['error']);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade900,
          content: Text('⚠️ Falló la prueba con ARCA: $e'),
        ),
      );
    } finally {
      setState(() => _probandoArca = false);
    }
  }

  // =========================================================================
  // 💳 LÓGICA MERCADO PAGO
  // =========================================================================
  Future<void> _cargarConfiguracionMP() async {
    try {
      final doc = await _firestore
          .collection('configuraciones_fiscales')
          .doc('mp_reglas')
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        _accessTokenMpCtrl.text = data['accessToken'] ?? '';
        _publicKeyMpCtrl.text = data['publicKey'] ?? '';
        _modoProduccionMp = data['modoProduccion'] ?? false;
      }
    } catch (e) {
      print("Error cargando Mercado Pago: $e");
    } finally {
      setState(() => _cargandoMp = false);
    }
  }

  Future<void> _guardarConfiguracionMP() async {
    try {
      await _firestore
          .collection('configuraciones_fiscales')
          .doc('mp_reglas')
          .set({
            'accessToken': _accessTokenMpCtrl.text.trim(),
            'publicKey': _publicKeyMpCtrl.text.trim(),
            'modoProduccion': _modoProduccionMp,
            'ultimaActualizacion': FieldValue.serverTimestamp(),
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('✅ Credenciales de Mercado Pago guardadas.'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text('❌ Error al guardar Mercado Pago: $e'),
        ),
      );
    }
  }

  // =========================================================================
  // 🎨 INTERFAZ GRÁFICA
  // =========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración de Integraciones & Fiscalidad'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.cyanAccent,
          labelColor: Colors.cyanAccent,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.receipt_long_rounded), text: 'ARCA / AFIP'),
            Tab(icon: Icon(Icons.qr_code_2_rounded), text: 'Mercado Pago'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildFormularioArca(), _buildFormularioMercadoPago()],
      ),
    );
  }

  // FORMULARIO ARCA / AFIP
  Widget _buildFormularioArca() {
    if (_cargandoArca) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SizedBox(
          width: 600,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Facturación Electrónica ARCA',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Asegúrese de subir los archivos .crt y .key en la carpeta de funciones del backend.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const Divider(height: 24),

                  TextField(
                    controller: _cuitArcaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'CUIT de la Empresa / Club',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge),
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _ptoVentaArcaCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Punto de Venta Autorizado (Ej: 1)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.store),
                    ),
                  ),
                  const SizedBox(height: 16),

                  DropdownButtonFormField<int>(
                    value: _comprobanteTipoArca,
                    decoration: const InputDecoration(
                      labelText: 'Tipo Comprobante por Defecto',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.description),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 11,
                        child: Text('Factura C (Monotributo / Exento)'),
                      ),
                      DropdownMenuItem(
                        value: 6,
                        child: Text(
                          'Factura B (Resp. Inscripto a Cons. Final)',
                        ),
                      ),
                      DropdownMenuItem(
                        value: 1,
                        child: Text(
                          'Factura A (Resp. Inscripto a Resp. Inscripto)',
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setState(() => _comprobanteTipoArca = val!),
                  ),
                  const SizedBox(height: 16),

                  SwitchListTile(
                    title: const Text('Modo Producción'),
                    subtitle: Text(
                      _modoProduccionArca
                          ? 'Emitiendo comprobantes legales reales'
                          : 'Entorno Homologación / Testing',
                    ),
                    value: _modoProduccionArca,
                    activeColor: Colors.green,
                    onChanged: (val) =>
                        setState(() => _modoProduccionArca = val),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _probandoArca ? null : _probarConexionArca,
                          icon: _probandoArca
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.sync),
                          label: const Text('Probar Conexión'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _guardarConfiguracionArca,
                          icon: const Icon(Icons.save, color: Colors.white),
                          label: const Text(
                            'Guardar ARCA',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // FORMULARIO MERCADO PAGO
  Widget _buildFormularioMercadoPago() {
    if (_cargandoMp) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: SizedBox(
          width: 600,
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Image.network(
                        'https://http2.mlstatic.com/frontend-assets/ui-navigation/5.19.1/mercadopago/logo__large.png',
                        height: 28,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.qr_code,
                          color: Colors.blue,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text(
                        'Credenciales Mercado Pago',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Obtenga sus credenciales desde el panel de desarrolladores de Mercado Pago.',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  const Divider(height: 24),

                  TextField(
                    controller: _accessTokenMpCtrl,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Access Token (PROD_ / TEST_)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.key_rounded),
                      helperText:
                          'Requerido para generar cobros y escuchar webhooks IPN',
                    ),
                  ),
                  const SizedBox(height: 16),

                  TextField(
                    controller: _publicKeyMpCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Public Key (Opcional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.lock_open_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SwitchListTile(
                    title: const Text('Entorno Real / Producción'),
                    subtitle: Text(
                      _modoProduccionMp
                          ? 'Procesando pagos monetarios reales'
                          : 'Modo Sandbox / Pruebas',
                    ),
                    value: _modoProduccionMp,
                    activeColor: Colors.blue,
                    onChanged: (val) => setState(() => _modoProduccionMp = val),
                  ),
                  const SizedBox(height: 24),

                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(
                          0xFF009EE3,
                        ), // Azul oficial Mercado Pago
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      onPressed: _guardarConfiguracionMP,
                      icon: const Icon(Icons.save, color: Colors.white),
                      label: const Text(
                        'Guardar Credenciales MP',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
