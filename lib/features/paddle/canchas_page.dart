import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_functions/cloud_functions.dart';
import '../inventario/inventario_general_model.dart';
import 'cancha_padel_model.dart';
import 'gestion_clases_padel_page.dart';
import 'turnos_fijos_padel_page.dart';
import 'item_pro_shop_venta.dart';
import 'paddle_ids.dart';
import 'reserva_cancha_model.dart';
import 'reserva_cancha_repository.dart';
import '../../shared/mercado_pago_dialog.dart';
import 'marcador_tv_page.dart';
import 'marcador_mando_auxiliar.dart';

class CanchasPage extends StatefulWidget {
  const CanchasPage({super.key});

  @override
  State<CanchasPage> createState() => _CanchasPageState();
}

class _CanchasPageState extends State<CanchasPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final _formKey = GlobalKey<FormState>();

  // 🚨 El bridge de WhatsApp exige un ID token de admin desde que se le
  // agregó autenticación — esta llamada nunca mandaba el header y fallaba
  // en silencio (401) desde entonces.
  Future<Map<String, String>> _headersWhatsapp() async {
    final token = await FirebaseAuth.instance.currentUser?.getIdToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  double _precioSocioRef = 4500.0;
  double _precioExternoRef = 6000.0;

  // Lógica Horaria e Iluminación Nocturna
  int _horaApertura = 8;
  int _horaCierre = 23;
  int _duracionSeleccionada = 1;
  int _horaInicioCarga = 20;
  double _plusLuzAnexo = 1500.0;
  int? _horaInicioSeleccionada;

  bool _cargandoTarifas = true;

  // 🎾 Canchas dinámicas (canchas_padel): cada cancha puede pisar el precio
  // base/plus de luz global. Antes la lista de canchas y los precios eran
  // un único doc plano (configuracion_paddle/canchas +
  // configuraciones_paddle/ajustes_globales) iguales para todas.
  List<CanchaPadelModel> _canchasPadel = [];
  StreamSubscription<QuerySnapshot>? _canchasPadelSub;

  CanchaPadelModel? _canchaPadelDe(String nombre) {
    for (final c in _canchasPadel) {
      if (c.nombre == nombre) return c;
    }
    return null;
  }

  List<String> get _nombresCanchasActivas => _canchasPadel.isNotEmpty
      ? _canchasPadel.map((c) => c.nombre).toList()
      : const ['Cancha 1 Cristal', 'Cancha 2 Cristal', 'Cancha 3 Muro'];

  double _precioBaseHoraParaCancha(String cancha) {
    final c = _canchaPadelDe(cancha);
    final esSocio = _tipoCliente == 'Socio';
    return esSocio
        ? (c?.precioBaseHoraSocio ?? _precioSocioRef)
        : (c?.precioBaseHoraExterno ?? _precioExternoRef);
  }

  int _horaInicioLuzParaCancha(String cancha) =>
      _canchaPadelDe(cancha)?.horaInicioLuz ?? _horaInicioCarga;

  double _plusLuzParaCancha(String cancha) =>
      _canchaPadelDe(cancha)?.precioAdicionalLuz ?? _plusLuzAnexo;

  double _precioHoraParaCancha(String cancha, int hora) {
    final base = _precioBaseHoraParaCancha(cancha);
    final horaLuz = _horaInicioLuzParaCancha(cancha);
    return hora >= horaLuz ? base + _plusLuzParaCancha(cancha) : base;
  }

  // 🛍️ Pro-Shop real (conectado a inventario_general, tipoInventario
  // tipoInventarioProShop): antes paleta/pelotas eran un cargo fijo por
  // hora, sin relación con ningún stock.
  List<InventarioGeneralModel> _productosProShop = [];
  bool _cargandoProShop = true;
  final Map<String, int> _cantidadesProShop = {};

  List<ItemProShopVenta> get _itemsProShopSeleccionados {
    final items = <ItemProShopVenta>[];
    for (final producto in _productosProShop) {
      final cantidad = _cantidadesProShop[producto.id] ?? 0;
      if (cantidad > 0) {
        items.add(
          ItemProShopVenta(
            productoId: producto.id,
            nombre: producto.nombre,
            cantidad: cantidad,
            precioUnitario: producto.precioVenta,
          ),
        );
      }
    }
    return items;
  }

  double get _totalProShopSeleccionado =>
      _itemsProShopSeleccionados.fold(0.0, (acc, i) => acc + i.subtotal);

  Future<void> _cargarProductosProShop() async {
    final snap = await _firestore
        .collection('inventario_general')
        .where('tipoInventario', isEqualTo: tipoInventarioProShop)
        .where('disponible', isEqualTo: true)
        .get();
    if (!mounted) return;
    setState(() {
      _productosProShop = snap.docs
          .map(InventarioGeneralModel.fromFirestore)
          .toList();
      _cargandoProShop = false;
    });
  }

  void _escucharCanchasPadel() {
    _canchasPadelSub = _firestore
        .collection('canchas_padel')
        .orderBy('ordenVisualizacion')
        .snapshots()
        .listen((snap) {
          if (!mounted) return;
          setState(() {
            _canchasPadel = snap.docs
                .map((d) => CanchaPadelModel.fromFirestore(d.id, d.data()))
                .where((c) => c.activa)
                .toList();
          });
        });
  }

  final _clienteController = TextEditingController();
  DateTime _fechaSeleccionada = DateTime.now();

  String? _canchaSel;
  String _tipoCliente = 'Socio';
  String? _socioIdSeleccionado;
  String _metodoPagoSel = 'Cuenta Corriente';

  String _busquedaSocio = "";
  Map<String, dynamic>? _socioElegido;

  // 💸 Antes la búsqueda de socio acá streameaba en vivo TODA la colección
  // (recreando el listener en cada tecla tipeada, o sea releyendo la
  // colección entera por letra). Ahora se trae una sola vez al abrir la
  // pantalla y se filtra en memoria.
  List<QueryDocumentSnapshot> _todosLosSocios = [];
  bool _cargandoSocios = true;

  Future<void> _cargarSocios() async {
    setState(() => _cargandoSocios = true);
    final snap = await _firestore.collection('socios').get();
    if (mounted) {
      setState(() {
        _todosLosSocios = snap.docs;
        _cargandoSocios = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _cargarTarifarioGlobal();
    _cargarSocios();
    _cargarProductosProShop();
    _escucharCanchasPadel();
  }

  @override
  void dispose() {
    _clienteController.dispose();
    _canchasPadelSub?.cancel();
    super.dispose();
  }

  Future<void> _cargarTarifarioGlobal() async {
    setState(() => _cargandoTarifas = true);
    try {
      final docAjustes = await _firestore
          .collection('configuraciones_paddle')
          .doc('ajustes_globales')
          .get();

      if (docAjustes.exists && docAjustes.data() != null) {
        final data = docAjustes.data()!;
        setState(() {
          _precioSocioRef =
              (data['precio_base_cancha'] as num?)?.toDouble() ?? 4500.0;
          _precioExternoRef =
              (data['precio_base_externo'] as num?)?.toDouble() ?? 6000.0;
          _horaInicioCarga = (data['hora_inicio_luz'] as num?)?.toInt() ?? 20;
          _plusLuzAnexo =
              (data['precio_adicional_luz'] as num?)?.toDouble() ?? 1500.0;

          _horaApertura = (data['hora_apertura'] as num?)?.toInt() ?? 8;
          _horaCierre = (data['hora_cierre'] as num?)?.toInt() ?? 23;
        });
      }
    } catch (e) {
      debugPrint("Error cargando configuración comercial: $e");
    } finally {
      setState(() => _cargandoTarifas = false);
    }
  }

  double get totalReservaEnTiempoReal {
    if (_horaInicioSeleccionada == null || _canchaSel == null) return 0.0;

    double total = 0.0;
    for (
      int h = _horaInicioSeleccionada!;
      h < _horaInicioSeleccionada! + _duracionSeleccionada;
      h++
    ) {
      total += _precioHoraParaCancha(_canchaSel!, h);
    }
    return total + _totalProShopSeleccionado;
  }

  Future<void> _crearVentaPendienteParaCaja({
    required String socioId,
    required String nombreSocio,
    required String numeroCancha,
    required String horaTurno,
    required double precioCancha,
    List<Map<String, dynamic>> equipamientoAlquilado = const [],
  }) async {
    try {
      List<Map<String, dynamic>> itemsCobro = [
        {
          'id': 'servicio_cancha_paddle',
          'nombre': 'Alquiler $numeroCancha ($horaTurno)',
          'precio': precioCancha,
          'cantidad': 1,
          'es_producto_fisico': false,
        },
      ];

      for (var equipo in equipamientoAlquilado) {
        itemsCobro.add({
          'id': equipo['id'],
          'nombre': equipo['nombre'],
          'precio': equipo['precio'],
          'cantidad': equipo['cantidad'],
          'es_producto_fisico': equipo['es_producto_fisico'],
        });
      }

      await _firestore.collection('ventas_pendientes').add({
        'socio_id': socioId,
        'nombre_socio': nombreSocio,
        'origen': 'Reserva $numeroCancha - $horaTurno',
        'fecha_creacion': FieldValue.serverTimestamp(),
        'estado': 'Pendiente',
        'items': itemsCobro,
      });
    } catch (e) {
      print('Error al enviar standby a caja: $e');
    }
  }

  /// 📲 Notificación por WhatsApp al Socio
  Future<void> _enviarNotificacionReservaWhatsApp({
    required String telefono,
    required String nombreSocio,
    required String cancha,
    required DateTime fecha,
    required int horaInicio,
    required int duracion,
  }) async {
    final telefonoLimpio = telefono.replaceAll(RegExp(r'\D'), '');
    if (telefonoLimpio.isEmpty) return;

    final String fechaFormateada =
        "${fecha.day.toString().padLeft(2, '0')}/${fecha.month.toString().padLeft(2, '0')}/${fecha.year}";
    final String horaInicioStr = "${horaInicio.toString().padLeft(2, '0')}:00";
    final String horaFinStr =
        "${(horaInicio + duracion).toString().padLeft(2, '0')}:00";

    final mensaje =
        '''
🎾 *¡RESERVA CONFIRMADA - OQUA CLUB DEPORTIVO!*

Hola *$nombreSocio*, confirmamos tu turno de pádel:

📍 *Cancha:* $cancha
📅 *Fecha:* $fechaFormateada
⏰ *Horario:* De $horaInicioStr a $horaFinStr hs ($duracion hr/s)

¡Te esperamos en el club! Por favor, recordá avisar con anticipación en caso de requerir cancelación.
''';

    try {
      final resp = await http.post(
        Uri.parse('https://servicio-whatsapp-oqua.onrender.com/send-whatsapp'),
        headers: await _headersWhatsapp(),
        body: jsonEncode({'phone': telefonoLimpio, 'message': mensaje}),
      );
      if (resp.statusCode != 200) {
        debugPrint(
          '⚠️ Notificación WhatsApp no enviada (${resp.statusCode}): ${resp.body}',
        );
        _avisarFalloWhatsapp();
      }
    } catch (e) {
      debugPrint('⚠️ No se pudo enviar la notificación de WhatsApp: $e');
      _avisarFalloWhatsapp();
    }
  }

  // 🚨 Antes un envío fallido sólo quedaba en debugPrint (invisible en
  // release) — el staff nunca se enteraba de que el socio no recibió la
  // confirmación de su turno.
  void _avisarFalloWhatsapp() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('⚠️ No se pudo enviar la confirmación por WhatsApp.'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  static const List<String> _nombresDias = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  // 🔁 Mismo criterio que el self-service (reserva_cancha_screen.dart):
  // reusa la cancha/horario/fecha ya cargados en el formulario — la fecha
  // elegida define qué día de la semana se repite. Útil para abonos que el
  // staff arregla de palabra en el mostrador.
  Future<void> _asignarTurnoFijo() async {
    if (_canchaSel == null || _horaInicioSeleccionada == null) {
      _snack('Elegí cancha y horario primero.', Colors.orange);
      return;
    }
    if (_tipoCliente != 'Socio' || _socioIdSeleccionado == null) {
      _snack('El turno fijo sólo se puede asignar a un socio.', Colors.orange);
      return;
    }
    final String nombreFinal =
        '${_socioElegido?['nombre'] ?? ''} ${_socioElegido?['apellido'] ?? ''}'
            .trim();
    final String dia = _nombresDias[_fechaSeleccionada.weekday - 1];

    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Asignar turno fijo?'),
        content: Text(
          '$nombreFinal va a tener reservado todos los $dia a las '
          '$_horaInicioSeleccionada:00hs en $_canchaSel, automáticamente, '
          'hasta que se cancele.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      final resp = await FirebaseFunctions.instance
          .httpsCallable('crearTurnoRecurrenteCanchaStaff')
          .call({
            'socioId': _socioIdSeleccionado,
            'nombreCliente': nombreFinal,
            'cancha': _canchaSel,
            'diaSemana': _fechaSeleccionada.weekday,
            'horaInicio': _horaInicioSeleccionada,
            'duracionHoras': _duracionSeleccionada,
          });
      if (!mounted) return;
      if (resp.data['success'] == true) {
        _snack('Turno fijo asignado a $nombreFinal.', Colors.green);
      } else {
        _snack(
          resp.data['error'] ?? 'No se pudo asignar el turno fijo.',
          Colors.red,
        );
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', Colors.red);
    }
  }

  Future<void> _registrarReserva() async {
    if (!_formKey.currentState!.validate() ||
        _canchaSel == null ||
        _horaInicioSeleccionada == null) {
      _snack(
        'Completar todos los campos (selecciona un horario en la grilla).',
        Colors.orange,
      );
      return;
    }

    if (_tipoCliente == 'Socio' && _socioIdSeleccionado == null) {
      _snack('Selecciona un socio válido de la lista buscador.', Colors.orange);
      return;
    }

    if (_horaInicioSeleccionada! + _duracionSeleccionada > _horaCierre) {
      _snack(
        'La duración seleccionada excede el horario de cierre del complejo.',
        Colors.red,
      );
      return;
    }

    final reservaId = idReservaCancha(
      fecha: _fechaSeleccionada,
      cancha: _canchaSel!,
      horaInicio: _horaInicioSeleccionada!,
      duracionHoras: _duracionSeleccionada,
    );

    final String nombreFinal = _tipoCliente == 'Socio'
        ? ('${_socioElegido?['nombre'] ?? ''} ${_socioElegido?['apellido'] ?? ''}'
              .trim())
        : _clienteController.text.trim();

    double costoCanchaTotal = 0.0;
    for (
      int h = _horaInicioSeleccionada!;
      h < _horaInicioSeleccionada! + _duracionSeleccionada;
      h++
    ) {
      costoCanchaTotal += _precioHoraParaCancha(_canchaSel!, h);
    }
    final double costoExtrasTotal = _totalProShopSeleccionado;
    final List<ItemProShopVenta> itemsProShop = _itemsProShopSeleccionados;

    final double precioFinalCalculado = costoCanchaTotal + costoExtrasTotal;

    final nuevaReserva = ReservaCanchaModel(
      id: reservaId,
      cancha: _canchaSel!,
      nombreCliente: nombreFinal,
      socioId: _tipoCliente == 'Socio' ? _socioIdSeleccionado : null,
      fecha: _fechaSeleccionada,
      horaInicio: _horaInicioSeleccionada!,
      duracionHoras: _duracionSeleccionada,
      precio: precioFinalCalculado,
      metodoPago: _metodoPagoSel,
      itemsProShop: itemsProShop,
    );

    try {
      // 🚨 Antes esto chequeaba solapamiento con un `get()` y recién después
      // escribía la reserva con un `set()` aparte: dos reservas confirmadas
      // casi al mismo tiempo podían pasar las dos ese chequeo (TOCTOU) y
      // terminar pisándose o duplicando el horario. Ahora todo el chequeo +
      // escritura (incluyendo el descuento de stock del Pro-Shop) es
      // atómico (ver reserva_cancha_repository.dart).
      try {
        await reservarCanchaAtomica(
          firestore: _firestore,
          reserva: nuevaReserva,
        );
      } on HorarioOcupadoException {
        _snack(
          'Solapamiento detectado. El bloque ya se encuentra reservado.',
          Colors.red,
        );
        return;
      } on StockInsuficienteException catch (e) {
        _snack('$e', Colors.red);
        return;
      }

      // 🧾💳 MERCADO PAGO REAL: antes era sólo una etiqueta que el staff
      // tildaba a mano sin ninguna verificación. Reutiliza el mismo diálogo
      // (y el mismo par de Cloud Functions) que ya se conectó en el POS.
      if (_metodoPagoSel == 'Mercado Pago' && mounted) {
        await mostrarSelectorCobroMercadoPago(
          context,
          ruta: 'reservas_canchas/$reservaId',
          campoMonto: 'precio',
          campoMedioPago: 'metodoPago',
          concepto: 'Reserva $_canchaSel - $nombreFinal',
        );
      }

      // 📲 DISPARO AUTOMÁTICO DE WHATSAPP
      final String? telefonoSocio =
          (_tipoCliente == 'Socio' && _socioElegido != null)
          ? (_socioElegido!['telefono'] as String?)
          : null;
      if (telefonoSocio != null && telefonoSocio.isNotEmpty) {
        _enviarNotificacionReservaWhatsApp(
          telefono: telefonoSocio,
          nombreSocio: nombreFinal,
          cancha: _canchaSel!,
          fecha: _fechaSeleccionada,
          horaInicio: _horaInicioSeleccionada!,
          duracion: _duracionSeleccionada,
        );
      }

      if (_tipoCliente == 'Socio' && _socioIdSeleccionado != null) {
        // 🚨 'es_producto_fisico': false a propósito, aunque ahora sea una
        // venta real de Pro-Shop: el stock ya se descontó atómicamente al
        // crear la reserva (reservarCanchaAtomica). Si acá fuera 'true', el
        // POS volvería a descontar el mismo stock una segunda vez cuando
        // caja cobre esta venta pendiente (ver pos_caja_page.dart, bloque
        // "DESCUENTO DE STOCK DINÁMICO").
        final List<Map<String, dynamic>> extras = itemsProShop
            .map(
              (item) => {
                'id': item.productoId,
                'nombre': '${item.nombre} (x${item.cantidad})',
                'precio': item.subtotal,
                'cantidad': item.cantidad,
                'es_producto_fisico': false,
              },
            )
            .toList();

        final String stringBloqueParaCaja =
            "${_horaInicioSeleccionada!.toString().padLeft(2, '0')}:00 hs por $_duracionSeleccionada Hora(s)";
        await _crearVentaPendienteParaCaja(
          socioId: _socioIdSeleccionado!,
          nombreSocio: nombreFinal,
          numeroCancha: _canchaSel!,
          horaTurno: stringBloqueParaCaja,
          precioCancha: costoCanchaTotal,
          equipamientoAlquilado: extras,
        );
      }

      _limpiarFormulario();
      if (mounted) {
        _snack('¡Turno registrado y notificación enviada!', Colors.green);
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', Colors.red);
    }
  }

  Future<void> _mostrarConsolaTurnoOcupado(ReservaCanchaModel reserva) async {
    // 🚨 Esta reserva bloquea la cancha para una CLASE de pádel (ver
    // clase_padel_repository.dart, que la crea con este mismo
    // 'metodoPago' a propósito). Si se la dejara cancelar/señar acá como a
    // cualquier turno suelto, el doc de la clase (con sus alumnos y pagos
    // ya generados) quedaría huérfano, apuntando a una reserva borrada.
    if (reserva.metodoPago == 'Clase de Pádel') {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ocupado por una clase de pádel'),
          content: Text(
            '${reserva.nombreCliente}\n\n'
            'Este horario está reservado por una clase. Gestioná sus '
            'alumnos, pagos o la cancelación desde "Clases de Pádel".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const GestionClasesPadelPage(),
                  ),
                );
              },
              child: const Text('Ir a Clases de Pádel'),
            ),
          ],
        ),
      );
      return;
    }

    final senaCtrl = TextEditingController();
    String medioSena = 'Efectivo ARS';

    final double senaPrevia = reserva.senaAbonada;

    // 🔧 Antes se buscaba la caja abierta por un nombre de usuario fijo
    // ('Administrador Central'), que no coincide con el modelo real de caja
    // por terminal que usa pos_caja_page.dart ('nombreCajaTerminal'), así
    // que la seña nunca llegaba a ninguna caja real. Ahora se consulta igual
    // que el POS: cajas con estado=='Abierta', identificadas por terminal.
    final cajasAbiertasSnap = await _firestore
        .collection('control_cajas')
        .where('estado', isEqualTo: 'Abierta')
        .get();
    final List<String> terminalesAbiertas = cajasAbiertasSnap.docs
        .map((d) => (d.data()['nombreCajaTerminal'] as String?) ?? '')
        .where((n) => n.isNotEmpty)
        .toSet()
        .toList();
    String? terminalSeleccionada = terminalesAbiertas.isNotEmpty
        ? terminalesAbiertas.first
        : null;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: Text('Administrar: ${reserva.nombreCliente}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cancha: ${reserva.cancha} | Hora: ${reserva.horaInicio}:00 hs',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                'Valor Restante por Cobrar: \$${reserva.precio.toStringAsFixed(0)} ARS',
                style: const TextStyle(color: Colors.grey),
              ),
              if (senaPrevia > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    'Seña ya entregada: \$$senaPrevia (${reserva.detalleSena})',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              const Divider(height: 24),
              const Text(
                'Registrar Entrega de Seña:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: senaCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Monto Seña',
                        border: OutlineInputBorder(),
                        prefixText: '\$ ',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: medioSena,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'Efectivo ARS',
                          child: Text('Efectivo'),
                        ),
                        DropdownMenuItem(
                          value: 'Mercado Pago',
                          child: Text('Mercado Pago'),
                        ),
                        DropdownMenuItem(value: 'MODO', child: Text('MODO')),
                      ],
                      onChanged: (v) => medioSena = v!,
                    ),
                  ),
                ],
              ),
              if (terminalesAbiertas.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8.0),
                  child: Text(
                    '⚠️ No hay ninguna caja abierta: la seña va a quedar registrada en la reserva, pero no se va a sumar a ningún arqueo hasta que se abra una caja.',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                )
              else if (terminalesAbiertas.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: DropdownButtonFormField<String>(
                    initialValue: terminalSeleccionada,
                    decoration: const InputDecoration(
                      labelText: 'Asentar en caja',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: terminalesAbiertas
                        .map(
                          (t) => DropdownMenuItem(value: t, child: Text(t)),
                        )
                        .toList(),
                    onChanged: (v) =>
                        setModalState(() => terminalSeleccionada = v),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton.icon(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () async {
                Navigator.pop(context);
                // 🚨 Antes sólo borraba el doc de la reserva: los slots de
                // hora ocupada quedaban huérfanos y esas horas se mostraban
                // como ocupadas para siempre. Ahora libera todo junto.
                await cancelarReservaCanchaAtomica(
                  firestore: _firestore,
                  reserva: reserva,
                );
                _snack(
                  '🔓 Cancha liberada. El turno vuelve a estar disponible.',
                  Colors.green,
                );
              },
              icon: const Icon(Icons.delete_forever),
              label: const Text('Liberar / Cancelar Turno'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
              ),
              onPressed: () async {
                final montoSena = double.tryParse(senaCtrl.text.trim()) ?? 0.0;
                if (montoSena <= 0) return;

                Navigator.pop(context);

                await _firestore
                    .collection('reservas_canchas')
                    .doc(reserva.id)
                    .update({
                      'precio': reserva.precio - montoSena,
                      'senaAbonada': senaPrevia + montoSena,
                      'detalleSena': 'Señado con $medioSena',
                    });

                if (terminalSeleccionada != null) {
                  final cajaQuery = await _firestore
                      .collection('control_cajas')
                      .where(
                        'nombreCajaTerminal',
                        isEqualTo: terminalSeleccionada,
                      )
                      .where('estado', isEqualTo: 'Abierta')
                      .limit(1)
                      .get();

                  if (cajaQuery.docs.isNotEmpty) {
                    String campo = medioSena == 'Efectivo ARS'
                        ? 'totalEfectivoARS'
                        : (medioSena == 'Mercado Pago'
                              ? 'totalMercadoPago'
                              : 'totalModo');
                    await _firestore
                        .collection('control_cajas')
                        .doc(cajaQuery.docs.first.id)
                        .update({campo: FieldValue.increment(montoSena)});
                  }
                }

                _snack(
                  terminalSeleccionada != null
                      ? '💰 Seña de \$$montoSena asentada en caja "$terminalSeleccionada" y descontada del total.'
                      : '💰 Seña de \$$montoSena descontada del total (no se sumó a ninguna caja: no hay ninguna abierta).',
                  Colors.green,
                );
              },
              child: const Text(
                'Asentar Seña',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _anularReservasHistoricasViejas() async {
    final DateTime hoy = DateTime.now();
    final DateTime umbralSaneamiento = DateTime(hoy.year, hoy.month, hoy.day);

    try {
      final snapshot = await _firestore.collection('reservas_canchas').get();
      WriteBatch batch = _firestore.batch();
      int contadorBorrados = 0;

      for (var doc in snapshot.docs) {
        final data = doc.data();
        if (data['fecha'] != null) {
          final DateTime fechaReserva = (data['fecha'] as Timestamp).toDate();
          if (fechaReserva.isBefore(umbralSaneamiento)) {
            batch.delete(doc.reference);
            contadorBorrados++;
          }
        }
      }

      if (contadorBorrados > 0) {
        await batch.commit();
        _snack(
          '🧹 Se purgaron $contadorBorrados turnos obsoletos del historial.',
          Colors.teal,
        );
      } else {
        _snack(
          '✅ El historial de reservas se encuentra limpio y al día.',
          Colors.blue,
        );
      }
    } catch (e) {
      _snack('❌ Error al depurar historial: $e', Colors.red);
    }
  }

  void _limpiarFormulario() {
    setState(() {
      _clienteController.clear();
      _canchaSel = null;
      _horaInicioSeleccionada = null;
      _socioIdSeleccionado = null;
      _socioElegido = null;
      _busquedaSocio = "";
      _cantidadesProShop.clear();
      _duracionSeleccionada = 1;
    });
  }

  void _snack(String msg, Color c) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: c));
  }

  List<Widget> _generarBloquesHorarios(
    String canchaNombre,
    Map<String, ReservaCanchaModel> mapaReservas,
    String fechaIdStr,
  ) {
    List<Widget> celdas = [];

    for (int hora = _horaApertura; hora < _horaCierre; hora++) {
      final String bloqueStr = "${hora.toString().padLeft(2, '0')}:00 hs";

      final double precioBloqueFinal = _precioHoraParaCancha(
        canchaNombre,
        hora,
      );

      bool estaOcupado = false;
      ReservaCanchaModel? reservaActiva;

      mapaReservas.forEach((id, r) {
        final String fId = fechaIdStrCancha(r.fecha);
        if (fId == fechaIdStr && r.cancha == canchaNombre) {
          int inicio = r.horaInicio;
          int fin = inicio + r.duracionHoras;
          if (hora >= inicio && hora < fin) {
            estaOcupado = true;
            reservaActiva = r;
          }
        }
      });

      final bool esElSeleccionadoActualmente =
          _canchaSel == canchaNombre && _horaInicioSeleccionada == hora;

      String rotuloCliente = 'Disponible';
      if (estaOcupado && reservaActiva != null) {
        rotuloCliente = reservaActiva!.senaAbonada > 0
            ? '${reservaActiva!.nombreCliente} (💰 SEÑADO)'
            : reservaActiva!.nombreCliente;
      } else if (esElSeleccionadoActualmente) {
        rotuloCliente = 'Seleccionado';
      }

      celdas.add(
        InkWell(
          onTap: () {
            if (!estaOcupado) {
              setState(() {
                _canchaSel = canchaNombre;
                _horaInicioSeleccionada = hora;
              });
            } else {
              if (reservaActiva != null)
                _mostrarConsolaTurnoOcupado(reservaActiva!);
            }
          },
          child: Container(
            width: 180,
            height: 85,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: estaOcupado
                  ? const Color(0xFFFFE2E2)
                  : (esElSeleccionadoActualmente
                        ? Colors.indigo.shade50
                        : const Color(0xFFF0FDF4)),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: estaOcupado
                    ? Colors.red.shade200
                    : (esElSeleccionadoActualmente
                          ? Colors.indigo
                          : Colors.green.shade200),
                width: esElSeleccionadoActualmente ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      bloqueStr,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: estaOcupado
                            ? Colors.red.shade900
                            : Colors.green.shade900,
                      ),
                    ),
                    if (hora >= _horaInicioCarga && !estaOcupado)
                      const Icon(
                        Icons.lightbulb_outline_rounded,
                        size: 14,
                        color: Colors.orange,
                      ),
                  ],
                ),
                Text(
                  rotuloCliente,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  estaOcupado
                      ? 'Ocupado'
                      : '\$${precioBloqueFinal.toStringAsFixed(0)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: estaOcupado
                        ? Colors.red.shade700
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return celdas;
  }

  @override
  Widget build(BuildContext context) {
    if (_cargandoTarifas) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.indigo),
              SizedBox(height: 16),
              Text('Sincronizando grilla y tarifario comercial...'),
            ],
          ),
        ),
      );
    }

    final fechaIdStr = fechaIdStrCancha(_fechaSeleccionada);

    // 📱 Panel izquierdo: formulario de nueva reserva. Se arma como closure
    // para reutilizar exactamente el mismo contenido en el layout ancho (Row
    // de dos columnas) y en el apilado vertical de celular.
    Widget panelNuevaReserva({required bool movil}) {
      final contenidoFormulario = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nueva Reserva de Paddle',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _tipoCliente,
            decoration: const InputDecoration(
              labelText: 'Tipo de Cliente',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'Socio', child: Text('Socio del Club')),
              DropdownMenuItem(
                value: 'Externo',
                child: Text('Externo (No Socio)'),
              ),
            ],
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _tipoCliente = val;
                  _metodoPagoSel = val == 'Socio'
                      ? 'Cuenta Corriente'
                      : 'Efectivo';
                  _socioIdSeleccionado = null;
                  _socioElegido = null;
                });
              }
            },
          ),
          const SizedBox(height: 20),
          if (_tipoCliente == 'Socio') ...[
            if (_socioElegido == null) ...[
              TextFormField(
                decoration: const InputDecoration(
                  labelText: 'Buscar Socio...',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) =>
                    setState(() => _busquedaSocio = v.toLowerCase()),
              ),
              const SizedBox(height: 10),
              if (_busquedaSocio.length >= 3)
                Container(
                  constraints: const BoxConstraints(maxHeight: 150),
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.white,
                  ),
                  child: Builder(
                    builder: (context) {
                      if (_cargandoSocios) {
                        return const Center(child: LinearProgressIndicator());
                      }
                      final filtrados = _todosLosSocios.where((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        final nombre = (d['nombre'] ?? '')
                            .toString()
                            .toLowerCase();
                        final apellido = (d['apellido'] ?? '')
                            .toString()
                            .toLowerCase();
                        final dni = (d['dni'] ?? '').toString().toLowerCase();
                        return nombre.contains(_busquedaSocio) ||
                            apellido.contains(_busquedaSocio) ||
                            dni.contains(_busquedaSocio);
                      }).toList();

                      if (filtrados.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Text(
                            'No hay coincidencias.',
                            style: TextStyle(color: Colors.grey, fontSize: 13),
                          ),
                        );
                      }

                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: filtrados.length,
                        itemBuilder: (context, idx) {
                          final doc = filtrados[idx];
                          final d = doc.data() as Map<String, dynamic>;
                          return ListTile(
                            title: Text(
                              '${d['nombre'] ?? ''} ${d['apellido'] ?? ''}'
                                  .trim(),
                            ),
                            subtitle: Text('DNI: ${d['dni'] ?? 'S/D'}'),
                            onTap: () => setState(() {
                              _socioElegido = d;
                              _socioIdSeleccionado = doc.id;
                            }),
                          );
                        },
                      );
                    },
                  ),
                ),
            ] else ...[
              Card(
                color: const Color(0xFFEFF6FF),
                child: ListTile(
                  leading: const Icon(Icons.check_circle, color: Colors.blue),
                  title: Text(
                    '${_socioElegido!['nombre'] ?? ''} ${_socioElegido!['apellido'] ?? ''}'
                        .trim(),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => setState(() => _socioElegido = null),
                  ),
                ),
              ),
            ],
          ] else ...[
            TextFormField(
              controller: _clienteController,
              decoration: const InputDecoration(
                labelText: 'Responsable Externo',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_outline),
              ),
              validator: (v) =>
                  v == null || v.isEmpty ? 'Ingresa el nombre' : null,
            ),
          ],
          const SizedBox(height: 20),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Cancha y Horario Seleccionado',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.sports_tennis),
            ),
            child: Text(
              _canchaSel != null && _horaInicioSeleccionada != null
                  ? '$_canchaSel - ${_horaInicioSeleccionada!.toString().padLeft(2, '0')}:00 hs'
                  : 'Toca una celda libre en la grilla',
              style: TextStyle(
                color: _canchaSel != null ? Colors.black : Colors.grey,
                fontWeight: _canchaSel != null
                    ? FontWeight.bold
                    : Alignment.topLeft == null
                    ? FontWeight.normal
                    : FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<int>(
            initialValue: _duracionSeleccionada,
            decoration: const InputDecoration(
              labelText: 'Duración de la Reserva',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.schedule_rounded),
            ),
            items: const [
              DropdownMenuItem(value: 1, child: Text('1 Hora')),
              DropdownMenuItem(value: 2, child: Text('2 Horas (Turno Doble)')),
            ],
            onChanged: (val) =>
                setState(() => _duracionSeleccionada = val ?? 1),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: _metodoPagoSel,
            decoration: const InputDecoration(
              labelText: 'Método de Pago',
              border: OutlineInputBorder(),
            ),
            items: [
              if (_tipoCliente == 'Socio')
                const DropdownMenuItem(
                  value: 'Cuenta Corriente',
                  child: Text('Cuenta Corriente 📋'),
                ),
              const DropdownMenuItem(
                value: 'Efectivo',
                child: Text('Efectivo ARS'),
              ),
              const DropdownMenuItem(
                value: 'Mercado Pago',
                child: Text('Mercado Pago'),
              ),
            ],
            onChanged: (val) =>
                setState(() => _metodoPagoSel = val ?? 'Efectivo'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Pro-Shop (venta real: descuenta stock):',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (_cargandoProShop)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(),
            )
          else if (_productosProShop.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Text(
                'No hay productos de Pro-Shop cargados (Inventario → tipo "Pro-Shop").',
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            )
          else
            ..._productosProShop.map((producto) {
              final cantidad = _cantidadesProShop[producto.id] ?? 0;
              final sinStock = producto.stockActual <= 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${producto.nombre} (\$${producto.precioVenta.toStringAsFixed(0)} c/u · stock ${producto.stockActual})',
                        style: TextStyle(
                          fontSize: 13,
                          color: sinStock ? Colors.grey : Colors.black87,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: cantidad > 0
                          ? () => setState(
                              () => _cantidadesProShop[producto.id] =
                                  cantidad - 1,
                            )
                          : null,
                    ),
                    SizedBox(
                      width: 20,
                      child: Text(
                        '$cantidad',
                        textAlign: TextAlign.center,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: (!sinStock && cantidad < producto.stockActual)
                          ? () => setState(
                              () => _cantidadesProShop[producto.id] =
                                  cantidad + 1,
                            )
                          : null,
                    ),
                  ],
                ),
              );
            }),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Precio Cancha (Base):',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    Text(
                      '\$${((_canchaSel != null ? _precioBaseHoraParaCancha(_canchaSel!) : 0.0) * _duracionSeleccionada).toStringAsFixed(0)}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                if (_canchaSel != null &&
                    _horaInicioSeleccionada != null &&
                    _horaInicioSeleccionada! >=
                        _horaInicioLuzParaCancha(_canchaSel!)) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Plus Nocturno (Luz):',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      Text(
                        '+\$${(_plusLuzParaCancha(_canchaSel!) * _duracionSeleccionada).toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_itemsProShopSeleccionados.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pro-Shop:',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      Text(
                        '+\$${_totalProShopSeleccionado.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Colors.blue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: Divider(height: 1),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'TOTAL A COBRAR:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '\$${totalReservaEnTiempoReal.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: _registrarReserva,
            child: const Text(
              'Confirmar Turno & Enviar a Caja',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            icon: const Icon(Icons.event_repeat_rounded, size: 18),
            label: const Text('Asignar turno fijo semanal (abono)'),
            onPressed: _asignarTurnoFijo,
          ),
        ],
      );

      return Container(
        padding: EdgeInsets.all(movil ? 20 : 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Form(
          key: _formKey,
          // En celular el scroll lo maneja la columna exterior: un
          // SingleChildScrollView vertical dentro de una altura no acotada
          // reventaría con "Vertical viewport was given unbounded height".
          child: movil
              ? contenidoFormulario
              : SingleChildScrollView(child: contenidoFormulario),
        ),
      );
    }

    // 📱 Panel derecho: grilla de disponibilidad de canchas.
    Widget panelDisponibilidad({required bool movil}) {
      const tituloGrilla = Text(
        'Disponibilidad de Canchas',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      );

      final accionesGrilla = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Purgar Reservas de Días Anteriores',
            icon: const Icon(
              Icons.cleaning_services_rounded,
              color: Colors.teal,
            ),
            onPressed: _anularReservasHistoricasViejas,
          ),
          IconButton(
            tooltip: 'Turnos fijos y clases recurrentes',
            icon: const Icon(Icons.event_repeat_rounded, color: Colors.indigo),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TurnosFijosPadelPage()),
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _fechaSeleccionada,
                firstDate: DateTime.now().subtract(const Duration(days: 7)),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (picked != null) {
                setState(() => _fechaSeleccionada = picked);
              }
            },
            icon: const Icon(Icons.calendar_month),
            label: Text(
              '${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
            ),
          ),
        ],
      );

      return Container(
        padding: EdgeInsets.all(movil ? 16 : 32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 📱 En pantalla angosta el título y los botones de acción no
            // entran en la misma línea: se apilan.
            if (movil) ...[
              tituloGrilla,
              const SizedBox(height: 8),
              accionesGrilla,
            ] else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [tituloGrilla, accionesGrilla],
              ),
            SizedBox(height: movil ? 16 : 24),
            Expanded(
              // 🎾 Lista de canchas dinámica: antes era un único doc plano
              // (configuracion_paddle/canchas) que se escuchaba acá mismo;
              // ahora viene de la suscripción a canchas_padel que ya vive en
              // el estado de la página (_escucharCanchasPadel), así que no
              // hace falta otro StreamBuilder anidado para esto.
              child: Builder(
                builder: (context) {
                  final List<String> canchasDinamicas = _nombresCanchasActivas;

                  // 🚨 Antes esto traía TODA la colección 'reservas_canchas'
                  // sin filtro sólo para armar la grilla del día elegido —
                  // cada reserva nueva de cualquier día disparaba el
                  // listener completo, y la lectura crecía sin techo con
                  // los meses. Ahora se acota al rango del día seleccionado
                  // (mismo campo 'fecha' que ya usa ReservaCanchaModel).
                  return StreamBuilder<QuerySnapshot>(
                    stream: _firestore
                        .collection('reservas_canchas')
                        .where(
                          'fecha',
                          isGreaterThanOrEqualTo: Timestamp.fromDate(
                            DateTime(_fechaSeleccionada.year, _fechaSeleccionada.month, _fechaSeleccionada.day),
                          ),
                        )
                        .where(
                          'fecha',
                          isLessThan: Timestamp.fromDate(
                            DateTime(_fechaSeleccionada.year, _fechaSeleccionada.month, _fechaSeleccionada.day)
                                .add(const Duration(days: 1)),
                          ),
                        )
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData)
                        return const Center(child: CircularProgressIndicator());

                      final mapaReservas = {
                        for (var doc in snapshot.data!.docs)
                          doc.id: ReservaCanchaModel.fromFirestore(
                            doc.id,
                            doc.data() as Map<String, dynamic>,
                          ),
                      };

                      return ListView.builder(
                        itemCount: canchasDinamicas.length,
                        itemBuilder: (context, cIdx) {
                          final canchaNombre = canchasDinamicas[cIdx];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: ExpansionTile(
                              initiallyExpanded: cIdx == 0,
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      canchaNombre,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Marcador en TV / Proyector',
                                    icon: const Icon(
                                      Icons.tv_rounded,
                                      color: Colors.indigo,
                                    ),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => MarcadorTvPage(
                                          canchaNombre: canchaNombre,
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Mando Auxiliar de Marcador',
                                    icon: const Icon(
                                      Icons.sports_tennis,
                                      color: Colors.teal,
                                    ),
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            MarcadorMandoAuxiliarPage(
                                          canchaNombre: canchaNombre,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              children: [
                                Container(
                                  color: Colors.white,
                                  padding: const EdgeInsets.all(16),
                                  child: Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: _generarBloquesHorarios(
                                      canchaNombre,
                                      mapaReservas,
                                      fechaIdStr,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // 📱 Debajo de 700px el formulario de reserva y la grilla de canchas
          // no entran lado a lado (era un Row fijo flex:2 / flex:3): se apilan
          // en una columna con scroll. La grilla tiene adentro un Expanded +
          // ListView, así que fuera del Row necesita una altura acotada para
          // no romper con constraints verticales infinitas.
          final bool esMovil = constraints.maxWidth < 700;

          if (esMovil) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  panelNuevaReserva(movil: true),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 440,
                    child: panelDisponibilidad(movil: true),
                  ),
                ],
              ),
            );
          }

          return Padding(
            padding: const EdgeInsets.all(40.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 2, child: panelNuevaReserva(movil: false)),
                const SizedBox(width: 40),
                Expanded(flex: 3, child: panelDisponibilidad(movil: false)),
              ],
            ),
          );
        },
      ),
    );
  }
}
