/// Every user-facing string in one place. The core speaks Czech to the user
/// and English to the compiler.
public enum ErrorMessages {

    public static func describe(_ error: any Error) -> String {
        switch error {
        case let error as PipelineError:
            return describe(error)
        case let error as SecretError:
            return describe(error)
        case let error as ConfigError:
            return describe(error)
        default:
            return String(describing: error)
        }
    }

    static func describe(_ error: PipelineError) -> String {
        switch error {
        case .noText:
            return "Ve schránce není text."
        case .inputTooLarge(let bytes, let limit):
            return "Vstup má \(bytes) B, limit je \(limit) B."
        case .providerFailed(let failure):
            return "Model neodpověděl: \(describe(failure))"
        case .verificationFailed(let count):
            return "Výsledek neprošel kontrolou (\(count) \(segmentWord(count))). "
                + "Schránka zůstala beze změny."
        }
    }

    static func describe(_ failure: ProviderFailure) -> String {
        switch failure {
        case .unreachable:
            return "nepodařilo se k němu připojit."
        case .unauthorized:
            return "odmítl přihlašovací klíč."
        case .http(let status):
            return "vrátil chybu HTTP \(status)."
        case .unparsableResponse:
            return "vrátil odpověď, kterou nešlo zpracovat."
        }
    }

    static func describe(_ error: SecretError) -> String {
        switch error {
        case .notFound(let name):
            return "Nepodařilo se načíst klíč: \(name)."
        case .unsupported(let kind):
            return "Zdroj tajemství \(kind) není v tomto prostředí dostupný."
        }
    }

    static func describe(_ error: ConfigError) -> String {
        switch error {
        case .serializationFailed:
            return "Konfiguraci se nepodařilo zapsat."
        case .unknownActiveProfile(let name):
            return "Konfigurace odkazuje na profil \(name), který v ní není."
        case .invalidEndpoint(let profile, let value):
            return "Profil \(profile) má neplatnou adresu: \(value). "
                + "Očekává se http:// nebo https:// včetně hostitele."
        }
    }

    static func segmentWord(_ count: Int) -> String {
        switch count {
        case 1: return "vadný segment"
        case 2...4: return "vadné segmenty"
        default: return "vadných segmentů"
        }
    }
}
