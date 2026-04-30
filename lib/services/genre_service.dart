import 'package:supabase_flutter/supabase_flutter.dart';

class GenreService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<String>> fetchGenres() async {
    try {
      final response = await _supabase
          .from('genres')
          .select('name')
          .eq('is_active', true)
          .order('name');

      return (response as List)
          .map((genre) => genre['name'].toString())
          .toList();
    } catch (e) {
      print('Error fetching genres: $e');
      return ['All', 'Music']; // fallback
    }
  }
}
