/// The single source of truth for the version.
///
/// The Makefile reads this constant and stamps it into the bundle's Info.plist,
/// so the app, the CLI and the bundle can never disagree about which version
/// they are.
public enum Czechator {
    public static let version = "1.0.0"
}
