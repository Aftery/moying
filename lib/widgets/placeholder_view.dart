import 'package:flutter/material.dart';

import '../config/app_palette.dart';

/// 统一的占位空态视图（书籍/电影/个人页复用）
class PlaceholderView extends StatelessWidget {
  const PlaceholderView({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                gradient: context.colors.readingGradient,
                borderRadius: BorderRadius.circular(28),
              ),
              child: Icon(icon, color: Colors.white, size: 46),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style:  TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.colors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              description,
              textAlign: TextAlign.center,
              style:  TextStyle(
                fontSize: 14,
                height: 1.6,
                color: context.colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
