/// What starts a correction.
///
/// Both implementations end in the same `AppModel.run()`, so nothing behind
/// this protocol knows which one is active — otherwise swapping the trigger
/// would leak through the whole application.
@MainActor
protocol Trigger: AnyObject {
    func start(_ action: @escaping @MainActor () -> Void) throws
    func stop()
}
