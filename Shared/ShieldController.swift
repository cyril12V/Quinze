import Foundation
import FamilyControls
import ManagedSettings
import LearningPrimitives

/// What the slot engine needs from ManagedSettings. A protocol so the state machine is unit-testable
/// without the system frameworks doing anything.
protocol ShieldControlling {
    /// Shields the apps/categories/websites described by `selectionData` for the slot's own store.
    /// Returns false (and shields nothing) when there is nothing safe to shield.
    @discardableResult
    func apply(slot: SessionSlot, selectionData: Data?, mode: StoredMode) -> Bool
    /// Removes every setting of the slot's store. Never touches the other slots' stores.
    func clear(slot: SessionSlot)
}

struct SystemShieldController: ShieldControlling {
    init() {}

    static func store(for slot: SessionSlot) -> ManagedSettingsStore {
        ManagedSettingsStore(named: ManagedSettingsStore.Name(ScreenTimeNames.storeRawName(for: slot)))
    }

    static func decodeSelection(_ data: Data?) -> FamilyActivitySelection? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }

    @discardableResult
    func apply(slot: SessionSlot, selectionData: Data?, mode: StoredMode) -> Bool {
        guard let selection = Self.decodeSelection(selectionData) else { return false }
        let apps = selection.applicationTokens
        let categories = selection.categoryTokens
        let domains = selection.webDomainTokens
        let store = Self.store(for: slot)

        switch mode {
        case .selectedApps:
            guard !(apps.isEmpty && categories.isEmpty && domains.isEmpty) else { return false }
            store.shield.applications = apps.isEmpty ? nil : apps
            store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories, except: [])
            store.shield.webDomains = domains.isEmpty ? nil : domains
            store.shield.webDomainCategories = nil
        case .allExceptAllowed:
            // Without at least one allowed app the shield would also lock Quinze itself: refuse.
            guard !apps.isEmpty else { return false }
            store.shield.applications = nil
            store.shield.applicationCategories = .all(except: apps)
            store.shield.webDomains = nil
            store.shield.webDomainCategories = .all(except: domains)
        }
        return true
    }

    func clear(slot: SessionSlot) {
        Self.store(for: slot).clearAllSettings()
    }
}
