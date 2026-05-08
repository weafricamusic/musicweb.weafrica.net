
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../providers/ads_provider.dart';
import '../services/banner_ad_service.dart';

/// WeAfrica Music Banner Ad Widget
/// 
/// Shows banner ad for free users, hidden for premium
class WeAfricaBannerAd extends StatefulWidget {
  const WeAfricaBannerAd({
    super.key,
    this.onAdLoaded,
    this.onAdFailed,
  });

  final VoidCallback? onAdLoaded;
  final VoidCallback? onAdFailed;

  @override
  State<WeAfricaBannerAd> createState() => _WeAfricaBannerAdState();
}

class _WeAfricaBannerAdState extends State<WeAfricaBannerAd> {
  BannerAd? _bannerAd;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    if (kIsWeb) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      widget.onAdFailed?.call();
      return;
    }

    final ad = await BannerAdService.instance.createBannerAd();
    
    if (mounted) {
      setState(() {
        _bannerAd = ad;
        _isLoading = false;
        _hasError = ad == null;
      });

      if (ad != null) {
        widget.onAdLoaded?.call();
      } else {
        widget.onAdFailed?.call();
      }
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Don't show for premium users
    if (AdsProvider.instance.isPremium) {
      return const SizedBox.shrink();
    }

    // Don't show on web
    if (kIsWeb) {
      return const SizedBox.shrink();
    }

    // Show loading or error state
    if (_isLoading || _hasError || _bannerAd == null) {
      return Container(
        height: 50,
        color: Colors.transparent,
      );
    }

    return Container(
      height: 50,
      width: double.infinity,
      color: const Color(0xFF1A2F1A), // WeAfrica dark green
      child: AdWidget(ad: _bannerAd!),
    );
  }
}