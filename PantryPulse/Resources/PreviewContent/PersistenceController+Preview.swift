#if DEBUG
extension PersistenceController {
    /// A fresh empty store per preview. Call load() before accessing its context.
    static func preview() -> PersistenceController {
        PersistenceController(inMemory: true)
    }
}
#endif
