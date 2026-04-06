/// Modelo espelhando a tabela `contagem_itens`.
class ContagemItem {
  final int id;
  final int uploadId;
  final String codigo;
  final String produto;
  final String categoria;
  final int qtdEstoque;
  final String status;      // 'pendente' | 'certa' | 'divergencia'
  final String motivo;
  final int qtdDivergencia;
  final String registradoEm;
  /// Nota/observação persistente do produto em estoque_mestre (ex: nome do cooperado).
  final String notaProduto;

  const ContagemItem({
    required this.id,
    this.uploadId = 0,
    required this.codigo,
    required this.produto,
    required this.categoria,
    this.qtdEstoque = 0,
    this.status = 'pendente',
    this.motivo = '',
    this.qtdDivergencia = 0,
    this.registradoEm = '',
    this.notaProduto = '',
  });

  bool get isPendente => status == 'pendente';
  bool get isOk => status == 'certa';
  bool get isDivergente => status == 'divergencia';

  factory ContagemItem.fromMap(Map<String, dynamic> map) {
    return ContagemItem(
      id: _toInt(map['id']),
      uploadId: _toInt(map['upload_id']),
      codigo: map['codigo']?.toString() ?? '',
      produto: map['produto']?.toString() ?? '',
      categoria: map['categoria']?.toString() ?? '',
      qtdEstoque: _toInt(map['qtd_estoque']),
      status: map['status']?.toString() ?? 'pendente',
      motivo: map['motivo']?.toString() ?? '',
      qtdDivergencia: _toInt(map['qtd_divergencia']),
      registradoEm: map['registrado_em']?.toString() ?? '',
      notaProduto: map['nota_produto']?.toString() ?? '',
    );
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}

/// Representa uma divergência já registrada na tabela `divergencias`.
class DivergenciaExistente {
  final int id;
  final String cooperado;
  final int delta; // negativo = falta, positivo = sobra
  final String status; // 'falta' | 'sobra'

  const DivergenciaExistente({
    required this.id,
    required this.cooperado,
    required this.delta,
    required this.status,
  });

  factory DivergenciaExistente.fromMap(Map<String, dynamic> map) {
    return DivergenciaExistente(
      id: _toInt(map['id']),
      cooperado: map['cooperado']?.toString() ?? '',
      delta: _toInt(map['delta']),
      status: map['status']?.toString() ?? '',
    );
  }

  static int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}
