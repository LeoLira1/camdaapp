import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/date_utils.dart';
import '../../data/models/divergencia_item.dart';
import '../../data/repositories/divergencias_repository.dart';
import '../../shared/widgets/loading_widget.dart' as lw;
import '../../shared/widgets/glass_card.dart';

class DivergenciasScreen extends StatefulWidget {
  const DivergenciasScreen({super.key});

  @override
  State<DivergenciasScreen> createState() => _DivergenciasScreenState();
}

class _DivergenciasScreenState extends State<DivergenciasScreen> {
  final _repo = DivergenciasRepository();

  List<DivergenciaItem> _itens = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() { _loading = true; _error = null; });
    try {
      final itens = await _repo.getAll();
      if (!mounted) return;
      setState(() { _itens = itens; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _resolver(DivergenciaItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resolver divergência'),
        content: Text(
          'Confirma resolução de "${item.produto}"?\n\n'
          'O estoque_mestre será resetado para qtd_sistema (${item.qtdSistema}) e status = OK.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.green, foregroundColor: AppColors.background),
            child: const Text('Resolver'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.resolver(item.id, item.codigo);
      await _loadData();
    } catch (e) {
      _snackError('$e');
    }
  }

  void _snackError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.red),
    );
  }

  // ── KPIs ──────────────────────────────────────────────────────────────────

  int get _totalFaltas => _itens.where((i) => i.isFalta).fold(0, (s, i) => s + i.delta.abs());
  int get _totalSobras => _itens.where((i) => i.isSobra).fold(0, (s, i) => s + i.delta.abs());

  // ── Agrupamento por cooperado ─────────────────────────────────────────────

  Map<String, List<DivergenciaItem>> get _porCooperado {
    final map = <String, List<DivergenciaItem>>{};
    for (final item in _itens) {
      final key = item.cooperado.isEmpty ? '(sem cooperado)' : item.cooperado;
      map.putIfAbsent(key, () => []).add(item);
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            if (_loading)
              const Expanded(child: lw.LoadingWidget(message: 'Carregando divergências...'))
            else if (_error != null)
              Expanded(child: lw.ErrorWidget(message: _error!, onRetry: _loadData))
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadData,
                  color: AppColors.green,
                  backgroundColor: AppColors.surface,
                  child: _itens.isEmpty
                      ? const lw.EmptyWidget(
                          message: 'Nenhuma divergência ativa.',
                          icon: Icons.check_circle_outline,
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          children: [
                            _buildKpis(),
                            const SizedBox(height: 12),
                            ..._buildGrupos(),
                          ],
                        ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final now = CamdaDateUtils.nowBRT();
    final hora = CamdaDateUtils.formatTime(now);
    final diaNome = CamdaDateUtils.diaSemanaFull(now);
    final data = CamdaDateUtils.formatDate(now);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ShaderMask(
                shaderCallback: (bounds) =>
                    const LinearGradient(colors: [AppColors.red, AppColors.amber]).createShader(bounds),
                child: const Text(
                  'Divergências',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh, color: AppColors.textMuted, size: 20),
                tooltip: 'Atualizar',
              ),
            ],
          ),
          Text(
            '$diaNome · $data · $hora',
            style: const TextStyle(
              fontFamily: 'JetBrainsMono',
              fontSize: 11,
              color: AppColors.textDisabled,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildKpis() {
    return GlassCard(
      enableBlur: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        _kpiBox('${_itens.length}', 'Divergências', AppColors.amber),
        _kpiDivider(),
        _kpiBox('$_totalFaltas', 'Un. Faltando', AppColors.red),
        _kpiDivider(),
        _kpiBox('$_totalSobras', 'Un. Sobrando', AppColors.amber),
      ]),
    ).animate().fadeIn(duration: 500.ms, delay: 80.ms);
  }

  Widget _kpiBox(String value, String label, Color color) {
    return Expanded(
      child: Column(children: [
        Text(value, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textMuted), textAlign: TextAlign.center),
      ]),
    );
  }

  Widget _kpiDivider() => Container(width: 1, height: 36, color: AppColors.surfaceBorder);

  List<Widget> _buildGrupos() {
    final grupos = _porCooperado;
    final widgets = <Widget>[];
    var idx = 0;
    for (final entry in grupos.entries) {
      final cooperado = entry.key;
      final itens = entry.value;
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.empresaColor(cooperado == '(sem cooperado)' ? '' : cooperado),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              cooperado,
              style: TextStyle(
                fontFamily: 'Outfit', fontSize: 13, fontWeight: FontWeight.w700,
                color: AppColors.empresaColor(cooperado == '(sem cooperado)' ? '' : cooperado),
              ),
            ),
            const SizedBox(width: 6),
            Text('(${itens.length})', style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          ]),
        ).animate().fadeIn(duration: 300.ms, delay: (idx * 20).clamp(0, 400).ms),
      );
      for (final item in itens) {
        widgets.add(
          _DivergenciaTile(item: item, onResolver: () => _resolver(item))
              .animate()
              .fadeIn(duration: 200.ms, delay: (idx * 15).clamp(0, 400).ms),
        );
        widgets.add(const SizedBox(height: 6));
        idx++;
      }
    }
    return widgets;
  }
}

// ── Tile ─────────────────────────────────────────────────────────────────────

class _DivergenciaTile extends StatelessWidget {
  final DivergenciaItem item;
  final VoidCallback onResolver;

  const _DivergenciaTile({required this.item, required this.onResolver});

  @override
  Widget build(BuildContext context) {
    final color = item.isFalta ? AppColors.red : AppColors.amber;
    final sinal = item.isFalta ? '−' : '+';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(
              item.produto,
              style: const TextStyle(fontFamily: 'Outfit', fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color.withOpacity(0.4)),
            ),
            child: Text(
              '$sinal${item.delta.abs()}',
              style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 15, fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text(item.categoria, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
          if (item.codigo.isNotEmpty) ...[
            const Text(' · ', style: TextStyle(fontSize: 10, color: AppColors.textDisabled)),
            Text(item.codigo, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: AppColors.textDisabled)),
          ],
        ]),
        const SizedBox(height: 4),
        Row(children: [
          _infoChip('Sistema: ${item.qtdSistema}', AppColors.textMuted),
          const SizedBox(width: 6),
          _infoChip('Físico: ${item.qtdFisica}', color),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              item.isFalta ? 'FALTA' : 'SOBRA',
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: color, letterSpacing: 0.5),
            ),
          ),
          const Spacer(),
          GestureDetector(
            onTap: onResolver,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.green.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.green.withOpacity(0.3)),
              ),
              child: const Text('✓ Resolver', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.green)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _infoChip(String text, Color color) {
    return Text(text, style: TextStyle(fontFamily: 'JetBrainsMono', fontSize: 10, color: color));
  }
}
