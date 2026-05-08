import 'package:flutter/material.dart';

import '../providers/wallet_provider.dart';
import '../services/coin_purchase_service.dart';
import '../widgets/coin_balance_card.dart';
import '../../ads/screens/watch_and_earn_screen.dart';

/// WeAfrica Wallet Screen
/// 
/// Shows coin balance, purchase options, and earnings
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _refreshBalance();
  }

  Future<void> _refreshBalance() async {
    await WalletProvider.instance.refreshBalance();
  }

  Future<void> _buyCoins(CoinPackage package) async {
    setState(() => _isLoading = true);
    
    final result = await CoinPurchaseService.instance.purchasePackage(package.id);
    
    if (result.success && result.coinsReceived != null) {
      // Add purchased coins to wallet
      await WalletProvider.instance.addCoinsFromAd(result.coinsReceived!);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Added ${result.coinsReceived} coins!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
    
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = WalletProvider.instance;
    
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        title: const Text('Wallet'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _refreshBalance,
        color: const Color(0xFFD4AF37),
        backgroundColor: const Color(0xFF1A1A1A),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Balance Card
              CoinBalanceCard(
                balance: wallet.balance,
                isLoading: wallet.isLoading,
                onAddCoins: () => _showAddCoinsSheet(context),
                onViewHistory: () => _showTransactionHistory(context),
              ),
              
              const SizedBox(height: 32),
              
              // Quick Actions
              _buildSectionTitle('Quick Actions'),
              const SizedBox(height: 16),
              _buildQuickActions(),
              
              const SizedBox(height: 32),
              
              // Buy Coins Section
              _buildSectionTitle('Buy Coins'),
              const SizedBox(height: 16),
              _buildCoinPackages(),
              
              if (wallet.isCreator) ...[
                const SizedBox(height: 32),
                _buildCreatorEarnings(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
            icon: Icons.videocam,
            title: 'Watch Ad',
            subtitle: 'Earn free coins',
            color: const Color(0xFFD4AF37),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WatchAndEarnScreen()),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionCard(
            icon: Icons.card_giftcard,
            title: 'Redeem',
            subtitle: 'Use promo code',
            color: const Color(0xFF666666),
            onTap: () => _showRedeemCodeDialog(),
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF333333)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoinPackages() {
    final packages = CoinPurchaseService.instance.packages;
    
    return Column(
      children: packages.map((package) {
        final isPopular = package.isPopular;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            gradient: isPopular
                ? const LinearGradient(
                    colors: [Color(0xFF1A1A1A), Color(0xFF2A1A0A)],
                  )
                : null,
            color: isPopular ? null : const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isPopular ? const Color(0xFFD4AF37) : const Color(0xFF333333),
              width: isPopular ? 2 : 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFD4AF37), Color(0xFFE5C158)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.monetization_on,
                color: Color(0xFF0A0A0A),
              ),
            ),
            title: Row(
              children: [
                Text(
                  '${package.totalCoins} Coins',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (package.bonusCoins > 0) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '+${package.bonusCoins} FREE',
                      style: const TextStyle(
                        color: Color(0xFFD4AF37),
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            subtitle: Text(
              '\$${package.priceUsd.toStringAsFixed(2)}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.2),
                fontSize: 14,
              ),
            ),
            trailing: ElevatedButton(
              onPressed: _isLoading ? null : () => _buyCoins(package),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFD4AF37),
                foregroundColor: const Color(0xFF0A0A0A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Buy'),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCreatorEarnings() {
    final earnings = WalletProvider.instance.creatorEarnings;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Creator Earnings'),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1A2F1A), Color(0xFF0F1F0F)],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFD4AF37).withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Available',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.2),
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '\$${earnings?.availableForWithdrawal.toStringAsFixed(2) ?? "0.00"}',
                    style: const TextStyle(
                      color: Color(0xFFD4AF37),
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Color(0xFF333333)),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildEarningStat(
                    'Total',
                    '\$${earnings?.totalEarnings.toStringAsFixed(2) ?? "0.00"}',
                  ),
                  _buildEarningStat(
                    'Pending',
                    '\$${earnings?.pendingEarnings.toStringAsFixed(2) ?? "0.00"}',
                  ),
                  _buildEarningStat(
                    'Withdrawn',
                    '\$${earnings?.totalWithdrawn.toStringAsFixed(2) ?? "0.00"}',
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showWithdrawalDialog(),
                  icon: const Icon(Icons.account_balance_wallet),
                  label: const Text('Withdraw'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD4AF37),
                    foregroundColor: const Color(0xFF0A0A0A),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEarningStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.2),
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  void _showAddCoinsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A1A),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Get More Coins',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.videocam, color: Color(0xFFD4AF37)),
              title: const Text(
                'Watch Ads',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Earn free coins',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF666666)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const WatchAndEarnScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.shopping_cart, color: Color(0xFFD4AF37)),
              title: const Text(
                'Buy Coins',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: Text(
                'Instant delivery',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.2)),
              ),
              trailing: const Icon(Icons.arrow_forward_ios, color: Color(0xFF666666)),
              onTap: () {
                Navigator.pop(context);
                // Scroll to packages
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showTransactionHistory(BuildContext context) {
    // TODO: Navigate to transaction history
  }

  void _showRedeemCodeDialog() {
    // TODO: Show promo code redemption
  }

  void _showWithdrawalDialog() {
    // TODO: Show withdrawal request dialog
  }
}