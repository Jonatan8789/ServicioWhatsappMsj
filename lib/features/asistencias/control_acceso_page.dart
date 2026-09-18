import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../services/fichaje_profesor_service.dart';
import '../../theme/app_theme.dart';

class ControlAccesoPage extends StatefulWidget {
  final String rolUsuario;

  const ControlAccesoPage({super.key, required this.rolUsuario});

  @override
  State<ControlAccesoPage> createState() => _ControlAccesoPageState();
}

class _ControlAccesoPageState extends State<ControlAccesoPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _busquedaController = TextEditingController();
  final FocusNode _lectorFocusNode = FocusNode();

  // 🛡️ Filtro de seguridad: ignora capturas generadas antes de cargar/refrescar la pantalla
  final int _horaInicioSesion = DateTime.now().millisecondsSinceEpoch;

  // 🔌 SUSCRIPCIÓN PARA FIRESTORE (PUENTE C#)
  StreamSubscription<DocumentSnapshot>? _subHuellasFirestore;
  String? _ultimaHuellaProcesada;

  Map<String, dynamic>? _socioEncontrado;
  String? _socioIdEncontrado;
  bool _buscando = false;

  // Estados de autorización
  bool _cuotaAlDia = false;
  bool _aptoMedicoVigente = false;
  bool _matriculaAlDia = false;
  bool _estadoHabilitado = false;
  double _saldoCuentaCorriente = 0.0;

  // Control de Clases del Mes
  String _frecuenciaPase = 'Pase Libre';
  int _limiteClasesMes = 999;
  int _clasesUsadasMes = 0;
  int _creditosRestantes = 999;
  bool _tieneCreditoDisponible = true;

  @override
  void initState() {
    super.initState();
    _ultimaHuellaProcesada = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _conectarLectorBiometricoFirestore();
      _lectorFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _subHuellasFirestore?.cancel();
    _lectorFocusNode.dispose();
    _busquedaController.dispose();
    super.dispose();
  }

  // 🔌 CONEXIÓN EN TIEMPO REAL CON EL RESULTADO DEL MOTOR C#
  void _conectarLectorBiometricoFirestore() {
    _subHuellasFirestore = _firestore
        .collection('capturas_temp')
        .doc('terminal_recepcion')
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;
            if (snapshot.exists && snapshot.data() != null) {
              final data = snapshot.data() as Map<String, dynamic>;
              final String? dniIdentificado = data['dniIdentificado'];
              final String? huellaBase64 = data['huella'];
              final Timestamp? timestamp = data['timestamp'];

              if (timestamp != null) {
                final int msLectura = timestamp.millisecondsSinceEpoch;

                // 🛑 IGNORAR LECTURAS VIEJAS: Descarta capturas guardadas antes de refrescar
                if (msLectura < _horaInicioSesion) return;

                final String claveLectura = "$msLectura";

                if (claveLectura != _ultimaHuellaProcesada) {
                  _ultimaHuellaProcesada = claveLectura;

                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;

                    // 🟢 1. MATCH ENCONTRADO EN C# -> Carga ficha
                    if (dniIdentificado != null && dniIdentificado.isNotEmpty) {
                      debugPrint(
                        "🎯 Socio/Profesor identificado por DNI: $dniIdentificado",
                      );
                      _procesarEntradaLector(dniIdentificado);
                    }
                    // 🟡 2. HUELLA NUEVA NO REGISTRADA -> Abre diálogo
                    else if (huellaBase64 != null && huellaBase64.isNotEmpty) {
                      debugPrint(
                        "⚡ Abriendo diálogo para vincular nueva huella...",
                      );
                      _ofrecerEnrolamientoHuellaUnificado(huellaBase64);
                    }
                  });
                }
              }
            }
          },
          onError: (e) {
            debugPrint("Error al escuchar huellas en Firestore: $e");
          },
        );
  }

  // 🔍 PROCESAMIENTO DEL DNI / ESCÁNER MANUAL
  Future<void> _procesarEntradaLector(String query) async {
    final String codigoLeido = query.trim();
    if (codigoLeido.isEmpty) return;
    setState(() => _buscando = true);

    try {
      // 1. Detección de Profesores por DNI
      final profeSnap = await _firestore
          .collection('profesores')
          .where('dni', isEqualTo: codigoLeido)
          .limit(1)
          .get();

      if (profeSnap.docs.isNotEmpty) {
        final docProfe = profeSnap.docs.first;
        final dataProfe = docProfe.data();
        final List<dynamic> especialidades = dataProfe['especialidades'] ?? [];
        await _ficharProfesor(
          docProfe.id,
          dataProfe['nombre'] ?? 'Profesor',
          dataProfe['dni'] ?? codigoLeido,
          especialidad: especialidades.isNotEmpty
              ? especialidades.first.toString()
              : '',
        );
        return;
      }

      // 2. Detección de Socios por DNI
      final snapSocio = await _firestore
          .collection('socios')
          .where('dni', isEqualTo: codigoLeido)
          .limit(1)
          .get();

      if (snapSocio.docs.isNotEmpty) {
        final doc = snapSocio.docs.first;
        final data = doc.data();
        final String socioId = doc.id;

        final hoy = DateTime.now();
        final periodoActualStr =
            "${hoy.year}-${hoy.month.toString().padLeft(2, '0')}";

        final String? cubiertoHasta = data['mesesCubiertosHasta']?.toString();
        bool promoVigente = false;
        if (cubiertoHasta != null &&
            cubiertoHasta.compareTo(periodoActualStr) >= 0) {
          promoVigente = true;
        }

        final double saldo = (data['saldoCuentaCorriente'] ?? 0.0).toDouble();
        bool cuota = saldo >= 0 || promoVigente;
        bool matricula = data['matriculaAlDia'] == true;

        bool apto = false;
        if (data['vencimientoAptoMedico'] != null) {
          DateTime vencApto = (data['vencimientoAptoMedico'] as Timestamp)
              .toDate();
          apto = vencApto.isAfter(hoy);
        }

        final String frecuenciaRaw = (data['frecuencia'] ?? 'Pase Libre')
            .toString()
            .toLowerCase();
        int limite = 999;

        if (frecuenciaRaw.contains('1') || frecuenciaRaw.contains('una')) {
          limite = 4;
        } else if (frecuenciaRaw.contains('2') ||
            frecuenciaRaw.contains('dos')) {
          limite = 8;
        } else if (frecuenciaRaw.contains('3') ||
            frecuenciaRaw.contains('tres')) {
          limite = 12;
        } else if (frecuenciaRaw.contains('4') ||
            frecuenciaRaw.contains('cuatro')) {
          limite = 16;
        } else if (frecuenciaRaw.contains('libre')) {
          limite = 999;
        }

        final docCreditoRef = _firestore
            .collection('socios')
            .doc(socioId)
            .collection('creditos_mensuales')
            .doc(periodoActualStr);

        final docCredito = await docCreditoRef.get();
        int usadas = 0;

        if (!docCredito.exists) {
          await docCreditoRef.set({
            'periodo': periodoActualStr,
            'clasesUsadas': 0,
            'limiteClases': limite,
            'fechaInicio': DateTime.now(),
          });
        } else {
          final creditoData = docCredito.data();
          usadas = (creditoData?['clasesUsadas'] as num?)?.toInt() ?? 0;
          // 🚨 Respeta clases extra acreditadas manualmente ("Acreditar Clases
          // Extra" en la ficha del socio): ese diálogo incrementa
          // 'limiteClases' sobre este mismo documento, pero antes de este fix
          // nunca se leía de vuelta, así que el crédito no tenía ningún efecto
          // en el acceso.
          final int? limiteAlmacenado = (creditoData?['limiteClases'] as num?)
              ?.toInt();
          if (limiteAlmacenado != null && limite != 999) {
            limite = limiteAlmacenado;
          }
        }

        int restantes = limite == 999 ? 999 : (limite - usadas);
        bool tieneCredito = limite == 999 || restantes > 0;
        bool accesoPermitido = cuota && apto && tieneCredito;

        setState(() {
          _socioIdEncontrado = socioId;
          _socioEncontrado = data;
          _saldoCuentaCorriente = saldo;
          _cuotaAlDia = cuota;
          _matriculaAlDia = matricula;
          _aptoMedicoVigente = apto;
          _frecuenciaPase = data['frecuencia'] ?? 'Pase Libre';
          _limiteClasesMes = limite;
          _clasesUsadasMes = usadas;
          _creditosRestantes = restantes;
          _tieneCreditoDisponible = tieneCredito;
          _estadoHabilitado = accesoPermitido;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error al procesar lectura: $e')));
    } finally {
      setState(() => _buscando = false);
    }
  }

  // 📷 ESCANEO DE CARNET QR — el QR codifica el mismo DNI que usa el resto
  // de esta pantalla, así que reutiliza _procesarEntradaLector sin lógica
  // de parseo adicional.
  void _abrirEscanerQr() {
    final MobileScannerController controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
    bool yaLeido = false;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Escanear Carnet QR'),
        content: SizedBox(
          width: 320,
          height: 320,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: MobileScanner(
              controller: controller,
              onDetect: (capture) {
                if (yaLeido || capture.barcodes.isEmpty) return;
                final codigo = capture.barcodes.first.rawValue;
                if (codigo != null && codigo.trim().isNotEmpty) {
                  yaLeido = true;
                  final String dniLeido = codigo.trim();
                  Navigator.pop(ctx);
                  _procesarEntradaLector(dniLeido);
                }
              },
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    ).then((_) => controller.dispose());
  }

  // 👨‍👩‍👧 DIÁLOGO DE VINCULACIÓN DE HUELLA NUEVA
  void _ofrecerEnrolamientoHuellaUnificado(String huellaTemplateCapturada) {
    final TextEditingController dniCtrl = TextEditingController();
    String tipoRolSeleccionado = 'Socio / Alumno';
    String relacionFamiliar = 'Propia del Socio';
    Map<String, dynamic>? entidadEncontrada;
    String? entidadIdEncontrada;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Row(
              children: [
                Icon(Icons.fingerprint_rounded, color: Colors.indigo, size: 28),
                SizedBox(width: 10),
                Text('Vincular Nueva Huella Digital'),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seleccioná el tipo de usuario e ingresá su DNI para asociar la huella:',
                    style: TextStyle(color: Colors.blueGrey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: tipoRolSeleccionado,
                    decoration: const InputDecoration(
                      labelText: 'Rol del Usuario',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge_outlined),
                      isDense: true,
                    ),
                    items: ['Socio / Alumno', 'Profesor / Staff']
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          tipoRolSeleccionado = val;
                          entidadEncontrada = null;
                          entidadIdEncontrada = null;
                          dniCtrl.clear();
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: dniCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'DNI del $tipoRolSeleccionado',
                      prefixIcon: const Icon(Icons.search),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) async {
                      final queryStr = val
                          .replaceAll(RegExp(r'[^0-9]'), '')
                          .trim();
                      if (queryStr.length >= 3) {
                        final coleccion =
                            tipoRolSeleccionado == 'Socio / Alumno'
                            ? 'socios'
                            : 'profesores';

                        final res = await _firestore
                            .collection(coleccion)
                            .where('dni', isEqualTo: queryStr)
                            .limit(1)
                            .get();

                        if (res.docs.isNotEmpty) {
                          setDialogState(() {
                            entidadIdEncontrada = res.docs.first.id;
                            entidadEncontrada = res.docs.first.data();
                          });
                        } else {
                          setDialogState(() {
                            entidadIdEncontrada = null;
                            entidadEncontrada = null;
                          });
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  if (entidadEncontrada != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Identificado: ${entidadEncontrada!['nombre']} (DNI: ${entidadEncontrada!['dni']})',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          if (tipoRolSeleccionado == 'Socio / Alumno') ...[
                            const SizedBox(height: 8),
                            DropdownButtonFormField<String>(
                              value: relacionFamiliar,
                              decoration: const InputDecoration(
                                labelText: 'Titular de la Huella',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items:
                                  [
                                        'Propia del Socio',
                                        'Padre / Madre / Tutor Legal',
                                        'Familiar Autorizado',
                                      ]
                                      .map(
                                        (r) => DropdownMenuItem(
                                          value: r,
                                          child: Text(r),
                                        ),
                                      )
                                      .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setDialogState(() => relacionFamiliar = val);
                                }
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  _busquedaController.clear();
                },
                child: const Text('Cancelar'),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                ),
                onPressed: entidadIdEncontrada == null
                    ? null
                    : () async {
                        try {
                          final coleccionTarget =
                              tipoRolSeleccionado == 'Socio / Alumno'
                              ? 'socios'
                              : 'profesores';

                          // 🟢 Sincroniza en huellasHashes y huellasTemplates para lectura cruzada
                          await _firestore
                              .collection(coleccionTarget)
                              .doc(entidadIdEncontrada)
                              .set({
                                'huellasHashes': FieldValue.arrayUnion([
                                  huellaTemplateCapturada,
                                ]),
                                'huellasTemplates': FieldValue.arrayUnion([
                                  huellaTemplateCapturada,
                                ]),
                                'huellaHash': huellaTemplateCapturada,
                                'ultimaVinculacionHuella':
                                    FieldValue.serverTimestamp(),
                              }, SetOptions(merge: true));

                          debugPrint(
                            "✅ Plantilla guardada en $coleccionTarget/$entidadIdEncontrada",
                          );

                          if (mounted) {
                            Navigator.pop(dialogCtx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '✅ Huella vinculada con éxito mediante motor biométrico nativo.',
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                            _busquedaController.clear();
                          }
                        } catch (e) {
                          debugPrint(
                            "🔴 Error al guardar huella en Firestore: $e",
                          );
                        }
                      },
                icon: const Icon(Icons.save_rounded, size: 18),
                label: const Text('Vincular y Procesar'),
              ),
            ],
          );
        },
      ),
    );
  }

  // 🧹 DIÁLOGO DE RESETEO DE HUELLAS REGISTRADAS
  void _mostrarDialogoReseteoHuellas() {
    final TextEditingController dniResetCtrl = TextEditingController();
    String rolReset = 'Socio / Alumno';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.restart_alt_rounded, color: Colors.red, size: 28),
              SizedBox(width: 8),
              Text('Resetear Huellas Digitales'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: rolReset,
                decoration: const InputDecoration(
                  labelText: 'Buscar en',
                  border: OutlineInputBorder(),
                ),
                items: ['Socio / Alumno', 'Profesor / Staff']
                    .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialogState(() => rolReset = v);
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: dniResetCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'DNI del Usuario',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final dniQuery = dniResetCtrl.text
                    .replaceAll(RegExp(r'[^0-9]'), '')
                    .trim();
                if (dniQuery.isEmpty) return;

                final targetColeccion = rolReset == 'Socio / Alumno'
                    ? 'socios'
                    : 'profesores';

                final snap = await _firestore
                    .collection(targetColeccion)
                    .where('dni', isEqualTo: dniQuery)
                    .limit(1)
                    .get();

                if (snap.docs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No se encontró el DNI.')),
                  );
                  return;
                }

                await snap.docs.first.reference.update({
                  'huellasHashes': [],
                  'huellasTemplates': [],
                  'huellaHash': '',
                  'fechaReseteoHuellas': DateTime.now(),
                });

                if (mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '🧹 Huellas reseteadas para ${snap.docs.first.data()['nombre']}.',
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Resetear Huellas'),
            ),
          ],
        ),
      ),
    );
  }

  // 📝 REGISTRO DE FICHAJE DE PROFESORES
  Future<void> _ficharProfesor(
    String profesorId,
    String nombreProfesor,
    String dniProfesor, {
    String especialidad = '',
  }) async {
    final String tipoFichaje = await FichajeProfesorService.ficharProfesor(
      profesorId: profesorId,
      nombreProfesor: nombreProfesor,
      dniProfesor: dniProfesor,
      especialidad: especialidad,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '✅ $tipoFichaje registrada para Docente $nombreProfesor (DNI: $dniProfesor)',
        ),
        backgroundColor: Colors.purple.shade800,
      ),
    );

    _busquedaController.clear();
    setState(() => _socioEncontrado = null);
  }

  // 📝 REGISTRO DE INGRESO DE SOCIOS
  Future<void> _registrarIngreso({
    required String modo,
    required String motivoExcepcion,
  }) async {
    if (_socioEncontrado == null) return;

    final DateTime ahora = DateTime.now();
    final String hoyStr =
        "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}-${ahora.day.toString().padLeft(2, '0')}";
    final String periodoClave =
        "${ahora.year}-${ahora.month.toString().padLeft(2, '0')}";

    // 🚨 Aviso (no bloqueante) de doble ingreso: una huella mal leída dos
    // veces, o un reintento manual, no debería descontar 2 clases ni asentar
    // 2 accesos silenciosamente. Se avisa y el operador decide.
    final yaIngresoHoy = await _firestore
        .collection('asistencias_accesos')
        .where('socioId', isEqualTo: _socioIdEncontrado)
        .where('fechaStr', isEqualTo: hoyStr)
        .limit(1)
        .get();
    if (yaIngresoHoy.docs.isNotEmpty) {
      final Timestamp? tsPrevio =
          yaIngresoHoy.docs.first.data()['fechaHora'] as Timestamp?;
      final String horaPrevia = tsPrevio != null
          ? DateFormat('HH:mm').format(tsPrevio.toDate())
          : '';
      if (!mounted) return;
      final bool continuar =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 10),
                  Text('Ingreso duplicado'),
                ],
              ),
              content: Text(
                '${_socioEncontrado!['nombre']} ya registró un ingreso hoy'
                '${horaPrevia.isNotEmpty ? ' a las $horaPrevia' : ''}.\n\n'
                '¿Registrar otro ingreso de todas formas?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade800,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Registrar Igual',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ) ??
          false;
      if (!continuar) return;
    }

    if (_limiteClasesMes != 999 && modo == 'AUTOMATICO') {
      final docCreditoRef = _firestore
          .collection('socios')
          .doc(_socioIdEncontrado!)
          .collection('creditos_mensuales')
          .doc(periodoClave);

      await docCreditoRef.update({'clasesUsadas': FieldValue.increment(1)});
    }

    await _firestore.collection('asistencias_accesos').add({
      'socioId': _socioIdEncontrado,
      'nombreSocio':
          '${_socioEncontrado!['nombre']} ${_socioEncontrado!['apellido'] ?? ''}'
              .trim(),
      'dniSocio': _socioEncontrado!['dni'] ?? 'S/D',
      'tipoEntidad': 'Socio',
      'fechaHora': Timestamp.fromDate(ahora),
      'fechaStr': hoyStr,
      'modo': modo,
      'motivoExcepcion': motivoExcepcion,
      'creditosRestantes': _limiteClasesMes == 999
          ? 'Libre'
          : '${_creditosRestantes - 1}/$_limiteClasesMes',
      'operador': widget.rolUsuario,
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('✅ Ingreso asentado para ${_socioEncontrado!['nombre']}'),
        backgroundColor: Colors.green,
      ),
    );

    setState(() {
      _socioEncontrado = null;
      _busquedaController.clear();
    });
  }

  void _solicitarBypassManual(BuildContext context) {
    final TextEditingController motivoCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Autorización de Excepción Manual'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Autorizar ingreso excepcional para socio no habilitado.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: motivoCtrl,
              decoration: const InputDecoration(
                labelText: 'Motivo de la excepción',
                hintText: 'Ej: Regularizó recién / Apto en trámite',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade800,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              if (motivoCtrl.text.trim().isEmpty) return;
              Navigator.pop(dialogCtx);
              _registrarIngreso(
                modo: 'EXCEPCION_MANUAL',
                motivoExcepcion: motivoCtrl.text.trim(),
              );
            },
            child: const Text('Autorizar e Ingresar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Control de Acceso & Recepción Híbrida'),
        actions: [
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: 'Resetear Huellas de Usuario',
            onPressed: _mostrarDialogoReseteoHuellas,
          ),
        ],
      ),
      body: KeyboardListener(
        focusNode: _lectorFocusNode,
        onKeyEvent: (event) {
          if (!_lectorFocusNode.hasFocus) {
            _busquedaController.selection = TextSelection.fromPosition(
              TextPosition(offset: _busquedaController.text.length),
            );
            _lectorFocusNode.requestFocus();
          }
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 📱 Por debajo de este ancho el panel del lector y el monitor
            // en vivo no entran lado a lado (era un Row fijo flex:5/flex:4):
            // se apilan en una columna con scroll, y el monitor —que adentro
            // tiene un Expanded+ListView, así que necesita una altura
            // acotada para funcionar fuera del Row original— pasa a tener
            // una altura fija con scroll propio.
            final bool esMovil = constraints.maxWidth < 900;

            if (esMovil) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTarjetaLector(),
                    const SizedBox(height: 16),
                    _socioEncontrado == null
                        ? _buildEstadoInicialLector()
                        : _buildFichaValidacionSocio(),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 420,
                      child: _buildMonitorIngresosHoy(),
                    ),
                  ],
                ),
              );
            }

            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 5,
                    child: Column(
                      children: [
                        _buildTarjetaLector(),
                        const SizedBox(height: 20),
                        Expanded(
                          child: _socioEncontrado == null
                              ? _buildEstadoInicialLector()
                              : _buildFichaValidacionSocio(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(flex: 4, child: _buildMonitorIngresosHoy()),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTarjetaLector() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: const Icon(
              Icons.fingerprint_rounded,
              size: 30,
              color: AppColors.teal,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _busquedaController,
              autofocus: true,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              decoration: const InputDecoration(
                hintText: 'Escaneá huella, QR o DNI…',
                hintStyle: TextStyle(
                  fontWeight: FontWeight.w400,
                  color: AppColors.textMuted,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
              ),
              onSubmitted: (val) => _procesarEntradaLector(val),
            ),
          ),
          const SizedBox(width: 12),
          if (_buscando)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          else ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 16,
                ),
              ),
              onPressed: _abrirEscanerQr,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
              label: const Text(
                'Escanear QR',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 16,
                ),
              ),
              onPressed: () => _procesarEntradaLector(_busquedaController.text),
              icon: const Icon(Icons.search_rounded, size: 19),
              label: const Text(
                'Validar',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEstadoInicialLector() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.badge_outlined,
              size: 56,
              color: AppColors.teal,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Esperando lectura de credencial o huella…',
            style: TextStyle(
              fontSize: 17,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Lector unificado: valida socios, tutores y fichaje de profesores.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildFichaValidacionSocio() {
    final String nombre =
        '${_socioEncontrado!['nombre'] ?? ''} ${_socioEncontrado!['apellido'] ?? ''}'
            .trim();
    final String dni = _socioEncontrado!['dni'] ?? '-';
    final String fotoUrl = _socioEncontrado!['fotoUrl'] ?? '';

    Color colorEstado = _estadoHabilitado
        ? AppColors.success
        : AppColors.danger;
    String textoEstado = _estadoHabilitado
        ? 'ACCESO HABILITADO'
        : 'ACCESO DENEGADO';

    String detalleCuota = _cuotaAlDia
        ? 'Al Día'
        : 'Deuda: \$${_saldoCuentaCorriente.abs().toStringAsFixed(0)}';

    String detalleCredito = _limiteClasesMes == 999
        ? 'Pase Libre'
        : 'Quedan $_creditosRestantes de $_limiteClasesMes clases';

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colorEstado, width: 2),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: colorEstado.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              textoEstado,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: colorEstado,
              ),
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(45),
                child: SizedBox(
                  width: 90,
                  height: 90,
                  child: fotoUrl.isNotEmpty
                      ? Image.network(
                          fotoUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              color: AppColors.surfaceMuted,
                              child: const Center(
                                child: SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.teal.shade200,
                              child: const Icon(
                                Icons.person,
                                size: 45,
                                color: Colors.white,
                              ),
                            );
                          },
                        )
                      : Container(
                          color: Colors.teal.shade200,
                          child: const Icon(
                            Icons.person,
                            size: 45,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nombre,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'DNI: $dni',
                      style: const TextStyle(color: Colors.grey, fontSize: 15),
                    ),
                    Text(
                      'Programa: ${_socioEncontrado!['deporte'] ?? 'General'} ($_frecuenciaPase)',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.teal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(height: 28),

          Row(
            children: [
              _buildItemRegla('Estado Financiero', _cuotaAlDia, detalleCuota),
              const SizedBox(width: 8),
              _buildItemRegla(
                'Apto Médico',
                _aptoMedicoVigente,
                _aptoMedicoVigente ? 'Vigente' : 'Vencido',
              ),
              const SizedBox(width: 8),
              _buildItemRegla(
                'Crédito Clases',
                _tieneCreditoDisponible,
                detalleCredito,
              ),
              const SizedBox(width: 8),
              _buildItemRegla(
                'Matrícula',
                _matriculaAlDia,
                _matriculaAlDia ? 'Al Día' : 'Pendiente',
              ),
            ],
          ),
          const Spacer(),

          Row(
            children: [
              if (_estadoHabilitado)
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    onPressed: () => _registrarIngreso(
                      modo: 'AUTOMATICO',
                      motivoExcepcion: '',
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 24),
                    label: const Text(
                      'REGISTRAR INGRESO Y DESCONTAR CLASE',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      side: const BorderSide(
                        color: AppColors.warning,
                        width: 2,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                    onPressed: () => _solicitarBypassManual(context),
                    icon: const Icon(
                      Icons.published_with_changes_rounded,
                      size: 24,
                    ),
                    label: const Text(
                      'AUTORIZAR EXCEPCIÓN MANUAL (ADMIN)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemRegla(String titulo, bool cumple, String detalle) {
    Color color = cumple ? AppColors.success : AppColors.danger;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(
              cumple ? Icons.check_circle : Icons.cancel,
              color: color,
              size: 24,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    detalle,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 📊 MONITOR EN VIVO DE ASISTENCIAS CON ETIQUETAS "PROFE" Y "SOCIO"
  Widget _buildMonitorIngresosHoy() {
    final DateTime hoy = DateTime.now();
    final String hoyStr =
        "${hoy.year}-${hoy.month.toString().padLeft(2, '0')}-${hoy.day.toString().padLeft(2, '0')}";

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Monitor Acceso en Vivo',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                Chip(
                  label: Text(DateFormat('dd/MM/yyyy').format(hoy)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore
                    .collection('asistencias_accesos')
                    .where('fechaStr', isEqualTo: hoyStr)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = snapshot.data!.docs;

                  if (docs.isEmpty) {
                    return const Center(
                      child: Text('Sin ingresos registrados en el día de hoy.'),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(height: 12),
                    itemBuilder: (context, idx) {
                      final data = docs[idx].data() as Map<String, dynamic>;
                      final DateTime hora = (data['fechaHora'] as Timestamp)
                          .toDate();
                      final bool esExcepcion =
                          data['modo'] == 'EXCEPCION_MANUAL';
                      final String tipoEntidad = data['tipoEntidad'] ?? 'Socio';
                      final bool esProfesor = tipoEntidad == 'Profesor';
                      final String dni = data['dniSocio'] ?? 'S/D';

                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: CircleAvatar(
                          backgroundColor: esProfesor
                              ? Colors.purple.shade100
                              : (esExcepcion
                                    ? Colors.orange.shade100
                                    : Colors.green.shade100),
                          child: Icon(
                            esProfesor
                                ? Icons.badge
                                : (esExcepcion
                                      ? Icons.warning_rounded
                                      : Icons.check_rounded),
                            color: esProfesor
                                ? Colors.purple.shade900
                                : (esExcepcion
                                      ? Colors.orange.shade900
                                      : Colors.green.shade900),
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            StatusBadge(
                              label: esProfesor ? 'PROFE' : 'SOCIO',
                              color: esProfesor
                                  ? Colors.purple.shade700
                                  : AppColors.info,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                data['nombreSocio'] ?? 'Usuario',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          esProfesor
                              ? 'DNI: $dni • Fichaje Docente (${data['tipoFichajeProfe'] ?? 'Ingreso'})'
                              : (esExcepcion
                                    ? 'DNI: $dni • Excepción: ${data['motivoExcepcion']}'
                                    : 'DNI: $dni • Acceso OK (Quedan: ${data['creditosRestantes'] ?? 'Libre'})'),
                          style: TextStyle(
                            color: esProfesor
                                ? Colors.purple.shade800
                                : (esExcepcion
                                      ? Colors.orange.shade800
                                      : Colors.grey),
                          ),
                        ),
                        trailing: Text(
                          DateFormat('HH:mm:ss').format(hora),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
