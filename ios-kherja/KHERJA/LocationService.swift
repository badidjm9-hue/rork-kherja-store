//
//  LocationService.swift
//  KHERJA
//
//  CoreLocation wrapper for GPS position + reverse geocoding.
//

import Combine
import CoreLocation
import Foundation
import MapKit

@MainActor
final class LocationService: NSObject, ObservableObject {
    @Published var location: CLLocation?
    @Published var authorization: CLAuthorizationStatus = .notDetermined
    @Published var isLocating = false

    static let shared = LocationService()

    private let manager = CLLocationManager()
    private var observing = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = manager.authorizationStatus
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        start()
    }

    func start() {
        if !observing {
            manager.startUpdatingLocation()
            observing = true
        }
        isLocating = true
    }

    func stop() {
        manager.stopUpdatingLocation()
        observing = false
        isLocating = false
    }

    func refreshOnce() {
        manager.requestLocation()
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let loc = locations.last
        Task { @MainActor in
            if let loc {
                self.location = loc
                self.isLocating = false
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.isLocating = false
            print("KHERJA location error: \(error)")
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
        }
    }
}

// MARK: - Geocoding + distance helpers

enum Geo {
    /// Road-distance estimate from straight line (typical Algerian street factor).
    static func roadDistanceKm(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let straight = MKMapPoint(a).distance(to: MKMapPoint(b)) / 1000.0
        return max(straight * 1.4, 0.3)
    }

    static func estimatedMinutes(km: Double, vehicle: VehicleKind) -> Int {
        let speed: Double = vehicle == .moto ? 26 : 22 // city average km/h
        return max(3, Int((km / speed * 60).rounded()))
    }

    static func reverseGeocode(_ coordinate: CLLocationCoordinate2D) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        let arabicPrefixes = ["Wilaya", "Commune"]
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            if let p = placemarks.first {
                let parts = [p.name, p.subLocality ?? p.locality, p.administrativeArea]
                    .compactMap { $0 }
                    .filter { !arabicPrefixes.contains($0) }
                return parts.prefix(2).joined(separator: ", ")
            }
        } catch {
            print("KHERJA geocode error: \(error)")
        }
        return String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude)
    }
}
