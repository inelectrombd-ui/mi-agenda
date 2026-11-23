import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'supabase_service.dart';

class AgendaPage extends StatefulWidget {
  const AgendaPage({super.key});

  @override
  State<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends State<AgendaPage> with SingleTickerProviderStateMixin {
  DateTime _focusedDay = DateTime.now();
  DateTime _selectedDay = DateTime.now();

  final _tituloCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  DateTime? _fechaNotaSeleccionada = DateTime.now();
  TimeOfDay? _horaAlarmaSeleccionada;
  String _prioridadSeleccionada = 'normal';
  int _vistaSeleccionada = 0; // 0: Día elegido, 1: Todas pendientes, 2: Realizadas

  List<Map<String, dynamic>> _todosLosPendientes = [];
  StreamSubscription? _realtimeSub;
  Timer? _relojAlarmas;
  Timer? _repetidorSonido;
  final Set<String> _alarmasEnPantalla = {};
  @override
  void initState() {
    super.initState();
    _escucharPendientesEnTiempoReal();
    _relojAlarmas = Timer.periodic(const Duration(seconds: 3), (_) => _verificarAlarmas());
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _relojAlarmas?.cancel();
    _repetidorSonido?.cancel();
    _tituloCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _escucharPendientesEnTiempoReal() {
    final userId = SupabaseService.client.auth.currentUser!.id;
    _realtimeSub = SupabaseService.client
        .from('pendientes')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('fecha_alarma', ascending: true)
        .listen((datos) {
      if (mounted) {
        setState(() {
          _todosLosPendientes = List<Map<String, dynamic>>.from(datos);
        });
        _verificarAlarmas();
      }
    });
  }
  void _verificarAlarmas() {
    final ahora = DateTime.now();
    int vencidosSinAtender = 0;

    for (final item in _todosLosPendientes) {
      final bool completada = item['completada'] ?? false;
      final bool notificada = item['notificada'] ?? false;
      final bool tieneAlarma = item['tiene_alarma'] ?? false;
      final String? fechaStr = item['fecha_alarma'];

      if (!completada && tieneAlarma && fechaStr != null) {
        final fechaAlarma = DateTime.parse(fechaStr).toLocal();

        if (fechaAlarma.isBefore(ahora) || fechaAlarma.isAtSameMomentAs(ahora)) {
          vencidosSinAtender++;
          final String id = item['id'].toString();

          if (!notificada && !_alarmasEnPantalla.contains(id)) {
            _dispararAlertaCompleta(item);
          }
        }
      }
    }

    if (vencidosSinAtender > 0) {
      SupabaseService.cambiarTituloPestana('🔴 ($vencidosSinAtender) ¡Pendiente vencido!');
    } else {
      SupabaseService.cambiarTituloPestana('Mi Agenda Personal');
    }
  }
  void _dispararAlertaCompleta(Map<String, dynamic> item) {
    final String id = item['id'].toString();
    final String titulo = item['titulo'] ?? 'Pendiente';
    final String desc = item['descripcion'] ?? '';
    final bool urgente = item['prioridad'] == 'urgente';

    _alarmasEnPantalla.add(id);

    SupabaseService.enviarNotificacionPush(
      urgente ? '🚨 URGENTE: $titulo' : '⏰ Recordatorio: $titulo',
      desc.isEmpty ? 'Tienes un pendiente programado para este momento.' : desc,
    );

    SupabaseService.sonarAlarma(urgente: urgente);
    _repetidorSonido?.cancel();
    _repetidorSonido = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_alarmasEnPantalla.isNotEmpty) {
        SupabaseService.sonarAlarma(urgente: urgente);
      } else {
        _repetidorSonido?.cancel();
      }
    });

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ModalAlarmaInteractiva(
        item: item,
        onCompletar: () async {
          _detenerAlertaLocal(id);
          Navigator.of(ctx).pop();
          await _alternarCompletada(id, true);
        },
        onPosponer: (minutos) async {
          _detenerAlertaLocal(id);
          Navigator.of(ctx).pop();
          final nuevaFecha = DateTime.now().add(Duration(minutes: minutos)).toUtc();
          await SupabaseService.client
              .from('pendientes')
              .update({
                'fecha_alarma': nuevaFecha.toIso8601String(),
                'tiene_alarma': true,
                'notificada': false,
              })
              .eq('id', id);
        },
        onSilenciar: () async {
          _detenerAlertaLocal(id);
          Navigator.of(ctx).pop();
          await SupabaseService.client
              .from('pendientes')
              .update({'notificada': true})
              .eq('id', id);
        },
      ),
    );
  }

  void _detenerAlertaLocal(String id) {
    _alarmasEnPantalla.remove(id);
    if (_alarmasEnPantalla.isEmpty) {
      _repetidorSonido?.cancel();
    }
  }
  Future<void> _alternarCompletada(String id, bool nuevoEstado) async {
    // 1. Respuesta visual inmediata en pantalla (0 ms)
    setState(() {
      final index = _todosLosPendientes.indexWhere((e) => e['id'].toString() == id);
      if (index != -1) {
        _todosLosPendientes[index] = {
          ..._todosLosPendientes[index],
          'completada': nuevoEstado,
          if (nuevoEstado) 'notificada': true,
        };
      }
    });

    // 2. Sincronizar con Supabase en segundo plano
    await SupabaseService.client
        .from('pendientes')
        .update({
          'completada': nuevoEstado,
          if (nuevoEstado) 'notificada': true,
        })
        .eq('id', id);
  }

  Future<void> _eliminarPendiente(String id) async {
    // 1. Quitar de la lista en pantalla al instante
    setState(() {
      _todosLosPendientes.removeWhere((e) => e['id'].toString() == id);
    });

    if (mounted) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nota eliminada'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    // 2. Eliminar de Supabase
    await SupabaseService.client.from('pendientes').delete().eq('id', id);
  }

  Future<void> _guardarNotaRapida() async {
    final titulo = _tituloCtrl.text.trim();
    if (titulo.isEmpty) return;

    SupabaseService.sonarAlarma(urgente: false);

    DateTime? fechaFinal;
    final bool conAlarma = _horaAlarmaSeleccionada != null;

    if (_fechaNotaSeleccionada != null || conAlarma) {
      final base = _fechaNotaSeleccionada ?? _selectedDay;
      final hora = _horaAlarmaSeleccionada ?? const TimeOfDay(hour: 12, minute: 0);
      fechaFinal = DateTime(base.year, base.month, base.day, hora.hour, hora.minute);
    }

    final data = {
      'titulo': titulo,
      'descripcion': _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      'fecha_alarma': fechaFinal?.toUtc().toIso8601String(),
      'tiene_alarma': conAlarma,
      'prioridad': _prioridadSeleccionada,
      'completada': false,
      'notificada': false,
    };

    _tituloCtrl.clear();
    _descCtrl.clear();
    setState(() {
      _horaAlarmaSeleccionada = null;
      _prioridadSeleccionada = 'normal';
    });

    await SupabaseService.client.from('pendientes').insert(data);
  }

  Future<void> _elegirSoloFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaNotaSeleccionada ?? _selectedDay,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (fecha != null) {
      setState(() {
        _fechaNotaSeleccionada = fecha;
        _selectedDay = fecha;
        _focusedDay = fecha;
      });
    }
  }

  Future<void> _elegirAlarmaOpcional() async {
    final hora = await showTimePicker(
      context: context,
      initialTime: _horaAlarmaSeleccionada ??
          TimeOfDay.fromDateTime(DateTime.now().add(const Duration(minutes: 5))),
    );
    if (hora != null) {
      setState(() {
        _fechaNotaSeleccionada ??= _selectedDay;
        _horaAlarmaSeleccionada = hora;
      });
    }
  }

  List<Map<String, dynamic>> _obtenerEventosDelDia(DateTime day) {
    return _todosLosPendientes.where((item) {
      final fechaStr = item['fecha_alarma'];
      if (fechaStr == null) return false;
      final fechaLocal = DateTime.parse(fechaStr).toLocal();
      return isSameDay(fechaLocal, day);
    }).toList();
  }

  Color _colorPrioridad(String? prioridad) {
    switch (prioridad) {
      case 'urgente':
        return const Color(0xFFDC2626);
      case 'baja':
        return const Color(0xFF0D9488);
      default:
        return const Color(0xFF0284C7);
    }
  }
  @override
  Widget build(BuildContext context) {
    final esPantallaAncha = MediaQuery.of(context).size.width > 850;
    final notasSinFecha = _todosLosPendientes
        .where((e) => e['fecha_alarma'] == null && !(e['completada'] ?? false))
        .toList();
    final eventosDelDia = _obtenerEventosDelDia(_selectedDay);

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 1,
        shadowColor: Colors.black12,
        title: const Row(
          children: [
            Icon(Icons.calendar_month_rounded, color: Color(0xFF0284C7)),
            SizedBox(width: 10),
            Text('Mi Agenda Interactiva', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Probar sonido y notificación',
            icon: const Icon(Icons.notifications_active_outlined, color: Color(0xFFD97706)),
            onPressed: () async {
              await SupabaseService.pedirPermisoPush();
              SupabaseService.sonarAlarma(urgente: false);
              SupabaseService.enviarNotificacionPush(
                'Prueba de Agenda',
                '¡El sonido y las notificaciones están activos!',
              );
            },
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout_rounded, color: Color(0xFF475569)),
            onPressed: () => SupabaseService.client.auth.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: esPantallaAncha
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: _construirPanelCalendario()),
                  const SizedBox(width: 20),
                  Expanded(flex: 6, child: _construirPanelNotasYPendientes(notasSinFecha, eventosDelDia)),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _construirPanelCalendario(),
                    const SizedBox(height: 16),
                    _construirPanelNotasYPendientes(notasSinFecha, eventosDelDia, scrollable: false),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _construirPanelCalendario() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TableCalendar(
        firstDay: DateTime.utc(2024, 1, 1),
        lastDay: DateTime.utc(2030, 12, 31),
        focusedDay: _focusedDay,
        selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
        eventLoader: _obtenerEventosDelDia,
        startingDayOfWeek: StartingDayOfWeek.monday,
        calendarStyle: CalendarStyle(
          defaultTextStyle: const TextStyle(color: Color(0xFF1E293B)),
          weekendTextStyle: const TextStyle(color: Color(0xFF64748B)),
          outsideTextStyle: const TextStyle(color: Color(0xFFCBD5E1)),
          todayDecoration: BoxDecoration(
            color: const Color(0xFF0284C7).withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          todayTextStyle: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold),
          selectedDecoration: const BoxDecoration(
            color: Color(0xFF0284C7),
            shape: BoxShape.circle,
          ),
          markerDecoration: const BoxDecoration(
            color: Color(0xFFD97706),
            shape: BoxShape.circle,
          ),
        ),
        headerStyle: const HeaderStyle(
          formatButtonVisible: false,
          titleCentered: true,
          titleTextStyle: TextStyle(color: Color(0xFF0F172A), fontSize: 18, fontWeight: FontWeight.bold),
          leftChevronIcon: Icon(Icons.chevron_left, color: Color(0xFF0F172A)),
          rightChevronIcon: Icon(Icons.chevron_right, color: Color(0xFF0F172A)),
        ),
        onDaySelected: (selectedDay, focusedDay) {
          setState(() {
            _selectedDay = selectedDay;
            _focusedDay = focusedDay;
            _fechaNotaSeleccionada = selectedDay;
          });
        },
      ),
    );
  }
  Widget _construirPanelNotasYPendientes(
    List<Map<String, dynamic>> notasSinFecha,
    List<Map<String, dynamic>> eventosDelDia, {
    bool scrollable = true,
  }) {
    final todasPendientes = _todosLosPendientes
        .where((e) => !(e['completada'] ?? false))
        .toList();
    final todasRealizadas = _todosLosPendientes
        .where((e) => (e['completada'] ?? false))
        .toList()
        .reversed
        .toList();

    final contenido = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFBAE6FD), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⚡ Nota Rápida / Nuevo Pendiente',
                style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tituloCtrl,
                onSubmitted: (_) => _guardarNotaRapida(),
                style: const TextStyle(color: Color(0xFF0F172A)),
                decoration: InputDecoration(
                  hintText: '¿Qué tienes pendiente?',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descCtrl,
                style: const TextStyle(color: Color(0xFF334155), fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Detalles opcionales...',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.event, size: 18, color: Color(0xFF0284C7)),
                    backgroundColor: const Color(0xFFF1F5F9),
                    side: const BorderSide(color: Color(0xFFCBD5E1)),
                    label: Text(
                      _fechaNotaSeleccionada == null
                          ? 'Sin fecha'
                          : DateFormat('dd/MM/yyyy').format(_fechaNotaSeleccionada!),
                      style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                    ),
                    onPressed: _elegirSoloFecha,
                  ),
                  if (_fechaNotaSeleccionada != null)
                    InkWell(
                      onTap: () => setState(() {
                        _fechaNotaSeleccionada = null;
                        _horaAlarmaSeleccionada = null;
                      }),
                      child: const Padding(
                        padding: EdgeInsets.all(6.0),
                        child: Icon(Icons.cancel, size: 20, color: Color(0xFF94A3B8)),
                      ),
                    ),

                  ActionChip(
                    avatar: Icon(
                      _horaAlarmaSeleccionada == null ? Icons.alarm_off : Icons.alarm_on,
                      size: 18,
                      color: _horaAlarmaSeleccionada == null ? const Color(0xFF64748B) : const Color(0xFFD97706),
                    ),
                    backgroundColor: _horaAlarmaSeleccionada == null
                        ? const Color(0xFFF1F5F9)
                        : const Color(0xFFFEF3C7),
                    side: BorderSide(
                      color: _horaAlarmaSeleccionada == null ? const Color(0xFFCBD5E1) : const Color(0xFFF59E0B),
                    ),
                    label: Text(
                      _horaAlarmaSeleccionada == null
                          ? 'Alarma (Opcional)'
                          : _horaAlarmaSeleccionada!.format(context),
                      style: TextStyle(
                        color: _horaAlarmaSeleccionada == null ? const Color(0xFF334155) : const Color(0xFFB45309),
                        fontWeight: _horaAlarmaSeleccionada == null ? FontWeight.normal : FontWeight.bold,
                      ),
                    ),
                    onPressed: _elegirAlarmaOpcional,
                  ),
                  if (_horaAlarmaSeleccionada != null)
                    InkWell(
                      onTap: () => setState(() => _horaAlarmaSeleccionada = null),
                      child: const Padding(
                        padding: EdgeInsets.all(6.0),
                        child: Icon(Icons.cancel, size: 20, color: Color(0xFF94A3B8)),
                      ),
                    ),

                  DropdownButton<String>(
                    value: _prioridadSeleccionada,
                    dropdownColor: Colors.white,
                    style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w500),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'baja', child: Text('🟢 Baja')),
                      DropdownMenuItem(value: 'normal', child: Text('🔵 Normal')),
                      DropdownMenuItem(value: 'urgente', child: Text('🔴 Urgente')),
                    ],
                    onChanged: (val) => setState(() => _prioridadSeleccionada = val ?? 'normal'),
                  ),
                  ElevatedButton.icon(
                    onPressed: _guardarNotaRapida,
                    icon: const Icon(Icons.add_task),
                    label: const Text('Guardar'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _botonPestana(0, '📅 Día Elegido (${eventosDelDia.length})'),
              const SizedBox(width: 8),
              _botonPestana(1, '⏳ Todas Pendientes (${todasPendientes.length})'),
              const SizedBox(width: 8),
              _botonPestana(2, '✅ Realizadas (${todasRealizadas.length})'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_vistaSeleccionada == 0) ...[
          Text(
            '📅 Notas y Pendientes del ${DateFormat('dd/MM/yyyy').format(_selectedDay)}',
            style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (eventosDelDia.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('No hay notas programadas para este día.', style: TextStyle(color: Color(0xFF64748B))),
            )
          else
            ...eventosDelDia.map((e) => _construirTarjetaPendiente(e)),
          const SizedBox(height: 20),
          Text(
            '📌 Notas Rápidas sin fecha (${notasSinFecha.length})',
            style: const TextStyle(color: Color(0xFFD97706), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (notasSinFecha.isEmpty)
            const Text('Tu bandeja de notas sin fecha está limpia.', style: TextStyle(color: Color(0xFF64748B)))
          else
            ...notasSinFecha.map((e) => _construirTarjetaPendiente(e)),
        ] else if (_vistaSeleccionada == 1) ...[
          const Text(
            '⏳ Historial Global de Pendientes Activas',
            style: TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (todasPendientes.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('¡Excelente! No tienes ninguna tarea pendiente.', style: TextStyle(color: Color(0xFF64748B))),
            )
          else
            ...todasPendientes.map((e) => _construirTarjetaPendiente(e, mostrarFechaCompleta: true)),
        ] else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '✅ Historial de Notas Realizadas',
                style: TextStyle(color: Color(0xFF16A34A), fontSize: 16, fontWeight: FontWeight.bold),
              ),
              if (todasRealizadas.isNotEmpty)
                TextButton.icon(
                  onPressed: () async {
                    final userId = SupabaseService.client.auth.currentUser!.id;
                    setState(() {
                      _todosLosPendientes.removeWhere((e) => (e['completada'] ?? false));
                    });
                    await SupabaseService.client
                        .from('pendientes')
                        .delete()
                        .eq('user_id', userId)
                        .eq('completada', true);
                  },
                  icon: const Icon(Icons.delete_sweep, size: 18, color: Color(0xFFDC2626)),
                  label: const Text('Vaciar historial', style: TextStyle(color: Color(0xFFDC2626), fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (todasRealizadas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Aún no has marcado notas como realizadas.', style: TextStyle(color: Color(0xFF64748B))),
            )
          else
            ...todasRealizadas.map((e) => _construirTarjetaPendiente(e, mostrarFechaCompleta: true)),
        ],
      ],
    );

    return scrollable ? SingleChildScrollView(child: contenido) : contenido;
  }
  Widget _botonPestana(int indice, String texto) {
    final activa = _vistaSeleccionada == indice;
    return ChoiceChip(
      label: Text(
        texto,
        style: TextStyle(
          color: activa ? Colors.white : const Color(0xFF334155),
          fontWeight: activa ? FontWeight.bold : FontWeight.w500,
        ),
      ),
      selected: activa,
      selectedColor: const Color(0xFF0284C7),
      backgroundColor: Colors.white,
      side: BorderSide(color: activa ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1)),
      onSelected: (_) => setState(() => _vistaSeleccionada = indice),
    );
  }

  Widget _construirTarjetaPendiente(Map<String, dynamic> item, {bool mostrarFechaCompleta = false}) {
    final String id = item['id'].toString();
    final bool completada = item['completada'] ?? false;
    final bool tieneAlarma = item['tiene_alarma'] ?? false;
    final String? fechaStr = item['fecha_alarma'];
    final fechaLocal = fechaStr != null ? DateTime.parse(fechaStr).toLocal() : null;
    final colorBorde = completada ? const Color(0xFF16A34A) : _colorPrioridad(item['prioridad']);

    String textoSubtituloFecha;
    IconData iconoFecha;
    if (fechaLocal == null) {
      textoSubtituloFecha = 'Nota rápida sin fecha';
      iconoFecha = Icons.push_pin_outlined;
    } else if (tieneAlarma) {
      textoSubtituloFecha = DateFormat(mostrarFechaCompleta ? 'dd/MM/yyyy HH:mm' : 'HH:mm').format(fechaLocal);
      iconoFecha = Icons.alarm_on;
    } else {
      textoSubtituloFecha = mostrarFechaCompleta
          ? '${DateFormat('dd/MM/yyyy').format(fechaLocal)} (Sin alarma)'
          : 'Agendado hoy (Sin alarma)';
      iconoFecha = Icons.event_note;
    }

    return Container(
      key: ValueKey(id),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Franja lateral de color de prioridad
          Container(
            width: 5,
            height: 48,
            decoration: BoxDecoration(
              color: colorBorde,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 6),

          // Botón Check táctil grande e instantáneo
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _alternarCompletada(id, !completada),
              child: Padding(
                padding: const EdgeInsets.all(10.0),
                child: Icon(
                  completada ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: completada ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // Contenido de texto (Título, detalles y fecha/alarma)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['titulo'] ?? '',
                  style: TextStyle(
                    color: completada ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                    decoration: completada ? TextDecoration.lineThrough : null,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                if (item['descripcion'] != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    item['descripcion'],
                    style: const TextStyle(color: Color(0xFF475569), fontSize: 12),
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      iconoFecha,
                      size: 14,
                      color: tieneAlarma ? const Color(0xFFD97706) : colorBorde,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      textoSubtituloFecha,
                      style: TextStyle(
                        color: tieneAlarma ? const Color(0xFFB45309) : colorBorde,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Botón Eliminar táctil grande e instantáneo
          Material(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _eliminarPendiente(id),
              child: const Padding(
                padding: EdgeInsets.all(10.0),
                child: Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 22),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _ModalAlarmaInteractiva extends StatefulWidget {
  final Map<String, dynamic> item;
  final VoidCallback onCompletar;
  final Function(int) onPosponer;
  final VoidCallback onSilenciar;

  const _ModalAlarmaInteractiva({
    required this.item,
    required this.onCompletar,
    required this.onPosponer,
    required this.onSilenciar,
  });

  @override
  State<_ModalAlarmaInteractiva> createState() => _ModalAlarmaInteractivaState();
}

class _ModalAlarmaInteractivaState extends State<_ModalAlarmaInteractiva> with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final urgente = widget.item['prioridad'] == 'urgente';
    final colorBase = urgente ? const Color(0xFFDC2626) : const Color(0xFF0284C7);

    return AnimatedBuilder(
      animation: _animCtrl,
      builder: (context, child) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: colorBase.withValues(alpha: 0.4 + (_animCtrl.value * 0.6)),
              width: 2 + (_animCtrl.value * 3),
            ),
          ),
          title: Row(
            children: [
              Icon(Icons.notifications_active, color: colorBase, size: 32),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  urgente ? '¡ALERTA URGENTE!' : '¡Recordatorio de Agenda!',
                  style: TextStyle(color: colorBase, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.item['titulo'] ?? '',
                style: const TextStyle(color: Color(0xFF0F172A), fontSize: 20, fontWeight: FontWeight.bold),
              ),
              if (widget.item['descripcion'] != null) ...[
                const SizedBox(height: 8),
                Text(widget.item['descripcion'], style: const TextStyle(color: Color(0xFF475569), fontSize: 15)),
              ],
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: widget.onSilenciar,
              child: const Text('Silenciar', style: TextStyle(color: Color(0xFF64748B))),
            ),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => widget.onPosponer(5),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD97706)),
                  child: const Text('+5 min'),
                ),
                OutlinedButton(
                  onPressed: () => widget.onPosponer(15),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFD97706)),
                  child: const Text('+15 min'),
                ),
                ElevatedButton.icon(
                  onPressed: widget.onCompletar,
                  icon: const Icon(Icons.check_circle),
                  label: const Text('Completar'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
