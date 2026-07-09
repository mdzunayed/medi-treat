# Notification sounds

Drop the audio asset(s) here. The notification + chat providers load:

- `notification_chime.mp3` — played when a new notification arrives in the
  foreground (see `lib/features/notifications/providers/notification_provider.dart`).
- `message_pop.mp3` — played when a new chat message arrives over the
  socket (see `lib/features/chat/providers/chat_provider.dart`).

Keep clips short (≤500 ms) and normalised so they don't startle users
during quiet rooms. The providers play through `audioplayers` in
`PlayerMode.lowLatency` mode, so the file should be small enough to live
in memory comfortably (a 50–100 KB mp3 is plenty).
