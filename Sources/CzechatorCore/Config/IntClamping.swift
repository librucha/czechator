/// Shared by every config type that pins a hand-edited value into a range.
///
/// Was `fileprivate` in TriggerConfig.swift; EditBudget needs the same helper
/// and a second copy would be one more place to keep in step.
extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
