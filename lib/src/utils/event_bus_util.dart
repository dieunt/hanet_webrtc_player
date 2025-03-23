// ignore_for_file: unnecessary_new, prefer_generic_function_type_aliases

import 'dart:async';
import 'package:event_bus/event_bus.dart';

/// A type alias for event callback functions
typedef EventCallback<T> = void Function(T event);

/// A utility class for managing event bus operations
///
/// This class provides a singleton instance for handling event bus operations
/// including subscribing to events, emitting events, and managing subscriptions.
class EventBusUtils {
  /// Private constructor to prevent direct instantiation
  EventBusUtils._internal() {
    _eventBus = EventBus();
  }

  /// The singleton instance of EventBusUtils
  static EventBusUtils get instance => _getInstance();

  /// The private instance field
  static late EventBusUtils _instance;

  /// Flag to track if instance has been created
  static bool _isInstanceCreated = false;

  /// The underlying EventBus instance
  late final EventBus _eventBus;

  /// Gets or creates the singleton instance
  static EventBusUtils _getInstance() {
    if (!_isInstanceCreated) {
      _instance = EventBusUtils._internal();
      _isInstanceCreated = true;
    }
    return _instance;
  }

  /// Subscribes to events of type T
  ///
  /// [callback] is the function to be called when an event of type T is received
  /// Returns a [StreamSubscription] that can be used to cancel the subscription
  StreamSubscription<T> on<T>(EventCallback<T> callback) {
    return _eventBus.on<T>().listen(callback);
  }

  /// Emits an event to all subscribers
  ///
  /// [event] is the event to be emitted
  void emit<T>(T event) {
    _eventBus.fire(event);
  }

  /// Cancels a subscription
  ///
  /// [subscription] is the subscription to be cancelled
  void off(StreamSubscription subscription) {
    subscription.cancel();
  }
}

/// Global instance of EventBusUtils for easy access
final eventBus = EventBusUtils.instance;
