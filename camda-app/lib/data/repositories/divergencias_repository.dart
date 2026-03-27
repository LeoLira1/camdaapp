import '../database/turso_client.dart';
import '../models/divergencia_item.dart';

class DivergenciasRepository {
  final TursoClient _client;

  DivergenciasRepository({TursoClient? client})
      : _client = client ?? TursoClient.instance;

  /// Busca todas as divergências ativas com qtd_sistema do estoque_mestre.
  /// Ordenado por cooperado → produto (igual ao dashboard Streamlit).
  Future<List<DivergenciaItem>> getAll() async {
    final result = await _client.query('''
      SELECT d.id, d.codigo, d.produto, d.categoria, d.delta, d.status,
             COALESCE(d.cooperado, '') as cooperado, d.criado_em,
             COALESCE(em.qtd_sistema, 0) as qtd_sistema
      FROM divergencias d
      LEFT JOIN estoque_mestre em ON UPPER(TRIM(em.codigo)) = UPPER(TRIM(d.codigo))
      ORDER BY d.cooperado, d.produto
    ''');
    if (result.hasError) throw TursoException(result.error!);
    return result.toMaps().map(DivergenciaItem.fromMap).toList();
  }

  /// Resolve divergência: remove de `divergencias`.
  /// Só reseta estoque_mestre se NÃO restar nenhuma outra divergência ativa
  /// para o mesmo produto — comportamento idêntico ao dashboard Streamlit.
  Future<void> resolver(int id, String codigo) async {
    final now = _nowBRT();
    // Deleta a divergência específica
    final deleteResult = await _client.query(
      'DELETE FROM divergencias WHERE id=?',
      [id],
    );
    if (deleteResult.hasError) throw TursoException(deleteResult.error!);

    // Conta divergências restantes para o mesmo produto
    final countResult = await _client.query(
      'SELECT COUNT(*) as cnt FROM divergencias WHERE UPPER(TRIM(codigo)) = UPPER(TRIM(?))',
      [codigo],
    );
    if (countResult.hasError) throw TursoException(countResult.error!);

    final rows = countResult.toMaps();
    final remaining = rows.isNotEmpty ? (rows.first['cnt'] as int? ?? 0) : 0;

    // Só reseta estoque_mestre se não restar mais nenhuma divergência
    if (remaining == 0) {
      await _client.query(
        "UPDATE estoque_mestre SET status='ok', qtd_fisica=qtd_sistema, diferenca=0, ultima_contagem=? WHERE UPPER(TRIM(codigo)) = UPPER(TRIM(?)) AND status IN ('falta','sobra')",
        [now, codigo],
      );
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
}
