import '../database/turso_client.dart';
import '../models/lancamento.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_queue_service.dart';

class LancamentosRepository {
  final TursoClient _client;

  LancamentosRepository({TursoClient? client})
      : _client = client ?? TursoClient.instance;

  Future<List<Lancamento>> getAll({int limit = 200}) async {
    try {
      final result = await _client.query('''
        SELECT id, codigo, produto, categoria, tipo, quantidade, motivo, registrado_em
        FROM lancamentos_manuais
        ORDER BY id DESC
        LIMIT ?
      ''', [limit]);
      if (result.hasError) throw TursoException(result.error!);
      final rows = result.toMaps();
      await CacheService.saveLancamentos(rows);
      CacheService.isOffline = false;
      return rows.map(Lancamento.fromMap).toList();
    } catch (e) {
      final (cached, _) = await CacheService.loadLancamentos();
      if (cached != null && cached.isNotEmpty) {
        CacheService.isOffline = true;
        return cached.map(Lancamento.fromMap).take(limit).toList();
      }
      rethrow;
    }
  }

  Future<void> inserir({
    required String codigo,
    required String produto,
    required String categoria,
    required String tipo,
    required int quantidade,
    String motivo = '',
  }) async {
    final now = DateTime.now().toIso8601String();
    const sql = '''
      INSERT INTO lancamentos_manuais
        (codigo, produto, categoria, tipo, quantidade, motivo, registrado_em)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    ''';
    final args = [codigo, produto, categoria, tipo, quantidade, motivo.trim(), now];

    if (!ConnectivityService.isOnline) {
      await SyncQueueService.enqueue(sql, args);
      await CacheService.insertLancamento({
        'id': -DateTime.now().millisecondsSinceEpoch,
        'codigo': codigo,
        'produto': produto,
        'categoria': categoria,
        'tipo': tipo,
        'quantidade': quantidade,
        'motivo': motivo.trim(),
        'registrado_em': now,
      });
      return;
    }
    await _client.query(sql, args);
  }

  Future<void> excluir(int id) async {
    const sql = 'DELETE FROM lancamentos_manuais WHERE id = ?';

    if (!ConnectivityService.isOnline) {
      await SyncQueueService.enqueue(sql, [id]);
      await CacheService.removeLancamento(id);
      return;
    }
    await _client.query(sql, [id]);
  }

  Future<List<Map<String, dynamic>>> getResumoTipos() async {
    try {
      final result = await _client.query('''
        SELECT tipo,
               COUNT(*) as total_registros,
               SUM(quantidade) as total_quantidade
        FROM lancamentos_manuais
        GROUP BY tipo
        ORDER BY total_registros DESC
      ''');
      if (result.hasError) throw TursoException(result.error!);
      return result.toMaps();
    } catch (_) {
      // Offline: agrega a partir do cache
      final (cached, _) = await CacheService.loadLancamentos();
      if (cached != null && cached.isNotEmpty) {
        final grupos = <String, Map<String, dynamic>>{};
        for (final r in cached) {
          final tipo = r['tipo']?.toString() ?? '';
          if (tipo.isEmpty) continue;
          grupos.putIfAbsent(tipo, () => {'tipo': tipo, 'total_registros': 0, 'total_quantidade': 0});
          grupos[tipo]!['total_registros'] = (grupos[tipo]!['total_registros'] as int) + 1;
          grupos[tipo]!['total_quantidade'] = (grupos[tipo]!['total_quantidade'] as int) + _toInt(r['quantidade']);
        }
        return grupos.values.toList()
          ..sort((a, b) => (b['total_registros'] as int).compareTo(a['total_registros'] as int));
      }
      rethrow;
    }
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}
