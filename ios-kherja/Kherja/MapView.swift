//
//  MapView.swift
//  Kherja
//
//  MapKit wrapper: pins, route line, tap-to-pick destination.
//

import MapKit
import SwiftUI
import UIKit

// MARK: - Annotation model

struct MapPoint: Equatable {
    var coordinate: CLLocationCoordinate2D
    var kind: PinKind
    var title: String

    enum PinKind: String {
        case pickup
        case destination
        case driver
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}

// MARK: - Representable

struct RideMapView: UIViewRepresentable {
    var points: [MapPoint]
    var pickMode = false
    var onPick: ((CLLocationCoordinate2D) -> Void)?
    var showUserLocation = true

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = showUserLocation
        map.showsBuildings = true
        map.pointOfInterestFilter = .includingAll
        map.tintColor = KJ.blue.uiColor
        map.isRotateEnabled = false
        let config = MKStandardMapConfiguration(emphasisStyle: .muted)
        config.pointOfInterestFilter = .includingAll
        map.preferredConfiguration = config

        if pickMode {
            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            map.addGestureRecognizer(tap)
        }
        context.coordinator.parent = self
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(map: map)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: RideMapView?
        private var lastRouteKey = ""
        private var routeOverlay: MKPolyline?

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = gesture.view as? MKMapView else { return }
            let point = gesture.location(in: map)
            let coord = map.convert(point, toCoordinateFrom: map)
            parent?.onPick?(coord)
        }

        func sync(map: MKMapView) {
            guard let parent else { return }
            // Annotations keyed by kind.
            var wanted: [String: MapPoint] = [:]
            for p in parent.points { wanted[p.kind.rawValue] = p }

            let existing = map.annotations.compactMap { $0 as? PointAnnotation }
            let stale = existing.filter { ann in
                guard let p = wanted[ann.kind] else { return true }
                return p.coordinate != ann.coordinate
            }
            if !stale.isEmpty { map.removeAnnotations(stale) }
            for (kind, p) in wanted where !existing.contains(where: { $0.kind == kind && $0.coordinate == p.coordinate }) {
                let a = PointAnnotation()
                a.kind = kind
                a.coordinate = p.coordinate
                a.title = p.title
                map.addAnnotation(a)
            }

            // Route between pickup and destination.
            let routeKey = parent.points.compactMap { p -> String? in
                p.kind == .pickup || p.kind == .destination ? "\(p.coordinate.latitude),\(p.coordinate.longitude)" : nil
            }.joined(separator: "|")

            if routeKey != lastRouteKey {
                lastRouteKey = routeKey
                if let old = routeOverlay {
                    map.removeOverlay(old)
                    routeOverlay = nil
                }
                let pickup = parent.points.first { $0.kind == .pickup }?.coordinate
                let dest = parent.points.first { $0.kind == .destination }?.coordinate
                if let pickup, let dest {
                    requestRoute(from: pickup, to: dest, into: map)
                }
                // Fit region
                let coords = parent.points.map(\.coordinate)
                if !coords.isEmpty {
                    fit(map: map, coords: coords)
                }
            }
        }

        private func requestRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, into map: MKMapView) {
            let request = MKDirections.Request()
            request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
            request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
            request.transportType = .automobile
            let directions = MKDirections(request: request)
            Task { @MainActor in
                let response = try? await directions.calculate()
                let line = response?.routes.first?.polyline ?? Self.straightLine(from: from, to: to)
                self.routeOverlay = line
                map.addOverlay(line, level: .aboveRoads)
            }
        }

        private static func straightLine(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> MKPolyline {
            MKPolyline(coordinates: [from, to], count: 2)
        }

        private func fit(map: MKMapView, coords: [CLLocationCoordinate2D]) {
            var rect = MKMapRect.null
            for c in coords {
                let p = MKMapPoint(c)
                rect = rect.union(MKMapRect(x: p.x - 400, y: p.y - 400, width: 800, height: 800))
            }
            let insets = UIEdgeInsets(top: 70, left: 50, bottom: 50, right: 50)
            map.setVisibleMapRect(rect, edgePadding: insets, animated: true)
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }
            let r = MKPolylineRenderer(polyline: line)
            r.strokeColor = KJ.blue.uiColor
            r.lineWidth = 5
            r.lineCap = .round
            return r
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let a = annotation as? PointAnnotation else { return nil }
            let id = "pin-\(a.kind)"
            let view: MKMarkerAnnotationView
            if let reused = mapView.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView {
                view = reused
                view.annotation = a
            } else {
                view = MKMarkerAnnotationView(annotation: a, reuseIdentifier: id)
            }
            switch MapPoint.PinKind(rawValue: a.kind) ?? .pickup {
            case .pickup:
                view.markerTintColor = KJ.blue.uiColor
                view.glyphImage = UIImage(systemName: "location.circle.fill")
            case .destination:
                view.markerTintColor = KJ.burgundy.uiColor
                view.glyphImage = UIImage(systemName: "mappin.circle.fill")
            case .driver:
                view.markerTintColor = KJ.ink.uiColor
                view.glyphImage = UIImage(systemName: "car.fill")
            }
            view.canShowCallout = true
            view.displayPriority = .required
            return view
        }
    }
}

final class PointAnnotation: MKPointAnnotation {
    var kind: String = MapPoint.PinKind.pickup.rawValue
}

extension Color {
    var uiColor: UIColor { UIColor(self) }
}
