import '../database/turso_client.dart';
import '../models/validade_lote.dart';
import '../../core/services/cache_service.dart';

class ValidadeRepository {
  final TursoClient _client;

  ValidadeRepository({TursoClient? client})
      : _client = client ?? TursoClient.instance;

  Future<List<ValidadeLote>> getAll({String? grupo}) async {
    var sql = '''
      SELECT id, filial, grupo, produto, lote, fabricacao, vencimento,
             quantidade, valor, uploaded_em
      FROM validade_lotes
    ''';
    final args = <dynamic>[];
    if (grupo != null && grupo.isNotEmpty) {
      sql += ' WHERE grupo = ?';
      args.add(grupo);
    }
    sql += ' ORDER BY vencimento ASC';

    try {
      final result = await _client.query(sql, args);
      if (result.hasError) throw TursoException(result.error!);
      final rows = result.toMaps();
      if (grupo == null) {
        await CacheService.saveValidade(rows);
        CacheService.isOffline = false;
      }
      return rows.map(ValidadeLote.fromMap).toList();
    } catch (e) {
      if (grupo == null) {
        final (cached, _) = await CacheService.loadValidade();
        if (cached != null && cached.isNotEmpty) {
          CacheService.isOffline = true;
          return cached.map(ValidadeLote.fromMap).toList();
        }
      }
      rethrow;
    }
  }

  Future<List<ValidadeLote>> getProximosAoVencer({int dias = 30}) async {
    final hoje = DateTime.now();
    final limite = hoje.add(Duration(days: dias));
    try {
      final result = await _client.query(
        '''SELECT id, filial, grupo, produto, lote, fabricacao, vencimento,
                  quantidade, valor, uploaded_em
           FROM validade_lotes
           WHERE vencimento <= ? AND vencimento >= ?
           ORDER BY vencimento ASC''',
        [limite.toIso8601String().substring(0, 10),
         hoje.toIso8601String().substring(0, 10)],
      );
      if (result.hasError) throw TursoException(result.error!);
      return result.toMaps().map(ValidadeLote.fromMap).toList();
    } catch (_) {
      final (cached, _) = await CacheService.loadValidade();
      if (cached != null && cached.isNotEmpty) {
        final hojeStr = hoje.toIso8601String().substring(0, 10);
        final limiteStr = limite.toIso8601String().substring(0, 10);
        return cached
            .map(ValidadeLote.fromMap)
            .where((v) => v.vencimento.compareTo(hojeStr) >= 0 && v.vencimento.compareTo(limiteStr) <= 0)
            .toList();
      }
      rethrow;
    }
  }

  Future<List<ValidadeLote>> getVencidos() async {
    final hoje = DateTime.now().toIso8601String().substring(0, 10);
    try {
      final result = await _client.query(
        '''SELECT id, filial, grupo, produto, lote, fabricacao, vencimento,
                  quantidade, valor, uploaded_em
           FROM validade_lotes
           WHERE vencimento < ?
           ORDER BY vencimento ASC''',
        [hoje],
      );
      if (result.hasError) throw TursoException(result.error!);
      return result.toMaps().map(ValidadeLote.fromMap).toList();
    } catch (_) {
      final (cached, _) = await CacheService.loadValidade();
      if (cached != null && cached.isNotEmpty) {
        return cached
            .map(ValidadeLote.fromMap)
            .where((v) => v.vencimento.compareTo(hoje) < 0)
            .toList();
      }
      rethrow;
    }
  }

  Future<List<String>> getGrupos() async {
    try {
      final result = await _client.query(
        'SELECT DISTINCT grupo FROM validade_lotes ORDER BY grupo',
      );
      if (result.hasError) throw TursoException(result.error!);
      return result.rows
          .map((r) => r.first?.toString() ?? '')
          .where((g) => g.isNotEmpty)
          .toList();
    } catch (_) {
      final (cached, _) = await CacheService.loadValidade();
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

  Future<ValidadeResumo> getResumo() async {
    final hoje = DateTime.now().toIso8601String().substring(0, 10);
    final critico = DateTime.now().add(const Duration(days: 7))
        .toIso8601String().substring(0, 10);
    final alerta = DateTime.now().add(const Duration(days: 30))
        .toIso8601String().substring(0, 10);

    try {
      final result = await _client.query('''
        SELECT
          COUNT(*) as total,
          SUM(CASE WHEN vencimento < ? THEN 1 ELSE 0 END) as vencidos,
          SUM(CASE WHEN vencimento >= ? AND vencimento <= ? THEN 1 ELSE 0 END) as criticos,
          SUM(CASE WHEN vencimento > ? AND vencimento <= ? THEN 1 ELSE 0 END) as alertas
        FROM validade_lotes
      ''', [hoje, hoje, critico, critico, alerta]);

      if (result.hasError) throw TursoException(result.error!);
      final row = result.toMaps().firstOrNull ?? {};
      return ValidadeResumo(
        total: _toInt(row['total']),
        vencidos: _toInt(row['vencidos']),
        criticos: _toInt(row['criticos']),
        alertas: _toInt(row['alertas']),
      );
    } catch (_) {
      // Offline: calcula resumo a partir do cache
      final (cached, _) = await CacheService.loadValidade();
      if (cached != null && cached.isNotEmpty) {
        final lotes = cached.map(ValidadeLote.fromMap).toList();
        int vencidos = 0, criticos = 0, alertas = 0;
        for (final l in lotes) {
          if (l.vencimento.compareTo(hoje) < 0) {
            vencidos++;
          } else if (l.vencimento.compareTo(critico) <= 0) {
            criticos++;
          } else if (l.vencimento.compareTo(alerta) <= 0) {
            alertas++;
          }
        }
        return ValidadeResumo(
          total: lotes.length,
          vencidos: vencidos,
          criticos: criticos,
          alertas: alertas,
        );
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

class ValidadeResumo {
  final int total;
  final int vencidos;
  final int criticos;
  final int alertas;

  const ValidadeResumo({
    this.total = 0,
    this.vencidos = 0,
    this.criticos = 0,
    this.alertas = 0,
  });
}
