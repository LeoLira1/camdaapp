import '../database/turso_client.dart';
import '../models/venda.dart';
import '../../core/services/cache_service.dart';

class VendasRepository {
  final TursoClient _client;

  VendasRepository({TursoClient? client})
      : _client = client ?? TursoClient.instance;

  Future<List<Venda>> getAll({String? grupo}) async {
    var sql = '''
      SELECT id, codigo, produto, grupo, qtd_vendida, qtd_estoque, data_upload
      FROM vendas_historico
    ''';
    final args = <dynamic>[];
    if (grupo != null && grupo.isNotEmpty) {
      sql += ' WHERE grupo = ?';
      args.add(grupo);
    }
    sql += ' ORDER BY data_upload DESC, qtd_vendida DESC';

    try {
      final result = await _client.query(sql, args);
      if (result.hasError) throw TursoException(result.error!);
      final rows = result.toMaps();
      // Salva cache apenas quando não há filtro (dados completos)
      if (grupo == null) {
        await CacheService.saveVendas(rows);
        CacheService.isOffline = false;
      }
      return rows.map(Venda.fromMap).toList();
    } catch (e) {
      // Fallback para cache local quando a rede falha
      if (grupo == null) {
        final (cached, _) = await CacheService.loadVendas();
        if (cached != null && cached.isNotEmpty) {
          CacheService.isOffline = true;
          return cached.map(Venda.fromMap).toList();
        }
      }
      rethrow;
    }
  }

  Future<List<String>> getGrupos() async {
    try {
      final result = await _client.query(
        'SELECT DISTINCT grupo FROM vendas_historico ORDER BY grupo',
      );
      if (result.hasError) throw TursoException(result.error!);
      return result.rows
          .map((r) => r.first?.toString() ?? '')
          .where((g) => g.isNotEmpty)
          .toList();
    } catch (_) {
      // Offline: extrai grupos do cache
      final (cached, _) = await CacheService.loadVendas();
      if (cached != null) {
        return cached
            .map((r) => r['grupo']?.toString() ?? '')
            .where((g) => g.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getTopProdutos({int limit = 10}) async {
    try {
      final result = await _client.query('''
        SELECT produto, grupo,
               SUM(qtd_vendida) as total_vendido,
               MAX(data_upload) as ultima_data
        FROM vendas_historico
        GROUP BY produto
        ORDER BY total_vendido DESC
        LIMIT ?
      ''', [limit]);
      if (result.hasError) throw TursoException(result.error!);
      return result.toMaps();
    } catch (_) {
      // Offline: agrega a partir do cache
      final (cached, _) = await CacheService.loadVendas();
      if (cached != null && cached.isNotEmpty) {
        final totals = <String, Map<String, dynamic>>{};
        for (final r in cached) {
          final nome = r['produto']?.toString() ?? '';
          if (nome.isEmpty) continue;
          if (!totals.containsKey(nome)) {
            totals[nome] = {'produto': nome, 'grupo': r['grupo'], 'total_vendido': 0, 'ultima_data': r['data_upload']};
          }
          totals[nome]!['total_vendido'] = (totals[nome]!['total_vendido'] as int) + _toInt(r['qtd_vendida']);
        }
        final sorted = totals.values.toList()
          ..sort((a, b) => (b['total_vendido'] as int).compareTo(a['total_vendido'] as int));
        return sorted.take(limit).toList();
      }
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getVendasPorGrupo() async {
    try {
      final result = await _client.query('''
        SELECT grupo, SUM(qtd_vendida) as total_vendido, COUNT(DISTINCT produto) as produtos
        FROM vendas_historico
        GROUP BY grupo
        ORDER BY total_vendido DESC
      ''');
      if (result.hasError) throw TursoException(result.error!);
      return result.toMaps();
    } catch (_) {
      // Offline: agrega a partir do cache
      final (cached, _) = await CacheService.loadVendas();
      if (cached != null && cached.isNotEmpty) {
        final groups = <String, Map<String, dynamic>>{};
        for (final r in cached) {
          final grupo = r['grupo']?.toString() ?? '';
          if (grupo.isEmpty) continue;
          groups.putIfAbsent(grupo, () => {'grupo': grupo, 'total_vendido': 0, 'produtos': <String>{}});
          groups[grupo]!['total_vendido'] = (groups[grupo]!['total_vendido'] as int) + _toInt(r['qtd_vendida']);
          (groups[grupo]!['produtos'] as Set<String>).add(r['produto']?.toString() ?? '');
        }
        return groups.values.map((g) {
          return {'grupo': g['grupo'], 'total_vendido': g['total_vendido'], 'produtos': (g['produtos'] as Set).length};
        }).toList()
          ..sort((a, b) => (b['total_vendido'] as int).compareTo(a['total_vendido'] as int));
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
