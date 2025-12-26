import MapKit
import SwiftUI

struct Cluster: Identifiable {
  let id = UUID()
  let coordinate: CLLocationCoordinate2D
  let count: Int
  let items: [MediaItem]
}

struct ContentView: View {
  @ObservedObject private var directoryManager = DirectoryManager.shared
  @ObservedObject private var mediaScanner = MediaScanner.shared
  @Environment(\.openWindow) private var openWindow
  @State private var selectedItem: MediaItem?
  @State private var viewMode: String = UserDefaults.standard.string(forKey: "viewMode") ?? "Grid"
  @State private var region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1)
  )
  @State private var clusters: [Cluster] = []

  private var itemsWithGPS: [MediaItem] {
    sortedItems.filter { $0.metadata?.gps != nil }
  }

  private var sortedItems: [MediaItem] {
    mediaScanner.items.sorted { item1, item2 in
      let date1 = item1.metadata?.creationDate ?? Date.distantPast
      let date2 = item2.metadata?.creationDate ?? Date.distantPast
      return date1 > date2  // Most recent first
    }
  }

  private var monthlyGroups: [(month: String, items: [MediaItem])] {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMMM yyyy"

    let grouped = Dictionary(grouping: sortedItems) { item in
      guard let date = item.metadata?.creationDate else {
        return "Unknown"
      }
      return formatter.string(from: date)
    }

    return grouped.map { (month: $0.key, items: $0.value) }
      .sorted { $0.month > $1.month }
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

  private func averageCoordinate(_ items: [MediaItem]) -> CLLocationCoordinate2D {
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
    ZStack {
      VStack(spacing: 0) {
        if viewMode == "Grid" {
          ScrollView {
            VStack(alignment: .leading, spacing: 16) {
              ForEach(monthlyGroups, id: \.month) { group in
                Section(header: Text(group.month).font(.headline).padding(.horizontal)) {
                  LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                    ForEach(group.items) { item in
                      MediaItemView(item: item, onTap: { selectedItem = item })
                    }
                  }
                  .padding(.horizontal, 8)
                }
              }
            }
            .padding(.bottom, 8)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewMode == "Map" {
          MapView(
            clusters: $clusters,
            region: $region,
            onClusterTap: { cluster in
              if cluster.count == 1 {
                selectedItem = cluster.items.first
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

      if let selected = selectedItem {
        FullMediaView(
          item: selected,
          onClose: { selectedItem = nil },
          onNext: { nextItem() },
          onPrev: { prevItem() }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transition(.opacity)
      }
    }
    .navigationTitle("Media Browser")
    .toolbar {
      ToolbarItemGroup(placement: .automatic) {
        if let progress = mediaScanner.scanProgress {
          ProgressView(value: Double(progress.current), total: Double(progress.total))
            .frame(width: 100)
        }

        Button("Scan") {
          Task {
            await MediaScanner.shared.scan(directories: directoryManager.directories)
          }
        }
        .disabled(mediaScanner.isScanning || directoryManager.directories.isEmpty)

        Button(action: {
          openWindow(id: "settings")
        }) {
          Image(systemName: "gear")
        }
        .help("Settings")
        .keyboardShortcut(",", modifiers: .command)
      }
      ToolbarItem {
        Picker("View Mode", selection: $viewMode) {
          Image(systemName: "square.grid.2x2").tag("Grid")
          Image(systemName: "map").tag("Map")
        }
        .pickerStyle(.segmented)
      }
    }

  }

  private func nextItem() {
    guard let index = sortedItems.firstIndex(where: { $0.id == selectedItem?.id }) else { return }
    let nextIndex = (index + 1) % sortedItems.count
    selectedItem = sortedItems[nextIndex]
  }

  private func prevItem() {
    guard let index = sortedItems.firstIndex(where: { $0.id == selectedItem?.id }) else { return }
    let prevIndex = (index - 1 + sortedItems.count) % sortedItems.count
    selectedItem = sortedItems[prevIndex]
  }
}

struct ContentView_Previews: PreviewProvider {
  static var previews: some View {
    ContentView()
  }
}
