import 'package:flutter/material.dart';

class PPTopBar extends StatelessWidget {
  const PPTopBar({super.key, required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 18,
          color: const Color(0xFF6049E3),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: _WindowControls(compact: compact),
        ),
        Container(
          color: const Color(0xFFE3E3EA),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              if (!compact) const Spacer(),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 873),
                  child: const _SearchInput(),
                ),
              ),
              const Spacer(),
              _ActionChip(
                label: 'Notifications',
                icon: Icons.notifications_none,
                color: Colors.white,
                textColor: const Color(0xFF3C3C3C),
              ),
              const SizedBox(width: 8),
              Container(
                width: 82,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFAFFFA9),
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.cloud,
                  size: 24,
                  color: Color(0xFF3BBE3D),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchInput extends StatelessWidget {
  const _SearchInput();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: TextField(
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF3C3C3C),
          height: 1.0,
        ),
        cursorColor: const Color(0xFF5E5E5E),
        cursorWidth: 1.2,
        cursorHeight: 10,
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          hintText: 'Search Company',
          hintStyle: const TextStyle(fontSize: 11, color: Color(0xFF7D7D7D)),
          prefixIcon: const Icon(
            Icons.search,
            size: 14,
            color: Color(0xFF6E6E6E),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 24,
            minHeight: 24,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.only(top: 6, right: 10, bottom: 6),
          filled: true,
          fillColor: const Color(0xFFF8F8F8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFD5D5D5)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: const BorderSide(color: Color(0xFFD5D5D5)),
          ),
        ),
      ),
    );
  }
}

class _WindowControls extends StatelessWidget {
  const _WindowControls({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (!compact) ...const [
          Icon(Icons.remove, size: 12, color: Colors.white70),
          SizedBox(width: 8),
          Icon(Icons.check_box_outline_blank, size: 10, color: Colors.white70),
          SizedBox(width: 8),
        ],
        const Icon(Icons.close, size: 12, color: Colors.white70),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.textColor,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E8E8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: textColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
