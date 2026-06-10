class _MetricCard extends StatefulWidget {
  final String label;
  final double value;
  final String unit;
  final Color color;
  final IconData icon;
  final bool isRunning;

  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
    required this.icon,
    this.isRunning = false,
  });

  @override
  State<_MetricCard> createState() => _MetricCardState();
}

class _MetricCardState extends State<_MetricCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    if (widget.isRunning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(_MetricCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRunning && !oldWidget.isRunning) {
      _controller.repeat();
    } else if (!widget.isRunning && oldWidget.isRunning) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cardContent = Container(
      width: 160,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: widget.color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: widget.color.withValues(alpha: 0.8),
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${widget.value} ${widget.unit}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );

    if (!widget.isRunning) return cardContent;

    return Container(
      width: 160,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
      ),
      child: Stack(
        children: [
          cardContent,
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return FractionallySizedBox(
                  widthFactor: 0.4,
                  alignment: Alignment(-1.5 + (_controller.value * 3.0), 0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.0),
                          widget.color.withValues(alpha: 0.15),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(widget.color.withValues(alpha: 0.5)),
            ),
          ),
        ],
      ),
    );
  }
}
