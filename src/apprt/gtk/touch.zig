const std = @import("std");

/// Tracks a single touchscreen gesture in logical widget coordinates.
/// Movement stays a tap until it crosses the threshold, at which point
/// predominantly vertical movement becomes scrolling and other movement starts
/// text selection.
pub const Gesture = struct {
    pub const movement_threshold: f64 = 8.0;

    pub const Point = struct {
        x: f64,
        y: f64,
    };

    pub const Finish = union(enum) {
        tap: Point,
        scroll: Scroll,
        selection: Selection,
        cancel,
    };

    pub const Scroll = struct {
        delta_y: f64,

        /// The gesture origin is present only when this update first
        /// classifies the gesture as a scroll.
        origin: ?Point,
    };

    pub const Selection = struct {
        /// The current absolute position of the selection gesture.
        point: Point,

        /// The gesture origin is present only when movement first classifies
        /// the gesture as selection.
        origin: ?Point,
    };

    pub const Update = union(enum) {
        scroll: Scroll,
        selection: Selection,
    };

    const Phase = enum {
        idle,
        pending,
        scrolling,
        selecting,
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

    /// Updates the cumulative offset and returns a scroll delta or selection
    /// position after the gesture crosses the movement threshold.
    pub fn update(self: *Gesture, offset: Point) ?Update {
        var origin: ?Point = null;
        switch (self.phase) {
            .idle => return null,
            .pending => {
                const distance_squared =
                    offset.x * offset.x + offset.y * offset.y;
                if (distance_squared < movement_threshold * movement_threshold)
                    return null;

                self.phase = if (@abs(offset.y) > @abs(offset.x))
                    .scrolling
                else
                    .selecting;
                origin = self.start;
            },
            .scrolling, .selecting => {},
        }

        return switch (self.phase) {
            .scrolling => result: {
                const delta = offset.y - self.last_offset_y;
                self.last_offset_y = offset.y;
                break :result .{ .scroll = .{
                    .delta_y = delta,
                    .origin = origin,
                } };
            },
            .selecting => .{ .selection = .{
                .point = .{
                    .x = self.start.x + offset.x,
                    .y = self.start.y + offset.y,
                },
                .origin = origin,
            } },
            .idle, .pending => unreachable,
        };
    }

    /// Finishes the gesture, accounting for any final movement that did not
    /// arrive in an update callback.
    pub fn finish(self: *Gesture, offset: Point) Finish {
        const final_update = self.update(offset);
        const result: Finish = switch (self.phase) {
            .pending => .{ .tap = .{
                .x = self.start.x + offset.x,
                .y = self.start.y + offset.y,
            } },
            .scrolling => .{ .scroll = if (final_update) |value|
                switch (value) {
                    .scroll => |scroll| scroll,
                    .selection => unreachable,
                }
            else
                .{ .delta_y = 0, .origin = null } },
            .selecting => .{ .selection = switch (final_update.?) {
                .selection => |selection| selection,
                .scroll => unreachable,
            } },
            .idle => .cancel,
        };

        self.* = .{};
        return result;
    }

    /// Abandons the current gesture without producing a final action.
    pub fn cancel(self: *Gesture) void {
        self.* = .{};
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

    // Once scrolling starts, horizontal movement must not start selection.
    try std.testing.expectEqualDeep(
        Gesture.Update{ .scroll = .{
            .delta_y = -1,
            .origin = null,
        } },
        gesture.update(.{ .x = 20, .y = -15 }).?,
    );
    try std.testing.expectEqual(
        Gesture.Finish{ .scroll = .{
            .delta_y = -1,
            .origin = null,
        } },
        gesture.finish(.{ .x = 22, .y = -16 }),
    );
}

test "touch gesture classifies horizontal movement as selection" {
    var gesture: Gesture = .{};
    gesture.begin(.{ .x = 20, .y = 30 });

    try std.testing.expectEqualDeep(
        Gesture.Update{ .selection = .{
            .point = .{ .x = 30, .y = 32 },
            .origin = .{ .x = 20, .y = 30 },
        } },
        gesture.update(.{ .x = 10, .y = 2 }).?,
    );

    // Once selection starts, vertical movement must not turn into scrolling.
    try std.testing.expectEqualDeep(
        Gesture.Update{ .selection = .{
            .point = .{ .x = 31, .y = 50 },
            .origin = null,
        } },
        gesture.update(.{ .x = 11, .y = 20 }).?,
    );
    try std.testing.expectEqualDeep(
        Gesture.Finish{ .selection = .{
            .point = .{ .x = 32, .y = 52 },
            .origin = null,
        } },
        gesture.finish(.{ .x = 12, .y = 22 }),
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

test "touch gesture accounts for selection first observed at finish" {
    var gesture: Gesture = .{};
    gesture.begin(.{ .x = 20, .y = 30 });

    try std.testing.expectEqualDeep(
        Gesture.Finish{ .selection = .{
            .point = .{ .x = 32, .y = 33 },
            .origin = .{ .x = 20, .y = 30 },
        } },
        gesture.finish(.{ .x = 12, .y = 3 }),
    );
}

test "touch gesture cancel resets active selection" {
    var gesture: Gesture = .{};
    gesture.begin(.{ .x = 20, .y = 30 });
    _ = gesture.update(.{ .x = 10, .y = 2 });

    gesture.cancel();
    try std.testing.expectEqual(
        Gesture.Finish.cancel,
        gesture.finish(.{ .x = 12, .y = 3 }),
    );
}
