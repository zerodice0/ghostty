const std = @import("std");

/// Tracks a single touchscreen gesture in logical widget coordinates.
/// Movement stays a tap until it crosses the threshold, at which point
/// predominantly vertical movement becomes scrolling and other movement is
/// ignored.
pub const Gesture = struct {
    pub const movement_threshold: f64 = 8.0;

    pub const Point = struct {
        x: f64,
        y: f64,
    };

    pub const Finish = union(enum) {
        tap: Point,
        scroll: Scroll,
        cancel,
    };

    pub const Scroll = struct {
        delta_y: f64,

        /// The gesture origin is present only when this update first
        /// classifies the gesture as a scroll.
        origin: ?Point,
    };

    pub const Update = union(enum) {
        scroll: Scroll,
        rejected,
    };

    const Phase = enum {
        idle,
        pending,
        scrolling,
        rejected,
    };

    start: Point = .{ .x = 0, .y = 0 },
    last_offset_y: f64 = 0,
    phase: Phase = .idle,

    pub fn begin(self: *Gesture, start: Point) void {
        self.* = .{
            .start = start,
            .phase = .pending,
        };
    }

    /// Updates the cumulative offset and returns the new vertical scroll
    /// delta, if the gesture has been classified as a vertical swipe.
    pub fn update(self: *Gesture, offset: Point) ?Update {
        var origin: ?Point = null;
        switch (self.phase) {
            .idle, .rejected => return null,
            .pending => {
                const distance_squared =
                    offset.x * offset.x + offset.y * offset.y;
                if (distance_squared < movement_threshold * movement_threshold)
                    return null;

                if (@abs(offset.y) <= @abs(offset.x)) {
                    self.phase = .rejected;
                    return .rejected;
                }

                self.phase = .scrolling;
                origin = self.start;
            },
            .scrolling => {},
        }

        const delta = offset.y - self.last_offset_y;
        self.last_offset_y = offset.y;
        return .{ .scroll = .{
            .delta_y = delta,
            .origin = origin,
        } };
    }

    /// Finishes the gesture, accounting for any final movement that did not
    /// arrive in an update callback.
    pub fn finish(self: *Gesture, offset: Point) Finish {
        const final_scroll = self.update(offset);
        const result: Finish = switch (self.phase) {
            .pending => .{ .tap = .{
                .x = self.start.x + offset.x,
                .y = self.start.y + offset.y,
            } },
            .scrolling => .{ .scroll = if (final_scroll) |value|
                switch (value) {
                    .scroll => |scroll| scroll,
                    .rejected => unreachable,
                }
            else
                .{ .delta_y = 0, .origin = null } },
            .idle, .rejected => .cancel,
        };

        self.* = .{};
        return result;
    }
};

test "touch gesture classifies small movement as a tap" {
    var gesture: Gesture = .{};
    gesture.begin(.{ .x = 20, .y = 30 });

    try std.testing.expectEqual(null, gesture.update(.{ .x = 3, .y = -2 }));
    const result = gesture.finish(.{ .x = 3, .y = -2 });

    try std.testing.expectEqualDeep(
        Gesture.Finish{ .tap = .{ .x = 23, .y = 28 } },
        result,
    );
}

test "touch gesture accumulates vertical swipe deltas" {
    var gesture: Gesture = .{};
    gesture.begin(.{ .x = 20, .y = 30 });

    try std.testing.expectEqualDeep(
        Gesture.Update{ .scroll = .{
            .delta_y = -10,
            .origin = .{ .x = 20, .y = 30 },
        } },
        gesture.update(.{ .x = 2, .y = -10 }).?,
    );
    try std.testing.expectEqualDeep(
        Gesture.Update{ .scroll = .{
            .delta_y = -4,
            .origin = null,
        } },
        gesture.update(.{ .x = 3, .y = -14 }).?,
    );
    try std.testing.expectEqual(
        Gesture.Finish{ .scroll = .{
            .delta_y = -2,
            .origin = null,
        } },
        gesture.finish(.{ .x = 3, .y = -16 }),
    );
}

test "touch gesture rejects non-vertical movement" {
    var gesture: Gesture = .{};
    gesture.begin(.{ .x = 20, .y = 30 });

    try std.testing.expectEqual(
        Gesture.Update.rejected,
        gesture.update(.{ .x = 10, .y = 2 }).?,
    );
    try std.testing.expectEqual(
        Gesture.Finish.cancel,
        gesture.finish(.{ .x = 12, .y = 3 }),
    );
}

test "touch gesture accounts for movement first observed at finish" {
    var gesture: Gesture = .{};
    gesture.begin(.{ .x = 20, .y = 30 });

    try std.testing.expectEqual(
        Gesture.Finish{ .scroll = .{
            .delta_y = 12,
            .origin = .{ .x = 20, .y = 30 },
        } },
        gesture.finish(.{ .x = 1, .y = 12 }),
    );
}
