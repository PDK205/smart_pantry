import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pantry_provider.dart';
import 'settings_provider.dart';

class ChatMessage {
  final bool fromUser;
  final String text;
  final bool isError;
  const ChatMessage(this.fromUser, this.text, {this.isError = false});
}

class ChatState {
  final List<ChatMessage> messages;
  final bool sending;

  /// Đoạn trả lời đang stream (chưa hoàn tất).
  final String streaming;
  const ChatState({this.messages = const [], this.sending = false, this.streaming = ''});

  ChatState copyWith({List<ChatMessage>? messages, bool? sending, String? streaming}) => ChatState(
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        streaming: streaming ?? this.streaming,
      );
}

class ChatNotifier extends StateNotifier<ChatState> {
  ChatNotifier(this._ref) : super(const ChatState());
  final Ref _ref;
  StreamSubscription<String>? _sub;

  Future<void> send(String text) async {
    final t = text.trim();
    if (t.isEmpty || state.sending) return;
    final ai = _ref.read(pantryAiProvider);
    final gemini = _ref.read(geminiServiceProvider);
    if (ai == null || gemini == null) {
      state = state.copyWith(messages: [
        ...state.messages,
        ChatMessage(true, t),
        const ChatMessage(false, 'Bạn cần nhập Gemini API key trong Cài đặt để trò chuyện với Bếp trưởng AI.',
            isError: true),
      ]);
      return;
    }

    final history = [...state.messages.where((m) => !m.isError), ChatMessage(true, t)];
    state = state.copyWith(messages: [...state.messages, ChatMessage(true, t)], sending: true, streaming: '');

    // Gửi tối đa 20 tin gần nhất, bắt đầu bằng tin của người dùng.
    var recent = history.length > 20 ? history.sublist(history.length - 20) : history;
    while (recent.isNotEmpty && !recent.first.fromUser) {
      recent = recent.sublist(1);
    }
    final foods = _ref.read(pantryProvider).value ?? const [];
    final buffer = StringBuffer();
    final done = Completer<void>();

    _sub = gemini
        .streamText(
          system: ai.chatSystemPrompt(foods),
          contents: [
            for (final m in recent)
              {
                'role': m.fromUser ? 'user' : 'model',
                'parts': [
                  {'text': m.text}
                ],
              }
          ],
        )
        .listen(
          (chunk) {
            buffer.write(chunk);
            if (mounted) state = state.copyWith(streaming: buffer.toString());
          },
          onError: (Object e) {
            if (mounted) {
              state = state.copyWith(
                messages: [
                  ...state.messages,
                  if (buffer.isNotEmpty) ChatMessage(false, buffer.toString()),
                  ChatMessage(false, '$e', isError: true),
                ],
                sending: false,
                streaming: '',
              );
            }
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            if (mounted && state.sending) {
              state = state.copyWith(
                messages: [
                  ...state.messages,
                  ChatMessage(false, buffer.isEmpty ? '(Không có phản hồi)' : buffer.toString()),
                ],
                sending: false,
                streaming: '',
              );
            }
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    await done.future;
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    if (!state.sending) return;
    state = state.copyWith(
      messages: [
        ...state.messages,
        if (state.streaming.isNotEmpty) ChatMessage(false, state.streaming),
      ],
      sending: false,
      streaming: '',
    );
  }

  void clear() {
    _sub?.cancel();
    state = const ChatState();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) => ChatNotifier(ref));
