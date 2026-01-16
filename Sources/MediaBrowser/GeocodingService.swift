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

    // Only return a string if we have at least one component
    guard !geocodeParts.isEmpty else { return nil }

    return geocodeParts.joined(separator: ", ")
  }
}

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
      // Get up to 45 items that have GPS but no geocode (throttled to stay under Apple's 50/minute limit)
      let itemsToGeocode = DatabaseManager.shared.getItemsNeedingGeocode(limit: 45)

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
  }

}
