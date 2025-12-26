import MapKit
import SwiftUI

struct MapView: NSViewRepresentable {
  @Binding var clusters: [Cluster]
  @Binding var region: MKCoordinateRegion
  let onClusterTap: (Cluster) -> Void
  let onRegionChange: (MKCoordinateRegion) -> Void

  private let baseThumbnailSize = CGSize(width: 30, height: 30)
  private let maxThumbnailSize = CGSize(width: 45, height: 45)  // 50% larger at max zoom

  private func calculateThumbnailSize(for zoomLevel: Double) -> CGSize {
    // Scale thumbnail size from 30px at low zoom to 45px at high zoom (15+)
    let normalizedZoom = max(0, min(1, (zoomLevel - 5) / 10))  // Normalize zoom from 5-15 to 0-1
    let scaleFactor = 1.0 + (0.5 * normalizedZoom)  // Scale from 1.0 to 1.5
    let newSize = CGSize(
      width: baseThumbnailSize.width * scaleFactor,
      height: baseThumbnailSize.height * scaleFactor
    )
    return newSize
  }

  private func createRoundedThumbnail(from image: NSImage, size: CGSize) -> NSImage {
    let shadowOffset: CGFloat = 2.0
    let shadowSize = CGSize(
      width: size.width + shadowOffset * 2, height: size.height + shadowOffset * 2)

    let roundedImage = NSImage(size: shadowSize)
    roundedImage.lockFocus()

    // Draw shadow first
    let shadowRect = CGRect(
      x: shadowOffset,
      y: shadowOffset,
      width: size.width,
      height: size.height
    )
    let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: 4.0, yRadius: 4.0)
    NSColor.black.withAlphaComponent(0.3).setFill()
    shadowPath.fill()

    // Create rounded rect path for image
    let imageRect = CGRect(origin: .zero, size: size)
    let roundedPath = NSBezierPath(roundedRect: imageRect, xRadius: 4.0, yRadius: 4.0)
    roundedPath.addClip()

    // Draw the image
    image.draw(in: imageRect)

    // Draw border
    NSColor.black.withAlphaComponent(0.7).setStroke()
    roundedPath.lineWidth = 1.0
    roundedPath.stroke()

    roundedImage.unlockFocus()
    return roundedImage
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(self)
  }

  func makeNSView(context: Context) -> MKMapView {
    let mapView = MKMapView()
    mapView.delegate = context.coordinator
    mapView.region = region
    mapView.setRegion(region, animated: false)
    mapView.showsUserLocation = false
    mapView.addAnnotations(clusters.map(MapAnnotation.init))
    return mapView
  }

  func updateNSView(_ mapView: MKMapView, context: Context) {
    if !mapView.region.center.latitude.isEqual(to: region.center.latitude, accuracy: 0.0001)
      || !mapView.region.center.longitude.isEqual(to: region.center.longitude, accuracy: 0.0001)
      || !mapView.region.span.latitudeDelta.isEqual(to: region.span.latitudeDelta, accuracy: 0.0001)
      || !mapView.region.span.longitudeDelta.isEqual(
        to: region.span.longitudeDelta, accuracy: 0.0001)
    {
      mapView.setRegion(region, animated: true)
    }

    let existingAnnotations = mapView.annotations
    let newAnnotations = clusters.map(MapAnnotation.init)

    // Remove annotations that no longer exist
    for annotation in existingAnnotations {
      if !(newAnnotations.contains {
        $0.coordinate.latitude == annotation.coordinate.latitude
          && $0.coordinate.longitude == annotation.coordinate.longitude
      }) {
        mapView.removeAnnotation(annotation)
      }
    }

    // Add new annotations
    for annotation in newAnnotations {
      let exists = existingAnnotations.contains { existing in
        existing.coordinate.latitude == annotation.coordinate.latitude
          && existing.coordinate.longitude == annotation.coordinate.longitude
      }
      if !exists {
        mapView.addAnnotation(annotation)
      }
    }
  }

  class Coordinator: NSObject, MKMapViewDelegate {
    var parent: MapView

    init(_ parent: MapView) {
      self.parent = parent
    }

    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
      parent.onRegionChange(mapView.region)
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
      if let annotation = view.annotation as? MapAnnotation {
        parent.onClusterTap(annotation.cluster)
        mapView.deselectAnnotation(annotation, animated: false)
      }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
      guard let annotation = annotation as? MapAnnotation else { return nil }

      let identifier = annotation.cluster.count < 5 ? "PhotoPin" : "ClusterPin"
      var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

      if annotationView == nil {
        annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        annotationView?.canShowCallout = false
        annotationView?.centerOffset = CGPoint(x: 0, y: -20)
      } else {
        annotationView?.annotation = annotation
      }

      if annotation.cluster.count < 5 {
        // For small clusters (1-4 items), show individual thumbnails
        if let item = annotation.cluster.items.first {
          // Calculate thumbnail size based on zoom level
          let zoomLevel = log2(360 / parent.region.span.longitudeDelta)
          let thumbnailSize = parent.calculateThumbnailSize(for: zoomLevel)

          // Start with camera icon as fallback
          annotationView?.image = NSImage(
            systemSymbolName: "camera.fill", accessibilityDescription: nil)

          let url = item.url
          Task {
            if let thumbnail = await ThumbnailCache.shared.thumbnail(
              for: url, size: thumbnailSize)
            {
              // Create rounded thumbnail with 1 pixel border
              let borderedImage = parent.createRoundedThumbnail(
                from: thumbnail, size: thumbnailSize)
              await MainActor.run {
                annotationView?.image = borderedImage
              }
            }
          }
        }
      } else {
        let size = min(max(CGFloat(25 + Int(Double(annotation.cluster.count) * 1.5)), 35), 70)

        let image = NSImage(size: CGSize(width: size, height: size))
        image.lockFocus()

        let rect = CGRect(x: 0, y: 0, width: size, height: size)
        NSColor.systemBlue.withAlphaComponent(0.9).setFill()
        NSBezierPath(ovalIn: rect).fill()

        NSColor.white.setFill()
        let attributes: [NSAttributedString.Key: Any] = [
          .font: NSFont.boldSystemFont(ofSize: max(12, size / 4)),
          .foregroundColor: NSColor.white,
        ]
        let text = "\(annotation.cluster.count)"
        let textSize = text.size(withAttributes: attributes)
        let textRect = CGRect(
          x: (size - textSize.width) / 2,
          y: (size - textSize.height) / 2,
          width: textSize.width,
          height: textSize.height
        )
        text.draw(in: textRect, withAttributes: attributes)

        image.unlockFocus()
        annotationView?.image = image
      }

      return annotationView
    }
  }
}

class MapAnnotation: NSObject, MKAnnotation {
  let cluster: Cluster
  var coordinate: CLLocationCoordinate2D { cluster.coordinate }

  init(cluster: Cluster) {
    self.cluster = cluster
    super.init()
  }
}

extension Double {
  func isEqual(to other: Double, accuracy: Double) -> Bool {
    return abs(self - other) <= accuracy
  }
}
