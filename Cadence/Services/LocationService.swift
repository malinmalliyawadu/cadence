import CoreLocation
import MapKit
import Foundation
import Observation

/// One-shot "where am I" for the forecast. Reverse-geocodes to a place name for the settings screen.
@MainActor
@Observable
final class LocationService {
    struct Fix: Sendable, Equatable {
        let latitude: Double
        let longitude: Double
        let name: String
    }

    enum State: Sendable, Equatable {
        case idle, requesting, denied, located(Fix), failed(String)
    }

    private(set) var state: State = .idle
    private let manager = CLLocationManager()
    private var delegate: Delegate?

    func locate() {
        if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            state = .denied
            return
        }
        state = .requesting
        let delegate = Delegate { [weak self] result in
            Task { @MainActor in self?.handle(result) }
        }
        self.delegate = delegate
        manager.delegate = delegate
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            manager.requestLocation()
        }
    }

    private func handle(_ result: Delegate.Result) {
        switch result {
        case .authorized:
            manager.requestLocation()
        case .denied:
            state = .denied
        case .location(let location):
            Task { await resolveName(for: location) }
        case .failed(let message):
            state = .failed(message)
        }
    }

    private func resolveName(for location: CLLocation) async {
        let coordinate = location.coordinate
        var name = String(format: "%.2f, %.2f", coordinate.latitude, coordinate.longitude)
        if let request = MKReverseGeocodingRequest(location: location),
           let item = try? await request.mapItems.first,
           let city = item.addressRepresentations?.cityName {
            name = city
        }
        state = .located(Fix(latitude: coordinate.latitude, longitude: coordinate.longitude, name: name))
    }

    /// CLLocationManager calls back on an arbitrary queue, so the delegate is a plain class that
    /// forwards into the main actor.
    private final class Delegate: NSObject, CLLocationManagerDelegate {
        enum Result: Sendable {
            case authorized, denied, location(CLLocation), failed(String)
        }

        let onResult: @Sendable (Result) -> Void
        init(onResult: @escaping @Sendable (Result) -> Void) { self.onResult = onResult }

        func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: onResult(.authorized)
            case .denied, .restricted: onResult(.denied)
            case .notDetermined: break
            @unknown default: break
            }
        }

        func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
            if let last = locations.last { onResult(.location(last)) }
        }

        func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
            onResult(.failed(error.localizedDescription))
        }
    }
}
