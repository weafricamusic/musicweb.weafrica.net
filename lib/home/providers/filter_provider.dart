import 'package:flutter/material.dart';

class FilterProvider with ChangeNotifier {
  // Current active filters
  String? _selectedCountry;
  String? _selectedGenre;
  
  // Country selection modal state
  bool _isCountryModalOpen = false;

  // Getters
  String? get selectedCountry => _selectedCountry;
  String? get selectedGenre => _selectedGenre;
  bool get isCountryModalOpen => _isCountryModalOpen;
  
  // Filter state indicators
  bool get hasActiveFilter => _selectedCountry != null || _selectedGenre != null;
  String? get activeFilterLabel {
    if (_selectedCountry != null) return _selectedCountry;
    if (_selectedGenre != null) return _selectedGenre;
    return null;
  }

  // Set country filter
  void setCountryFilter(String? country) {
    if (country == _selectedCountry) {
      // Toggle off if same country is selected
      _selectedCountry = null;
      _selectedGenre = null; // Clear genre when country is cleared
    } else {
      _selectedCountry = country;
      _selectedGenre = null; // Clear genre when country is selected
    }
    notifyListeners();
  }

  // Set genre filter
  void setGenreFilter(String? genre) {
    if (genre == _selectedGenre) {
      // Toggle off if same genre is selected
      _selectedGenre = null;
      _selectedCountry = null; // Clear country when genre is cleared
    } else {
      _selectedGenre = genre;
      _selectedCountry = null; // Clear country when genre is selected
    }
    notifyListeners();
  }

  // Clear all filters
  void clearFilters() {
    _selectedCountry = null;
    _selectedGenre = null;
    notifyListeners();
  }

  // Open/close country modal
  void openCountryModal() {
    _isCountryModalOpen = true;
    notifyListeners();
  }

  void closeCountryModal() {
    _isCountryModalOpen = false;
    notifyListeners();
  }

  // Check if a filter is active for UI highlighting
  bool isCountryActive(String country) => _selectedCountry == country;
  bool isGenreActive(String genre) => _selectedGenre == genre;
}