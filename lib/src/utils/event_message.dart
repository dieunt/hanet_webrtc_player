/// Base class for all event messages
abstract class EventMessage {
  /// The message content
  final String message;

  /// Creates a new event message
  const EventMessage(this.message);

  /// Gets the message content
  String get msg => message;
}

/// Event message for received messages
class ReceiveMsgEvent extends EventMessage {
  /// Creates a new received message event
  const ReceiveMsgEvent(String message) : super(message);
}

/// Event message for deleted session messages
class DeleteSessionMsgEvent extends EventMessage {
  /// Creates a new deleted session message event
  const DeleteSessionMsgEvent(String message) : super(message);
}

/// Event message for new session messages
class NewSessionMsgEvent extends EventMessage {
  /// Creates a new session message event
  const NewSessionMsgEvent(String message) : super(message);
}

/// Event message for sending messages
class SendMsgEvent {
  /// The event type
  final String eventType;

  /// The event data
  final Map<String, dynamic> data;

  /// Creates a new send message event
  const SendMsgEvent(this.eventType, this.data);

  /// Gets the event type
  String get event => eventType;

  /// Gets the event data
  Map<String, dynamic> get eventData => data;
}
