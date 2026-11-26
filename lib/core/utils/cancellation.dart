class CancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;

  void throwIfCancelled(Object reason) {
    if (_cancelled) throw reason;
  }
}
