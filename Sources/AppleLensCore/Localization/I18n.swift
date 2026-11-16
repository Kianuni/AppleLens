import Foundation
import Observation
import os

public enum AppLanguage: String, CaseIterable, Codable, Sendable {
    case zhHans = "zh-Hans"
    case en = "en"

    public var shortLabel: String {
        switch self {
        case .zhHans: return "中文"
        case .en: return "EN"
        }
    }

    public var displayName: String {
        switch self {
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }

    public static var systemDefault: AppLanguage {
        if let first = Locale.preferredLanguages.first, first.lowercased().hasPrefix("zh") {
            return .zhHans
        }
        return .en
    }
}

@inline(__always)
public func tr(_ zh: String, _ en: String, lang: AppLanguage) -> String {
    switch lang {
    case .zhHans: return zh
    case .en: return en
    }
}

@Observable
public final class LanguageManager: Sendable {
    public static let shared = LanguageManager()
    private static let storageKey = "applelens.language"

    private struct State: Sendable {
        var language: AppLanguage
        var generation: UInt64 = 0
        var persistedGeneration: UInt64 = 0
    }

    @ObservationIgnored
    private let stateLock: OSAllocatedUnfairLock<State>

    @ObservationIgnored
    private let defaultsLock: OSAllocatedUnfairLock<UserDefaults>

    @ObservationIgnored
    private let persistenceQueue = DispatchQueue(label: "com.kianuni.AppleLens.language.persistence")

    public var current: AppLanguage {
        get {
            access(keyPath: \.current)
            return stateLock.withLock { $0.language }
        }
        set {
            let targetGeneration = withMutation(keyPath: \.current) {
                stateLock.withLock { state -> UInt64 in
                    state.language = newValue
                    state.generation &+= 1
                    return state.generation
                }
            }
            persistUpTo(generation: targetGeneration)
        }
    }

    public init(defaults: UserDefaults = .standard) {
        let initial: AppLanguage
        if let raw = defaults.string(forKey: Self.storageKey),
           let saved = AppLanguage(rawValue: raw) {
            initial = saved
        } else {
            initial = .systemDefault
        }
        self.stateLock = OSAllocatedUnfairLock(initialState: State(language: initial))
        self.defaultsLock = OSAllocatedUnfairLock(uncheckedState: defaults)
    }

    public func toggle() {
        let targetGeneration = withMutation(keyPath: \.current) {
            stateLock.withLock { state -> UInt64 in
                let toggled: AppLanguage = (state.language == .zhHans) ? .en : .zhHans
                state.language = toggled
                state.generation &+= 1
                return state.generation
            }
        }
        persistUpTo(generation: targetGeneration)
    }

    private func persistUpTo(generation targetGeneration: UInt64) {
        persistenceQueue.sync {
            let pending: (language: AppLanguage, generation: UInt64)? = stateLock.withLock { state in
                guard state.persistedGeneration < targetGeneration || state.persistedGeneration < state.generation else {
                    return nil
                }
                return (state.language, state.generation)
            }
            guard let pending else { return }

            let defaults = defaultsLock.withLockUnchecked { $0 }
            defaults.set(pending.language.rawValue, forKey: Self.storageKey)

            stateLock.withLock { state in
                if pending.generation > state.persistedGeneration {
                    state.persistedGeneration = pending.generation
                }
            }
        }
    }

    public func text(_ zh: String, _ en: String) -> String {
        tr(zh, en, lang: current)
    }
}
