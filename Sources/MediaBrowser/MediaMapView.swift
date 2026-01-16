import MapKit
import SwiftUI

struct MediaMapView: View {
  @ObservedObject private var mediaScanner = MediaScanner.shared
  let lightboxItem: MediaItem?
  let searchQuery: String
  let onFullScreen: (MediaItem) -> Void

  @State private var region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
  )
  @State private var clusters: [Cluster] = []

  init(
    lightboxItem: MediaItem?,
    searchQuery: String,
    onFullScreen: @escaping (MediaItem) -> Void
  ) {
    self.lightboxItem = lightboxItem
    self.searchQuery = searchQuery
    self.onFullScreen = onFullScreen
  }

  private var itemsWithGPS: [LocalFileSystemMediaItem] {
    let allGPSItems = mediaScanner.items.filter { $0.metadata?.gps != nil }
    let filteredItems =
      searchQuery.isEmpty
      ? allGPSItems
      : allGPSItems.filter { $0.matchesSearchQuery(searchQuery) }

    return filteredItems.sorted { item1, item2 in
      let date1 = item1.metadata?.creationDate ?? Date.distantPast
      let date2 = item2.metadata?.creationDate ?? Date.distantPast
      return date1 > date2  // Most recent first
    }
  }

  private var sortedItems: [LocalFileSystemMediaItem] {
    return mediaScanner.items.sorted { item1, item2 in
      let date1 = item1.metadata?.creationDate ?? Date.distantPast
      let date2 = item2.metadata?.creationDate ?? Date.distantPast
      return date1 > date2  // Most recent first
    }
  }

  private func distance(_ c1: CLLocationCoordinate2D, _ c2: CLLocationCoordinate2D) -> Double {
    let lat1 = c1.latitude * .pi / 180
    let lon1 = c1.longitude * .pi / 180
    let lat2 = c2.latitude * .pi / 180
    let lon2 = c2.longitude * .pi / 180
    let dlat = lat2 - lat1
    let dlon = lon2 - lon1
    let a = sin(dlat / 2) * sin(dlat / 2) + cos(lat1) * cos(lat2) * sin(dlon / 2) * sin(dlon / 2)
    let c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return 6371 * c  // km
  }

  private func averageCoordinate(_ items: [LocalFileSystemMediaItem]) -> CLLocationCoordinate2D {
    let coords = items.map {
      CLLocationCoordinate2D(
        latitude: $0.metadata!.gps!.latitude, longitude: $0.metadata!.gps!.longitude)
    }
    let avgLat = coords.map { $0.latitude }.reduce(0, +) / Double(coords.count)
    let avgLon = coords.map { $0.longitude }.reduce(0, +) / Double(coords.count)
    return CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
  }

  private func computeClusters() {
    guard !itemsWithGPS.isEmpty else {
      clusters = []
      return
    }

    // Dynamic clustering distance based on zoom level
    let zoomLevel = log2(360 / region.span.longitudeDelta)

    // At maximum zoom (15+), disable clustering completely
    if zoomLevel >= 15 {
      clusters = itemsWithGPS.map { item in
        let coord = CLLocationCoordinate2D(
          latitude: item.metadata!.gps!.latitude, longitude: item.metadata!.gps!.longitude)
        return Cluster(coordinate: coord, count: 1, items: [item])
      }
      return
    }

    let clusterDistance: Double

    // Adjust clustering threshold based on zoom level
    if zoomLevel < 5 {
      clusterDistance = max(region.span.latitudeDelta, region.span.longitudeDelta) * 0.7  // Very zoomed out - very aggressive clustering
    } else if zoomLevel < 8 {
      clusterDistance = max(region.span.latitudeDelta, region.span.longitudeDelta) * 0.5  // Medium-low zoom - very aggressive clustering
    } else if zoomLevel < 12 {
      clusterDistance = max(region.span.latitudeDelta, region.span.longitudeDelta) * 0.25  // Medium zoom - aggressive clustering
    } else {
      clusterDistance = max(region.span.latitudeDelta, region.span.longitudeDelta) * 0.02  // Very zoomed in - minimal clustering
    }

    // Also limit by absolute distance (in km) to prevent over-clustering at high zoom
    let maxClusterRadiusKm = 0.5  // Maximum cluster radius of 500m

    var tempClusters: [Cluster] = []
    let sortedItems = itemsWithGPS.sorted { item1, item2 in
      let coord1 = CLLocationCoordinate2D(
        latitude: item1.metadata!.gps!.latitude, longitude: item1.metadata!.gps!.longitude)
      let coord2 = CLLocationCoordinate2D(
        latitude: item2.metadata!.gps!.latitude, longitude: item2.metadata!.gps!.longitude)
      return coord1.latitude < coord2.latitude
        || (coord1.latitude == coord2.latitude && coord1.longitude < coord2.longitude)
    }

    for item in sortedItems {
      let coord = CLLocationCoordinate2D(
        latitude: item.metadata!.gps!.latitude, longitude: item.metadata!.gps!.longitude)

      // Find existing cluster within both distance thresholds
      let candidateIndex = tempClusters.firstIndex { cluster in
        let coordDist = distance(cluster.coordinate, coord)
        let kmDist = coordDist * 111.32  // Approximate km per degree at equator
        return coordDist < clusterDistance || kmDist < maxClusterRadiusKm
      }

      if let index = candidateIndex {
        let cluster = tempClusters[index]
        let newItems = cluster.items + [item]
        let newCoord = averageCoordinate(newItems)
        tempClusters[index] = Cluster(
          coordinate: newCoord, count: cluster.count + 1, items: newItems)
      } else {
        tempClusters.append(Cluster(coordinate: coord, count: 1, items: [item]))
      }
    }

    // Keep all clusters, but small ones (< 5 items) will be shown as individual thumbnails
    clusters = tempClusters
  }

  private func zoomToCluster(_ cluster: Cluster) {
    let coords = cluster.items.map {
      CLLocationCoordinate2D(
        latitude: $0.metadata!.gps!.latitude, longitude: $0.metadata!.gps!.longitude)
    }
    let minLat = coords.map { $0.latitude }.min()!
    let maxLat = coords.map { $0.latitude }.max()!
    let minLon = coords.map { $0.longitude }.min()!
    let maxLon = coords.map { $0.longitude }.max()!
    let center = CLLocationCoordinate2D(
      latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    let span = MKCoordinateSpan(
      latitudeDelta: max(maxLat - minLat, 0.01) * 1.2,
      longitudeDelta: max(maxLon - minLon, 0.01) * 1.2)
    region = MKCoordinateRegion(center: center, span: span)
  }

  private func regionForItems(_ items: [MediaItem]) -> MKCoordinateRegion {
    guard let first = items.first, let gps = first.metadata?.gps else {
      return MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
        span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10))  // Default to SF
    }
    return MKCoordinateRegion(
      center: CLLocationCoordinate2D(latitude: gps.latitude, longitude: gps.longitude),
      span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
  }

  var body: some View {
    MapView(
      clusters: $clusters,
      region: $region,
      onClusterTap: { cluster in
        if cluster.count == 1 {
          if let firstItem = cluster.items.first,
            let selectedItem = firstItem as LocalFileSystemMediaItem?
          {
            onFullScreen(selectedItem)
          }
        } else {
          zoomToCluster(cluster)
        }
      },
      onRegionChange: { newRegion in
        region = newRegion
        computeClusters()
      }
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear {
      region = regionForItems(itemsWithGPS)
      computeClusters()
    }
    .onChange(of: mediaScanner.items) {
      computeClusters()
    }
  }
}
