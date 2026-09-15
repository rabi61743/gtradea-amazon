import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';

/// Six boxes for an authenticator code, in the same style as the phone
/// verification page's code entry, so the two read as one system.
///
/// One real, invisible field sits over the boxes: it takes the keyboard,
/// accepts a pasted code and offers the platform's one-time-code autofill.
/// [onCompleted] fires when the sixth digit lands, so a pasted or autofilled
/// code submits without a second tap.
class TotpCodeField extends StatelessWidget {
  const TotpCodeField({
    super.key,
    required this.controller,
    this.onCompleted,
    this.enabled = true,
    this.autofocus = true,
  });

  static const length = 6;

  final TextEditingController controller;
  final ValueChanged<String>? onCompleted;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final text = controller.text;
        return LayoutBuilder(
          builder: (context, constraints) {
            // 46-point boxes when there is room, narrower on a small phone,
            // so six always fit on one line.
            final box = ((constraints.maxWidth - 5 * 8) / length).clamp(36.0, 48.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Container(
                        width: box,
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusControl,
                          ),
                          border: Border.all(
                            color: i < text.length
                                ? theme.colorScheme.primary.withValues(
                                    alpha: 0.55,
                                  )
                                : theme.colorScheme.outlineVariant,
                            width: i == text.length && enabled ? 1.6 : 1,
                          ),
                        ),
                        child: Text(
                          i < text.length ? text[i] : '',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Positioned.fill(
                  child: Semantics(
                    label: 'Authenticator code',
                    child: TextField(
                      controller: controller,
                      enabled: enabled,
                      autofocus: autofocus,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(length),
                      ],
                      onChanged: (value) {
                        if (value.length == length) onCompleted?.call(value);
                      },
                      showCursor: false,
                      enableInteractiveSelection: false,
                      style: const TextStyle(
                        color: Colors.transparent,
                        fontSize: 1,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        counterText: '',
                        filled: false,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
