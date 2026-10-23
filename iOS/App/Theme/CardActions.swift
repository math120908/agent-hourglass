/// Callbacks an account card can trigger; the host view supplies the behavior.
struct CardActions {
    var signIn: () -> Void = {}
    var copyDiagnostics: () -> Void = {}
    var toggleReset: () -> Void = {}
}
