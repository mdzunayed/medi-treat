import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/support_config.dart';
import '../../../core/models/assigned_doctor.dart';
import '../../../core/theme/mt_colors.dart';
import '../../../core/theme/mt_text_styles.dart';
import '../../../core/widgets/initials_avatar.dart';
import '../../../core/widgets/vitals_grid.dart';
import '../models/message_model.dart';
import '../providers/chat_provider.dart';

// Re-export the shared [PatientVitals] + [VitalsGrid] so existing
// call-sites (`ChatScreen(patientVitals: …)`) keep compiling without
// importing `core/widgets/vitals_grid.dart` themselves.
export '../../../core/widgets/vitals_grid.dart' show PatientVitals, VitalsGrid;

/// Which side of the conversation is rendering. Drives the context
/// sidebar (doctor sees patient vitals, patient sees the assigned-doctor
/// credential card) and the role-specific app bar action.
enum ChatRole { patient, doctor }

/// Premium real-time consultation console. Responsive: a single column
/// on mobile (< 768 px) and a 65/35 split with a fixed context sidebar
/// on desktop / web. Powered by [chatProvider] — same as the original
/// surface, only the visual shell changes.
class ChatScreen extends ConsumerStatefulWidget {
  final String appointmentId;
  final String currentUserId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;
  final String? otherUserSubtitle;

  /// Which dashboard is showing this chat. Defaults to patient.
  final ChatRole role;

  /// Patient view → populated assigned doctor for the sidebar credential
  /// card. Optional; the sidebar gracefully degrades when absent.
  final AssignedDoctor? assignedDoctor;

  // ---- Doctor view sidebar inputs (all optional) -------------------------

  /// Free-text patient address shown on the doctor's sidebar map card.
  final String? patientAddress;

  /// Patient phone for the "Call Patient" quick-action button on the
  /// doctor sidebar.
  final String? patientPhone;

  /// Service title (e.g. "Post-surgery home care") rendered as the
  /// sidebar header subtitle.
  final String? careType;

  /// Latest vitals snapshot — drives the BP / Temp / SpO₂ tile row on
  /// the doctor sidebar. Defaults to `PatientVitals.empty`.
  final PatientVitals patientVitals;

  const ChatScreen({
    super.key,
    required this.appointmentId,
    required this.currentUserId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatarUrl,
    this.otherUserSubtitle,
    this.role = ChatRole.patient,
    this.assignedDoctor,
    this.patientAddress,
    this.patientPhone,
    this.careType,
    this.patientVitals = PatientVitals.empty,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  int _previousMessageCount = 0;

  /// Anything ≥ this width gets the split-pane layout.
  static const double _desktopBreakpoint = 768;

  /// Center-constrained chat thread cap on wide screens.
  static const double _chatColumnMaxWidth = 800;

  ChatArgs get _args => ChatArgs(
        appointmentId: widget.appointmentId,
        currentUserId: widget.currentUserId,
        otherUserId: widget.otherUserId,
      );

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  Future<void> _handleSend() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    await ref.read(chatProvider(_args).notifier).sendMessage(text);
    if (mounted) _inputFocus.requestFocus();
  }

  void _maybeScrollToBottom(int newCount) {
    if (newCount == _previousMessageCount) return;
    _previousMessageCount = newCount;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _callHelpline(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final uri = Uri(scheme: 'tel', path: SupportConfig.supportPhone);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Could not open the dialer. Call ${SupportConfig.supportPhoneDisplay} manually.',
          ),
        ),
      );
    }
  }

  void _logVitals(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Log vitals — coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider(_args));
    _maybeScrollToBottom(state.messages.length);

    return Scaffold(
      backgroundColor: MtColors.bg,
      appBar: _ChatAppBar(
        name: widget.otherUserName,
        avatarUrl: widget.otherUserAvatarUrl,
        subtitle: widget.otherUserSubtitle ?? 'Active Chat Support',
        isConnected: state.isConnected,
        role: widget.role,
        onLogVitals: () => _logVitals(context),
        onCallHelpline: () => _callHelpline(context),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= _desktopBreakpoint;
            final chatPane = _ChatPane(
              state: state,
              scrollController: _scrollController,
              currentUserId: widget.currentUserId,
              otherUserName: widget.otherUserName,
              otherUserAvatarUrl: widget.otherUserAvatarUrl,
              inputController: _inputController,
              inputFocus: _inputFocus,
              onSend: _handleSend,
              onRetry: () =>
                  ref.read(chatProvider(_args).notifier).refresh(),
              isDesktop: isDesktop,
              maxThreadWidth: _chatColumnMaxWidth,
            );

            if (!isDesktop) {
              return chatPane;
            }

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 65, child: chatPane),
                Container(width: 1, color: MtColors.line),
                Expanded(
                  flex: 35,
                  child: _ContextSidebar(
                    role: widget.role,
                    assignedDoctor: widget.assignedDoctor,
                    patientName: widget.role == ChatRole.doctor
                        ? widget.otherUserName
                        : null,
                    patientAddress: widget.patientAddress,
                    patientPhone: widget.patientPhone,
                    careType: widget.careType,
                    vitals: widget.patientVitals,
                    onCallHelpline: () => _callHelpline(context),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// App bar
// ---------------------------------------------------------------------------

class _ChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String name;
  final String? avatarUrl;
  final String subtitle;
  final bool isConnected;
  final ChatRole role;
  final VoidCallback onLogVitals;
  final VoidCallback onCallHelpline;

  const _ChatAppBar({
    required this.name,
    required this.avatarUrl,
    required this.subtitle,
    required this.isConnected,
    required this.role,
    required this.onLogVitals,
    required this.onCallHelpline,
  });

  @override
  Size get preferredSize => const Size.fromHeight(68);

  @override
  Widget build(BuildContext context) {
    final statusLabel = isConnected
        ? (role == ChatRole.doctor ? 'Active Sync' : 'Online & Connected')
        : 'Reconnecting…';
    final statusColor = isConnected
        ? (role == ChatRole.doctor ? const Color(0xFF3B82F6) : const Color(0xFF10B981))
        : MtColors.ink3;

    return AppBar(
      backgroundColor: MtColors.surface,
      foregroundColor: MtColors.ink,
      elevation: 0,
      titleSpacing: 0,
      title: Row(
        children: [
          _Avatar(name: name, url: avatarUrl, size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    _PulseDot(color: statusColor, pulsing: isConnected),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        statusLabel,
                        style: MtTextStyles.bodySm.copyWith(
                          color: MtColors.ink2,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (role == ChatRole.doctor)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: _RoleActionButton(
              icon: Icons.monitor_heart_outlined,
              label: 'Log Vitals',
              onPressed: onLogVitals,
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: _RoleActionButton(
              icon: Icons.support_agent,
              label: 'Call Helpline',
              onPressed: onCallHelpline,
            ),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: MtColors.line),
      ),
    );
  }
}

class _RoleActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _RoleActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: MtTextStyles.labelMd),
      style: ElevatedButton.styleFrom(
        backgroundColor: MtColors.brand,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  final Color color;
  final bool pulsing;
  const _PulseDot({required this.color, required this.pulsing});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.pulsing) {
      return Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
      );
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return SizedBox(
          width: 14,
          height: 14,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 14 * (0.6 + 0.4 * t),
                height: 14 * (0.6 + 0.4 * t),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.25 * (1 - t)),
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Chat pane (message list + floating input)
// ---------------------------------------------------------------------------

class _ChatPane extends StatelessWidget {
  final ChatState state;
  final ScrollController scrollController;
  final String currentUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;
  final TextEditingController inputController;
  final FocusNode inputFocus;
  final Future<void> Function() onSend;
  final Future<void> Function() onRetry;
  final bool isDesktop;
  final double maxThreadWidth;

  const _ChatPane({
    required this.state,
    required this.scrollController,
    required this.currentUserId,
    required this.otherUserName,
    required this.otherUserAvatarUrl,
    required this.inputController,
    required this.inputFocus,
    required this.onSend,
    required this.onRetry,
    required this.isDesktop,
    required this.maxThreadWidth,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: _CenterConstrained(
            maxWidth: isDesktop ? maxThreadWidth : double.infinity,
            child: _ChatBody(
              state: state,
              scrollController: scrollController,
              currentUserId: currentUserId,
              otherUserName: otherUserName,
              otherUserAvatarUrl: otherUserAvatarUrl,
              onRetry: onRetry,
            ),
          ),
        ),
        _CenterConstrained(
          maxWidth: isDesktop ? maxThreadWidth : double.infinity,
          child: state.canSendMessages
              ? _FloatingInputBar(
                  controller: inputController,
                  focusNode: inputFocus,
                  isSending: state.isSending,
                  onSend: onSend,
                )
              : const _ChatLockedFooter(),
        ),
      ],
    );
  }
}

class _CenterConstrained extends StatelessWidget {
  final double maxWidth;
  final Widget child;
  const _CenterConstrained({required this.maxWidth, required this.child});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Body / message list
// ---------------------------------------------------------------------------

class _ChatBody extends StatelessWidget {
  final ChatState state;
  final ScrollController scrollController;
  final String currentUserId;
  final String otherUserName;
  final String? otherUserAvatarUrl;
  final Future<void> Function() onRetry;

  const _ChatBody({
    required this.state,
    required this.scrollController,
    required this.currentUserId,
    required this.otherUserName,
    required this.otherUserAvatarUrl,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (state.status == ChatStatus.loading && state.messages.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: MtColors.brand),
      );
    }
    if (state.status == ChatStatus.error && state.messages.isEmpty) {
      return _ChatError(
        message: state.errorMessage ?? 'Could not load messages.',
        onRetry: onRetry,
      );
    }
    if (state.messages.isEmpty) {
      return const _EmptyConversation();
    }

    final messages = state.messages;
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final isMine = msg.isMine(currentUserId);

        final prev = index > 0 ? messages[index - 1] : null;
        final next =
            index + 1 < messages.length ? messages[index + 1] : null;

        // Group block detection — same sender within 2 minutes of the
        // previous row collapses spacing + repeated avatar/timestamp.
        final sameSenderAsPrev =
            prev != null && prev.senderId == msg.senderId;
        final closeToPrev = prev != null &&
            msg.timestamp.difference(prev.timestamp).inMinutes.abs() <= 2;
        final isGroupContinuation = sameSenderAsPrev && closeToPrev;

        final sameSenderAsNext =
            next != null && next.senderId == msg.senderId;
        final closeToNext = next != null &&
            next.timestamp.difference(msg.timestamp).inMinutes.abs() <= 2;
        final isGroupLast = !(sameSenderAsNext && closeToNext);

        final showDateChip = index == 0 ||
            !_isSameDay(messages[index - 1].timestamp, msg.timestamp);

        return Column(
          crossAxisAlignment:
              isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (showDateChip) _DateChip(date: msg.timestamp),
            _MessageBubble(
              message: msg,
              isMine: isMine,
              otherName: otherUserName,
              otherAvatarUrl: otherUserAvatarUrl,
              isGroupContinuation: isGroupContinuation,
              isGroupLast: isGroupLast,
            ),
            SizedBox(height: isGroupLast ? 12 : 3),
          ],
        );
      },
    );
  }

  static bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _DateChip extends StatelessWidget {
  final DateTime date;
  const _DateChip({required this.date});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday = now.year == date.year &&
        now.month == date.month &&
        now.day == date.day;
    final label = isToday
        ? 'Today'
        : DateFormat('EEE, MMM d').format(date.toLocal());
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: MtColors.surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: MtColors.line),
          ),
          child: Text(
            label,
            style: MtTextStyles.bodySm.copyWith(color: MtColors.ink3),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final String otherName;
  final String? otherAvatarUrl;
  final bool isGroupContinuation;
  final bool isGroupLast;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.otherName,
    required this.otherAvatarUrl,
    required this.isGroupContinuation,
    required this.isGroupLast,
  });

  @override
  Widget build(BuildContext context) {
    final timeLabel = DateFormat('h:mm a').format(message.timestamp.toLocal());

    // Corner radii per the spec — outgoing is square at bottom-right,
    // incoming is square at bottom-left. Continuation bubbles within a
    // block flatten the leading corner so the block reads as a single
    // visual unit.
    final topRadius = isGroupContinuation
        ? const Radius.circular(8)
        : const Radius.circular(18);
    final bubbleShape = BorderRadius.only(
      topLeft: isMine ? const Radius.circular(18) : topRadius,
      topRight: isMine ? topRadius : const Radius.circular(18),
      bottomLeft: Radius.circular(isMine ? 18 : 4),
      bottomRight: Radius.circular(isMine ? 4 : 18),
    );

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: _bubbleMaxWidth(context),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: isMine ? MtColors.brand : const Color(0xFFF1F5F9), // ultra-soft neutral
        borderRadius: bubbleShape,
        boxShadow: [
          BoxShadow(
            color: (isMine ? MtColors.brand : MtColors.ink)
                .withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.messageText,
            style: MtTextStyles.bodyMd.copyWith(
              color: isMine ? Colors.white : MtColors.ink,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          // Inline metadata strip — only on the last bubble in a block
          // so the visual doesn't clutter consecutive sends.
          if (isGroupLast) ...[
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeLabel,
                  style: MtTextStyles.bodySm.copyWith(
                    color: isMine
                        ? Colors.white.withValues(alpha: 0.78)
                        : MtColors.ink3,
                    fontSize: 10.5,
                    height: 1.0,
                  ),
                ),
                if (isMine) ...[
                  const SizedBox(width: 4),
                  _DeliveryTicks(isRead: message.isRead),
                ],
              ],
            ),
          ],
        ],
      ),
    );

    if (isMine) {
      return bubble;
    }

    // Incoming row: show the avatar only on the LAST bubble of a block
    // (the one that carries the timestamp). Earlier bubbles in the
    // block use a transparent spacer of the same width so the column
    // edges stay aligned.
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isGroupLast)
          _Avatar(name: otherName, url: otherAvatarUrl, size: 28)
        else
          const SizedBox(width: 28),
        const SizedBox(width: 8),
        Flexible(child: bubble),
      ],
    );
  }

  double _bubbleMaxWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w >= 768) {
      // On wide layouts the chat column is already capped at 800 px —
      // bubbles can comfortably take ~70 % of that.
      return 560;
    }
    return w * 0.74;
  }
}

/// Single-tick (sent) / double-tick (delivered/read) indicator. Read
/// state turns the ticks brand-blue so it stands out against the white
/// timestamp text inside an outgoing bubble.
class _DeliveryTicks extends StatelessWidget {
  final bool isRead;
  const _DeliveryTicks({required this.isRead});

  @override
  Widget build(BuildContext context) {
    final color = isRead ? const Color(0xFF60A5FA) : Colors.white.withValues(alpha: 0.78);
    return Icon(
      isRead ? Icons.done_all : Icons.done,
      size: 14,
      color: color,
    );
  }
}

// ---------------------------------------------------------------------------
// Floating pill input
// ---------------------------------------------------------------------------

class _FloatingInputBar extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSending;
  final Future<void> Function() onSend;

  const _FloatingInputBar({
    required this.controller,
    required this.focusNode,
    required this.isSending,
    required this.onSend,
  });

  @override
  State<_FloatingInputBar> createState() => _FloatingInputBarState();
}

class _FloatingInputBarState extends State<_FloatingInputBar> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncHasText);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncHasText);
    super.dispose();
  }

  void _syncHasText() {
    final next = widget.controller.text.trim().isNotEmpty;
    if (next != _hasText) {
      setState(() => _hasText = next);
    }
  }

  void _showAttachMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: MtColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MtColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                _AttachAction(
                  icon: Icons.location_on_outlined,
                  label: 'Share live location',
                  description: 'Send your current coordinates to the doctor.',
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Location share — coming soon')),
                    );
                  },
                ),
                _AttachAction(
                  icon: Icons.description_outlined,
                  label: 'Attach clinical report',
                  description: 'Photograph or upload a lab / prescription PDF.',
                  onTap: () {
                    Navigator.of(sheetCtx).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Attachments — coming soon')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSend = _hasText && !widget.isSending;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        14,
        8,
        14,
        12 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: MtColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: MtColors.line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              onPressed: () => _showAttachMenu(context),
              tooltip: 'Quick actions',
              icon: const Icon(
                Icons.add_circle_outline,
                color: MtColors.ink2,
              ),
            ),
            Expanded(
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: 'Type a medical update…',
                  hintStyle:
                      MtTextStyles.bodyMd.copyWith(color: MtColors.ink3),
                ),
              ),
            ),
            const SizedBox(width: 6),
            _AnimatedSendButton(
              enabled: canSend,
              isSending: widget.isSending,
              onTap: widget.onSend,
            ),
          ],
        ),
      ),
    );
  }
}

class _AttachAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  const _AttachAction({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: MtColors.brandSofter,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: MtColors.brand, size: 20),
      ),
      title: Text(label, style: MtTextStyles.labelLg),
      subtitle: Text(
        description,
        style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
      ),
    );
  }
}

class _AnimatedSendButton extends StatelessWidget {
  final bool enabled;
  final bool isSending;
  final Future<void> Function() onTap;
  const _AnimatedSendButton({
    required this.enabled,
    required this.isSending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final background = enabled ? MtColors.brand : MtColors.brandSofter;
    final iconColor = enabled ? Colors.white : MtColors.brand;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        boxShadow: enabled
            ? [
                BoxShadow(
                  color: MtColors.brand.withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 4),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? () => onTap() : null,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: isSending
                ? const SizedBox(
                    key: ValueKey('sending'),
                    width: 18,
                    height: 18,
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  )
                : Icon(
                    Icons.send,
                    key: const ValueKey('send'),
                    size: 20,
                    color: iconColor,
                  ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Context sidebar (desktop only)
// ---------------------------------------------------------------------------

class _ContextSidebar extends StatelessWidget {
  final ChatRole role;
  final AssignedDoctor? assignedDoctor;
  final String? patientName;
  final String? patientAddress;
  final String? patientPhone;
  final String? careType;
  final PatientVitals vitals;
  final VoidCallback onCallHelpline;

  const _ContextSidebar({
    required this.role,
    required this.assignedDoctor,
    required this.patientName,
    required this.patientAddress,
    required this.patientPhone,
    required this.careType,
    required this.vitals,
    required this.onCallHelpline,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MtColors.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              role == ChatRole.doctor ? 'PATIENT CONTEXT' : 'CONSULTATION',
              style: MtTextStyles.sectionLabel.copyWith(
                color: MtColors.ink3,
                letterSpacing: 1.1,
              ),
            ),
            const SizedBox(height: 12),
            if (role == ChatRole.doctor)
              _DoctorSidebar(
                patientName: patientName ?? '—',
                careType: careType,
                vitals: vitals,
                patientAddress: patientAddress,
                patientPhone: patientPhone,
              )
            else
              _PatientSidebar(
                doctor: assignedDoctor,
                onCallHelpline: onCallHelpline,
              ),
          ],
        ),
      ),
    );
  }
}

// ----- Doctor side: vitals + address ----------------------------------------

class _DoctorSidebar extends StatelessWidget {
  final String patientName;
  final String? careType;
  final PatientVitals vitals;
  final String? patientAddress;
  final String? patientPhone;

  const _DoctorSidebar({
    required this.patientName,
    required this.careType,
    required this.vitals,
    required this.patientAddress,
    required this.patientPhone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SidebarCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Avatar(name: patientName, url: null, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patientName,
                          style: MtTextStyles.labelLg
                              .copyWith(color: MtColors.ink),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if ((careType ?? '').isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            careType!,
                            style: MtTextStyles.bodySm
                                .copyWith(color: MtColors.ink2),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SidebarSectionTitle(label: 'Active vitals'),
        const SizedBox(height: 8),
        VitalsGrid(vitals: vitals),
        const SizedBox(height: 18),
        _SidebarSectionTitle(label: 'Home address'),
        const SizedBox(height: 8),
        _MapPlaceholderCard(address: patientAddress),
        if ((patientPhone ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          _SidebarPrimaryButton(
            icon: Icons.phone,
            label: 'Call patient',
            onPressed: () async {
              final uri = Uri(scheme: 'tel', path: patientPhone);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ],
    );
  }
}

class _MapPlaceholderCard extends StatelessWidget {
  final String? address;
  const _MapPlaceholderCard({required this.address});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3EE),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _MiniMapPainter()),
                ),
                const Center(
                  child: Icon(
                    Icons.location_on,
                    color: MtColors.brand,
                    size: 30,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: MtColors.line),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.place_outlined,
                    size: 16, color: MtColors.ink2),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    (address ?? '').isEmpty
                        ? 'Address shared at dispatch.'
                        : address!,
                    style: MtTextStyles.bodySm
                        .copyWith(color: MtColors.ink2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniMapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final block = Paint()..color = const Color(0xFFE0E9DF);
    final street = Paint()
      ..color = const Color(0xFFF6F8F5)
      ..strokeWidth = 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFEEF3EE));
    final cols = [0.18, 0.52, 0.82];
    final rows = [0.25, 0.58, 0.86];
    double prevY = 0;
    for (final ry in [...rows, 1.0]) {
      double prevX = 0;
      for (final rx in [...cols, 1.0]) {
        final rect = Rect.fromLTRB(
          prevX * size.width + 4,
          prevY * size.height + 4,
          rx * size.width - 4,
          ry * size.height - 4,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(4)),
          block,
        );
        prevX = rx;
      }
      prevY = ry;
    }
    for (final c in cols) {
      canvas.drawLine(
        Offset(c * size.width, 0),
        Offset(c * size.width, size.height),
        street,
      );
    }
    for (final r in rows) {
      canvas.drawLine(
        Offset(0, r * size.height),
        Offset(size.width, r * size.height),
        street,
      );
    }
  }

  @override
  bool shouldRepaint(_) => false;
}

// ----- Patient side: doctor credentials + emergency call --------------------

class _PatientSidebar extends StatelessWidget {
  final AssignedDoctor? doctor;
  final VoidCallback onCallHelpline;
  const _PatientSidebar({required this.doctor, required this.onCallHelpline});

  @override
  Widget build(BuildContext context) {
    final d = doctor;
    if (d == null) {
      return _SidebarCard(
        child: Text(
          'Your assigned doctor will appear here once the admin confirms the visit.',
          style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SidebarCard(
          child: Column(
            children: [
              _Avatar(name: d.fullName, url: d.profilePicture, size: 64),
              const SizedBox(height: 10),
              Text(
                d.fullName,
                textAlign: TextAlign.center,
                style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
              ),
              if (d.specialty.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  d.specialty,
                  textAlign: TextAlign.center,
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
              ],
              if (d.isVerifiedDoctor) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: MtColors.brandSofter,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: MtColors.brandSoft),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.verified,
                          size: 14, color: MtColors.brand),
                      const SizedBox(width: 4),
                      Text(
                        'Verified by Taafi',
                        style: MtTextStyles.bodySm.copyWith(
                          color: MtColors.brand,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        if ((d.bmdcLicense ?? '').isNotEmpty)
          _SidebarKeyValue(
            label: 'BMDC LICENSE',
            value: d.bmdcLicense!,
            icon: Icons.badge_outlined,
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _MiniStat(
                label: 'Experience',
                value: d.yearsExperience > 0 ? '${d.yearsExperience} yr' : '—',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniStat(
                label: 'Rating',
                value: d.rating > 0 ? d.rating.toStringAsFixed(1) : '—',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _MiniStat(
                label: 'Reviews',
                value: d.reviewCount > 0 ? '${d.reviewCount}' : '—',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if ((d.phone ?? '').isNotEmpty)
          _SidebarPrimaryButton(
            icon: Icons.phone,
            label: 'Call doctor',
            onPressed: () async {
              final uri = Uri(scheme: 'tel', path: d.phone);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        const SizedBox(height: 10),
        _SidebarSecondaryButton(
          icon: Icons.support_agent,
          label: 'Call 24/7 helpline',
          onPressed: onCallHelpline,
        ),
      ],
    );
  }
}

class _SidebarCard extends StatelessWidget {
  final Widget child;
  const _SidebarCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: MtColors.line),
      ),
      child: child,
    );
  }
}

class _SidebarSectionTitle extends StatelessWidget {
  final String label;
  const _SidebarSectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: MtTextStyles.sectionLabel.copyWith(
        color: MtColors.ink3,
        letterSpacing: 1.1,
      ),
    );
  }
}

class _SidebarKeyValue extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _SidebarKeyValue({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: MtColors.brandSofter,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: MtColors.brand, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: MtTextStyles.sectionLabel.copyWith(
                    color: MtColors.ink3,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: MtTextStyles.labelMd.copyWith(color: MtColors.ink),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: MtColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MtColors.line),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: MtTextStyles.bodySm.copyWith(
              color: MtColors.ink3,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarPrimaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _SidebarPrimaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: MtTextStyles.labelLg),
        style: ElevatedButton.styleFrom(
          backgroundColor: MtColors.brand,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }
}

class _SidebarSecondaryButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _SidebarSecondaryButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label, style: MtTextStyles.labelLg),
        style: OutlinedButton.styleFrom(
          foregroundColor: MtColors.brand,
          side: const BorderSide(color: MtColors.brand),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _Avatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  const _Avatar({required this.name, required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    final cleaned = name.replaceFirst(RegExp(r'^[Dd]r\.?\s+'), '');
    final src = url;
    if (src != null && src.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          src,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => InitialsAvatar(
            name: cleaned,
            size: size,
            backgroundColor: MtColors.brand,
            textColor: Colors.white,
          ),
        ),
      );
    }
    return InitialsAvatar(
      name: cleaned,
      size: size,
      backgroundColor: MtColors.brand,
      textColor: Colors.white,
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: const BoxDecoration(
                color: MtColors.brandSofter,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                size: 32,
                color: MtColors.brand,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'Start the conversation',
              style: MtTextStyles.h2.copyWith(color: MtColors.ink),
            ),
            const SizedBox(height: 6),
            Text(
              'Messages you send here are delivered instantly and stay '
              'attached to this appointment.',
              textAlign: TextAlign.center,
              style: MtTextStyles.bodyMd.copyWith(color: MtColors.ink2),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatError extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ChatError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 36,
              color: MtColors.ink3,
            ),
            const SizedBox(height: 12),
            Text(
              "Couldn't load conversation",
              style: MtTextStyles.labelLg.copyWith(color: MtColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: () => onRetry(),
              style: ElevatedButton.styleFrom(
                backgroundColor: MtColors.brand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Footer that replaces the floating input pane once the appointment
/// status flips to `completed` (or otherwise closed). Mirrors the
/// archived-chat lock-strip so the patient + provider both understand
/// the conversation is now read-only — they can still scroll the
/// transcript, just not append to it.
class _ChatLockedFooter extends StatelessWidget {
  const _ChatLockedFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: MtColors.surface,
        border: Border(top: BorderSide(color: MtColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(
        16,
        14,
        16,
        14 + MediaQuery.of(context).viewPadding.bottom,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: MtColors.brandSofter,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.lock_outline,
              size: 16,
              color: MtColors.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This visit has wrapped up.',
                  style: MtTextStyles.labelMd.copyWith(
                    color: MtColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'The conversation is now read-only. Open a new request to chat with a provider again.',
                  style: MtTextStyles.bodySm.copyWith(color: MtColors.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
