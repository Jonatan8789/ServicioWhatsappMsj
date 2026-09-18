import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'csv_utils.dart';
import 'csv_download.dart';

/// Definición de una columna del explorador: cómo mostrarla (texto) y,
/// opcionalmente, un valor comparable para poder ordenar por ella (si no se
/// da, se ordena alfabéticamente por el texto mostrado).
class ColumnaExplorador<T> {
  final String etiqueta;
  final String Function(T item) texto;
  final Comparable Function(T item)? orden;
  final bool visibleInicialmente;

  const ColumnaExplorador({
    required this.etiqueta,
    required this.texto,
    this.orden,
    this.visibleInicialmente = true,
  });
}

/// Tabla de datos genérica y reutilizable: búsqueda libre, filtro opcional
/// por rango de fechas, columnas ordenables y visibilidad de columnas
/// configurable, y exportación a CSV de exactamente lo que se está viendo
/// (filtrado + columnas visibles). Pensada para no tener que reescribir la
/// misma tabla-con-filtros a mano en cada pantalla de "explorador".
class DataExplorer<T> extends StatefulWidget {
  final List<T> items;
  final List<ColumnaExplorador<T>> columnas;
  final String nombreArchivoCsv;
  final DateTime Function(T item)? fechaDe;
  final String Function(T item)? textoBusquedaExtra;
  final Widget Function(BuildContext context, T item)? accionesFila;

  const DataExplorer({
    super.key,
    required this.items,
    required this.columnas,
    required this.nombreArchivoCsv,
    this.fechaDe,
    this.textoBusquedaExtra,
    this.accionesFila,
  });

  @override
  State<DataExplorer<T>> createState() => _DataExplorerState<T>();
}

class _DataExplorerState<T> extends State<DataExplorer<T>> {
  final TextEditingController _busquedaController = TextEditingController();
  String _busqueda = '';
  DateTimeRange? _rangoFechas;
  int? _columnaOrden;
  bool _ordenAscendente = true;
  late Set<String> _columnasVisibles;

  @override
  void initState() {
    super.initState();
    _columnasVisibles = widget.columnas
        .where((c) => c.visibleInicialmente)
        .map((c) => c.etiqueta)
        .toSet();
  }

  @override
  void dispose() {
    _busquedaController.dispose();
    super.dispose();
  }

  List<T> get _itemsFiltrados {
    var lista = widget.items;

    if (_rangoFechas != null && widget.fechaDe != null) {
      final desde = DateTime(
        _rangoFechas!.start.year,
        _rangoFechas!.start.month,
        _rangoFechas!.start.day,
      );
      final hasta = DateTime(
        _rangoFechas!.end.year,
        _rangoFechas!.end.month,
        _rangoFechas!.end.day,
        23,
        59,
        59,
      );
      lista = lista.where((item) {
        final f = widget.fechaDe!(item);
        return !f.isBefore(desde) && !f.isAfter(hasta);
      }).toList();
    }

    if (_busqueda.isNotEmpty) {
      final q = _busqueda.toLowerCase();
      lista = lista.where((item) {
        final enColumnas = widget.columnas.any(
          (c) => c.texto(item).toLowerCase().contains(q),
        );
        final enExtra =
            widget.textoBusquedaExtra?.call(item).toLowerCase().contains(q) ??
            false;
        return enColumnas || enExtra;
      }).toList();
    }

    if (_columnaOrden != null) {
      final columna = widget.columnas[_columnaOrden!];
      lista = List.of(lista)
        ..sort((a, b) {
          final va = columna.orden?.call(a) ?? columna.texto(a);
          final vb = columna.orden?.call(b) ?? columna.texto(b);
          final cmp = Comparable.compare(va, vb);
          return _ordenAscendente ? cmp : -cmp;
        });
    }

    return lista;
  }

  void _exportarCsv(List<T> items, List<ColumnaExplorador<T>> columnasVisibles) {
    final csv = generarCsv(
      columnasVisibles.map((c) => c.etiqueta).toList(),
      items.map((item) => columnasVisibles.map((c) => c.texto(item)).toList()).toList(),
    );
    final marcaTiempo = DateFormat('yyyy-MM-dd_HHmm').format(DateTime.now());
    try {
      descargarCsv('${widget.nombreArchivoCsv}_$marcaTiempo.csv', csv);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final columnasVisibles = widget.columnas
        .where((c) => _columnasVisibles.contains(c.etiqueta))
        .toList();
    final itemsFiltrados = _itemsFiltrados;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBarraFiltros(columnasVisibles, itemsFiltrados),
        const SizedBox(height: 8),
        Text(
          '${itemsFiltrados.length} de ${widget.items.length} resultados',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: itemsFiltrados.isEmpty
              ? const Center(child: Text('Sin resultados para este filtro.'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      sortColumnIndex: _columnaOrden,
                      sortAscending: _ordenAscendente,
                      columns: [
                        for (int i = 0; i < columnasVisibles.length; i++)
                          DataColumn(
                            label: Text(
                              columnasVisibles[i].etiqueta,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            onSort: (colIndex, asc) {
                              setState(() {
                                _columnaOrden = widget.columnas.indexOf(
                                  columnasVisibles[colIndex],
                                );
                                _ordenAscendente = asc;
                              });
                            },
                          ),
                        if (widget.accionesFila != null)
                          const DataColumn(label: Text('')),
                      ],
                      rows: [
                        for (final item in itemsFiltrados)
                          DataRow(
                            cells: [
                              for (final c in columnasVisibles)
                                DataCell(Text(c.texto(item))),
                              if (widget.accionesFila != null)
                                DataCell(widget.accionesFila!(context, item)),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildBarraFiltros(
    List<ColumnaExplorador<T>> columnasVisibles,
    List<T> itemsFiltrados,
  ) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 260,
          child: TextField(
            controller: _busquedaController,
            decoration: const InputDecoration(
              hintText: 'Buscar...',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _busqueda = v.trim()),
          ),
        ),
        if (widget.fechaDe != null)
          OutlinedButton.icon(
            onPressed: () async {
              final rango = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: _rangoFechas,
              );
              if (rango != null) setState(() => _rangoFechas = rango);
            },
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              _rangoFechas == null
                  ? 'Rango de fechas'
                  : '${DateFormat('dd/MM/yy').format(_rangoFechas!.start)} - ${DateFormat('dd/MM/yy').format(_rangoFechas!.end)}',
            ),
          ),
        if (_rangoFechas != null)
          IconButton(
            tooltip: 'Quitar filtro de fecha',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() => _rangoFechas = null),
          ),
        PopupMenuButton<String>(
          tooltip: 'Columnas visibles',
          icon: const Icon(Icons.view_column_outlined),
          itemBuilder: (context) => widget.columnas
              .map(
                (c) => CheckedPopupMenuItem<String>(
                  value: c.etiqueta,
                  checked: _columnasVisibles.contains(c.etiqueta),
                  child: Text(c.etiqueta),
                ),
              )
              .toList(),
          onSelected: (etiqueta) {
            setState(() {
              if (_columnasVisibles.contains(etiqueta)) {
                if (_columnasVisibles.length > 1) {
                  _columnasVisibles.remove(etiqueta);
                }
              } else {
                _columnasVisibles.add(etiqueta);
              }
            });
          },
        ),
        OutlinedButton.icon(
          onPressed: () => _exportarCsv(itemsFiltrados, columnasVisibles),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Exportar CSV'),
        ),
      ],
    );
  }
}
