import '../database/turso_client.dart';
import '../models/pendencia.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_queue_service.dart';

class PendenciasRepository {
  final TursoClient _client;

  PendenciasRepository({TursoClient? client})
      : _client = client ?? TursoClient.instance;

  Future<List<Pendencia>> getAll() async {
    try {
      final result = await _client.query('''
        SELECT id, foto_base64, data_registro, COALESCE(observacao, '') as observacao
        FROM pendencias_entrega
        ORDER BY data_registro ASC
      ''');
      if (result.hasError) throw TursoException(result.error!);
      final rows = result.toMaps();
      await CacheService.savePendencias(rows);
      CacheService.isOffline = false;
      return rows.map(Pendencia.fromMap).toList();
    } catch (e) {
      final (cached, _) = await CacheService.loadPendencias();
      if (cached != null && cached.isNotEmpty) {
        CacheService.isOffline = true;
        return cached.map(Pendencia.fromMap).toList();
      }
      rethrow;
    }
  }

  Future<void> inserir({
    required String fotoBase64,
    String observacao = '',
  }) async {
    final hoje = DateTime.now().toIso8601String().substring(0, 10);
    const sql = 'INSERT INTO pendencias_entrega (foto_base64, data_registro, observacao) VALUES (?, ?, ?)';
    final args = [fotoBase64, hoje, observacao.trim()];

    if (!ConnectivityService.isOnline) {
      await SyncQueueService.enqueue(sql, args);
      await CacheService.insertPendencia({
        'id': -DateTime.now().millisecondsSinceEpoch,
        'foto_base64': fotoBase64,
        'data_registro': hoje,
        'observacao': observacao.trim(),
      });
      return;
    }
    await _client.query(sql, args);
  }

  Future<void> deletar(int id) async {
    const sql = 'DELETE FROM pendencias_entrega WHERE id = ?';

    if (!ConnectivityService.isOnline) {
      await SyncQueueService.enqueue(sql, [id]);
      await CacheService.removePendencia(id);
      return;
    }
    await _client.query(sql, [id]);
  }

  Future<void> atualizarObservacao(int id, String observacao) async {
    const sql = 'UPDATE pendencias_entrega SET observacao = ? WHERE id = ?';

    if (!ConnectivityService.isOnline) {
      await SyncQueueService.enqueue(sql, [observacao.trim(), id]);
      await CacheService.updatePendenciaObservacao(id, observacao.trim());
      return;
    }
    await _client.query(sql, [observacao.trim(), id]);
  }

  int diasDesde(String dataRegistro) {
    try {
      final dt = DateTime.parse(dataRegistro);
      return DateTime.now().difference(dt).inDays;
    } catch (_) {
      return 0;
    }
  }
}
