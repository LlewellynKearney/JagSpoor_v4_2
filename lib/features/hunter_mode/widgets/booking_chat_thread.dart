import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/theme/app_theme.dart';
import '../services/chat_and_filter_service.dart';

/// Standard hunter↔outfitter negotiation chat thread for a booking.
///
/// Renders the `bookings/{bookingId}/chats` subcollection as a stream of
/// bubbles with an inline composer. This is the canonical chat component used
/// by the Custom Package Builder (and reusable by any booking surface): it
/// captures the same look-and-feel as the marketplace / outfitter-dashboard
/// chat drawers while being self-contained — drop it onto any screen that has
/// a `bookingId` and a `ThemeController`.
///
/// Messages are written via [ChatAndFilterService.sendChatMessage], which
/// stamps `senderId` (current user) + `senderName`. The current user's own
/// messages render right-aligned (accent tint); the counterparty renders
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
  final TextEditingController _chatController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();
  // Retained FocusNode so the composer keeps keyboard focus across rebuilds
  // (the Scaffold resizes for the software keyboard, which can otherwise
  // drop focus / collapse the chat). Disposed in dispose().
  final FocusNode _chatFocusNode = FocusNode();
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
  }

  @override
  void dispose() {
    _chatController.dispose();
    _chatScrollController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
  }

  Future<void> _sendMessage() async {
    final text = _chatController.text.trim();
    if (text.isEmpty || _isSending) return;
    setState(() => _isSending = true);
    try {
      await ChatAndFilterService.instance.sendChatMessage(
        bookingId: widget.bookingId,
        messageText: text,
        senderName: widget.senderName,
      );
      _chatController.clear();
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_chatScrollController.hasClients) {
          _chatScrollController.animateTo(
            _chatScrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
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
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          // Stable key + retained FocusNode keep the composer
                          // mounted + focused across the Scaffold's keyboard
                          // inset rebuilds (prevents the keyboard "kick-out").
                          key: const ValueKey('bookingChatComposer'),
                          controller: _chatController,
                          focusNode: _chatFocusNode,
                          scrollPadding: const EdgeInsets.only(bottom: 80),
                          style: TextStyle(color: theme.textColor),
                          decoration: InputDecoration(
                            hintText: 'Type a message...',
                            hintStyle:
                                TextStyle(color: theme.subtitleColor),
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
                              : const Icon(Icons.send_rounded,
                                  color: Colors.white),
                          onPressed: _isSending ? null : _sendMessage,
                        ),
                      ),
                    ],
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
