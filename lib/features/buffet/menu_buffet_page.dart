import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'producto_buffet_model.dart';
import '../inventario/inventario_general_page.dart';

class MenuBuffetPage extends StatefulWidget {
  const MenuBuffetPage({super.key});

  @override
  State<MenuBuffetPage> createState() => _MenuBuffetPageState();
}

class _MenuBuffetPageState extends State<MenuBuffetPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _categoriaFiltro = 'Todas';
  String _searchQuery = '';

  final List<String> _categorias = [
    'Todas',
    'Bebidas',
    'Minutas',
    'Menú Diario',
    'Kiosco',
    'Cafetería',
  ];

  // 🚀 AJUSTE MASIVO DE PRECIOS POR PORCENTAJE
  void _mostrarDialogoAjusteMasivo() {
    String catSeleccionada = 'Bebidas';
    final porcentajeCtrl = TextEditingController(text: '10');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.trending_up_rounded, color: Colors.indigo),
              SizedBox(width: 8),
              Text('Ajuste Masivo de Precios'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Incrementá o reducí los precios de venta al público de toda una categoría:',
                style: TextStyle(fontSize: 13, color: Colors.blueGrey),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: catSeleccionada,
                decoration: const InputDecoration(
                  labelText: 'Categoría a modificar',
                  border: OutlineInputBorder(),
                ),
                items: _categorias
                    .where((c) => c != 'Todas')
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (v) => setModalState(() => catSeleccionada = v!),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: porcentajeCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Porcentaje de Variación (%)',
                  hintText: 'Ej: 10 o -5',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.percent_rounded),
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
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final double porcentaje =
                    double.tryParse(porcentajeCtrl.text.trim()) ?? 0.0;
                if (porcentaje == 0) return;

                Navigator.pop(ctx);
                final snapshot = await _firestore
                    .collection('inventario_general')
                    .where('categoria', isEqualTo: catSeleccionada)
                    .get();

                WriteBatch batch = _firestore.batch();
                int modificados = 0;

                for (var doc in snapshot.docs) {
                  final data = doc.data();
                  final double precioActual =
                      (data['precioVenta'] ?? data['precio'] as num?)
                          ?.toDouble() ??
                      0.0;
                  if (precioActual > 0) {
                    final double nuevoPrecio =
                        precioActual + (precioActual * (porcentaje / 100));
                    batch.update(doc.reference, {
                      'precioVenta': nuevoPrecio,
                      'precio': nuevoPrecio,
                    });
                    modificados++;
                  }
                }

                await batch.commit();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '✅ Se actualizaron $modificados artículos en $catSeleccionada ($porcentaje%).',
                      ),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              },
              child: const Text('Aplicar Variación'),
            ),
          ],
        ),
      ),
    );
  }

  void _mostrarFormularioProducto([ProductoBuffetModel? producto]) {
    final formKey = GlobalKey<FormState>();
    final nombreCtrl = TextEditingController(text: producto?.nombre ?? '');
    final descCtrl = TextEditingController(text: producto?.descripcion ?? '');
    final precioCtrl = TextEditingController(
      text: producto?.precio != null ? producto!.precio.toStringAsFixed(0) : '',
    );
    final precioCostoCtrl = TextEditingController(
      text: producto?.precioCosto != null
          ? producto!.precioCosto.toStringAsFixed(0)
          : '',
    );
    final stockCtrl = TextEditingController(
      text: producto?.stock.toString() ?? '0',
    );
    final stockMinimoCtrl = TextEditingController(
      text: producto?.stockMinimo.toString() ?? '5',
    );
    final codBarrasCtrl = TextEditingController(
      text: producto?.codigoBarras ?? '',
    );
    final codInternoCtrl = TextEditingController(
      text: producto?.codigoInterno ?? '',
    );

    String? proveedorSeleccionadoId = producto?.proveedorId;
    String catSel = producto?.categoria ?? 'Minutas';
    bool disponible = producto?.disponible ?? true;

    bool esCombo = producto?.esCombo ?? false;
    List<ComponenteCombo> componentesSeleccionados =
        producto?.componentes != null
        ? List<ComponenteCombo>.from(producto!.componentes)
        : [];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) => AlertDialog(
            title: Text(
              producto == null
                  ? 'Nuevo Artículo / Combo'
                  : 'Editar Artículo / Combo',
            ),
            content: SizedBox(
              width: 600,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SwitchListTile(
                        title: const Text(
                          '¿Es un Combo de productos?',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo,
                          ),
                        ),
                        subtitle: const Text(
                          'Habilita la baja de stock múltiple de sus componentes.',
                        ),
                        value: esCombo,
                        activeThumbColor: Colors.indigo,
                        onChanged: (val) => setModalState(() => esCombo = val),
                      ),
                      const Divider(),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: nombreCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombre del Producto / Combo',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v!.isEmpty ? 'Requerido' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: descCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Descripción / Detalle comercial',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: codBarrasCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Cód. Barras (Escáner)',
                                prefixIcon: Icon(Icons.qr_code_scanner),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: codInternoCtrl,
                              decoration: const InputDecoration(
                                labelText: 'SKU / Cód. Interno',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: precioCostoCtrl,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: esCombo
                                    ? 'Costo Estimado (\$)'
                                    : 'Precio Costo (\$ Compra)',
                                prefixIcon: const Icon(
                                  Icons.monetization_on_outlined,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                              validator: (v) => v!.isEmpty ? 'Requerido' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: precioCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Precio Venta al Público (\$ PVP)',
                                prefixIcon: Icon(Icons.attach_money),
                                border: OutlineInputBorder(),
                              ),
                              validator: (v) => v!.isEmpty ? 'Requerido' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: catSel,
                              decoration: const InputDecoration(
                                labelText: 'Categoría',
                                border: OutlineInputBorder(),
                              ),
                              items: _categorias
                                  .where((c) => c != 'Todas')
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(c),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (val) => catSel = val!,
                            ),
                          ),
                          if (!esCombo) ...[
                            const SizedBox(width: 16),
                            Expanded(
                              child: StreamBuilder<QuerySnapshot>(
                                stream: _firestore
                                    .collection('proveedores')
                                    .snapshots(),
                                builder: (context, snapProv) {
                                  List<DropdownMenuItem<String>> provItems = [];
                                  if (snapProv.hasData) {
                                    for (var doc in snapProv.data!.docs) {
                                      final d =
                                          doc.data() as Map<String, dynamic>;
                                      provItems.add(
                                        DropdownMenuItem(
                                          value: doc.id,
                                          child: Text(d['razonSocial'] ?? ''),
                                        ),
                                      );
                                    }
                                  }
                                  return DropdownButtonFormField<String>(
                                    initialValue: proveedorSeleccionadoId,
                                    decoration: const InputDecoration(
                                      labelText: 'Proveedor',
                                      border: OutlineInputBorder(),
                                    ),
                                    items: provItems,
                                    onChanged: (val) =>
                                        proveedorSeleccionadoId = val,
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 16),

                      if (esCombo) ...[
                        const Text(
                          'Estructura del Combo (Componentes):',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: StreamBuilder<QuerySnapshot>(
                            stream: _firestore
                                .collection('inventario_general')
                                .where('esCombo', isEqualTo: false)
                                .where('tipoInventario', isEqualTo: 'Buffet')
                                .snapshots(),
                            builder: (context, snapSub) {
                              if (!snapSub.hasData) {
                                return const LinearProgressIndicator();
                              }
                              final listaDisponibles = snapSub.data!.docs;

                              return Column(
                                children: [
                                  ListView.builder(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: componentesSeleccionados.length,
                                    itemBuilder: (context, cIdx) {
                                      final itemCombo =
                                          componentesSeleccionados[cIdx];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 4.0,
                                        ),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: DropdownButtonFormField<String>(
                                                initialValue:
                                                    itemCombo.productoId.isEmpty
                                                    ? null
                                                    : itemCombo.productoId,
                                                decoration:
                                                    const InputDecoration(
                                                      border:
                                                          OutlineInputBorder(),
                                                      isDense: true,
                                                    ),
                                                items: listaDisponibles.map((
                                                  d,
                                                ) {
                                                  final raw =
                                                      d.data()
                                                          as Map<
                                                            String,
                                                            dynamic
                                                          >;
                                                  return DropdownMenuItem(
                                                    value: d.id,
                                                    child: Text(
                                                      raw['nombre'] ?? '',
                                                    ),
                                                  );
                                                }).toList(),
                                                onChanged: (v) => setModalState(
                                                  () {
                                                    componentesSeleccionados[cIdx] =
                                                        ComponenteCombo(
                                                          productoId: v!,
                                                          cantidad: itemCombo
                                                              .cantidad,
                                                        );
                                                  },
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            SizedBox(
                                              width: 70,
                                              child: TextFormField(
                                                initialValue: itemCombo.cantidad
                                                    .toString(),
                                                keyboardType:
                                                    TextInputType.number,
                                                decoration:
                                                    const InputDecoration(
                                                      labelText: 'Cant',
                                                      border:
                                                          OutlineInputBorder(),
                                                      isDense: true,
                                                    ),
                                                onChanged: (v) =>
                                                    itemCombo
                                                        .productoId
                                                        .isNotEmpty
                                                    ? componentesSeleccionados[cIdx] =
                                                          ComponenteCombo(
                                                            productoId:
                                                                itemCombo
                                                                    .productoId,
                                                            cantidad:
                                                                int.tryParse(
                                                                  v,
                                                                ) ??
                                                                1,
                                                          )
                                                    : null,
                                              ),
                                            ),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.delete,
                                                color: Colors.red,
                                              ),
                                              onPressed: () => setModalState(
                                                () => componentesSeleccionados
                                                    .removeAt(cIdx),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(Icons.add),
                                    label: const Text(
                                      'Agregar Producto al Combo',
                                    ),
                                    onPressed: () => setModalState(
                                      () => componentesSeleccionados.add(
                                        ComponenteCombo(
                                          productoId: '',
                                          cantidad: 1,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                      ] else ...[
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: stockCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Stock Actual',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: TextFormField(
                                controller: stockMinimoCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Stock Mínimo Alerta',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  if (formKey.currentState!.validate()) {
                    final int stockActualCalc = esCombo
                        ? 0
                        : (int.tryParse(stockCtrl.text) ?? 0);

                    final data = {
                      'nombre': nombreCtrl.text.trim(),
                      'descripcion': descCtrl.text.trim(),
                      'categoria': catSel,
                      'precioVenta': double.tryParse(precioCtrl.text) ?? 0.0,
                      'precio': double.tryParse(precioCtrl.text) ?? 0.0,
                      'precioCosto':
                          double.tryParse(precioCostoCtrl.text) ?? 0.0,
                      'stockActual': stockActualCalc,
                      'stockMinimo': esCombo
                          ? 0
                          : (int.tryParse(stockMinimoCtrl.text) ?? 5),
                      'codigoBarras': codBarrasCtrl.text.trim(),
                      'codigoInterno': codInternoCtrl.text.trim(),
                      'proveedorId': esCombo ? null : proveedorSeleccionadoId,
                      'disponible': esCombo
                          ? disponible
                          : (disponible && stockActualCalc > 0),
                      'esCombo': esCombo,
                      'tipoInventario': 'Buffet',
                      'componentes': esCombo
                          ? componentesSeleccionados
                                .map((c) => c.toMap())
                                .toList()
                          : [],
                      'requiereCocina':
                          catSel == 'Minutas' || catSel == 'Menú Diario',
                    };

                    if (producto == null) {
                      await _firestore
                          .collection('inventario_general')
                          .add(data);
                    } else {
                      await _firestore
                          .collection('inventario_general')
                          .doc(producto.id)
                          .update(data);
                    }
                    if (context.mounted) Navigator.pop(context);
                  }
                },
                child: const Text('Guardar'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => Scaffold(
                appBar: AppBar(
                  backgroundColor: const Color(0xFF1E293B),
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: const Text(
                    'Volver al Menú del Buffet',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  elevation: 0,
                ),
                body: const InventarioGeneralPage(),
              ),
            ),
          );
        },
        backgroundColor: Colors.orange.shade700,
        icon: const Icon(Icons.inventory_2_rounded, color: Colors.white),
        label: const Text(
          'Ir a Central de Inventario',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(40.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestión del Menú - Buffet',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    Text(
                      'Administrá los costos, precios de venta, alertas de stock mínimo y combos articulados del buffet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                  ),
                  onPressed: _mostrarDialogoAjusteMasivo,
                  icon: const Icon(Icons.trending_up_rounded, size: 18),
                  label: const Text(
                    'Ajuste Masivo %',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            TextField(
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o escanear código de barras...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
              ),
              onChanged: (value) =>
                  setState(() => _searchQuery = value.toLowerCase()),
            ),
            const SizedBox(height: 24),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categorias.map((cat) {
                  final seleccionado = _categoriaFiltro == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12.0),
                    child: ChoiceChip(
                      label: Text(
                        cat,
                        style: TextStyle(
                          fontWeight: seleccionado
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      selected: seleccionado,
                      selectedColor: Colors.orange.shade100,
                      onSelected: (bool selected) {
                        if (selected) setState(() => _categoriaFiltro = cat);
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('inventario_general').snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final List<ProductoBuffetModel> productos = [];
                  for (var doc in snapshot.data!.docs) {
                    final p = ProductoBuffetModel.fromFirestore(doc);
                    final rawData = doc.data() as Map<String, dynamic>? ?? {};

                    final bool esDeBuffet =
                        rawData['tipoInventario'] == 'Buffet' ||
                        !rawData.containsKey('tipoInventario');

                    if (esDeBuffet &&
                        (_categoriaFiltro == 'Todas' ||
                            p.categoria == _categoriaFiltro) &&
                        (_searchQuery.isEmpty ||
                            p.nombre.toLowerCase().contains(_searchQuery) ||
                            p.codigoBarras.toLowerCase().contains(
                              _searchQuery,
                            ))) {
                      productos.add(p);
                    }
                  }

                  if (productos.isEmpty) {
                    return const Center(
                      child: Text(
                        'No se encontraron artículos cargados en esta categoría.',
                      ),
                    );
                  }

                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 300,
                          mainAxisSpacing: 20,
                          crossAxisSpacing: 20,
                          childAspectRatio: 1.05,
                        ),
                    itemCount: productos.length,
                    itemBuilder: (context, index) {
                      final prod = productos[index];

                      // 📈 Cálculo de Margen Comercial %
                      final double costo = prod.precioCosto;
                      final double pvp = prod.precio;
                      final double margenPorcentaje = costo > 0
                          ? (((pvp - costo) / costo) * 100)
                          : 0.0;
                      final bool stockCritico =
                          !prod.esCombo && prod.stock <= prod.stockMinimo;

                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: stockCritico
                                ? Colors.red.shade400
                                : Colors.grey.shade200,
                            width: stockCritico ? 2 : 1,
                          ),
                        ),
                        color: Colors.white,
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: prod.esCombo
                                          ? Colors.orange.shade100
                                          : (stockCritico
                                                ? Colors.red.shade100
                                                : Colors.grey.shade100),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      prod.esCombo
                                          ? 'COMBO 🔥'
                                          : (stockCritico
                                                ? 'CRÍTICO ⚠️'
                                                : prod.categoria),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: prod.esCombo
                                            ? Colors.orange.shade900
                                            : (stockCritico
                                                  ? Colors.red.shade900
                                                  : Colors.blueGrey),
                                      ),
                                    ),
                                  ),
                                  Switch(
                                    value: prod.disponible,
                                    activeThumbColor: Colors.green,
                                    onChanged: (val) => _firestore
                                        .collection('inventario_general')
                                        .doc(prod.id)
                                        .update({'disponible': val}),
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Text(
                                prod.nombre,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    prod.esCombo
                                        ? 'Contiene: ${prod.componentes.length} arts.'
                                        : 'Stock: ${prod.stock} un.',
                                    style: TextStyle(
                                      color: stockCritico
                                          ? Colors.red.shade700
                                          : Colors.blueGrey,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (margenPorcentaje > 0)
                                    Text(
                                      'Margen: +${margenPorcentaje.toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        color: Colors.teal,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '\$${prod.precio.toStringAsFixed(0)}',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade700,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.edit_rounded,
                                      color: Colors.blueGrey,
                                    ),
                                    onPressed: () =>
                                        _mostrarFormularioProducto(prod),
                                  ),
                                ],
                              ),
                            ],
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
