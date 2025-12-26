import MapKit
import SwiftUI

struct MapView: NSViewRepresentable {
  @Binding var clusters: [Cluster]
  @Binding var region: MKCoordinateRegion
  let onClusterTap: (Cluster) -> Void
  let onRegionChange: (MKCoordinateRegion) -> Void

  private let thumbnailSize = CGSize(width: 30, height: 30)

  private func createRoundedThumbnail(from image: NSImage, size: CGSize) -> NSImage {
    let roundedImage = NSImage(size: size)
    roundedImage.lockFocus()

    // Create rounded rect path
    let rect = CGRect(origin: .zero, size: size)
    let radius: CGFloat = 4.0
    let roundedPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    roundedPath.addClip()

    // Draw the image
    image.draw(in: rect)

    // Draw translucent dark border
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

      let identifier = annotation.cluster.count == 1 ? "PhotoPin" : "ClusterPin"
      var annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: identifier)

      if annotationView == nil {
        annotationView = MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
        annotationView?.canShowCallout = false
        annotationView?.centerOffset = CGPoint(x: 0, y: -20)
      } else {
        annotationView?.annotation = annotation
      }

      if annotation.cluster.count == 1 {
        // For individual photos, load and display thumbnail with rounded border
        // Start with camera icon as fallback
        annotationView?.image = NSImage(
          systemSymbolName: "camera.fill", accessibilityDescription: nil)

        let item = annotation.cluster.items.first
        let url = item?.url
        Task {
          if let url = url,
            let thumbnail = await ThumbnailCache.shared.thumbnail(
              for: url, size: parent.thumbnailSize)
          {
            // Create rounded thumbnail with 1 pixel border
            let borderedImage = parent.createRoundedThumbnail(
              from: thumbnail, size: parent.thumbnailSize)
            await MainActor.run {
              annotationView?.image = borderedImage
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
