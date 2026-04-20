class Event {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String location;
  final String imageUrl;
  final double price;
  final List<String> artists;
  final bool isVirtual;
  final bool isVipAvailable;
  final int ticketsSold;
  final int totalTickets;

  const Event({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.location,
    required this.imageUrl,
    required this.price,
    required this.artists,
    required this.isVirtual,
    required this.isVipAvailable,
    required this.ticketsSold,
    required this.totalTickets,
  });

  double get soldPercent {
    if (totalTickets <= 0) return 0;
    return (ticketsSold / totalTickets).clamp(0, 1);
  }

  bool get isSellingFast => soldPercent >= 0.25;
}
