import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart' as cloud_functions;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Diálogo de cobro real por Mercado Pago — genera una preferencia de
/// Checkout Pro (vía la Cloud Function `crearCobroMercadoPago`, que fija el
/// monto leyendo el documento real en Firestore, nunca confiando en lo que
/// mande el cliente) y espera la confirmación de `webhookMercadoPago` (que
/// valida el pago contra la API de MP) antes de dar el cobro por
/// verificado. Compartido entre todas las pantallas que cobran (POS,
/// reservas de cancha, cuotas, torneos) para no duplicar esta lógica.
///
/// [ruta] es la ruta completa del documento ya creado en Firestore (sirve
/// tanto para colecciones planas — 'ventas_buffet/ventaId' — como para
/// subcolecciones — 'socios/socioId/cuenta_corriente/movId'). [campoMonto]
/// es el nombre del campo numérico a cobrar en ese documento (por defecto
/// 'total'); [campoMedioPago] es el campo de texto que se pisa con
/// 'Mercado Pago (QR)' una vez confirmado (por defecto 'medio_pago').
///
/// [ruta] puede omitirse cuando [cloudFunction] es
/// 'crearCobroMercadoPagoSocio' (pago self-service iniciado por el propio
/// socio desde su dashboard): esa función nunca confía en una ruta que
/// mande el cliente, la resuelve y valida ella misma a partir del usuario
/// autenticado, y la devuelve en la respuesta — [parametrosExtra] es donde
/// va el `tipo` ('cuota' | 'reserva_cancha') y, para reservas, el
/// `reservaId`.
Future<void> mostrarDialogoCobroMercadoPago(
  BuildContext context, {
  String? ruta,
  required String concepto,
  String campoMonto = 'total',
  String campoMedioPago = 'medio_pago',
  String cloudFunction = 'crearCobroMercadoPago',
  Map<String, dynamic> parametrosExtra = const {},
}) async {
  String? initPoint;
  String? errorMp;
  String? rutaConfirmada = ruta;
  bool generando = true;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModalState) {
        if (generando && initPoint == null && errorMp == null) {
          cloud_functions.FirebaseFunctions.instance
              .httpsCallable(cloudFunction)
              .call({
                if (ruta != null) 'ruta': ruta,
                'campoMonto': campoMonto,
                'campoMedioPago': campoMedioPago,
                'concepto': concepto,
                ...parametrosExtra,
              })
              .then((resp) {
                if (!context.mounted) return;
                setModalState(() {
                  generando = false;
                  if (resp.data['success'] == true) {
                    initPoint = resp.data['initPoint'];
                    rutaConfirmada = resp.data['ruta'] ?? ruta;
                  } else {
                    errorMp = resp.data['error'] ?? 'Error desconocido.';
                  }
                });
              })
              .catchError((e) {
                if (!context.mounted) return;
                setModalState(() {
                  generando = false;
                  errorMp = e.toString();
                });
              });
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: Colors.indigo),
              SizedBox(width: 10),
              Text('Cobro con Mercado Pago'),
            ],
          ),
          content: SizedBox(
            width: 320,
            child: generando
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : errorMp != null
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: Text(
                      '⚠️ No se pudo generar el cobro: $errorMp\n\n'
                      'El comprobante ya quedó registrado — podés reintentar '
                      'el cobro o marcarlo como pagado por otro medio.',
                      style: const TextStyle(color: Colors.red),
                    ),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: QrImageView(
                          data: initPoint!,
                          version: QrVersions.auto,
                          size: 220,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () => launchUrl(
                          Uri.parse(initPoint!),
                          mode: LaunchMode.externalApplication,
                        ),
                        icon: const Icon(Icons.open_in_new_rounded, size: 18),
                        label: const Text('Abrir Link de Pago'),
                      ),
                      const SizedBox(height: 16),
                      // 🔄 Escucha en vivo el documento: el webhook lo marca
                      // 'Aprobado' apenas Mercado Pago confirma el pago.
                      StreamBuilder<DocumentSnapshot>(
                        stream: FirebaseFirestore.instance
                            .doc(rutaConfirmada!)
                            .snapshots(),
                        builder: (context, snap) {
                          final String estado =
                              (snap.data?.data()
                                  as Map<String, dynamic>?)?['estadoPagoMP']
                                  ?.toString() ??
                              '';
                          if (estado == 'Aprobado') {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                            });
                            return const Text(
                              '✅ ¡Pago confirmado por Mercado Pago!',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            );
                          }
                          return const Text(
                            'Esperando confirmación del pago…',
                            style: TextStyle(color: Colors.grey, fontSize: 12),
                          );
                        },
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    ),
  );
}

/// Punto de entrada para el STAFF: antes de cobrar, deja elegir entre QR
/// (Checkout Pro — el cliente escanea con su propio celular) o Posnet
/// (terminal física Point — el cliente paga con tarjeta/contactless en el
/// aparato, en el mostrador). El flujo QR reusa
/// [mostrarDialogoCobroMercadoPago] tal cual ya estaba; sólo agrega este
/// paso previo de selección. No usar esto para pagos self-service del
/// socio (ésos siempre son QR, el socio no tiene una terminal a mano).
Future<void> mostrarSelectorCobroMercadoPago(
  BuildContext context, {
  required String ruta,
  required String concepto,
  String campoMonto = 'total',
  String campoMedioPago = 'medio_pago',
}) async {
  final modo = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('¿Cómo cobrás?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.qr_code_2_rounded, color: Colors.indigo),
            title: const Text('QR'),
            subtitle: const Text('El cliente escanea con su celular'),
            onTap: () => Navigator.pop(ctx, 'qr'),
          ),
          ListTile(
            leading: const Icon(
              Icons.point_of_sale_rounded,
              color: Colors.indigo,
            ),
            title: const Text('Posnet'),
            subtitle: const Text('Tarjeta/contactless en la terminal física'),
            onTap: () => Navigator.pop(ctx, 'posnet'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ],
    ),
  );

  if (!context.mounted || modo == null) return;

  if (modo == 'qr') {
    await mostrarDialogoCobroMercadoPago(
      context,
      ruta: ruta,
      concepto: concepto,
      campoMonto: campoMonto,
      campoMedioPago: campoMedioPago,
    );
    return;
  }

  await _mostrarDialogoCobroPosnet(
    context,
    ruta: ruta,
    concepto: concepto,
    campoMonto: campoMonto,
    campoMedioPago: campoMedioPago,
  );
}

Future<void> _mostrarDialogoCobroPosnet(
  BuildContext context, {
  required String ruta,
  required String concepto,
  required String campoMonto,
  required String campoMedioPago,
}) async {
  List<Map<String, dynamic>>? terminales;
  String? errorCarga;
  String? terminalSeleccionado;
  bool enviando = false;
  String? errorEnvio;
  String? cobroId;
  String? rutaConfirmada;

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModalState) {
        if (terminales == null && errorCarga == null) {
          cloud_functions.FirebaseFunctions.instance
              .httpsCallable('listarTerminalesPosnetMP')
              .call({})
              .then((resp) {
                if (!context.mounted) return;
                setModalState(() {
                  if (resp.data['success'] == true) {
                    terminales = List<Map<String, dynamic>>.from(
                      (resp.data['terminales'] as List).map(
                        (t) => Map<String, dynamic>.from(t),
                      ),
                    );
                  } else {
                    errorCarga =
                        resp.data['error'] ??
                        'No se pudieron cargar las terminales.';
                  }
                });
              })
              .catchError((e) {
                if (!context.mounted) return;
                setModalState(() => errorCarga = e.toString());
              });
        }

        Widget contenido;
        if (errorCarga != null) {
          contenido = Text(
            '⚠️ $errorCarga',
            style: const TextStyle(color: Colors.red),
          );
        } else if (terminales == null) {
          contenido = const Padding(
            padding: EdgeInsets.symmetric(vertical: 30),
            child: Center(child: CircularProgressIndicator()),
          );
        } else if (terminales!.isEmpty) {
          contenido = const Text(
            'No hay terminales Posnet vinculadas a la cuenta de Mercado '
            'Pago. Vinculá un dispositivo Point desde tu cuenta de MP para '
            'poder usar esta opción.',
          );
        } else if (cobroId == null) {
          contenido = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Elegí la terminal:'),
              const SizedBox(height: 8),
              ...terminales!.map(
                (t) => RadioListTile<String>(
                  value: t['id'] as String,
                  groupValue: terminalSeleccionado,
                  title: Text(t['id'] as String? ?? '-'),
                  subtitle: Text('Modo: ${t['modoOperacion'] ?? '-'}'),
                  onChanged: (v) => setModalState(() => terminalSeleccionado = v),
                ),
              ),
              if (errorEnvio != null) ...[
                const SizedBox(height: 8),
                Text(
                  '⚠️ $errorEnvio',
                  style: const TextStyle(color: Colors.red),
                ),
              ],
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: (terminalSeleccionado == null || enviando)
                    ? null
                    : () async {
                        setModalState(() {
                          enviando = true;
                          errorEnvio = null;
                        });
                        try {
                          final resp = await cloud_functions
                              .FirebaseFunctions.instance
                              .httpsCallable('crearCobroMercadoPagoPosnet')
                              .call({
                                'ruta': ruta,
                                'campoMonto': campoMonto,
                                'campoMedioPago': campoMedioPago,
                                'concepto': concepto,
                                'terminalId': terminalSeleccionado,
                              });
                          if (!context.mounted) return;
                          setModalState(() {
                            enviando = false;
                            if (resp.data['success'] == true) {
                              cobroId = resp.data['cobroId'];
                              rutaConfirmada = resp.data['ruta'] ?? ruta;
                            } else {
                              errorEnvio =
                                  resp.data['error'] ?? 'Error desconocido.';
                            }
                          });
                        } catch (e) {
                          if (!context.mounted) return;
                          setModalState(() {
                            enviando = false;
                            errorEnvio = e.toString();
                          });
                        }
                      },
                child: enviando
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enviar cobro a la terminal'),
              ),
            ],
          );
        } else {
          // 🔄 Mismo patrón que el QR: escucha en vivo el documento real,
          // que el webhook de órdenes (webhookMercadoPagoOrder) marca
          // 'Aprobado' apenas el cliente completa el pago en la terminal.
          contenido = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.point_of_sale_rounded,
                size: 48,
                color: Colors.indigo,
              ),
              const SizedBox(height: 12),
              const Text(
                'Pedile al cliente que complete el pago en la terminal.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .doc(rutaConfirmada!)
                    .snapshots(),
                builder: (context, snap) {
                  final String estado =
                      (snap.data?.data()
                          as Map<String, dynamic>?)?['estadoPagoMP']
                          ?.toString() ??
                      '';
                  if (estado == 'Aprobado') {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                    });
                    return const Text(
                      '✅ ¡Pago confirmado!',
                      style: TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    );
                  }
                  return const Text(
                    'Esperando confirmación…',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  );
                },
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  await cloud_functions.FirebaseFunctions.instance
                      .httpsCallable('cancelarCobroPosnetMP')
                      .call({'cobroId': cobroId});
                  if (Navigator.canPop(ctx)) Navigator.pop(ctx);
                },
                child: const Text('Cancelar cobro'),
              ),
            ],
          );
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.point_of_sale_rounded, color: Colors.indigo),
              SizedBox(width: 10),
              Text('Cobro con Posnet'),
            ],
          ),
          content: SizedBox(width: 340, child: contenido),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar'),
            ),
          ],
        );
      },
    ),
  );
}
