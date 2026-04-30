import 'package:flutter/material.dart';

import '../../../features/wallet/providers/wallet_provider.dart';
import '../../../features/wallet/services/gift_service.dart';
import '../../../features/wallet/widgets/send_gift_dialog.dart';
import '../../../features/ads/widgets/soft_paywall.dart';

/// WeAfrica Live Battle Gift Overlay
/// 
/// Shows gift button and handles coin deduction in real-time
class GiftOverlay extends StatefulWidget {
  const GiftOverlay({
    super.key,
    required this.battleId,
    required this.creatorId,
    required this.creatorName,
    required this.onGiftSent,
  });

  final String battleId;
  final String creatorId;
  final String creatorName;
  final Function(GiftItem gift, int cost)? onGiftSent;

  @override
  State<GiftOverlay> createState() => _GiftOverlayState();
}

class _GiftOverlayState extends State<GiftOverlay> {
  bool _isSending = false;

  Future<void> _sendGift(String giftId) async {
    final wallet = WalletProvider.instance;
    final gift = GiftService.instance.getGift(giftId);
    
    if (gift == null) return;
    
    // Check if can afford
    if (!wallet.canAfford(gift.coinCost)) {
      // Show soft paywall
      SoftPaywall.show(
        context: context,
        title: 'Send ${gift.name}',
        message: 'You need ${gift.coinCost} coins to send this gift to ${widget.creatorName}',
        coinsNeeded: gift.coinCost,
      );
      return;
    }
    
    setState(() => _isSending = true);
    
    // Send the gift
    final success = await wallet.sendGift(
      creatorId: widget.creatorId,
      giftId: giftId,
      battleId: widget.battleId,
    );
    
    setState(() => _isSending = false);
    
    if (success) {
      widget.onGiftSent?.call(gift, gift.coinCost);
      
      // Show confirmation
      _showGiftAnimation(gift);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send gift. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showGiftAnimation(GiftItem gift) {
    // TODO: Show floating gift animation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Text(gift.emoji, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 12),
            Text('Sent ${gift.name} to ${widget.creatorName}!'),
          ],
        ),
        backgroundColor: const Color(0xFF1A2F1A),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showGiftSelector() {
    SendGiftDialog.show(
      context: context,
      artistName: widget.creatorName,
      userCoins: WalletProvider.instance.balance,
      onGiftSent: (gift) => _sendGift(gift.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 100,
      right: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Quick gift buttons
          _buildQuickGiftButton('clap', '👏', 10),
          const SizedBox(height: 8),
          _buildQuickGiftButton('fire', '🔥', 25),
          const SizedBox(height: 8),
          _buildQuickGiftButton('heart', '❤️', 50),
          const SizedBox(height: 12),
          
          // More gifts button
          GestureDetector(
            onTap: _isSending ? null : _showGiftSelector,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFE5C158)],
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFD4AF37).withValues(alpha: 0.4),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isSending)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Color(0xFF0A0A0A)),
                      ),
                    )
                  else ...[
                    const Icon(
                      Icons.card_giftcard,
                      color: Color(0xFF0A0A0A),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Gifts',
                      style: TextStyle(
                        color: Color(0xFF0A0A0A),
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickGiftButton(String giftId, String emoji, int cost) {
    final canAfford = WalletProvider.instance.canAfford(cost);
    
    return GestureDetector(
      onTap: canAfford && !_isSending ? () => _sendGift(giftId) : null,
      child: Opacity(
        opacity: canAfford ? 1.0 : 0.5,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: const Color(0xFF333333),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 6),
              Text(
                '$cost',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}