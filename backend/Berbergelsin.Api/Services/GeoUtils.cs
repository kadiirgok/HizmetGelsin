namespace Berbergelsin.Api.Services;

public static class GeoUtils
{
    /// <summary>İki koordinat arası metre cinsinden haversine mesafesi.
    /// (Bellekte NTS Point.Distance derece döndürdüğü için kullanılır.)</summary>
    public static double DistanceMeters(double lat1, double lng1, double lat2, double lng2)
    {
        const double r = 6371000; // dünya yarıçapı (m)
        var dLat = ToRad(lat2 - lat1);
        var dLng = ToRad(lng2 - lng1);
        var a = Math.Sin(dLat / 2) * Math.Sin(dLat / 2)
              + Math.Cos(ToRad(lat1)) * Math.Cos(ToRad(lat2))
              * Math.Sin(dLng / 2) * Math.Sin(dLng / 2);
        return 2 * r * Math.Asin(Math.Sqrt(a));
    }

    /// <summary>Şehir içi ~25 km/s ortalama hızla tahmini varış süresi (dk).</summary>
    public static int EtaMinutes(double distanceMeters)
        => Math.Max(1, (int)Math.Ceiling(distanceMeters / 416.0)); // 25 km/h ≈ 416 m/dk

    private static double ToRad(double deg) => deg * Math.PI / 180.0;
}
