/// Client for the Hibira Chat API: [ChatClient] calls the user routes and
/// takes `chat.*` events from a signed-in `HibiraClient`;
/// [ChatConversation] and [ChatConversationList] keep a conversation and
/// the user's conversations live.
library;

export 'src/client.dart' show ChatClient, ChatException, ChatTokenProvider;
export 'src/conversation.dart' show ChatConversation, ChatConversationState;
export 'src/conversation_list.dart'
    show ChatConversationList, ChatConversationListState;
export 'src/events.dart'
    show
        ChatEvent,
        ChatMessageAdded,
        ChatMessageUpdated,
        ChatTyping,
        ChatRead,
        ChatConversationChanged,
        ChatLeft,
        ChatDeleted;
export 'src/models.dart'
    show
        Attachment,
        Conversation,
        ConversationPage,
        Member,
        Message,
        MessagePage,
        Report,
        SearchPage,
        SendResult;
