import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/chat_and_filter_service.dart';

/// Isolated chat input bar that owns its own [TextEditingController] +
/// [FocusNode] + send-in-flight state, decoupled from the message list's
/// Firestore stream rebuilds.
///
/// Extracting the composer into a dedicated [StatefulWidget] guarantees that
/// when the message list stream emits, the keyboard resizes the Scaffold
/// (`resizeToAvoidBottomInset`), or any ancestor rebuilds, *only* this bar
/// maintains its isolated state — the [TextEditingController] and
/// [FocusNode] are created once in [initState] and disposed in [dispose],
/// so the input never loses focus / text / cursor position mid-typing and
/// the keyboard never "kicks out" the user.
///
/// The parent supplies the [bookingId], the sender display name, and the
/// [theme]; the bar handles the send lifecycle (validation, the
/// [ChatAndFilterService.sendChatMessage] call, the in-flight spinner, and
/// the success/error snackbar). On a successful send it invokes the optional
/// [onMessageSent] callback so the parent can scroll its own message list
/// to the bottom — the composer intentionally does NOT own a scroll
/// controller so the message-list scroll state stays with the list widget.
class ChatComposerBar extends StatefulWidget {
  final String bookingId;
  final ThemeController theme;

  /// Display name stamped on outgoing messages. Defaults to "Hunter" so the
  /// outfitter sees who they are negotiating with.
  final String senderName;

  /// Optional callback invoked after a message is successfully sent. The
  /// parent typically uses it to scroll its message list to the bottom.
  final VoidCallback? onMessageSent;

  const ChatComposerBar({
    super.key,
    required this.bookingId,
    required this.theme,
    this.senderName = 'Hunter',
    this.onMessageSent,
  });

  @override
  State<ChatComposerBar> createState() => _ChatComposerBarState();
}

class _ChatComposerBarState extends State<ChatComposerBar> {
  // Created ONCE in the State and disposed in dispose — never recreated
  // across parent rebuilds / keyboard insets / stream emissions.
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    // Capture the messenger before the async gap so a Snackbar still fires
    // even if this widget unmounts while the send is in flight.
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _isSending = true);
    try {
      await ChatAndFilterService.instance.sendChatMessage(
        bookingId: widget.bookingId,
        messageText: text,
        senderName: widget.senderName,
      );
      _controller.clear();
      widget.onMessageSent?.call();
    } catch (e) {
      if (messenger != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Failed to send message: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    // Wrap the input in a GestureDetector so an explicit tap requests focus
    // through our retained FocusNode, satisfying the platform's input-manager
    // view-target validation (some OEM keyboards/embedded text services reject
    // an implicit focus derived purely from a hit-test on the editable region).
    return GestureDetector(
      onTap: () => _focusNode.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Expanded(
            child: TextField(
              // Stable key so the element identity persists across ancestor
              // rebuilds (defense-in-depth on top of the isolated State).
              key: const ValueKey('chatComposerBar'),
              controller: _controller,
              focusNode: _focusNode,
              autofocus: false,
              scrollPadding: const EdgeInsets.only(bottom: 80),
              // Gracefully release focus on a tap outside the field without
              // triggering abrupt layout jumps from the keyboard inset.
              onTapOutside: (_) => _focusNode.unfocus(),
              style: TextStyle(color: theme.textColor),
              decoration: InputDecoration(
                hintText: 'Type a message...',
                hintStyle: TextStyle(color: theme.subtitleColor),
                filled: true,
                fillColor: theme.backgroundColor,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: theme.accentColor,
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: _isSending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white),
              onPressed: _isSending ? null : _sendMessage,
            ),
          ),
        ],
      ),
    );
  }
}
