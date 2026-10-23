public enum AuthError: Error, Sendable, Equatable {
    case portUnavailable, stateMismatch, timeout, cancelled, differentAccount
}
