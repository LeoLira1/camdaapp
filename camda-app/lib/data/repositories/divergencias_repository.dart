import '../database/turso_client.dart';
import '../models/divergencia_item.dart';

class DivergenciasRepository {
  final TursoClient _client;

  DivergenciasRepository({TursoClient? client})
      : _client = client ?? TursoClient.instance;

  /// Busca todas as divergências ativas com qtd_sistema do estoque_mestre.
  Future<List<DivergenciaItem>> getAll() async {
    final result = await _client.query('''
      SELECT d.id, d.codigo, d.produto, d.categoria, d.delta, d.status,
             COALESCE(d.cooperado, '') as cooperado, d.criado_em,
             COALESCE(em.qtd_sistema, 0) as qtd_sistema
      FROM divergencias d
      LEFT JOIN estoque_mestre em ON UPPER(TRIM(em.codigo)) = UPPER(TRIM(d.codigo))
      ORDER BY d.criado_em DESC
    ''');
    if (result.hasError) throw TursoException(result.error!);
    return result.toMaps().map(DivergenciaItem.fromMap).toList();
  }

  /// Resolve divergência: remove de `divergencias` e reseta `estoque_mestre`.
  Future<void> resolver(int id, String codigo) async {
    await _client.transaction([
      TursoQuery(
        sql: 'DELETE FROM divergencias WHERE id=?',
        args: [id],
      ),
      TursoQuery(
        sql: "UPDATE estoque_mestre SET status='ok', qtd_fisica=qtd_sistema, diferenca=0 WHERE codigo=?",
        args: [codigo],
      ),
    ]);
  }
}
