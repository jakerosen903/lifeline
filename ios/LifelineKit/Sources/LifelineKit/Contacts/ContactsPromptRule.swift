import Foundation

/// When the landing may show the one system prompt for contacts (spec, "Access"). Pure.
public enum ContactsPromptRule {
    /// The app asks once, and only when the system has no answer yet. It asks on the landing of the recording
    /// whose first kept moment names a person: before that, the prompt has no reason the owner can see.
    /// `landingIsQuiet` is false when the recording was heavy or a serious disclosure showed: no system dialog
    /// follows that, and the next quiet landing asks instead (PB36).
    public static func shouldAsk(access: ContactsAccess, askedBefore: Bool, keptPeopleInSession: Int, landingIsQuiet: Bool) -> Bool {
        access == .notAsked && !askedBefore && keptPeopleInSession > 0 && landingIsQuiet
    }
}
