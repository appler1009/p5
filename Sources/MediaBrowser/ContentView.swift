import MapKit
import SwiftUI

struct ContentView: View {
  @ObservedObject private var directoryManager = DirectoryManager.shared
  @ObservedObject private var mediaScanner = MediaScanner.shared
  @Environment(\.openWindow) private var openWindow
  @State private var selectedItem: MediaItem?
  @State private var viewMode: String = UserDefaults.standard.string(forKey: "viewMode") ?? "Grid"
  @State private var region = MKCoordinateRegion(
    center: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10))

  private var sortedItems: [MediaItem] {
    mediaScanner.items.sorted(by: {
      ($0.metadata?.creationDate ?? Date.distantPast)
        > ($1.metadata?.creationDate ?? Date.distantPast)
    })
  }

  private var monthlyGroups: [(month: String, items: [MediaItem])] {
    let calendar = Calendar.current
    let grouped = Dictionary(grouping: sortedItems) { item -> Date? in
      guard let date = item.metadata?.creationDate else { return nil }
      return calendar.date(from: calendar.dateComponents([.year, .month], from: date))
    }
    let sortedGroups = grouped.sorted { (lhs, rhs) -> Bool in
      guard let lhsDate = lhs.key, let rhsDate = rhs.key else { return lhs.key != nil }
      return lhsDate > rhsDate
    }
    return sortedGroups.map {
      (
        month: $0.key?.formatted(.dateTime.year().month(.wide)) ?? "Unknown",
        items: $0.value.sorted {
          ($0.metadata?.creationDate ?? Date.distantPast)
            > ($1.metadata?.creationDate ?? Date.distantPast)
        }
      )
    }
  }

  private var itemsWithGPS: [MediaItem] {
    sortedItems.filter { $0.metadata?.gps != nil }
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

  @ViewBuilder
  private func mainContent() -> some View {
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
    } else {
      Map(coordinateRegion: $region, annotationItems: itemsWithGPS) { item in
        MapAnnotation(
          coordinate: CLLocationCoordinate2D(
            latitude: item.metadata!.gps!.latitude, longitude: item.metadata!.gps!.longitude)
        ) {
          Image(systemName: "photo")
            .foregroundColor(.blue)
            .onTapGesture(count: 2) {
              selectedItem = item
            }
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  var body: some View {
    ZStack {
      VStack(spacing: 0) {
        mainContent()
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
        Button("Scan") {
          Task {
            await MediaScanner.shared.scan(directories: directoryManager.directories)
          }
        }
        .disabled(mediaScanner.isScanning || directoryManager.directories.isEmpty)

        if let progress = mediaScanner.scanProgress {
          ProgressView(value: Double(progress.current), total: Double(progress.total))
            .frame(width: 100)
        }

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
    .onChange(of: viewMode) { newValue in
      UserDefaults.standard.set(newValue, forKey: "viewMode")
      if newValue == "Map" {
        region = regionForItems(itemsWithGPS)
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
