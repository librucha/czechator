import CzechatorCore
import Foundation
import Testing

@testable import CzechatorApp

private func loadedForm(_ mutate: (inout Config) -> Void = { _ in }) -> SettingsFormState {
    var config = Config.builtIn
    mutate(&config)
    var form = SettingsFormState()
    form.load(from: config)
    return form
}

@Test func onlyCloudProfilesNeedAKey() {
    var form = loadedForm()
    form.selectProfile("local")
    #expect(form.editedProfileNeedsKey == false)
    form.selectProfile("openai")
    #expect(form.editedProfileNeedsKey)
}

@Test func aProfileThatAlreadyPointsAtTheKeychainKeepsItsAccount() {
    var form = loadedForm()
    form.selectProfile("openai")
    let account = form.ensureKeychainReference()
    #expect(account == "czechator-openai")
    #expect(form.config.profiles["openai"]?.apiKey == .keychain(account: "czechator-openai"))
}

@Test func aNewCloudProfileGetsAKeychainReferenceOnDemand() {
    // Until now a profile added from the window had nowhere to put a key, so
    // the field stayed disabled and the only way in was to edit the YAML.
    var form = loadedForm()
    form.addProfile()
    form.editedProfileFields?.kind = .openaiCompat
    #expect(form.editedProfileKeychainAccount == nil)

    let account = form.ensureKeychainReference()

    #expect(account != nil)
    #expect(form.editedProfileKeychainAccount == account)
    if case .keychain = form.editedProfileFields?.apiKey {
    } else {
        Issue.record(
            "expected a keychain reference, got \(String(describing: form.editedProfileFields?.apiKey))"
        )
    }
}

@Test func theAccountNameFollowsTheProfileName() {
    var form = loadedForm()
    form.addProfile()
    form.editedProfileName = "claude"
    form.commitRename()
    form.editedProfileFields?.kind = .openaiCompat

    #expect(form.ensureKeychainReference() == "czechator-claude")
}

@Test func aLocalProfileIsNotGivenAKeychainReference() {
    // An Ollama endpoint takes no key; inventing an account would leave a
    // reference nothing ever resolves.
    var form = loadedForm()
    form.selectProfile("local")
    #expect(form.ensureKeychainReference() == nil)
    #expect(form.config.profiles["local"]?.apiKey == nil)
}

@Test func aReferenceToSomethingOtherThanTheKeychainIsLeftAlone() {
    // A config may point at an environment variable on purpose. Overwriting it
    // with a Keychain account would break a setup that was working.
    var form = loadedForm {
        $0.profiles["openai"]?.apiKey = .environment(name: "OPENAI_API_KEY")
    }
    form.selectProfile("openai")

    #expect(form.editedProfileKeychainAccount == nil)
    #expect(form.ensureKeychainReference() == nil)
    #expect(form.config.profiles["openai"]?.apiKey == .environment(name: "OPENAI_API_KEY"))
}

@Test func askingTwiceDoesNotChangeTheAccount() {
    var form = loadedForm()
    form.addProfile()
    form.editedProfileFields?.kind = .openaiCompat
    let first = form.ensureKeychainReference()
    let second = form.ensureKeychainReference()
    #expect(first == second)
}
