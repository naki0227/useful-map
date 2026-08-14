@preconcurrency import CoreLocation
import Domain
import Foundation

/// Core Location による現在地取得（仕様書 12）。
/// When In Use 権限のみを要求し、位置情報を外部へ送信しない。
public final class CoreLocationService: NSObject, LocationProviding, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var continuations: [CheckedContinuation<Coordinate, Error>] = []
    private let lock = NSLock()

    public init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        self.manager.delegate = self
        self.manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    public var authorizationStatus: LocationAuthorizationStatus {
        switch manager.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        @unknown default: return .notDetermined
        }
    }

    public func requestAuthorization() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    public func currentCoordinate() async throws -> Coordinate {
        switch authorizationStatus {
        case .denied, .restricted:
            throw LocationError.denied
        case .notDetermined:
            requestAuthorization()
        case .authorized:
            break
        }

        if let cached = manager.location.map({ Coordinate($0.coordinate) }), cached.isValid {
            return cached
        }

        return try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            continuations.append(continuation)
            lock.unlock()
            manager.requestLocation()
        }
    }

    // MARK: - CLLocationManagerDelegate

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        resume(.success(Coordinate(location.coordinate)))
    }

    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let nsError = error as NSError
        let mapped: LocationError = nsError.code == CLError.denied.rawValue ? .denied : .unavailable
        resume(.failure(mapped))
    }

    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            resume(.failure(LocationError.denied))
        case .authorizedAlways, .authorizedWhenInUse:
            lock.lock()
            let waiting = !continuations.isEmpty
            lock.unlock()
            if waiting { manager.requestLocation() }
        default:
            break
        }
    }

    private func resume(_ result: Result<Coordinate, Error>) {
        lock.lock()
        let pending = continuations
        continuations.removeAll()
        lock.unlock()
        for continuation in pending {
            continuation.resume(with: result)
        }
    }
}
