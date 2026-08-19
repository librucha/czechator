/// Where the corrected text goes. MVP writes back to the clipboard; a later
/// version adds paste-in-place.
public protocol OutputSink: Sendable {
    func write(_ result: PipelineResult) throws
}
