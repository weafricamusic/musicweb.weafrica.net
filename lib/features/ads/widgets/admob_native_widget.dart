import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../../app/theme.dart';
import '../../../features/subscriptions/subscriptions_controller.dart';
import '../../../services/ads/admob_ads_service.dart';

class AdmobNativeWidget extends StatefulWidget {
  const AdmobNativeWidget({
    super.key,
    this.placement = 'feed',
    this.height = 120,
  });

  static const String factoryId = 'weafricaNative';

  final String placement;
  final double height;

  @override
  State<AdmobNativeWidget> createState() => _AdmobNativeWidgetState();
}

class _AdmobNativeWidgetState extends State<AdmobNativeWidget> {
  NativeAd? _ad;
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

    final ad = await AdmobAdsService.instance.createNative(
      factoryId: AdmobNativeWidget.factoryId,
      placement: widget.placement,
      listener: NativeAdListener(
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
          height: widget.height,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(8),
          child: AdWidget(ad: ad),
        );
      },
    );
  }
}
