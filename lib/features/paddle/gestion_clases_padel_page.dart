import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../shared/caja_abierta_helper.dart';
import '../profesores/profesor_model.dart';
import 'cancha_padel_repository.dart';
import 'clase_padel_model.dart';
import 'clase_padel_repository.dart';
import 'reserva_cancha_model.dart';
import 'reserva_cancha_repository.dart';

class GestionClasesPadelPage extends StatefulWidget {
  const GestionClasesPadelPage({super.key});

  @override
  State<GestionClasesPadelPage> createState() =>
      _GestionClasesPadelPageState();
}

class _GestionClasesPadelPageState extends State<GestionClasesPadelPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  DateTime _fechaSeleccionada = DateTime.now();

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  Future<void> _crearClase() async {
    final profesoresSnap = await _firestore
        .collection('profesores')
        .where('especialidades', arrayContains: 'Pádel')
        .where('activo', isEqualTo: true)
        .get();
    final profesores = profesoresSnap.docs
        .map((d) => ProfesorModel.fromFirestore(d.id, d.data()))
        .toList();
    final canchas = await obtenerNombresCanchasActivas(_firestore);

    if (!mounted) return;
    if (profesores.isEmpty) {
      _snack(
        '⚠️ No hay ningún profesor con la especialidad "Pádel" activo. '
        'Cargalo primero en Profesores.',
        Colors.orange,
      );
      return;
    }
    if (canchas.isEmpty) {
      _snack('⚠️ No hay ninguna cancha configurada.', Colors.orange);
      return;
    }

    final nombreCtrl = TextEditingController(text: 'Clase de Pádel');
    final cupoCtrl = TextEditingController(text: '4');
    final precioCtrl = TextEditingController(text: '3000');
    ProfesorModel profesorSel = profesores.first;
    String canchaSel = canchas.first;
    int horaSel = 18;
    int duracionSel = 1;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Nueva clase de pádel'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre (ej. Clase Intermedio)',
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<ProfesorModel>(
                  initialValue: profesorSel,
                  decoration: const InputDecoration(labelText: 'Profesor'),
                  items: profesores
                      .map(
                        (p) => DropdownMenuItem(value: p, child: Text(p.nombre)),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setModalState(() => profesorSel = v ?? profesorSel),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: canchaSel,
                  decoration: const InputDecoration(labelText: 'Cancha'),
                  items: canchas
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) =>
                      setModalState(() => canchaSel = v ?? canchaSel),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: horaSel,
                        decoration: const InputDecoration(labelText: 'Hora'),
                        items: List.generate(16, (i) => 7 + i)
                            .map(
                              (h) => DropdownMenuItem(
                                value: h,
                                child: Text('${h.toString().padLeft(2, '0')}:00'),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            setModalState(() => horaSel = v ?? horaSel),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: duracionSel,
                        decoration: const InputDecoration(
                          labelText: 'Duración',
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 hora')),
                          DropdownMenuItem(value: 2, child: Text('2 horas')),
                        ],
                        onChanged: (v) =>
                            setModalState(() => duracionSel = v ?? duracionSel),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cupoCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Cupo máximo',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: precioCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Precio por alumno',
                          prefixText: '\$ ',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nombreCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx);
                try {
                  await crearClasePadelAtomica(
                    firestore: _firestore,
                    nombre: nombreCtrl.text.trim(),
                    profesorId: profesorSel.id,
                    profesorNombre: profesorSel.nombre,
                    cancha: canchaSel,
                    fecha: _fechaSeleccionada,
                    horaInicio: horaSel,
                    duracionHoras: duracionSel,
                    cupoMaximo: int.tryParse(cupoCtrl.text) ?? 4,
                    precioPorAlumno: double.tryParse(precioCtrl.text) ?? 0,
                    creadoPor: 'admin',
                  );
                  _snack('✅ Clase creada.', Colors.green);
                } on HorarioOcupadoException {
                  _snack(
                    'Ese horario de "$canchaSel" ya está ocupado.',
                    Colors.red,
                  );
                } catch (e) {
                  _snack('Error: $e', Colors.red);
                }
              },
              child: const Text('Crear'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _darDeBaja(ClasePadelModel clase, String socioId) async {
    await cancelarInscripcionClasePadelAtomica(
      firestore: _firestore,
      claseId: clase.id,
      socioId: socioId,
    );
    _snack('Alumno dado de baja de la clase.', Colors.orange);
  }

  Future<void> _eliminarClase(ClasePadelModel clase) async {
    if (clase.inscriptosIds.isNotEmpty || clase.listaEsperaIds.isNotEmpty) {
      _snack(
        '⚠️ Esta clase tiene alumnos anotados — dalos de baja antes de eliminarla.',
        Colors.orange,
      );
      return;
    }
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Eliminar clase?'),
        content: Text('Se va a liberar la cancha "${clase.cancha}" de este horario.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    // 🔓 Mismo mecanismo que cualquier otra reserva (libera reserva + slots
    // juntos); no hace falta leer el doc real porque todo lo que necesita
    // ya está en la propia clase (cancha/fecha/hora/duración).
    await cancelarReservaCanchaAtomica(
      firestore: _firestore,
      reserva: ReservaCanchaModel(
        id: clase.reservaId,
        cancha: clase.cancha,
        nombreCliente: clase.nombre,
        fecha: clase.fecha,
        horaInicio: clase.horaInicio,
        duracionHoras: clase.duracionHoras,
        precio: 0,
        metodoPago: 'Clase de Pádel',
      ),
    );
    await _firestore.collection('clases_padel').doc(clase.id).delete();
    _snack('Clase eliminada y cancha liberada.', Colors.green);
  }

  Future<void> _registrarPagoManual(PagoClasePadelModel pago) async {
    final terminales = await terminalesConCajaAbierta(_firestore);
    if (!mounted) return;

    String medioPago = 'Efectivo ARS';
    String? terminalSel = terminales.isNotEmpty ? terminales.first : null;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('Registrar pago: ${pago.socioNombre}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Monto: \$${pago.monto.toStringAsFixed(0)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: medioPago,
                decoration: const InputDecoration(labelText: 'Medio de pago'),
                items: [...mediosPagoManualCaja, 'Mercado Pago']
                    .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                    .toList(),
                onChanged: (v) =>
                    setModalState(() => medioPago = v ?? medioPago),
              ),
              if (terminales.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    '⚠️ No hay ninguna caja abierta: el pago va a quedar '
                    'registrado, pero no se va a sumar a ningún arqueo.',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                )
              else if (terminales.length > 1)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: DropdownButtonFormField<String>(
                    initialValue: terminalSel,
                    decoration: const InputDecoration(
                      labelText: 'Asentar en caja',
                    ),
                    items: terminales
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) =>
                        setModalState(() => terminalSel = v),
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
              onPressed: () async {
                Navigator.pop(ctx);
                await _firestore
                    .collection('pagos_clases_padel')
                    .doc(pago.id)
                    .update({
                      'cobrado': true,
                      'medioPago': medioPago,
                      'fechaPago': FieldValue.serverTimestamp(),
                    });
                if (pago.ventaPendienteId != null) {
                  await _firestore
                      .collection('ventas_pendientes')
                      .doc(pago.ventaPendienteId)
                      .update({'estado': 'Cobrado', 'fechaCobro': DateTime.now()});
                }
                if (terminalSel != null) {
                  await sumarACajaAbierta(
                    _firestore,
                    terminal: terminalSel!,
                    medioPago: medioPago,
                    monto: pago.monto,
                  );
                }
                _snack('💰 Pago registrado.', Colors.green);
                // 📲 Aviso de recibo por WhatsApp (Fase 5) — 'soloSiFlagActivo'
                // hace que el propio callable chequee 'notifPagoConfirmadoActivo'
                // del lado del servidor antes de mandar nada (configuraciones_fiscales
                // es de lectura sólo-admin, un cajero no podría leerlo acá).
                try {
                  await FirebaseFunctions.instance
                      .httpsCallable('notificarWhatsappAdminASocio')
                      .call({
                        'socioId': pago.socioId,
                        'soloSiFlagActivo': 'notifPagoConfirmadoActivo',
                        'mensaje':
                            '🧾 *¡Pago recibido!*\n\nRecibimos tu pago de '
                            '\$${pago.monto.toStringAsFixed(0)} por la clase '
                            '"${pago.claseNombre}" ($medioPago). ¡Gracias!',
                      });
                } catch (_) {
                  // No bloquea el cobro si el envío falla.
                }
              },
              child: const Text('Registrar'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inicioDia = DateTime(
      _fechaSeleccionada.year,
      _fechaSeleccionada.month,
      _fechaSeleccionada.day,
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Clases de Pádel'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crearClase,
        icon: const Icon(Icons.add),
        label: const Text('Nueva clase'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Fecha: ${_fechaSeleccionada.day}/${_fechaSeleccionada.month}/${_fechaSeleccionada.year}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.calendar_month),
                  label: const Text('Cambiar fecha'),
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _fechaSeleccionada,
                      firstDate: DateTime.now().subtract(
                        const Duration(days: 30),
                      ),
                      lastDate: DateTime.now().add(const Duration(days: 60)),
                    );
                    if (picked != null) {
                      setState(() => _fechaSeleccionada = picked);
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('clases_padel')
                  .where(
                    'fecha',
                    isGreaterThanOrEqualTo: Timestamp.fromDate(inicioDia),
                  )
                  .where(
                    'fecha',
                    isLessThan: Timestamp.fromDate(
                      inicioDia.add(const Duration(days: 1)),
                    ),
                  )
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final clases = snapshot.data!.docs
                    .map(
                      (d) => ClasePadelModel.fromFirestore(
                        d.id,
                        d.data() as Map<String, dynamic>,
                      ),
                    )
                    .toList()
                  ..sort((a, b) => a.horaInicio.compareTo(b.horaInicio));

                if (clases.isEmpty) {
                  return const Center(
                    child: Text(
                      'No hay clases creadas para este día.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: clases.length,
                  itemBuilder: (context, i) => _buildClaseCard(clases[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClaseCard(ClasePadelModel c) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(
          '${c.nombre} · ${c.horaInicio.toString().padLeft(2, '0')}:00 hs',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${c.profesorNombre} · ${c.cancha} · ${c.inscriptosIds.length}/${c.cupoMaximo}'
          '${c.listaEsperaIds.isNotEmpty ? ' · ${c.listaEsperaIds.length} en espera' : ''}'
          ' · \$${c.precioPorAlumno.toStringAsFixed(0)}/alumno',
        ),
        children: [
          StreamBuilder<QuerySnapshot>(
            stream: _firestore
                .collection('pagos_clases_padel')
                .where('claseId', isEqualTo: c.id)
                .snapshots(),
            builder: (context, pagosSnap) {
              final pagosPorSocio = <String, PagoClasePadelModel>{};
              if (pagosSnap.hasData) {
                for (final doc in pagosSnap.data!.docs) {
                  final pago = PagoClasePadelModel.fromFirestore(
                    doc.id,
                    doc.data() as Map<String, dynamic>,
                  );
                  pagosPorSocio[pago.socioId] = pago;
                }
              }

              return Column(
                children: [
                  if (c.inscriptosIds.isEmpty && c.listaEsperaIds.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text(
                        'Sin alumnos anotados todavía.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ...List.generate(c.inscriptosIds.length, (idx) {
                    final socioId = c.inscriptosIds[idx];
                    final pago = pagosPorSocio[socioId];
                    final pagado = pago?.estaPago ?? false;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        pagado ? Icons.check_circle : Icons.schedule,
                        color: pagado ? Colors.green : Colors.orange,
                      ),
                      title: Text(c.inscriptosNombres[idx]),
                      subtitle: Text(
                        pagado
                            ? 'Pagado${pago?.medioPago != null ? ' (${pago!.medioPago})' : ''}'
                            : 'Pendiente de pago',
                        style: TextStyle(
                          fontSize: 11,
                          color: pagado ? Colors.green : Colors.orange,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (!pagado && pago != null)
                            TextButton(
                              onPressed: () => _registrarPagoManual(pago),
                              child: const Text('Cobrar'),
                            ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            tooltip: 'Dar de baja',
                            onPressed: () => _darDeBaja(c, socioId),
                          ),
                        ],
                      ),
                    );
                  }),
                  ...List.generate(c.listaEsperaIds.length, (idx) {
                    return ListTile(
                      dense: true,
                      leading: Text('#${idx + 1}'),
                      title: Text(c.listaEsperaNombres[idx]),
                      subtitle: const Text(
                        'En lista de espera',
                        style: TextStyle(fontSize: 11),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close, color: Colors.red),
                        onPressed: () => _darDeBaja(c, c.listaEsperaIds[idx]),
                      ),
                    );
                  }),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () => _eliminarClase(c),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                          size: 18,
                        ),
                        label: const Text(
                          'Eliminar clase',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
