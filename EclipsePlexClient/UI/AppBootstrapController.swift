//
//  AppBootstrapController.swift
//  EclipsePlexClient
//

import SwiftUI
import Combine

@MainActor
final class AppBootstrapController: ObservableObject {
    @Published private(set) var isReady = false
    private let launchTime = Date()

    func markReady(minimumDuration: TimeInterval = 0.25) async {
        guard !isReady else { return }
        let elapsed = Date().timeIntervalSince(launchTime)
        if elapsed < minimumDuration {
            let remaining = minimumDuration - elapsed
            let nanos = UInt64(max(0, remaining) * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanos)
        }
        withAnimation {
            isReady = true
        }
    }
}

