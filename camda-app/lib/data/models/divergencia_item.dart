/// Modelo espelhando a tabela `divergencias` com JOIN em `estoque_mestre`.
class DivergenciaItem {
  final int id;
  final String codigo;
  final String produto;
  final String categoria;
  final int delta;        // negativo=falta, positivo=sobra
  final String status;   // 'falta' | 'sobra'
  final String cooperado;
  final String criadoEm;
  final int qtdSistema;  // de estoque_mestre

  const DivergenciaItem({
    required this.id,
    required this.codigo,
    required this.produto,
    required this.categoria,
    required this.delta,
    required this.status,
    this.cooperado = '',
    this.criadoEm = '',
    this.qtdSistema = 0,
  });

  bool get isFalta => status == 'falta';
  bool get isSobra => status == 'sobra';

  int get qtdFisica => qtdSistema + delta; // delta negativo reduz

  factory DivergenciaItem.fromMap(Map<String, dynamic> map) {
    return DivergenciaItem(
      id: _toInt(map['id']),
      codigo: map['codigo']?.toString() ?? '',
      produto: map['produto']?.toString() ?? '',
      categoria: map['categoria']?.toString() ?? '',
      delta: _toInt(map['delta']),
      status: map['status']?.toString() ?? 'falta',
      cooperado: map['cooperado']?.toString() ?? '',
      criadoEm: map['criado_em']?.toString() ?? '',
      qtdSistema: _toInt(map['qtd_sistema']),
    );
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}
