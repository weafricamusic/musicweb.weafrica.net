import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../app/theme.dart';
import '../../../features/subscriptions/subscriptions_controller.dart';
import '../../../services/ads/admob_ads_service.dart';

class AdmobBannerWidget extends StatefulWidget {
  const AdmobBannerWidget({
    super.key,
    this.placement = 'home',
  });

  final String placement;

  @override
  State<AdmobBannerWidget> createState() => _AdmobBannerWidgetState();
}

class _AdmobBannerWidgetState extends State<AdmobBannerWidget> {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final adsEnabled = SubscriptionsController.instance.entitlements.effectiveAdsEnabled;
    if (!adsEnabled) return;

    final ad = await AdmobAdsService.instance.createBannerWithListener(
      placement: widget.placement,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (!mounted) return;
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
        },
      ),
    );

    if (!mounted) {
      ad?.dispose();
      return;
    }

    if (ad == null) return;

    setState(() => _ad = ad);
    await ad.load();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: SubscriptionsController.instance,
      builder: (context, _) {
        final adsEnabled = SubscriptionsController.instance.entitlements.effectiveAdsEnabled;
        if (!adsEnabled) return const SizedBox.shrink();

        final ad = _ad;
        if (ad == null || !_loaded) return const SizedBox.shrink();

        return Container(
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(8),
          child: SizedBox(
            width: ad.size.width.toDouble(),
            height: ad.size.height.toDouble(),
            child: AdWidget(ad: ad),
          ),
        );
      },
    );
  }
}
