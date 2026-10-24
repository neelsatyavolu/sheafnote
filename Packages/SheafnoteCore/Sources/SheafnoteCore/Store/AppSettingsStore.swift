import Foundation
import SwiftData

/// Synced settings live in `AppSetting` rows (one deterministic row per key); device-only settings in UserDefaults.
@MainActor
public final class AppSettingsStore {
    private let context: ModelContext
    private let defaults: UserDefaults

    public init(context: ModelContext, defaults: UserDefaults = .standard) {
        self.context = context
        self.defaults = defaults
    }

    public static func settingID(for key: String) -> UUID { Hashing.stableUUID("co.xanom.sheafnote.setting." + key) }

    public func synced<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        guard let row = row(for: key), row.deletedAt == nil else { return nil }
        return JSONCoding.decode(type, from: row.valueJSON)
    }

    public func setSynced<T: Encodable>(_ value: T, for key: String, now: Date = .now) throws {
        let data = JSONCoding.encode(value)
        if let existing = row(for: key) {
            existing.valueJSON = data
            existing.deletedAt = nil
            markDirty(existing, fields: ["valueJSON", "deletedAt"], now: now)
        } else {
            let created = AppSetting(id: Self.settingID(for: key), key: key, valueJSON: data, now: now)
            context.insert(created)
            markDirty(created, fields: ["key", "valueJSON"], now: now)
        }
        try context.save()
    }

    public func local<T: Decodable>(_ key: String, as type: T.Type) -> T? {
        defaults.data(forKey: Self.localKey(key)).flatMap { JSONCoding.decode(type, from: $0) }
    }

    public func setLocal<T: Encodable>(_ value: T, for key: String) {
        defaults.set(JSONCoding.encode(value), forKey: Self.localKey(key))
    }

    public func removeLocal(_ key: String) { defaults.removeObject(forKey: Self.localKey(key)) }

    private static func localKey(_ key: String) -> String { "sheafnote.\(key)" }

    private func row(for key: String) -> AppSetting? {
        let id = Self.settingID(for: key)
        return try? context.fetch(FetchDescriptor<AppSetting>(predicate: #Predicate { $0.id == id })).first
    }
}
