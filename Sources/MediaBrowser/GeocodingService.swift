import CoreLocation
import Foundation

extension CLPlacemark {
  /// Creates a geocoded location string from placemark components
  /// Returns a comma-separated string in order: subLocality, locality, administrativeArea, country
  var geocodeString: String? {
    var geocodeParts: [String] = []

    // Add components in order: most specific to most general
    if let subLocality = self.subLocality { geocodeParts.append(subLocality) }
    if let locality = self.locality { geocodeParts.append(locality) }
    if let administrativeArea = self.administrativeArea { geocodeParts.append(administrativeArea) }
    if let country = self.country { geocodeParts.append(country) }

    // Remove duplicates while preserving order
    var seen = Set<String>()
    let uniqueParts = geocodeParts.filter { seen.insert($0).inserted }

    // Only return a string if we have at least one component
    guard !uniqueParts.isEmpty else { return nil }

    return uniqueParts.joined(separator: ", ")
  }
}

@MainActor
class GeocodingService {
  let databaseManager: DatabaseManager
  static var shared: GeocodingService!

  private var timer: Timer?
  private var isProcessing = false

  init(databaseManager: DatabaseManager) {
    self.databaseManager = databaseManager
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
      // Get up to 30 items that have GPS but no geocode (throttled to stay under Apple's 400/10min limit)
      let itemsToGeocode = databaseManager.getItemsNeedingGeocode(limit: 30)

      for item in itemsToGeocode {
        guard let gps = item.metadata?.gps else { continue }

        let location = CLLocation(latitude: gps.latitude, longitude: gps.longitude)
        let geocoder = CLGeocoder()

        // TODO: Future upgrade to MapKit geocoding (macOS 26.0+)
        // When targeting macOS 26+, replace CLGeocoder with:
        // let request = MKReverseGeocodingRequest(coordinate: coordinate)
        // let response = try await request.response()
        // if let mapItem = response.mapItems.first {
        //     let address = mapItem.address.addressRepresentations.first?.localizedString
        // }

        do {
          let placemarks = try await geocoder.reverseGeocodeLocation(location)
          if let placemark = placemarks.first, let geocodeString = placemark.geocodeString {
            // Update database with geocode
            databaseManager.updateGeocode(for: item.id, geocode: geocodeString)

            // Update in-memory MediaItem for immediate keyword lookup availability
            await MediaScanner.shared.updateGeocode(for: item.id, geocode: geocodeString)

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

    // Print completion summary only if items were actually geocoded
    if geocodedCount > 0 {
      print("Geocoding cycle completed: \(geocodedCount) items geocoded")
    }
  }

}
