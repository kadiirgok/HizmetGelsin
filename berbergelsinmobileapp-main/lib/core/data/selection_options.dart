class SelectionCoordinate {
  const SelectionCoordinate(this.lat, this.lng);

  final double lat;
  final double lng;
}

class LocationOption {
  const LocationOption({
    required this.city,
    required this.district,
    required this.neighborhood,
    required this.lat,
    required this.lng,
  });

  final String city;
  final String district;
  final String neighborhood;
  final double lat;
  final double lng;
}

class ServiceSelectionOptions {
  const ServiceSelectionOptions._();

  static const categories = [
    'Tesisat',
    'Elektrik',
    'Tamir & Bakım',
    'Temizlik',
    'Nakliye',
    'Oto Servis',
    'Kuaför & Güzellik',
    'Sağlık & Bakım',
    'Özel Ders',
    'Organizasyon',
    'Evcil Hayvan',
    'Bahçe & Peyzaj',
    'Bilgisayar & Teknik Servis',
    'Beyaz Eşya',
    'İnşaat & Tadilat',
    'Diğer',
  ];

  static const locations = [
    LocationOption(
      city: 'İstanbul',
      district: 'Kadıköy',
      neighborhood: 'Caferağa',
      lat: 40.9877,
      lng: 29.0277,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Kadıköy',
      neighborhood: 'Rasimpaşa',
      lat: 40.9964,
      lng: 29.0238,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Kadıköy',
      neighborhood: 'Fenerbahçe',
      lat: 40.9742,
      lng: 29.0434,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Beşiktaş',
      neighborhood: 'Levent',
      lat: 41.0818,
      lng: 29.0124,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Beşiktaş',
      neighborhood: 'Etiler',
      lat: 41.0871,
      lng: 29.0357,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Beşiktaş',
      neighborhood: 'Ortaköy',
      lat: 41.0474,
      lng: 29.0256,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Üsküdar',
      neighborhood: 'Mimar Sinan',
      lat: 41.0234,
      lng: 29.0168,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Üsküdar',
      neighborhood: 'Altunizade',
      lat: 41.0215,
      lng: 29.0444,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Üsküdar',
      neighborhood: 'Çengelköy',
      lat: 41.0508,
      lng: 29.0519,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Bahçelievler',
      neighborhood: 'Yenibosna',
      lat: 40.9949,
      lng: 28.8355,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Bahçelievler',
      neighborhood: 'Şirinevler',
      lat: 40.9921,
      lng: 28.8479,
    ),
    LocationOption(
      city: 'İstanbul',
      district: 'Esenyurt',
      neighborhood: 'Cumhuriyet',
      lat: 41.0345,
      lng: 28.6801,
    ),
    LocationOption(
      city: 'Ankara',
      district: 'Çankaya',
      neighborhood: 'Kızılay',
      lat: 39.9208,
      lng: 32.8541,
    ),
    LocationOption(
      city: 'Ankara',
      district: 'Çankaya',
      neighborhood: 'Bahçelievler',
      lat: 39.9276,
      lng: 32.8234,
    ),
    LocationOption(
      city: 'Ankara',
      district: 'Çankaya',
      neighborhood: 'Oran',
      lat: 39.8467,
      lng: 32.8403,
    ),
    LocationOption(
      city: 'Ankara',
      district: 'Keçiören',
      neighborhood: 'Etlik',
      lat: 39.9806,
      lng: 32.8358,
    ),
    LocationOption(
      city: 'Ankara',
      district: 'Yenimahalle',
      neighborhood: 'Batıkent',
      lat: 39.9703,
      lng: 32.7045,
    ),
    LocationOption(
      city: 'İzmir',
      district: 'Konak',
      neighborhood: 'Alsancak',
      lat: 38.4382,
      lng: 27.1436,
    ),
    LocationOption(
      city: 'İzmir',
      district: 'Karşıyaka',
      neighborhood: 'Bostanlı',
      lat: 38.4563,
      lng: 27.0947,
    ),
    LocationOption(
      city: 'İzmir',
      district: 'Bornova',
      neighborhood: 'Kazımdirik',
      lat: 38.4621,
      lng: 27.2191,
    ),
    LocationOption(
      city: 'Bursa',
      district: 'Osmangazi',
      neighborhood: 'Heykel',
      lat: 40.1828,
      lng: 29.0665,
    ),
    LocationOption(
      city: 'Bursa',
      district: 'Nilüfer',
      neighborhood: 'Görükle',
      lat: 40.2239,
      lng: 28.8427,
    ),
    LocationOption(
      city: 'Antalya',
      district: 'Muratpaşa',
      neighborhood: 'Lara',
      lat: 36.8589,
      lng: 30.7553,
    ),
    LocationOption(
      city: 'Antalya',
      district: 'Konyaaltı',
      neighborhood: 'Liman',
      lat: 36.8491,
      lng: 30.6098,
    ),
  ];

  static List<String> get cities => _unique(locations.map((e) => e.city));

  static List<String> districtsFor(String? city) => _unique(
    locations
        .where((e) => city == null || city.isEmpty || e.city == city)
        .map((e) => e.district),
  );

  static List<String> neighborhoodsFor(String? city, String? district) =>
      _unique(
        locations
            .where((e) => city == null || city.isEmpty || e.city == city)
            .where(
              (e) =>
                  district == null ||
                  district.isEmpty ||
                  e.district == district,
            )
            .map((e) => e.neighborhood),
      );

  static SelectionCoordinate? coordinateFor(
    String? city,
    String? district,
    String? neighborhood,
  ) {
    final match = locations.where((e) {
      final cityOk = city == null || city.isEmpty || e.city == city;
      final districtOk =
          district == null || district.isEmpty || e.district == district;
      final neighborhoodOk =
          neighborhood == null ||
          neighborhood.isEmpty ||
          e.neighborhood == neighborhood;
      return cityOk && districtOk && neighborhoodOk;
    }).toList();
    if (match.isEmpty) return null;
    final selected = match.first;
    return SelectionCoordinate(selected.lat, selected.lng);
  }

  static String? validOrNull(List<String> options, String? value) {
    if (value == null || value.isEmpty) return null;
    return options.contains(value) ? value : null;
  }

  static List<String> _unique(Iterable<String> values) {
    final seen = <String>{};
    return [
      for (final value in values)
        if (seen.add(value)) value,
    ];
  }
}
