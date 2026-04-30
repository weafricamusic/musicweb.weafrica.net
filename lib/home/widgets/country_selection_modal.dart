import 'package:flutter/material.dart';
import '../../app/theme/weafrica_colors.dart';

/// Modal bottom sheet for selecting African countries by region
class CountrySelectionModal extends StatelessWidget {
  final Function(String?) onCountrySelected;
  final String? selectedCountry;

  const CountrySelectionModal({
    super.key,
    required this.onCountrySelected,
    this.selectedCountry,
  });

  // Country data organized by region
  static const Map<String, List<String>> countriesByRegion = {
    'WEST AFRICA': [
      'Nigeria',
      'Ghana',
      'Senegal',
      'Ivory Coast',
      'Mali',
      'Burkina Faso',
      'Guinea',
      'Sierra Leone',
      'Liberia',
      'Togo',
      'Benin',
      'Niger',
      'Gambia',
      'Guinea-Bissau',
      'Cabo Verde',
    ],
    'EAST AFRICA': [
      'Kenya',
      'Tanzania',
      'Uganda',
      'Ethiopia',
      'Rwanda',
      'Burundi',
      'South Sudan',
      'Somalia',
      'Djibouti',
      'Eritrea',
      'Seychelles',
      'Comoros',
      'Mauritius',
    ],
    'SOUTHERN AFRICA': [
      'South Africa',
      'Zambia',
      'Zimbabwe',
      'Malawi',
      'Mozambique',
      'Botswana',
      'Namibia',
      'Eswatini',
      'Lesotho',
      'Angola',
    ],
    'CENTRAL AFRICA': [
      'DRC',
      'Cameroon',
      'Gabon',
      'Congo',
      'Central African Republic',
      'Chad',
      'Equatorial Guinea',
      'Sao Tome and Principe',
    ],
    'NORTH AFRICA': [
      'Egypt',
      'Morocco',
      'Algeria',
      'Tunisia',
      'Libya',
      'Sudan',
    ],
  };

  // Get all countries as a flat list
  static List<String> get allCountries {
    return countriesByRegion.values.expand((c) => c).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0B0617),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Choose Country',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => onCountrySelected(null),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white70,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              onChanged: (value) {
                // TODO: Implement search filtering
              },
              decoration: InputDecoration(
                hintText: 'Search countries...',
                prefixIcon: const Icon(Icons.search, color: Colors.white54),
                filled: true,
                fillColor: Colors.white10,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              style: const TextStyle(color: Colors.white),
            ),
          ),

          const SizedBox(height: 16),

          // All Africa reset option
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildAllAfricaOption(context),
          ),

          const Divider(color: Colors.white10, height: 1),

          // Country list by region
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: countriesByRegion.length,
              itemBuilder: (context, regionIndex) {
                final region = countriesByRegion.keys.elementAt(regionIndex);
                final countries = countriesByRegion[region]!;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Region header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        region,
                        style: const TextStyle(
                          color: WeAfricaColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    // Country items
                    ...countries.map((country) => _buildCountryItem(country, context)),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllAfricaOption(BuildContext context) {
    final isSelected = selectedCountry == null;
    return InkWell(
      onTap: () => onCountrySelected(null),
          child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? WeAfricaColors.gold.withValues(alpha: 0.15) : null,
          borderRadius: BorderRadius.circular(12),
          border: isSelected ? Border.all(color: WeAfricaColors.gold.withValues(alpha: 0.5)) : null,
        ),
        child: Row(
          children: [
            const Text('🌍', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'All Africa',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: WeAfricaColors.gold, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCountryItem(String country, BuildContext context) {
    final isSelected = selectedCountry == country;
    
    return InkWell(
      onTap: () => onCountrySelected(country),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Country emoji placeholder (you could add flag emojis)
            Text(
              _getCountryFlag(country),
              style: const TextStyle(fontSize: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                country,
                style: TextStyle(
                  color: isSelected ? WeAfricaColors.gold : Colors.white,
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: WeAfricaColors.gold, size: 20),
          ],
        ),
      ),
    );
  }

  String _getCountryFlag(String country) {
    // Simple flag emoji mapping for common countries
    const flags = {
      'Nigeria': '🇳🇬',
      'Ghana': '🇬🇭',
      'South Africa': '🇿🇦',
      'Kenya': '🇰🇪',
      'Tanzania': '🇹🇿',
      'Uganda': '🇺🇬',
      'Ethiopia': '🇪🇹',
      'Egypt': '🇪🇬',
      'Morocco': '🇲🇦',
      'Algeria': '🇩🇿',
      'Tunisia': '🇹🇳',
      'Zambia': '🇿🇲',
      'Zimbabwe': '🇿🇼',
      'Malawi': '🇲🇼',
      'Mozambique': '🇲🇿',
      'Botswana': '🇧🇼',
      'Namibia': '🇳🇦',
      'DRC': '🇨🇩',
      'Cameroon': '🇨🇲',
      'Senegal': '🇸🇳',
      'Ivory Coast': '🇨🇮',
      'Angola': '🇦🇴',
      'Rwanda': '🇷🇼',
      'Eswatini': '🇸🇿',
      'Lesotho': '🇱🇸',
      'Gabon': '🇬🇦',
      'Libya': '🇱🇾',
      'Sudan': '🇸🇩',
    };
    return flags[country] ?? '🌍';
  }
}