/// Represents a suggested field value with an associated confidence score.
struct SuggestedFieldValue<Value: Sendable>: Sendable {
    let value: Value
    let confidence: Double
}
