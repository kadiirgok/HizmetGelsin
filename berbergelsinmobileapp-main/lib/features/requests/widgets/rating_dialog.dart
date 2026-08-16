import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// Yıldız satırı (salt görüntüleme).
class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.rating, this.size = 16});
  final double rating;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final filled = rating >= i + 0.75;
        final half = !filled && rating >= i + 0.25;
        return Icon(
          filled
              ? Icons.star_rounded
              : half
              ? Icons.star_half_rounded
              : Icons.star_outline_rounded,
          size: size,
          color: const Color(0xFFF5A623),
        );
      }),
    );
  }
}

/// Puanlama dialog'u.
/// - Sadece puan verilebilir (yorum zorunlu değil)
/// - Yorum yazılırsa puan zorunlu olur
/// - "Atla" ile ikisi de boş geçilebilir (null döner)
/// - "Gönder" ile (score, comment) döner
Future<({int score, String? comment})?> showRatingDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  int initialScore = 0,
  String? initialComment,
  int maxLength = 600,
}) {
  return showDialog<({int score, String? comment})>(
    context: context,
    builder: (context) => _RatingDialog(
      title: title,
      subtitle: subtitle,
      initialScore: initialScore,
      initialComment: initialComment,
      maxLength: maxLength,
    ),
  );
}

class _RatingDialog extends StatefulWidget {
  const _RatingDialog({
    required this.title,
    this.subtitle,
    required this.initialScore,
    this.initialComment,
    required this.maxLength,
  });
  final String title;
  final String? subtitle;
  final int initialScore, maxLength;
  final String? initialComment;

  @override
  State<_RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<_RatingDialog> {
  late int _score;
  late final TextEditingController _commentController;

  bool get _hasComment => _commentController.text.trim().isNotEmpty;
  bool get _canSubmit => _score > 0 || !_hasComment;

  @override
  void initState() {
    super.initState();
    _score = widget.initialScore;
    _commentController = TextEditingController(text: widget.initialComment);
    _commentController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        widget.title,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.subtitle != null) ...[
            Text(
              widget.subtitle!,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
          ],
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                return IconButton(
                  onPressed: () => setState(() => _score = i + 1),
                  iconSize: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  icon: Icon(
                    _score > i
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: const Color(0xFFF5A623),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            maxLines: 3,
            maxLength: widget.maxLength,
            decoration: InputDecoration(
              hintText: 'Yorumunuz (isteğe bağlı)',
              errorText: _hasComment && _score == 0
                  ? 'Yorum yazmak için puan vermelisiniz'
                  : null,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(
            'Atla',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: _canSubmit
              ? () => Navigator.pop(context, (
                  score: _score,
                  comment: _hasComment
                      ? _commentController.text.trim()
                      : null,
                ))
              : null,
          child: const Text('Gönder'),
        ),
      ],
    );
  }
}
