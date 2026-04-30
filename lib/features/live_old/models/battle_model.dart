class BattleModel {
  const BattleModel({
    required this.id,
    required this.competitor1Id,
    required this.competitor2Id,
    required this.competitor1Name,
    required this.competitor2Name,
    required this.competitor1Type,
    required this.competitor2Type,
    required this.competitor1Score,
    required this.competitor2Score,
    required this.timeRemaining,
    this.winnerId,
  });

  final String id;
  final String competitor1Id;
  final String competitor2Id;
  final String competitor1Name;
  final String competitor2Name;
  final String competitor1Type;
  final String competitor2Type;
  final int competitor1Score;
  final int competitor2Score;
  final int timeRemaining;
  final String? winnerId;

  bool get isActive => timeRemaining > 0 && winnerId == null;
  bool get isUrgent => timeRemaining < 30;

  String? get winnerName {
    final w = winnerId;
    if (w == null) return null;
    return w == competitor1Name ? competitor1Name : competitor2Name;
  }
}
