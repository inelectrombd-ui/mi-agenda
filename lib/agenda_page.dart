import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'supabase_service.dart';

@JS('window.open')
external void _abrirEnlaceWeb(JSString url, JSString target);

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
  bool _generandoPDF = false;

  List<Map<String, dynamic>> _todosLosPendientes = [];
  StreamSubscription? _realtimeSub;
  Timer? _relojAlarmas;
  Timer? _repetidorSonido;
  final Set<String> _alarmasEnPantalla = {};

  List<Map<String, dynamic>> _usuariosRegistrados = [];
  List<Map<String, dynamic>> _anuncios = [];
  StreamSubscription? _anunciosSub;
  final PageController _carruselCtrl = PageController();
  Timer? _timerCarrusel;
  int _indiceAnuncioActual = 0;

  bool get _esAdmin => SupabaseService.client.auth.currentUser?.email == 'inelectrombd@gmail.com';
  @override
  void initState() {
    super.initState();
    _escucharPendientesEnTiempoReal();
    _escucharAnunciosEnTiempoReal();
    if (_esAdmin) {
      _cargarUsuariosAdmin();
    }
    _relojAlarmas = Timer.periodic(const Duration(seconds: 3), (_) => _verificarAlarmas());
    _iniciarRotacionPublicidad();
  }

  void _iniciarRotacionPublicidad() {
    _timerCarrusel?.cancel();
    _timerCarrusel = Timer.periodic(const Duration(seconds: 5), (_) {
      final activos = _anunciosActivos;
      if (activos.length > 1 && _carruselCtrl.hasClients) {
        final siguiente = (_indiceAnuncioActual + 1) % activos.length;
        _carruselCtrl.animateToPage(
          siguiente,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  List<Map<String, dynamic>> get _anunciosActivos =>
      _anuncios.where((a) => (a['activo'] ?? false) == true).toList();

  @override
  void dispose() {
    _realtimeSub?.cancel();
    _anunciosSub?.cancel();
    _relojAlarmas?.cancel();
    _repetidorSonido?.cancel();
    _timerCarrusel?.cancel();
    _carruselCtrl.dispose();
    _tituloCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }
  void _escucharAnunciosEnTiempoReal() {
    _anunciosSub = SupabaseService.client
        .from('anuncios')
        .stream(primaryKey: ['id'])
        .order('orden', ascending: true)
        .listen((datos) {
      if (mounted) {
        final listaOrdenada = List<Map<String, dynamic>>.from(datos)
          ..sort((a, b) => ((a['orden'] ?? 0) as int).compareTo((b['orden'] ?? 0) as int));
        setState(() {
          _anuncios = listaOrdenada;
          if (_indiceAnuncioActual >= _anunciosActivos.length) {
            _indiceAnuncioActual = 0;
          }
        });
      }
    });
  }

  Future<void> _cargarUsuariosAdmin() async {
    try {
      final datos = await SupabaseService.client
          .from('perfiles_usuarios')
          .select()
          .order('fecha_registro', ascending: false);
      if (mounted) {
        setState(() {
          _usuariosRegistrados = List<Map<String, dynamic>>.from(datos);
        });
      }
    } catch (_) {}
  }

  void _mostrarPanelAdmin() {
    _cargarUsuariosAdmin();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.admin_panel_settings_rounded, color: Color(0xFF0284C7), size: 28),
            const SizedBox(width: 10),
            Text(
              'Usuarios Activos (${_usuariosRegistrados.length})',
              style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: _usuariosRegistrados.isEmpty
              ? const Text('No se encontraron registros.', style: TextStyle(color: Color(0xFF64748B)))
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: _usuariosRegistrados.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final u = _usuariosRegistrados[i];
                    final fecha = DateTime.parse(u['fecha_registro']).toLocal();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFE0F2FE),
                        child: Icon(Icons.person, color: Color(0xFF0284C7), size: 20),
                      ),
                      title: Text(
                        u['email'] ?? '',
                        style: const TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                      subtitle: Text(
                        'Registro: ${DateFormat('dd/MM/yyyy HH:mm').format(fecha)}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
  String? _formatearDestinoAnuncio(String entrada) {
    final limpio = entrada.trim();
    if (limpio.isEmpty) return null;
    if (limpio.startsWith('http://') || limpio.startsWith('https://')) {
      return limpio;
    }
    return 'https://$limpio';
  }

  Future<void> _borrarImagenDeStorage(String? urlImagen) async {
    if (urlImagen == null || urlImagen.isEmpty) return;
    try {
      const marcador = '/banners/';
      final idx = urlImagen.indexOf(marcador);
      if (idx != -1) {
        final nombreArchivo = Uri.decodeComponent(urlImagen.substring(idx + marcador.length).split('?').first);
        if (nombreArchivo.isNotEmpty) {
          await SupabaseService.client.storage.from('banners').remove([nombreArchivo]);
        }
      }
    } catch (_) {}
  }

  Future<void> _intercambiarOrdenAnuncios(int indiceActual, int indiceDestino) async {
    if (indiceDestino < 0 || indiceDestino >= _anuncios.length) return;
    final actual = _anuncios[indiceActual];
    final destino = _anuncios[indiceDestino];

    final ordenActual = actual['orden'] ?? indiceActual;
    final ordenDestino = destino['orden'] ?? indiceDestino;

    final nuevoOrdenActual = ordenActual == ordenDestino ? indiceDestino : ordenDestino;
    final nuevoOrdenDestino = ordenActual == ordenDestino ? indiceActual : ordenActual;

    setState(() {
      _anuncios[indiceActual] = {...actual, 'orden': nuevoOrdenActual};
      _anuncios[indiceDestino] = {...destino, 'orden': nuevoOrdenDestino};
      _anuncios.sort((a, b) => ((a['orden'] ?? 0) as int).compareTo((b['orden'] ?? 0) as int));
    });

    await SupabaseService.client.from('anuncios').update({'orden': nuevoOrdenActual}).eq('id', actual['id']);
    await SupabaseService.client.from('anuncios').update({'orden': nuevoOrdenDestino}).eq('id', destino['id']);
  }
  void _mostrarGestorPublicidad() {
    final titAnuncioCtrl = TextEditingController();
    final subAnuncioCtrl = TextEditingController();
    final contactoCtrl = TextEditingController();
    Uint8List? bytesImagenSeleccionada;
    String? nombreArchivoSeleccionado;
    String? idEditando;
    String? urlImagenExistente;
    bool subiendo = false;

    void limpiarFormulario() {
      titAnuncioCtrl.clear();
      subAnuncioCtrl.clear();
      contactoCtrl.clear();
      bytesImagenSeleccionada = null;
      nombreArchivoSeleccionado = null;
      idEditando = null;
      urlImagenExistente = null;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateModal) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.campaign_rounded, color: Color(0xFFD97706), size: 28),
                SizedBox(width: 10),
                Text(
                  'Gestor de Publicidad',
                  style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            content: SizedBox(
              width: 450,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          idEditando == null ? 'Agregar nuevo banner o anuncio:' : '✏️ Editando anuncio:',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: idEditando == null ? const Color(0xFF0284C7) : const Color(0xFFD97706),
                            fontSize: 13,
                          ),
                        ),
                        if (idEditando != null)
                          TextButton(
                            onPressed: () => setStateModal(limpiarFormulario),
                            child: const Text('Cancelar edición', style: TextStyle(fontSize: 12)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titAnuncioCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Título del anuncio *',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: subAnuncioCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Texto corto / Promoción (Opcional)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: contactoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'URL de destino (Opcional)',
                        hintText: 'https://walmart.com.mx',
                        prefixIcon: Icon(Icons.link_rounded, color: Color(0xFF0284C7)),
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.photo_library_outlined, color: Color(0xFF0284C7)),
                      label: Text(
                        nombreArchivoSeleccionado != null
                            ? 'Nueva imagen: $nombreArchivoSeleccionado'
                            : (urlImagenExistente != null
                                ? 'Cambiar imagen actual del banner'
                                : 'Elegir imagen del teléfono (Opcional)'),
                        overflow: TextOverflow.ellipsis,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 42),
                        side: const BorderSide(color: Color(0xFF0284C7)),
                      ),
                      onPressed: subiendo
                          ? null
                          : () async {
                              final picker = ImagePicker();
                              final archivo = await picker.pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 1200,
                                imageQuality: 85,
                              );
                              if (archivo != null) {
                                final bytes = await archivo.readAsBytes();
                                setStateModal(() {
                                  bytesImagenSeleccionada = bytes;
                                  nombreArchivoSeleccionado = archivo.name;
                                });
                              }
                            },
                    ),
                    if (bytesImagenSeleccionada != null || urlImagenExistente != null) ...[
                      const SizedBox(height: 8),
                      Stack(
                        alignment: Alignment.topRight,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: bytesImagenSeleccionada != null
                                ? Image.memory(
                                    bytesImagenSeleccionada!,
                                    height: 90,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  )
                                : Image.network(
                                    urlImagenExistente!,
                                    height: 90,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                  ),
                          ),
                          IconButton(
                            tooltip: 'Quitar imagen',
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: () => setStateModal(() {
                              bytesImagenSeleccionada = null;
                              nombreArchivoSeleccionado = null;
                              urlImagenExistente = null;
                            }),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: subiendo
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(idEditando == null ? Icons.add_circle_outline : Icons.save_outlined),
                        label: Text(
                          subiendo
                              ? 'Guardando...'
                              : (idEditando == null ? 'Publicar Anuncio' : 'Guardar Cambios'),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: idEditando == null ? const Color(0xFF0284C7) : const Color(0xFFD97706),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: subiendo
                            ? null
                            : () async {
                                final titulo = titAnuncioCtrl.text.trim();
                                if (titulo.isEmpty) return;

                                setStateModal(() => subiendo = true);
                                String? urlFinalImagen = urlImagenExistente;

                                try {
                                  if (bytesImagenSeleccionada != null) {
                                    if (idEditando != null) {
                                      final anterior = _anuncios.firstWhere(
                                        (a) => a['id'].toString() == idEditando,
                                        orElse: () => {},
                                      );
                                      await _borrarImagenDeStorage(anterior['imagen_url']);
                                    }

                                    final ext = (nombreArchivoSeleccionado ?? 'jpg').split('.').last;
                                    final rutaArchivo = 'banner_${DateTime.now().millisecondsSinceEpoch}.$ext';

                                    await SupabaseService.client.storage.from('banners').uploadBinary(
                                          rutaArchivo,
                                          bytesImagenSeleccionada!,
                                          fileOptions: const FileOptions(upsert: true),
                                        );

                                    urlFinalImagen =
                                        SupabaseService.client.storage.from('banners').getPublicUrl(rutaArchivo);
                                  } else if (idEditando != null && urlImagenExistente == null) {
                                    final anterior = _anuncios.firstWhere(
                                      (a) => a['id'].toString() == idEditando,
                                      orElse: () => {},
                                    );
                                    await _borrarImagenDeStorage(anterior['imagen_url']);
                                  }

                                  final enlaceFinal = _formatearDestinoAnuncio(contactoCtrl.text);

                                  if (idEditando == null) {
                                    final maxOrden = _anuncios.isEmpty
                                        ? 1
                                        : _anuncios
                                                .map((e) => (e['orden'] ?? 0) as int)
                                                .reduce((a, b) => a > b ? a : b) +
                                            1;

                                    await SupabaseService.client.from('anuncios').insert({
                                      'titulo': titulo,
                                      'subtitulo': subAnuncioCtrl.text.trim().isEmpty ? null : subAnuncioCtrl.text.trim(),
                                      'imagen_url': urlFinalImagen,
                                      'enlace_url': enlaceFinal,
                                      'activo': true,
                                      'orden': maxOrden,
                                    });
                                  } else {
                                    await SupabaseService.client.from('anuncios').update({
                                      'titulo': titulo,
                                      'subtitulo': subAnuncioCtrl.text.trim().isEmpty ? null : subAnuncioCtrl.text.trim(),
                                      'imagen_url': urlFinalImagen,
                                      'enlace_url': enlaceFinal,
                                    }).eq('id', idEditando!);
                                  }

                                  setStateModal(limpiarFormulario);
                                } finally {
                                  setStateModal(() => subiendo = false);
                                }
                              },
                      ),
                    ),
                    const Divider(height: 24),
                    Text(
                      'Anuncios guardados (${_anuncios.length}):',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A), fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (_anuncios.isEmpty)
                      const Text('No hay anuncios creados.', style: TextStyle(color: Color(0xFF64748B), fontSize: 12))
                    else
                      ...List.generate(_anuncios.length, (index) {
                        final anuncio = _anuncios[index];
                        final bool activo = anuncio['activo'] ?? false;
                        return Card(
                          color: const Color(0xFFF8FAFC),
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(
                              children: [
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    InkWell(
                                      onTap: index == 0
                                          ? null
                                          : () async {
                                              await _intercambiarOrdenAnuncios(index, index - 1);
                                              setStateModal(() {});
                                            },
                                      child: Icon(
                                        Icons.keyboard_arrow_up_rounded,
                                        color: index == 0 ? Colors.black12 : const Color(0xFF0284C7),
                                        size: 24,
                                      ),
                                    ),
                                    InkWell(
                                      onTap: index == _anuncios.length - 1
                                          ? null
                                          : () async {
                                              await _intercambiarOrdenAnuncios(index, index + 1);
                                              setStateModal(() {});
                                            },
                                      child: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        color: index == _anuncios.length - 1 ? Colors.black12 : const Color(0xFF0284C7),
                                        size: 24,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${index + 1}. ${anuncio['titulo'] ?? ''}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        anuncio['imagen_url'] != null ? '🖼️ Banner con imagen' : '📝 Tarjeta de texto',
                                        style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                      ),
                                    ],
                                  ),
                                ),
                                Switch(
                                  value: activo,
                                  activeThumbColor: const Color(0xFF16A34A),
                                  onChanged: (val) async {
                                    await SupabaseService.client
                                        .from('anuncios')
                                        .update({'activo': val})
                                        .eq('id', anuncio['id']);
                                    setStateModal(() {});
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Editar anuncio',
                                  icon: const Icon(Icons.edit_outlined, color: Color(0xFF0284C7), size: 20),
                                  onPressed: () {
                                    setStateModal(() {
                                      idEditando = anuncio['id'].toString();
                                      titAnuncioCtrl.text = anuncio['titulo'] ?? '';
                                      subAnuncioCtrl.text = anuncio['subtitulo'] ?? '';
                                      contactoCtrl.text = anuncio['enlace_url'] ?? '';
                                      urlImagenExistente = anuncio['imagen_url'];
                                      bytesImagenSeleccionada = null;
                                      nombreArchivoSeleccionado = null;
                                    });
                                  },
                                ),
                                IconButton(
                                  tooltip: 'Eliminar anuncio e imagen',
                                  icon: const Icon(Icons.delete_outline, color: Color(0xFFDC2626), size: 20),
                                  onPressed: () async {
                                    if (idEditando == anuncio['id'].toString()) {
                                      limpiarFormulario();
                                    }
                                    await _borrarImagenDeStorage(anuncio['imagen_url']);
                                    await SupabaseService.client
                                        .from('anuncios')
                                        .delete()
                                        .eq('id', anuncio['id']);
                                    setStateModal(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cerrar', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
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

    await SupabaseService.client
        .from('pendientes')
        .update({
          'completada': nuevoEstado,
          if (nuevoEstado) 'notificada': true,
        })
        .eq('id', id);
  }

  Future<void> _eliminarPendiente(String id) async {
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

    await SupabaseService.client.from('pendientes').delete().eq('id', id);
  }

  Future<void> _guardarNotaRapida() async {
    final titulo = _tituloCtrl.text.trim();
    if (titulo.isEmpty) return;

    final descripcion = _descCtrl.text.trim();
    DateTime? fechaFinal;
    final bool conAlarma = _horaAlarmaSeleccionada != null;

    if (_fechaNotaSeleccionada != null || conAlarma) {
      final base = _fechaNotaSeleccionada ?? _selectedDay;
      final hora = _horaAlarmaSeleccionada ?? const TimeOfDay(hour: 12, minute: 0);
      fechaFinal = DateTime(base.year, base.month, base.day, hora.hour, hora.minute);
    }

    final data = {
      'titulo': titulo,
      'descripcion': descripcion.isEmpty ? null : descripcion,
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

    if (conAlarma) {
      await SupabaseService.pedirPermisoPush();
    }

    await SupabaseService.client.from('pendientes').insert(data);
  }
  Future<void> _exportarReportePDF() async {
    if (_generandoPDF) return;
    setState(() => _generandoPDF = true);

    try {
      String tituloReporte;
      String nombreArchivo;
      List<Map<String, dynamic>> listaExportar;

      if (_vistaSeleccionada == 0) {
        final fechaDia = DateFormat('dd/MM/yyyy').format(_selectedDay);
        final fechaArchivo = DateFormat('dd-MM-yyyy').format(_selectedDay);
        tituloReporte = 'Actividades del Dia $fechaDia';
        nombreArchivo = 'Agenda_Dia_$fechaArchivo.pdf';
        final delDia = _obtenerEventosDelDia(_selectedDay);
        final sinFecha = _todosLosPendientes
            .where((e) => e['fecha_alarma'] == null && !(e['completada'] ?? false))
            .toList();
        listaExportar = [...delDia, ...sinFecha];
      } else if (_vistaSeleccionada == 1) {
        tituloReporte = 'Todas las Actividades Pendientes';
        nombreArchivo = 'Agenda_Pendientes_${DateFormat('dd-MM-yyyy').format(DateTime.now())}.pdf';
        listaExportar = _todosLosPendientes.where((e) => !(e['completada'] ?? false)).toList();
      } else {
        tituloReporte = 'Historial de Actividades Realizadas';
        nombreArchivo = 'Agenda_Realizadas_${DateFormat('dd-MM-yyyy').format(DateTime.now())}.pdf';
        listaExportar = _todosLosPendientes.where((e) => (e['completada'] ?? false)).toList().reversed.toList();
      }

      if (listaExportar.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay actividades en esta vista para exportar a PDF.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final pdf = pw.Document();
      final correoUsuario = SupabaseService.client.auth.currentUser?.email ?? '';
      final fechaEmision = DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now());

      String limpiarTexto(String? s) {
        if (s == null) return '';
        return s.replaceAll(RegExp(r'[^\x00-\xFF]'), '').trim();
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.letter,
          margin: const pw.EdgeInsets.all(32),
          header: (pw.Context ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'MI AGENDA INTERACTIVA',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800),
                  ),
                  pw.Text(
                    'Emitido: $fechaEmision',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                  ),
                ],
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                limpiarTexto(tituloReporte),
                style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.black),
              ),
              if (correoUsuario.isNotEmpty)
                pw.Text(
                  'Usuario: $correoUsuario  |  Total: ${listaExportar.length} registros',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
              pw.Divider(color: PdfColors.blue300, thickness: 1.5),
              pw.SizedBox(height: 8),
            ],
          ),
          footer: (pw.Context ctx) => pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 10),
            child: pw.Text(
              'Pagina ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
            ),
          ),
          build: (pw.Context ctx) {
            return [
              pw.TableHelper.fromTextArray(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.7),
                headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 10),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue700),
                cellStyle: const pw.TextStyle(fontSize: 9.5, color: PdfColors.grey900),
                cellPadding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                columnWidths: {
                  0: const pw.FlexColumnWidth(1.3),
                  1: const pw.FlexColumnWidth(3.5),
                  2: const pw.FlexColumnWidth(2.0),
                  3: const pw.FlexColumnWidth(1.2),
                },
                headers: ['Estado', 'Actividad / Detalles', 'Fecha / Alarma', 'Prioridad'],
                data: listaExportar.map((item) {
                  final bool comp = item['completada'] ?? false;
                  final bool alarma = item['tiene_alarma'] ?? false;
                  final String? fStr = item['fecha_alarma'];
                  final fLocal = fStr != null ? DateTime.parse(fStr).toLocal() : null;

                  final tit = limpiarTexto(item['titulo'] ?? '');
                  final desc = limpiarTexto(item['descripcion']);
                  final textoActividad = desc.isEmpty ? tit : '$tit\n($desc)';

                  String textoFecha;
                  if (fLocal == null) {
                    textoFecha = 'Sin fecha';
                  } else if (alarma) {
                    textoFecha = '${DateFormat('dd/MM/yyyy HH:mm').format(fLocal)} [Alarma]';
                  } else {
                    textoFecha = DateFormat('dd/MM/yyyy').format(fLocal);
                  }

                  final prioRaw = (item['prioridad'] ?? 'normal').toString();
                  final prioTexto = prioRaw == 'urgente'
                      ? 'URGENTE'
                      : (prioRaw == 'baja' ? 'Baja' : 'Normal');

                  return [
                    comp ? 'Realizada' : 'Pendiente',
                    textoActividad,
                    textoFecha,
                    prioTexto,
                  ];
                }).toList(),
              ),
            ];
          },
        ),
      );

      final bytes = await pdf.save();
      SupabaseService.descargarPDF(bytes, nombreArchivo);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Descargando $nombreArchivo...'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _generandoPDF = false);
    }
  }
  void _mostrarEditorNota(Map<String, dynamic> item) {
    final String id = item['id'].toString();
    final editTitCtrl = TextEditingController(text: item['titulo'] ?? '');
    final editDescCtrl = TextEditingController(text: item['descripcion'] ?? '');

    final String? fechaStr = item['fecha_alarma'];
    final DateTime? fechaExistente = fechaStr != null ? DateTime.parse(fechaStr).toLocal() : null;
    final bool teniaAlarma = item['tiene_alarma'] ?? false;

    DateTime? fechaEdit = fechaExistente;
    TimeOfDay? horaEdit = (fechaExistente != null && teniaAlarma)
        ? TimeOfDay(hour: fechaExistente.hour, minute: fechaExistente.minute)
        : null;
    String prioridadEdit = item['prioridad'] ?? 'normal';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateModal) {
          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(
              children: [
                Icon(Icons.edit_note_rounded, color: Color(0xFF0284C7), size: 28),
                SizedBox(width: 8),
                Text(
                  'Editar Nota / Pendiente',
                  style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: editTitCtrl,
                      textInputAction: TextInputAction.next,
                      style: const TextStyle(color: Color(0xFF0F172A)),
                      decoration: const InputDecoration(
                        labelText: 'Título *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: editDescCtrl,
                      textInputAction: TextInputAction.done,
                      style: const TextStyle(color: Color(0xFF334155)),
                      decoration: const InputDecoration(
                        labelText: 'Detalles opcionales',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.event, size: 18, color: Color(0xFF0284C7)),
                          backgroundColor: const Color(0xFFF1F5F9),
                          label: Text(
                            fechaEdit == null ? 'Sin fecha' : DateFormat('dd/MM/yyyy').format(fechaEdit!),
                            style: const TextStyle(color: Color(0xFF0F172A)),
                          ),
                          onPressed: () async {
                            final nuevaFecha = await showDatePicker(
                              context: context,
                              initialDate: fechaEdit ?? DateTime.now(),
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                            );
                            if (nuevaFecha != null) {
                              setStateModal(() => fechaEdit = nuevaFecha);
                            }
                          },
                        ),
                        if (fechaEdit != null)
                          InkWell(
                            onTap: () => setStateModal(() {
                              fechaEdit = null;
                              horaEdit = null;
                            }),
                            child: const Icon(Icons.cancel, size: 20, color: Color(0xFF94A3B8)),
                          ),
                        ActionChip(
                          avatar: Icon(
                            horaEdit == null ? Icons.alarm_off : Icons.alarm_on,
                            size: 18,
                            color: horaEdit == null ? const Color(0xFF64748B) : const Color(0xFFD97706),
                          ),
                          backgroundColor: horaEdit == null ? const Color(0xFFF1F5F9) : const Color(0xFFFEF3C7),
                          label: Text(
                            horaEdit == null ? 'Sin alarma' : horaEdit!.format(context),
                            style: TextStyle(
                              color: horaEdit == null ? const Color(0xFF334155) : const Color(0xFFB45309),
                              fontWeight: horaEdit == null ? FontWeight.normal : FontWeight.bold,
                            ),
                          ),
                          onPressed: () async {
                            final nuevaHora = await showTimePicker(
                              context: context,
                              initialTime: horaEdit ?? TimeOfDay.now(),
                            );
                            if (nuevaHora != null) {
                              setStateModal(() {
                                fechaEdit ??= DateTime.now();
                                horaEdit = nuevaHora;
                              });
                            }
                          },
                        ),
                        if (horaEdit != null)
                          InkWell(
                            onTap: () => setStateModal(() => horaEdit = null),
                            child: const Icon(Icons.cancel, size: 20, color: Color(0xFF94A3B8)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text('Prioridad: ', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        DropdownButton<String>(
                          value: prioridadEdit,
                          dropdownColor: Colors.white,
                          items: const [
                            DropdownMenuItem(value: 'baja', child: Text('🟢 Baja')),
                            DropdownMenuItem(value: 'normal', child: Text('🔵 Normal')),
                            DropdownMenuItem(value: 'urgente', child: Text('🔴 Urgente')),
                          ],
                          onChanged: (val) => setStateModal(() => prioridadEdit = val ?? 'normal'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.save_rounded),
                label: const Text('Guardar Cambios'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final nuevoTitulo = editTitCtrl.text.trim();
                  if (nuevoTitulo.isEmpty) return;

                  DateTime? fechaFinalEdit;
                  final bool conAlarmaEdit = horaEdit != null;
                  if (fechaEdit != null || conAlarmaEdit) {
                    final base = fechaEdit ?? DateTime.now();
                    final hora = horaEdit ?? const TimeOfDay(hour: 12, minute: 0);
                    fechaFinalEdit = DateTime(base.year, base.month, base.day, hora.hour, hora.minute);
                  }

                  final actualizacion = {
                    'titulo': nuevoTitulo,
                    'descripcion': editDescCtrl.text.trim().isEmpty ? null : editDescCtrl.text.trim(),
                    'fecha_alarma': fechaFinalEdit?.toUtc().toIso8601String(),
                    'tiene_alarma': conAlarmaEdit,
                    'prioridad': prioridadEdit,
                    if (conAlarmaEdit) 'notificada': false,
                  };

                  setState(() {
                    final idx = _todosLosPendientes.indexWhere((e) => e['id'].toString() == id);
                    if (idx != -1) {
                      _todosLosPendientes[idx] = {..._todosLosPendientes[idx], ...actualizacion};
                    }
                  });

                  Navigator.of(ctx).pop();

                  if (conAlarmaEdit) {
                    await SupabaseService.pedirPermisoPush();
                  }
                  await SupabaseService.client.from('pendientes').update(actualizacion).eq('id', id);
                },
              ),
            ],
          );
        },
      ),
    );
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
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Mi Agenda Interactiva',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        actions: [
          if (_esAdmin) ...[
            IconButton(
              tooltip: 'Gestionar Publicidad',
              icon: const Icon(Icons.campaign_rounded, color: Color(0xFFD97706)),
              onPressed: _mostrarGestorPublicidad,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
              child: ActionChip(
                avatar: const Icon(Icons.group_rounded, size: 18, color: Color(0xFF0284C7)),
                backgroundColor: const Color(0xFFE0F2FE),
                side: const BorderSide(color: Color(0xFFBAE6FD)),
                label: Text(
                  '${_usuariosRegistrados.length}',
                  style: const TextStyle(
                    color: Color(0xFF0284C7),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                tooltip: 'Ver usuarios registrados',
                onPressed: _mostrarPanelAdmin,
              ),
            ),
          ],
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
          if (!_esAdmin)
            IconButton(
              tooltip: 'Eliminar mi cuenta y datos',
              icon: const Icon(Icons.person_remove_outlined, color: Color(0xFFDC2626)),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: Colors.white,
                    title: const Text(
                      '¿Eliminar cuenta permanentemente?',
                      style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold),
                    ),
                    content: const Text(
                      'Se borrarán de inmediato tu usuario y todas tus notas guardadas. Esta acción no se puede deshacer.',
                      style: TextStyle(color: Color(0xFF475569)),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text('Cancelar'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFDC2626),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          await SupabaseService.client.rpc('eliminar_mi_cuenta');
                          await SupabaseService.client.auth.signOut();
                        },
                        child: const Text('Sí, borrar todo'),
                      ),
                    ],
                  ),
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
                  Expanded(
                    flex: 5,
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _construirPanelCalendario(),
                          const SizedBox(height: 16),
                          _construirCarruselPublicidad(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(flex: 6, child: _construirPanelNotasYPendientes(notasSinFecha, eventosDelDia)),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  children: [
                    _construirPanelCalendario(),
                    const SizedBox(height: 12),
                    _construirCarruselPublicidad(),
                    const SizedBox(height: 16),
                    _construirPanelNotasYPendientes(notasSinFecha, eventosDelDia, scrollable: false),
                  ],
                ),
              ),
      ),
    );
  }
  Widget _construirCarruselPublicidad() {
    final activos = _anunciosActivos;
    if (activos.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: _carruselCtrl,
            itemCount: activos.length,
            onPageChanged: (idx) => setState(() => _indiceAnuncioActual = idx),
            itemBuilder: (context, index) {
              final item = activos[index];
              final String? imgUrl = item['imagen_url'];
              final String? linkUrl = item['enlace_url'];

              return GestureDetector(
                onTap: () {
                  if (linkUrl != null && linkUrl.isNotEmpty) {
                    _abrirEnlaceWeb(linkUrl.toJS, '_blank'.toJS);
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0284C7), Color(0xFF1D4ED8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (imgUrl != null && imgUrl.isNotEmpty)
                          Image.network(
                            imgUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _contenidoTarjetaTextoAnuncio(item),
                          )
                        else
                          _contenidoTarjetaTextoAnuncio(item),
                        Positioned(
                          top: 8,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Patrocinado',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (activos.length > 1) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(activos.length, (i) {
              final seleccionado = i == _indiceAnuncioActual;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: seleccionado ? 16 : 7,
                height: 7,
                decoration: BoxDecoration(
                  color: seleccionado ? const Color(0xFF0284C7) : const Color(0xFFCBD5E1),
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ],
    );
  }

  Widget _contenidoTarjetaTextoAnuncio(Map<String, dynamic> item) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            item['titulo'] ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          if (item['subtitulo'] != null) ...[
            const SizedBox(height: 6),
            Text(
              item['subtitulo'],
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ],
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
                textInputAction: TextInputAction.next,
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
                textInputAction: TextInputAction.done,
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
              const SizedBox(width: 8),
              ActionChip(
                avatar: _generandoPDF
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFDC2626)),
                      )
                    : const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Color(0xFFDC2626)),
                backgroundColor: const Color(0xFFFEF2F2),
                side: const BorderSide(color: Color(0xFFFECACA)),
                label: const Text(
                  'PDF',
                  style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold),
                ),
                tooltip: 'Descargar reporte PDF de la lista actual',
                onPressed: _generandoPDF ? null : _exportarReportePDF,
              ),
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
          Container(
            width: 5,
            height: 48,
            decoration: BoxDecoration(
              color: colorBorde,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => _alternarCompletada(id, !completada),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Icon(
                  completada ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: completada ? const Color(0xFF16A34A) : const Color(0xFF94A3B8),
                  size: 28,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
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
          Material(
            color: const Color(0xFFE0F2FE),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _mostrarEditorNota(item),
              child: const Padding(
                padding: EdgeInsets.all(9.0),
                child: Icon(Icons.edit_outlined, color: Color(0xFF0284C7), size: 20),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Material(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _eliminarPendiente(id),
              child: const Padding(
                padding: EdgeInsets.all(9.0),
                child: Icon(Icons.delete_outline_rounded, color: Color(0xFFDC2626), size: 20),
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
