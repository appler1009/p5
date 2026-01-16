import CoreLocation
import Foundation

@MainActor
class GeocodingService {
  static let shared = GeocodingService()

  private var timer: Timer?
  private var isProcessing = false

  private init() {
    // Start the periodic geocoding timer
    startPeriodicGeocoding()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
  }

  private func startPeriodicGeocoding() {
    // Run every 60 seconds
    timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        await self?.processPendingGeocoding()
      }
    }
  }

  private func processPendingGeocoding() async {
    guard !isProcessing else { return }
    isProcessing = true

    var geocodedCount = 0

    do {
      // Get up to 50 items that have GPS but no geocode
      let itemsToGeocode = DatabaseManager.shared.getItemsNeedingGeocode(limit: 50)

      for item in itemsToGeocode {
        guard let gps = item.metadata?.gps else { continue }

        let location = CLLocation(latitude: gps.latitude, longitude: gps.longitude)
        let geocoder = CLGeocoder()

        do {
          let placemarks = try await geocoder.reverseGeocodeLocation(location)
          if let placemark = placemarks.first {
            // Create deduplicated geocode string
            var geocodeParts: [String] = []
            if let country = placemark.country { geocodeParts.append(country) }
            if let adminArea = placemark.administrativeArea { geocodeParts.append(adminArea) }
            if let locality = placemark.locality { geocodeParts.append(locality) }
            if let subLocality = placemark.subLocality { geocodeParts.append(subLocality) }

            let geocodeString = geocodeParts.joined(separator: ", ")

            // Update database with geocode
            DatabaseManager.shared.updateGeocode(for: item.id, geocode: geocodeString)
            geocodedCount += 1
          }
        } catch {
          // Skip this item and continue with others
          continue
        }

        // Small delay between requests to be respectful to the API
        try await Task.sleep(nanoseconds: 200_000_000)  // 0.2 seconds
      }
    } catch {
      // Handle any database errors
    }

    isProcessing = false

    // Print completion summary
    print("Geocoding cycle completed: \(geocodedCount) items geocoded")
  }

}
