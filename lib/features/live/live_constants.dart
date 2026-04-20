import 'package:flutter/material.dart';

class LiveConstants {
  static const int battleDurationShort = 180;
  static const int battleDurationMedium = 600;
  static const int battleDurationLong = 1800;
  static const int battleDurationEpic = 3600;
  
  static const String battleTypeFreestyle = 'freestyle';
  static const String battleTypeTrack = 'track';
  static const String battleTypeLive = 'live';
  static const String battleTypeProduction = 'production';
  
  static const Map<String, int> giftValues = {
    'rose': 5,
    'heart': 10,
    'crown': 50,
    'diamond': 100,
    'galaxy': 500,
    'rocket': 1000,
  };
  
  static const Color giftRoseColor = Color(0xFFFF69B4);
  static const Color giftHeartColor = Color(0xFFFF0000);
  static const Color giftCrownColor = Color(0xFFFFD700);
  static const Color giftDiamondColor = Color(0xFF00FFFF);
  static const Color giftGalaxyColor = Color(0xFF9B59B6);
  static const Color giftRocketColor = Color(0xFFFF6600);
  
  static const String battleChannelPrefix = 'battle:';
  static const String giftChannelPrefix = 'gift:';
  static const String chatChannelPrefix = 'chat:';
  
  static const int battleInviteTimeout = 60;
  static const int battleReadyTimeout = 30;
  static const int battleConnectTimeout = 10;
  
  static const double comboMultiplier = 0.1;
  static const int maxCombo = 10;
  
  static const Duration giftAnimationDuration = Duration(milliseconds: 800);
  static const Duration scoreUpdateDuration = Duration(milliseconds: 300);
  static const Duration battleStartCountdown = Duration(seconds: 3);
  
  static const String battleStatusWaiting = 'waiting';
  static const String battleStatusReady = 'ready';
  static const String battleStatusLive = 'live';
  static const String battleStatusEnded = 'ended';
  static const String battleStatusCancelled = 'cancelled';
  
  static const String inviteStatusPending = 'pending';
  static const String inviteStatusAccepted = 'accepted';
  static const String inviteStatusDeclined = 'declined';
  static const String inviteStatusExpired = 'expired';
  
  static const int defaultCoins = 100;
  static const int minCoinsForBattle = 50;
  static const int maxViewersPerBattle = 10000;
  
  static const double battleProgressBarHeight = 8.0;
  static const double battleAvatarSize = 48.0;
  static const double giftIconSize = 32.0;
  static const int maxTopGiftersDisplay = 5;
  
  static String getBattleDurationText(int seconds) {
    final minutes = seconds ~/ 60;
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    return '$hours hr ${minutes % 60} min';
  }
  
  static String getGiftName(String giftId) {
    return giftId[0].toUpperCase() + giftId.substring(1);
  }
  
  static Color getGiftColor(String giftId) {
    switch (giftId) {
      case 'rose': return giftRoseColor;
      case 'heart': return giftHeartColor;
      case 'crown': return giftCrownColor;
      case 'diamond': return giftDiamondColor;
      case 'galaxy': return giftGalaxyColor;
      case 'rocket': return giftRocketColor;
      default: return Colors.white;
    }
  }
  
  static int getGiftValue(String giftId) {
    return giftValues[giftId] ?? 0;
  }
}
