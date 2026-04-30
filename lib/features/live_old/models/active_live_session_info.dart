class ActiveLiveSessionInfo {
  const ActiveLiveSessionInfo({
    required this.channelId,
    this.title,
    this.startedAt,
    this.lastHeartbeatAt,
  });

  final String channelId;
  final String? title;
  final DateTime? startedAt;
  final DateTime? lastHeartbeatAt;
}
