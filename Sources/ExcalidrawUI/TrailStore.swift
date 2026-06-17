import ExcalidrawMath
import Foundation

/// Ephemeral fading trails for the laser pointer and the eraser. Points are
/// recorded in scene coordinates with a timestamp; the overlay renders them with
/// an age-based opacity and drops anything past `fadeDuration`. Plain class (no
/// observation): the overlay's `TimelineView` redraws every frame while a laser/
/// eraser tool is active, so it just reads the current points each frame.
public final class TrailStore {
    public struct Dot: Sendable {
        public var position: Point
        public var time: TimeInterval
    }

    /// How long (seconds) a trail point takes to fully fade out.
    public static let fadeDuration: TimeInterval = 0.7

    public private(set) var laser: [Dot] = []
    public private(set) var eraser: [Dot] = []

    public init() {}

    /// Append a point to the laser trail at `now`, pruning faded points.
    public func addLaser(_ position: Point, now: TimeInterval) {
        laser = prune(laser, now: now)
        laser.append(Dot(position: position, time: now))
    }

    /// Append a point to the eraser trail at `now`, pruning faded points.
    public func addEraser(_ position: Point, now: TimeInterval) {
        eraser = prune(eraser, now: now)
        eraser.append(Dot(position: position, time: now))
    }

    public func clear() {
        laser = []
        eraser = []
    }

    /// Points still within the fade window; the caller computes per-point opacity
    /// from `time`.
    public func visibleLaser(now: TimeInterval) -> [Dot] {
        prune(laser, now: now)
    }

    public func visibleEraser(now: TimeInterval) -> [Dot] {
        prune(eraser, now: now)
    }

    private func prune(_ points: [Dot], now: TimeInterval) -> [Dot] {
        points.filter { now - $0.time < Self.fadeDuration }
    }
}
