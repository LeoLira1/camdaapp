import '../database/turso_client.dart';
import '../models/contagem_item.dart';
import '../../core/services/cache_service.dart';
import '../../core/services/connectivity_service.dart';
import '../../core/services/sync_queue_service.dart';

class ContagemRepository {
  final TursoClient _client;

  ContagemRepository({TursoClient? client})
      : _client = client ?? TursoClient.instance;

  Future<List<ContagemItem>> getAll() async {
    try {
      final result = await _client.query('''
        WITH last_div AS (
          SELECT UPPER(TRIM(codigo)) AS cod,
                 cooperado,
                 ROW_NUMBER() OVER (
                   PARTITION BY UPPER(TRIM(codigo))
                   ORDER BY criado_em DESC
                 ) AS rn
          FROM divergencias
        )
        SELECT ci.id, ci.upload_id, ci.codigo, ci.produto, ci.categoria, ci.qtd_estoque,
               ci.status, COALESCE(ci.motivo,'') as motivo,
               COALESCE(ci.qtd_divergencia, 0) as qtd_divergencia, ci.registrado_em,
               COALESCE(
                 NULLIF(TRIM(em.observacoes),''),
                 NULLIF(TRIM(em.nota),''),
                 ld.cooperado,
                 ''
               ) as nota_produto
        FROM contagem_itens ci
        LEFT JOIN estoque_mestre em ON UPPER(TRIM(em.codigo)) = UPPER(TRIM(ci.codigo))
        LEFT JOIN last_div ld ON ld.cod = UPPER(TRIM(ci.codigo)) AND ld.rn = 1
        ORDER BY ci.categoria, ci.produto ASC
      ''');
      if (result.hasError) throw TursoException(result.error!);
      final rows = result.toMaps();
      await CacheService.saveContagem(rows);
      CacheService.isOffline = false;
      return rows.map(ContagemItem.fromMap).toList();
    } catch (e) {
      final (cached, _) = await CacheService.loadContagem();
      if (cached != null && cached.isNotEmpty) {
        CacheService.isOffline = true;
        return cached.map(ContagemItem.fromMap).toList();
      }
      rethrow;
    }
  }

  /// Marca item como certa (contagem confere).
  /// Executa transação: atualiza contagem_itens + reseta estoque_mestre + remove divergências do produto.
  Future<void> marcarCerta(int id, String codigo, int qtdSistema) async {
    final now = _nowBRT();
    if (!ConnectivityService.isOnline) {
      const sql = "UPDATE contagem_itens SET status='certa', qtd_divergencia=0, motivo='' WHERE id=?";
      await SyncQueueService.enqueue(sql, [id]);
      await SyncQueueService.enqueue(
        "DELETE FROM divergencias WHERE UPPER(TRIM(codigo)) = UPPER(TRIM(?))",
        [codigo],
      );
      await CacheService.updateContagemItem(id, status: 'certa', qtdDivergencia: 0, motivo: '');
      return;
    }
    await _client.transaction([
      TursoQuery(
        sql: "UPDATE contagem_itens SET status='certa', motivo='', qtd_divergencia=0 WHERE id=?",
        args: [id],
      ),
      TursoQuery(
        sql: "UPDATE estoque_mestre SET status='ok', qtd_fisica=qtd_sistema, diferenca=0, nota='', ultima_contagem=? WHERE codigo=? AND status IN ('falta','sobra')",
        args: [now, codigo],
      ),
      TursoQuery(
        sql: "DELETE FROM divergencias WHERE UPPER(TRIM(codigo)) = UPPER(TRIM(?))",
        args: [codigo],
      ),
    ]);
  }

  /// Marca item como divergente com quantidade, motivo e tipo.
  /// tipoDivergencia = 'falta' | 'sobra'
  /// Executa transação: contagem_itens + estoque_mestre + divergencias + historico_divergencias.
  Future<void> marcarDivergencia(
    int id,
    String codigo,
    int qtdSistema,
    int qtdDivergencia,
    String motivo,
    String tipoDivergencia,
  ) async {
    final now = _nowBRT();
    final qtdFisica = tipoDivergencia == 'sobra'
        ? qtdSistema + qtdDivergencia
        : (qtdSistema - qtdDivergencia).clamp(0, 999999);
    final diferenca = qtdFisica - qtdSistema;
    final delta = tipoDivergencia == 'sobra' ? qtdDivergencia : -qtdDivergencia;

    if (!ConnectivityService.isOnline) {
      const sql = "UPDATE contagem_itens SET status='divergencia', qtd_divergencia=?, motivo=? WHERE id=?";
      await SyncQueueService.enqueue(sql, [qtdDivergencia, motivo.trim(), id]);
      await CacheService.updateContagemItem(id,
          status: 'divergencia', qtdDivergencia: qtdDivergencia, motivo: motivo.trim());
      return;
    }
    await _client.transaction([
      TursoQuery(
        sql: "UPDATE contagem_itens SET status='divergencia', motivo=?, qtd_divergencia=? WHERE id=?",
        args: [motivo.trim(), qtdDivergencia, id],
      ),
      TursoQuery(
        sql: "UPDATE estoque_mestre SET status=?, qtd_fisica=?, diferenca=?, nota=?, observacoes=?, ultima_contagem=? WHERE codigo=?",
        args: [tipoDivergencia, qtdFisica, diferenca, motivo.trim(), motivo.trim(), now, codigo],
      ),
      TursoQuery(
        sql: "INSERT INTO divergencias (codigo, produto, categoria, delta, status, cooperado, criado_em) SELECT ?, produto, categoria, ?, ?, ?, ? FROM estoque_mestre WHERE codigo=?",
        args: [codigo, delta, tipoDivergencia, motivo.trim(), now, codigo],
      ),
      TursoQuery(
        sql: "INSERT INTO historico_divergencias (codigo, produto, categoria, cooperado, delta, status, criado_em) SELECT ?, produto, categoria, ?, ?, ?, ? FROM estoque_mestre WHERE codigo=?",
        args: [codigo, motivo.trim(), delta, tipoDivergencia, now, codigo],
      ),
    ]);
  }

  /// Reseta item para pendente.
  Future<void> resetar(int id) async {
    const sql = "UPDATE contagem_itens SET status='pendente', qtd_divergencia=0, motivo='' WHERE id=?";
    if (!ConnectivityService.isOnline) {
      await SyncQueueService.enqueue(sql, [id]);
      await CacheService.updateContagemItem(id, status: 'pendente', qtdDivergencia: 0, motivo: '');
      return;
    }
    await _client.query(sql, [id]);
  }

  Future<ContagemResumo> getResumo() async {
    try {
      final result = await _client.query('''
        SELECT
          COUNT(*) as total,
          SUM(CASE WHEN status='certa' THEN 1 ELSE 0 END) as ok,
          SUM(CASE WHEN status='divergencia' THEN 1 ELSE 0 END) as divergentes,
          SUM(CASE WHEN status='pendente' THEN 1 ELSE 0 END) as pendentes
        FROM contagem_itens
      ''');
      if (result.hasError) throw TursoException(result.error!);
      final row = result.toMaps().firstOrNull ?? {};
      return ContagemResumo(
        total: _toInt(row['total']),
        ok: _toInt(row['ok']),
        divergentes: _toInt(row['divergentes']),
        pendentes: _toInt(row['pendentes']),
      );
    } catch (_) {
      // Offline: calcula resumo a partir do cache
      final (cached, _) = await CacheService.loadContagem();
      if (cached != null) {
        int total = cached.length, ok = 0, div = 0, pend = 0;
        for (final r in cached) {
          final s = r['status']?.toString() ?? 'pendente';
          if (s == 'certa') ok++;
          else if (s == 'divergencia') div++;
          else pend++;
        }
        return ContagemResumo(total: total, ok: ok, divergentes: div, pendentes: pend);
      }
      return const ContagemResumo();
    }
  }

  static String _nowBRT() {
    final now = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

class ContagemResumo {
  final int total;
  final int ok;
  final int divergentes;
  final int pendentes;

  const ContagemResumo({
    this.total = 0,
    this.ok = 0,
    this.divergentes = 0,
    this.pendentes = 0,
  });

  double get pctConcluido => total > 0 ? ((ok + divergentes) / total) : 0.0;
}
