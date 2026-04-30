class RadioStationsService {
  const RadioStationsService();

  Future<List<Map<String, dynamic>>> listStations() async {
    return const <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'groove',
        'name': 'Groove Radio',
        'description': 'Live radio',
        'is_live': true,
      },
    ];
  }
}
