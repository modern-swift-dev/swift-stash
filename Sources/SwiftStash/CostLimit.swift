/// A limit on the total cost of the entries in a ``Cache``.
///
/// The cache computes each value's cost when the value is added and keeps the sum of
/// all costs at or below ``maxCost``, evicting entries in the order of its eviction policy.
///
/// Example:
/// ```swift
/// let cache = Cache(
///     storageEngine: MemoryStorageEngine<String, Data>(),
///     costLimit: CostLimit(maxCost: 10_000_000) { $0.count }
/// )
/// ```
public struct CostLimit<Value>: Sendable {

    /// The maximum total cost of the cache's entries.
    public let maxCost: Int

    /// Returns the cost of a value, such as its size in bytes. Negative costs count as zero.
    public let cost: @Sendable (Value) -> Int

    /// Creates a cost limit.
    ///
    /// - Parameters:
    ///   - maxCost: The maximum total cost of the cache's entries.
    ///   - cost: Returns the cost of a value, such as its size in bytes. Negative costs count as zero.
    public init(maxCost: Int, cost: @escaping @Sendable (Value) -> Int) {
        self.maxCost = maxCost
        self.cost = cost
    }

    /// The cost of a value, clamped to zero.
    func cost(of value: Value) -> Int {
        max(0, cost(value))
    }
}
