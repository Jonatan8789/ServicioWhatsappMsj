import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../services/auditoria_service.dart';

class ConfiguracionFiscalPage extends StatefulWidget {
  // Permite abrir la pantalla directo en una pestaña puntual (ej. el
  // "WhatsApp Pádel" del menú de Pádel, que quiere entrar derecho a los
  // interruptores de notificaciones sin pasar por ARCA/Mercado Pago).
  final int pestanaInicial;

  const ConfiguracionFiscalPage({Key? key, this.pestanaInicial = 0})
      : super(key: key);

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
  final _alicuotaIvaCtrl = TextEditingController(text: '21');
  int _comprobanteTipoArca = 11; // 11 = C, 1 = A, 6 = B
  bool _modoProduccionArca = false;
  bool _cargandoArca = true;
  bool _probandoArca = false;

  // 💳 CONTROLES MERCADO PAGO
  final _accessTokenMpCtrl = TextEditingController();
  final _publicKeyMpCtrl = TextEditingController();
  bool _modoProduccionMp = false;
  bool _cargandoMp = true;

  // 📲 CONTROLES WHATSAPP (destino de las notificaciones a "el admin")
  final _telefonoAdminWhatsappCtrl = TextEditingController();
  bool _cargandoWhatsapp = true;
  bool _recordatoriosActivos = false;
  bool _guardandoToggleRecordatorios = false;

  // 🎾 Interruptores de WhatsApp específicos de pádel (Fase 5): clases,
  // turno fijo, partido abierto y aviso de recibo de pago — todos default
  // apagados, mismo criterio de seguridad que 'recordatoriosActivos'.
  bool _notifClasesPadelActivo = false;
  bool _notifTurnoFijoActivo = false;
  bool _notifPartidoAbiertoActivo = false;
  bool _notifPagoConfirmadoActivo = false;
  bool _guardandoToggleNotifPadel = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.pestanaInicial,
    );
    _cargarConfiguracionArca();
    _cargarConfiguracionMP();
    _cargarConfiguracionWhatsapp();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _cuitArcaCtrl.dispose();
    _ptoVentaArcaCtrl.dispose();
    _alicuotaIvaCtrl.dispose();
    _accessTokenMpCtrl.dispose();
    _publicKeyMpCtrl.dispose();
    _telefonoAdminWhatsappCtrl.dispose();
    super.dispose();
  }

  // =========================================================================
  // 📲 LÓGICA WHATSAPP (teléfono de administrador)
  // =========================================================================
  Future<void> _cargarConfiguracionWhatsapp() async {
    try {
      final doc = await _firestore
          .collection('configuraciones_fiscales')
          .doc('whatsapp_reglas')
          .get();
      if (doc.exists) {
        final datos = doc.data()!;
        _telefonoAdminWhatsappCtrl.text = (datos['telefonoAdmin'] ?? '').toString();
        _recordatoriosActivos = datos['recordatoriosActivos'] == true;
        _notifClasesPadelActivo = datos['notifClasesPadelActivo'] == true;
        _notifTurnoFijoActivo = datos['notifTurnoFijoActivo'] == true;
        _notifPartidoAbiertoActivo = datos['notifPartidoAbiertoActivo'] == true;
        _notifPagoConfirmadoActivo = datos['notifPagoConfirmadoActivo'] == true;
      }
    } catch (e) {
      print("Error cargando WhatsApp: $e");
    } finally {
      setState(() => _cargandoWhatsapp = false);
    }
  }

  // 🔌 Se guarda aparte del botón "Guardar WhatsApp" para que prender/apagar
  // sea inmediato (sin tener que tocar el teléfono ni apretar guardar), y
  // con merge:true para no pisar el resto de la config al cambiarlo.
  Future<void> _cambiarToggleRecordatorios(bool valor) async {
    setState(() => _guardandoToggleRecordatorios = true);
    try {
      await _firestore
          .collection('configuraciones_fiscales')
          .doc('whatsapp_reglas')
          .set({'recordatoriosActivos': valor}, SetOptions(merge: true));
      if (mounted) setState(() => _recordatoriosActivos = valor);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardandoToggleRecordatorios = false);
    }
  }

  // 🎾 Mismo criterio que _cambiarToggleRecordatorios: inmediato y con
  // merge:true, un solo método genérico para los 4 interruptores de pádel
  // en vez de repetirlo 4 veces.
  Future<void> _cambiarToggleNotifPadel(String campo, bool valor) async {
    setState(() => _guardandoToggleNotifPadel = true);
    try {
      await _firestore
          .collection('configuraciones_fiscales')
          .doc('whatsapp_reglas')
          .set({campo: valor}, SetOptions(merge: true));
      if (mounted) {
        setState(() {
          switch (campo) {
            case 'notifClasesPadelActivo':
              _notifClasesPadelActivo = valor;
              break;
            case 'notifTurnoFijoActivo':
              _notifTurnoFijoActivo = valor;
              break;
            case 'notifPartidoAbiertoActivo':
              _notifPartidoAbiertoActivo = valor;
              break;
            case 'notifPagoConfirmadoActivo':
              _notifPagoConfirmadoActivo = valor;
              break;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _guardandoToggleNotifPadel = false);
    }
  }

  Future<void> _guardarConfiguracionWhatsapp() async {
    try {
      await _firestore
          .collection('configuraciones_fiscales')
          .doc('whatsapp_reglas')
          .set({
            'telefonoAdmin': _telefonoAdminWhatsappCtrl.text.trim(),
            'ultimaActualizacion': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      await registrarAuditoria(
        accion: 'guardar_configuracion_whatsapp',
        entidad: 'configuraciones_fiscales',
        entidadId: 'whatsapp_reglas',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('✅ Teléfono de WhatsApp guardado correctamente.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('❌ Error al guardar WhatsApp: $e'),
          ),
        );
      }
    }
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
        _alicuotaIvaCtrl.text = (data['alicuotaIvaPorcentaje'] ?? 21)
            .toString();
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
            'alicuotaIvaPorcentaje':
                double.tryParse(_alicuotaIvaCtrl.text.trim()) ?? 21,
            'ultimaActualizacion': FieldValue.serverTimestamp(),
          });
      // 📋 No se registran CUIT/credenciales en el detalle — sólo que la
      // config cambió y en qué modo, para no filtrar datos sensibles al
      // propio log de auditoría.
      await registrarAuditoria(
        accion: 'guardar_configuracion_arca',
        entidad: 'configuraciones_fiscales',
        entidadId: 'arca_reglas',
        detalle: {'modoProduccion': _modoProduccionArca},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('✅ Parámetros de ARCA guardados correctamente.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('❌ Error al guardar ARCA: $e'),
          ),
        );
      }
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
        if (!mounted) return;
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade900,
            content: Text('⚠️ Falló la prueba con ARCA: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _probandoArca = false);
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
      await registrarAuditoria(
        accion: 'guardar_configuracion_mercadopago',
        entidad: 'configuraciones_fiscales',
        entidadId: 'mp_reglas',
        detalle: {'modoProduccion': _modoProduccionMp},
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('✅ Credenciales de Mercado Pago guardadas.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('❌ Error al guardar Mercado Pago: $e'),
          ),
        );
      }
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
            Tab(icon: Icon(Icons.chat_rounded), text: 'WhatsApp'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFormularioArca(),
          _buildFormularioMercadoPago(),
          _buildFormularioWhatsapp(),
        ],
      ),
    );
  }

  // FORMULARIO WHATSAPP
  Widget _buildFormularioWhatsapp() {
    if (_cargandoWhatsapp) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            children: [
              Card(
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
                        'Notificaciones por WhatsApp',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Número al que se avisa cuando un socio adjunta un comprobante de pago desde su portal (con el código de país, sin espacios ni símbolos — ej: 5491112345678).',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const Divider(height: 24),
                      TextField(
                        controller: _telefonoAdminWhatsappCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono del Administrador',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.phone_android_rounded),
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F172A),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          onPressed: _guardarConfiguracionWhatsapp,
                          icon: const Icon(Icons.save, color: Colors.white),
                          label: const Text(
                            'Guardar WhatsApp',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildCardRecordatorios(),
              const SizedBox(height: 20),
              _buildCardNotificacionesPadel(),
            ],
          ),
        ),
      ),
    );
  }

  // 🎾 NOTIFICACIONES DE PÁDEL (Fase 5): clase confirmada, turno fijo
  // confirmado, eventos de partido abierto (alguien se une / se completa) y
  // aviso de recibo cuando se aprueba un pago por Mercado Pago. Cada uno es
  // un interruptor independiente, todos apagados por defecto.
  Widget _buildCardNotificacionesPadel() {
    Widget switchPadel({
      required String campo,
      required bool valor,
      required String titulo,
      required String subtitulo,
    }) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: valor,
        activeColor: Colors.green,
        onChanged: _guardandoToggleNotifPadel
            ? null
            : (v) => _cambiarToggleNotifPadel(campo, v),
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitulo, style: const TextStyle(fontSize: 11.5)),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notificaciones de Pádel',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Avisos automáticos por WhatsApp para eventos del módulo de pádel. Cada uno se prende por separado.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const Divider(height: 24),
            switchPadel(
              campo: 'notifClasesPadelActivo',
              valor: _notifClasesPadelActivo,
              titulo: 'Inscripción a clase confirmada',
              subtitulo: 'Avisa al alumno cuando queda anotado en una clase de pádel.',
            ),
            switchPadel(
              campo: 'notifTurnoFijoActivo',
              valor: _notifTurnoFijoActivo,
              titulo: 'Turno fijo confirmado',
              subtitulo: 'Avisa al socio cuando se le asigna un turno fijo de cancha.',
            ),
            switchPadel(
              campo: 'notifPartidoAbiertoActivo',
              valor: _notifPartidoAbiertoActivo,
              titulo: 'Partido abierto',
              subtitulo: 'Avisa cuando alguien se une a un partido abierto y cuando se completa el cupo de 4.',
            ),
            switchPadel(
              campo: 'notifPagoConfirmadoActivo',
              valor: _notifPagoConfirmadoActivo,
              titulo: 'Aviso de recibo (pago aprobado)',
              subtitulo: 'Avisa cuando Mercado Pago aprueba un pago hecho por el propio socio desde la app.',
            ),
          ],
        ),
      ),
    );
  }

  bool _enviandoRecordatorios = false;

  // 📲 RECORDATORIOS AUTOMÁTICOS: cuota pendiente, apto médico vencido/por
  // vencer y reservas de mañana. Corren solos todos los días a las 10:00 vía
  // Cloud Function programada; este botón dispara la misma lógica al toque
  // para poder probarla sin esperar al cron.
  Future<void> _enviarRecordatoriosAhora() async {
    setState(() => _enviandoRecordatorios = true);
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'enviarRecordatoriosManual',
      );
      final resp = await callable.call();
      if (!mounted) return;
      if (resp.data['success'] == true && resp.data['desactivado'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⏸️ El interruptor está apagado — no se mandó nada. Activalo arriba primero.'),
            backgroundColor: Colors.orange,
          ),
        );
      } else if (resp.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '✅ Recordatorios enviados — Cuotas: ${resp.data['cuotas']}, '
              'Aptos médicos: ${resp.data['aptos']}, Reservas: ${resp.data['reservas']}.',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: ${resp.data['error'] ?? 'desconocido'}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _enviandoRecordatorios = false);
    }
  }

  Widget _buildCardRecordatorios() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Recordatorios Automáticos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Todos los días a las 10:00 se avisa solo por WhatsApp a socios con cuota pendiente, apto médico vencido o por vencer (próximos 15 días), y a quienes tengan una reserva de cancha para el día siguiente.',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _recordatoriosActivos,
              activeColor: Colors.green,
              onChanged: _guardandoToggleRecordatorios ? null : _cambiarToggleRecordatorios,
              title: const Text(
                'Recordatorios activados',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              subtitle: Text(
                _recordatoriosActivos
                    ? 'Se están enviando mensajes reales a socios. Apagalo si todavía estás probando el sistema.'
                    : 'Apagado: no se manda ningún WhatsApp automático (ni por el cron ni por el botón de prueba de abajo). Ideal mientras el cliente prueba el sistema.',
                style: const TextStyle(fontSize: 11.5),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                onPressed: _enviandoRecordatorios ? null : _enviarRecordatoriosAhora,
                icon: _enviandoRecordatorios
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: const Text('Enviar Recordatorios Ahora (Prueba)'),
              ),
            ),
            if (!_recordatoriosActivos)
              const Padding(
                padding: EdgeInsets.only(top: 6),
                child: Text(
                  'El botón de arriba no manda nada mientras el interruptor esté apagado.',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // FORMULARIO ARCA / AFIP
  Widget _buildFormularioArca() {
    if (_cargandoArca) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
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

                  TextField(
                    controller: _alicuotaIvaCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Alícuota de IVA (%)',
                      helperText:
                          'Sólo se usa para Factura A/B (Responsable Inscripto). Factura C nunca discrimina IVA.',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.percent_rounded),
                    ),
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
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
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
