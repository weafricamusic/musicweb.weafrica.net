import '../models/live_gift.dart';
import 'gift_service.dart';

class LiveGiftCatalogService {
  Future<List<LiveGift>> fetchEnabledGifts() async {
    final catalog = await GiftService().listCatalog();

    return catalog
        .map(
          (g) => LiveGift(
            id: g.id,
            name: g.type.name,
            coinValue: g.coinValue,
            accessTier: g.accessTier,
          ),
        )
        .toList(growable: false);
  }
}
