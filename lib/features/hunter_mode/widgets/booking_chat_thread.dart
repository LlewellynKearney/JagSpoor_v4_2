import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import 'chat_composer_bar.dart';

/// Standard hunter↔outfitter negotiation chat thread for a booking.
///
/// Renders the `bookings/{bookingId}/chats` subcollection as a stream of
/// bubbles with an inline composer. This is the canonical chat component used
/// by the Custom Package Builder (and reusable by any booking surface): it
/// captures the same look-and-feel as the marketplace / outfitter-dashboard
/// chat drawers while being self-contained — drop it onto any screen that has
/// a `bookingId` and a `ThemeController`.
///
/// The input box is the isolated [ChatComposerBar], which owns its own
/// [TextEditingController] + [FocusNode] + send state. Decoupling the
/// composer into its own [StatefulWidget] guarantees the message list's
/// Firestore stream rebuilds (and the keyboard's
/// `resizeToAvoidBottomInset` rebuilds) never recreate the controller or
/// drop keyboard focus — the composer state lives in its own element subtree
/// and is never torn down by a list re-emission.
///
/// Outgoing messages are written via [ChatAndFilterService.sendChatMessage],
/// which stamps `senderId` (current user) + `senderName`. The current user's
/// own messages render right-aligned (accent tint); the counterparty renders
/// left-aligned with a sender label.
class BookingChatThread extends StatefulWidget {
  final String bookingId;
  final ThemeController theme;

  /// Display name used for outgoing messages. Defaults to "Hunter" so the
  /// outfitter sees who they are negotiating with.
  final String senderName;

  /// Whether the thread starts expanded.
  final bool initiallyExpanded;

  const BookingChatThread({
    super.key,
    required this.bookingId,
    required this.theme,
    this.senderName = 'Hunter',
    this.initiallyExpanded = false,
  });

  @override
  State<BookingChatThread> createState() => _BookingChatThreadState();
}

class _BookingChatThreadState extends State<BookingChatThread> {
  bool _isExpanded = false;
  // Owns ONLY the message-list scroll state. The composer's
  // TextEditingController + FocusNode live in the isolated ChatComposerBar,
  // so a stream re-emit / keyboard resize never touches the input state.
  final ScrollController _chatScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  void dispose() {
    _chatScrollController.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  /// Invoked by [ChatComposerBar] after a message is sent — scrolls the
  /// message list to the bottom so the new bubble is visible.
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.accentColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          // Expandable header.
          InkWell(
            onTap: _toggleExpanded,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.chat_rounded,
                        color: theme.accentColor, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '💬 Chat & Negotiation Thread',
                      style: TextStyle(
                        color: theme.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: theme.accentColor,
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('bookings')
                          .doc(widget.bookingId)
                          .collection('chats')
                          .orderBy('timestamp', descending: false)
                          .snapshots(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                                color: Colors.green),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Error loading chat',
                                style: const TextStyle(color: Colors.red)),
                          );
                        }
                        final messages = snapshot.data?.docs ?? [];
                        if (messages.isEmpty) {
                          return Center(
                            child: Text(
                              'No messages yet — start the conversation!',
                              style: TextStyle(color: theme.subtitleColor),
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: _chatScrollController,
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index].data()
                                as Map<String, dynamic>;
                            final senderId =
                                msg['senderId'] as String? ?? '';
                            final isMe = senderId ==
                                FirebaseAuth.instance.currentUser?.uid;
                            return _BookingChatBubble(
                              text: msg['text'] as String? ?? '',
                              senderName:
                                  msg['senderName'] as String? ?? 'Unknown',
                              isMe: isMe,
                              theme: theme,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Isolated composer: owns its own TextEditingController +
                  // FocusNode, decoupled from this message-list stream so
                  // a stream re-emit / keyboard resize never drops focus.
                  ChatComposerBar(
                    bookingId: widget.bookingId,
                    theme: theme,
                    senderName: widget.senderName,
                    onMessageSent: _scrollToBottom,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BookingChatBubble extends StatelessWidget {
  final String text;
  final String senderName;
  final bool isMe;
  final ThemeController theme;

  const _BookingChatBubble({
    required this.text,
    required this.senderName,
    required this.isMe,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isMe
              ? theme.accentColor.withValues(alpha: 0.2)
              : theme.cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 16),
          ),
          border: Border.all(
            color: isMe
                ? theme.accentColor.withValues(alpha: 0.3)
                : theme.accentColor.withValues(alpha: 0.1),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe)
              Text(
                senderName,
                style: TextStyle(
                  color: theme.accentColor,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            const SizedBox(height: 2),
            Text(text, style: TextStyle(color: theme.textColor, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
