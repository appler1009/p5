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
          if let placemark = placemarks.first {
            // Create deduplicated geocode string (most specific to most general)
            var geocodeParts: [String] = []
            if let subLocality = placemark.subLocality { geocodeParts.append(subLocality) }
            if let locality = placemark.locality { geocodeParts.append(locality) }
            if let adminArea = placemark.administrativeArea { geocodeParts.append(adminArea) }
            if let country = placemark.country { geocodeParts.append(country) }

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
  }

}
