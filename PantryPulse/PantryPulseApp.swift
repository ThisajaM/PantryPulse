//
//  PantryPulseApp.swift
//  PantryPulse
//
//  Created by Thisaja Mudalige on 2026-10-14.
//

import SwiftUI
import CoreData

@main
struct PantryPulseApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
