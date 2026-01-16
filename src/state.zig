//! Persistent state management for fzm.
//!
//! Stores user state in a JSON file at `<data_dir>/state.json`.
//! Currently tracks the "in use" version, with support for future
//! features like user-defined aliases.

const std = @import("std");
const dirs = @import("dirs.zig");

const STATE_FILE_NAME = "state.json";

/// Persistent fzm state.
pub const State = struct {
    allocator: std.mem.Allocator,

    /// The version currently "in use" (used by `fzm env` for symlinks).
    in_use: ?[]const u8 = null,

    /// User-defined version aliases
    aliases: std.json.ArrayHashMap([]const u8) = .{},

    /// Load state from `<data_dir>/state.json`.
    /// Returns default empty state if file doesn't exist.
    pub fn load(allocator: std.mem.Allocator) !State {
        const data_dir = try dirs.getDataDir(allocator);
        defer allocator.free(data_dir);
        return loadFromDir(allocator, data_dir);
    }

    fn loadFromDir(allocator: std.mem.Allocator, data_dir: []const u8) !State {
        const state_path = try std.fs.path.join(allocator, &.{ data_dir, STATE_FILE_NAME });
        defer allocator.free(state_path);

        const file = std.fs.openFileAbsolute(state_path, .{}) catch |err| switch (err) {
            error.FileNotFound => return .{ .allocator = allocator },
            else => return err,
        };
        defer file.close();

        const content = try file.readToEndAlloc(allocator, 1024 * 1024);
        defer allocator.free(content);

        const JsonState = struct {
            in_use: ?[]const u8 = null,
            aliases: std.json.ArrayHashMap([]const u8) = .{},
        };

        var parsed = std.json.parseFromSlice(JsonState, allocator, content, .{}) catch {
            // Corrupt state file - return default state
            return .{ .allocator = allocator };
        };
        defer parsed.deinit();

        // Dupe strings so they outlive the parsed JSON
        return .{
            .allocator = allocator,
            .in_use = if (parsed.value.in_use) |v| try allocator.dupe(u8, v) else null,
            .aliases = .{}, // TODO: deep copy aliases when implemented
        };
    }

    /// Save state to `<data_dir>/state.json`.
    /// Creates the data directory if it doesn't exist.
    pub fn save(self: *const State) !void {
        const data_dir = try dirs.getDataDir(self.allocator);
        defer self.allocator.free(data_dir);
        return self.saveToDir(data_dir);
    }

    fn saveToDir(self: *const State, data_dir: []const u8) !void {
        // Ensure data directory exists
        std.fs.cwd().makePath(data_dir) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };

        const state_path = try std.fs.path.join(self.allocator, &.{ data_dir, STATE_FILE_NAME });
        defer self.allocator.free(state_path);

        const file = try std.fs.createFileAbsolute(state_path, .{});
        defer file.close();

        const JsonState = struct {
            in_use: ?[]const u8,
            aliases: std.json.ArrayHashMap([]const u8),
        };

        const json_state: JsonState = .{
            .in_use = self.in_use,
            .aliases = self.aliases,
        };

        var buf: [4096]u8 = undefined;
        var writer = file.writer(&buf);
        try std.json.Stringify.value(json_state, .{ .whitespace = .indent_2 }, &writer.interface);
        try writer.interface.writeByte('\n');
        try writer.interface.flush();
    }

    /// Set the in-use version. Frees the previous value if set.
    pub fn setInUse(self: *State, version: []const u8) !void {
        if (self.in_use) |old| {
            self.allocator.free(old);
        }
        self.in_use = try self.allocator.dupe(u8, version);
    }

    /// Free allocated memory.
    pub fn deinit(self: *State) void {
        if (self.in_use) |v| {
            self.allocator.free(v);
            self.in_use = null;
        }
        // TODO: free aliases when implemented
    }
};

// Tests

const testing = std.testing;

test "load returns empty state when file doesn't exist" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var s = try State.loadFromDir(testing.allocator, tmp_path);
    defer s.deinit();

    try testing.expect(s.in_use == null);
}

test "save and load round-trip" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    // Create and save state
    var original: State = .{ .allocator = testing.allocator, .in_use = null };
    defer original.deinit();
    try original.setInUse("master");
    try original.saveToDir(tmp_path);

    // Load state
    var loaded = try State.loadFromDir(testing.allocator, tmp_path);
    defer loaded.deinit();

    try testing.expect(loaded.in_use != null);
    try testing.expectEqualStrings("master", loaded.in_use.?);
}

test "load handles corrupt JSON gracefully" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Write corrupt JSON
    const file = try tmp_dir.dir.createFile(STATE_FILE_NAME, .{});
    try file.writeAll("{ invalid json }");
    file.close();

    const tmp_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    var s = try State.loadFromDir(testing.allocator, tmp_path);
    defer s.deinit();

    // Should return default state, not error
    try testing.expect(s.in_use == null);
}

test "save creates directory if needed" {
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realpathAlloc(testing.allocator, ".");
    defer testing.allocator.free(tmp_path);

    const nested_path = try std.fs.path.join(testing.allocator, &.{ tmp_path, "nested", "dir" });
    defer testing.allocator.free(nested_path);

    var s: State = .{ .allocator = testing.allocator, .in_use = null };
    defer s.deinit();
    try s.setInUse("0.13.0");
    try s.saveToDir(nested_path);

    // Verify file was created
    var loaded = try State.loadFromDir(testing.allocator, nested_path);
    defer loaded.deinit();

    try testing.expectEqualStrings("0.13.0", loaded.in_use.?);
}

test "setInUse frees previous value" {
    var s: State = .{ .allocator = testing.allocator, .in_use = null };
    defer s.deinit();

    try s.setInUse("master");
    try testing.expectEqualStrings("master", s.in_use.?);

    try s.setInUse("0.13.0");
    try testing.expectEqualStrings("0.13.0", s.in_use.?);
}
