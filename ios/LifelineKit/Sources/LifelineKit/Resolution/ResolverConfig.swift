import Foundation

/// The resolver's numbers. Configuration, not code.
public struct ResolverConfig: Sendable, Equatable {
    /// How far "before" or "after" may reach past the target's edge.
    public var relativeSlackYears: Int
    /// A plain age ("when I was six") covers this many years from the birthday.
    public var ageBandYears: Int
    /// US school year: grade N runs from `schoolYearStartMonth` of birth year + N + gradeOffsetYears
    /// to `schoolYearEndMonth` of the following year.
    public var schoolYearStartMonth: Int
    public var schoolYearEndMonth: Int
    public var gradeOffsetYears: Int

    public init(relativeSlackYears: Int = 5, ageBandYears: Int = 1, schoolYearStartMonth: Int = 9, schoolYearEndMonth: Int = 6, gradeOffsetYears: Int = 5) {
        self.relativeSlackYears = relativeSlackYears; self.ageBandYears = ageBandYears
        self.schoolYearStartMonth = schoolYearStartMonth; self.schoolYearEndMonth = schoolYearEndMonth; self.gradeOffsetYears = gradeOffsetYears
    }

    public static let `default` = ResolverConfig()
}
