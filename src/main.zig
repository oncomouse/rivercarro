// Layout client for river <https://github.com/ifreund/river>
//
// Copyright 2021 Hugo Machet
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const mem = std.mem;
const math = std.math;
const assert = std.debug.assert;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const river = wayland.client.river;

const flags = @import("flags.zig");

const log = std.log.scoped(.rivercarro);

const usage =
    \\Usage: rivercarro [options]
    \\
    \\  -help           Print this help message and exit.
    \\  -view-padding   Set the padding around views in pixels. (Default 6)
    \\  -outer-padding  Set the padding around the edge of the layout area in
    \\                  pixels. (Default 6)
    \\
    \\  The following commands may also be sent to rivercarro at runtime:
    \\
    \\  -main-location  Set the initial location of the main area in the
    \\                  layout. (Default left)
    \\  -main-count     Set the initial number of views in the main area of the
    \\                  layout. (Default 1)
    \\  -main-ratio     Set the initial ratio of main area to total layout
    \\                  area. (Default: 0.6)
    \\  -no-smart-gaps  Disable smart gaps
    \\
;

const Command = enum {
    @"main-location",
    @"main-count",
    @"main-ratio",
};

const Location = enum {
    top,
    right,
    bottom,
    left,
    monocle,
};

// Configured through command line options
var default_view_padding: u32 = 6;
var default_outer_padding: u32 = 6;
var default_main_location: Location = .left;
var default_main_count: u32 = 1;
var default_main_ratio: f64 = 0.6;
var smart_gaps: bool = true;

var only_one_view: bool = false;

/// We don't free resources on exit, only when output globals are removed.
const gpa = std.heap.c_allocator;

const Context = struct {
    initialized: bool = false,
    layout_manager: ?*river.LayoutManagerV3 = null,
    outputs: std.TailQueue(Output) = .{},

    fn addOutput(context: *Context, registry: *wl.Registry, name: u32) !void {
        const wl_output = try registry.bind(name, wl.Output, 3);
        errdefer wl_output.release();
        const node = try gpa.create(std.TailQueue(Output).Node);
        errdefer gpa.destroy(node);
        try node.data.init(context, wl_output, name);
        context.outputs.append(node);
    }
};

const Output = struct {
    wl_output: *wl.Output,
    name: u32,

    main_location: Location,
    main_count: u32,
    main_ratio: f64,

    outer_padding: u32,
    view_padding: u32,

    layout: *river.LayoutV3 = undefined,

    fn init(output: *Output, context: *Context, wl_output: *wl.Output, name: u32) !void {
        output.* = .{
            .wl_output = wl_output,
            .name = name,
            .main_location = default_main_location,
            .main_count = default_main_count,
            .main_ratio = default_main_ratio,
            .outer_padding = default_outer_padding,
            .view_padding = default_view_padding,
        };
        if (context.initialized) try output.getLayout(context);
    }

    fn getLayout(output: *Output, context: *Context) !void {
        assert(context.initialized);
        output.layout = try context.layout_manager.?.getLayout(output.wl_output, "rivercarro");
        output.layout.setListener(*Output, layoutListener, output);
    }

    fn deinit(output: *Output) void {
        output.wl_output.release();
        output.layout.destroy();
    }

    fn layoutListener(layout: *river.LayoutV3, event: river.LayoutV3.Event, output: *Output) void {
        switch (event) {
            .namespace_in_use => fatal("namespace 'rivercarro' already in use.", .{}),

            .user_command => |ev| {
                var it = mem.tokenize(mem.span(ev.command), " ");
                const raw_cmd = it.next() orelse {
                    log.err("not enough arguments", .{});
                    return;
                };
                const raw_arg = it.next() orelse {
                    log.err("not enough arguments", .{});
                    return;
                };
                if (it.next() != null) {
                    log.err("too many arguments", .{});
                    return;
                }
                const cmd = std.meta.stringToEnum(Command, raw_cmd) orelse {
                    log.err("unknown command: {s}", .{raw_cmd});
                    return;
                };
                switch (cmd) {
                    .@"main-location" => {
                        output.main_location = std.meta.stringToEnum(Location, raw_arg) orelse {
                            log.err("unknown location: {s}", .{raw_arg});
                            return;
                        };
                    },
                    .@"main-count" => {
                        const arg = std.fmt.parseInt(i32, raw_arg, 10) catch |err| {
                            log.err("failed to parse argument: {}", .{err});
                            return;
                        };
                        switch (raw_arg[0]) {
                            '+' => output.main_count = math.add(
                                u32,
                                output.main_count,
                                @intCast(u32, arg),
                            ) catch math.maxInt(u32),
                            '-' => {
                                const result = @as(i33, output.main_count) + arg;
                                if (result >= 0) output.main_count = @intCast(u32, result);
                            },
                            else => output.main_count = @intCast(u32, arg),
                        }
                    },
                    .@"main-ratio" => {
                        const arg = std.fmt.parseFloat(f64, raw_arg) catch |err| {
                            log.err("failed to parse argument: {}", .{err});
                            return;
                        };
                        switch (raw_arg[0]) {
                            '+', '-' => {
                                output.main_ratio = math.clamp(output.main_ratio + arg, 0.1, 0.9);
                            },
                            else => output.main_ratio = math.clamp(arg, 0.1, 0.9),
                        }
                    },
                }
            },

            .layout_demand => |ev| {
                const main_count = math.clamp(output.main_count, 1, ev.view_count);
                const secondary_count = if (ev.view_count > main_count)
                    ev.view_count - main_count
                else
                    0;

                only_one_view = if (ev.view_count == 1 or output.main_location == .monocle)
                    true
                else
                    false;

                // Don't add gaps if there is only one view
                if (only_one_view and smart_gaps) {
                    default_outer_padding = 0;
                    default_view_padding = 0;
                } else {
                    default_outer_padding = output.outer_padding;
                    default_view_padding = output.view_padding;
                }

                const usable_width = switch (output.main_location) {
                    .left, .right, .monocle => ev.usable_width - 2 * default_outer_padding,
                    .top, .bottom => ev.usable_height - 2 * default_outer_padding,
                };
                const usable_height = switch (output.main_location) {
                    .left, .right, .monocle => ev.usable_height - 2 * default_outer_padding,
                    .top, .bottom => ev.usable_width - 2 * default_outer_padding,
                };

                // to make things pixel-perfect, we make the first main and first secondary
                // view slightly larger if the height is not evenly divisible
                var main_width: u32 = undefined;
                var main_height: u32 = undefined;
                var main_height_rem: u32 = undefined;

                var secondary_width: u32 = undefined;
                var secondary_height: u32 = undefined;
                var secondary_height_rem: u32 = undefined;

                if (output.main_location == .monocle) {
                    main_width = usable_width;
                    main_height = usable_height;

                    secondary_width = usable_width;
                    secondary_height = usable_height;
                } else {
                    if (main_count > 0 and secondary_count > 0) {
                        main_width = @floatToInt(u32, output.main_ratio * @intToFloat(f64, usable_width));
                        main_height = usable_height / main_count;
                        main_height_rem = usable_height % main_count;

                        secondary_width = usable_width - main_width;
                        secondary_height = usable_height / secondary_count;
                        secondary_height_rem = usable_height % secondary_count;
                    } else if (main_count > 0) {
                        main_width = usable_width;
                        main_height = usable_height / main_count;
                        main_height_rem = usable_height % main_count;
                    } else if (secondary_width > 0) {
                        main_width = 0;
                        secondary_width = usable_width;
                        secondary_height = usable_height / secondary_count;
                        secondary_height_rem = usable_height % secondary_count;
                    }
                }

                var i: u32 = 0;
                while (i < ev.view_count) : (i += 1) {
                    var x: i32 = undefined;
                    var y: i32 = undefined;
                    var width: u32 = undefined;
                    var height: u32 = undefined;

                    if (output.main_location == .monocle) {
                        x = 0;
                        y = 0;
                        width = main_width;
                        height = main_height;
                    } else {
                        if (i < main_count) {
                            x = 0;
                            y = @intCast(i32, (i * main_height) +
                            if (i > 0) default_view_padding else 0 +
                                if (i > 0) main_height_rem else 0);
                            width = main_width - default_view_padding / 2;
                            height = main_height -
                            if (i > 0) default_view_padding else 0 +
                            if (i == 0) main_height_rem else 0;
                        } else {
                            x = @intCast(i32, (main_width - default_view_padding / 2) + default_view_padding);
                            y = @intCast(i32, ((i - main_count) * secondary_height) +
                                if (i > main_count) default_view_padding  else 0 +
                                if (i > main_count) secondary_height_rem else 0);
                            width = secondary_width - default_view_padding / 2;
                            height = secondary_height -
                                if (i > main_count) default_view_padding else 0 +
                                if (i == main_count) secondary_height_rem else 0;
                        }
                    }

                    switch (output.main_location) {
                        .left => layout.pushViewDimensions(
                            x + @intCast(i32, default_outer_padding),
                            y + @intCast(i32, default_outer_padding),
                            width,
                            height,
                            ev.serial,
                        ),
                        .right => layout.pushViewDimensions(
                            @intCast(i32, usable_width - width) - x + @intCast(i32, default_outer_padding),
                            y + @intCast(i32, default_outer_padding),
                            width,
                            height,
                            ev.serial,
                        ),
                        .top => layout.pushViewDimensions(
                            y + @intCast(i32, default_outer_padding),
                            x + @intCast(i32, default_outer_padding),
                            height,
                            width,
                            ev.serial,
                        ),
                        .bottom => layout.pushViewDimensions(
                            y + @intCast(i32, default_outer_padding),
                            @intCast(i32, usable_width - width) - x + @intCast(i32, default_outer_padding),
                            height,
                            width,
                            ev.serial,
                        ),
                        .monocle => layout.pushViewDimensions(
                            x + @intCast(i32, default_outer_padding),
                            y + @intCast(i32, default_outer_padding),
                            width,
                            height,
                            ev.serial,
                        ),
                    }
                }

                switch (output.main_location) {
                    .left => layout.commit("left", ev.serial),
                    .right => layout.commit("right", ev.serial),
                    .top => layout.commit("top", ev.serial),
                    .bottom => layout.commit("bottom", ev.serial),
                    .monocle => layout.commit("monocle", ev.serial),
                }
            },
        }
    }
};

pub fn main() !void {
    // https://github.com/ziglang/zig/issues/7807
    const argv: [][*:0]const u8 = std.os.argv;
    const result = flags.parse(argv[1..], &[_]flags.Flag{
        .{ .name = "-help", .kind = .boolean },
        .{ .name = "-view-padding", .kind = .arg },
        .{ .name = "-outer-padding", .kind = .arg },
        .{ .name = "-main-location", .kind = .arg },
        .{ .name = "-main-count", .kind = .arg },
        .{ .name = "-main-ratio", .kind = .arg },
        .{ .name = "-no-smart-gaps", .kind = .boolean },
    }) catch {
        try std.io.getStdErr().writeAll(usage);
        std.os.exit(1);
    };
    if (result.args.len != 0) fatalPrintUsage("unknown option '{s}'", .{result.args[0]});

    if (result.boolFlag("-help")) {
        try std.io.getStdOut().writeAll(usage);
        std.os.exit(0);
    }
    if (result.argFlag("-view-padding")) |raw| {
        default_view_padding = std.fmt.parseUnsigned(u32, mem.span(raw), 10) catch
            fatalPrintUsage("invalid value '{s}' provided to -view-padding", .{raw});
    }
    if (result.argFlag("-outer-padding")) |raw| {
        default_outer_padding = std.fmt.parseUnsigned(u32, mem.span(raw), 10) catch
            fatalPrintUsage("invalid value '{s}' provided to -outer-padding", .{raw});
    }
    if (result.argFlag("-main-location")) |raw| {
        default_main_location = std.meta.stringToEnum(Location, mem.span(raw)) orelse
            fatalPrintUsage("invalid value '{s}' provided to -main-location", .{raw});
    }
    if (result.argFlag("-main-count")) |raw| {
        default_main_count = std.fmt.parseUnsigned(u32, mem.span(raw), 10) catch
            fatalPrintUsage("invalid value '{s}' provided to -main-count", .{raw});
    }
    if (result.argFlag("-main-ratio")) |raw| {
        default_main_ratio = std.fmt.parseFloat(f64, mem.span(raw)) catch
            fatalPrintUsage("invalid value '{s}' provided to -main-ratio", .{raw});
    }
    if (result.boolFlag("-no-smart-gaps")) {
        smart_gaps = false;
    }

    const display = wl.Display.connect(null) catch {
        std.debug.warn("Unable to connect to Wayland server.\n", .{});
        std.os.exit(1);
    };
    defer display.disconnect();

    var context: Context = .{};

    const registry = try display.getRegistry();
    registry.setListener(*Context, registryListener, &context);
    _ = try display.roundtrip();

    if (context.layout_manager == null) {
        fatal("Wayland compositor does not support river_layout_v3.\n", .{});
    }

    context.initialized = true;

    var it = context.outputs.first;
    while (it) |node| : (it = node.next) {
        const output = &node.data;
        try output.getLayout(&context);
    }

    while (true) _ = try display.dispatch();
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (std.cstr.cmp(global.interface, river.LayoutManagerV3.getInterface().name) == 0) {
                context.layout_manager = registry.bind(global.name, river.LayoutManagerV3, 1) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Output.getInterface().name) == 0) {
                context.addOutput(registry, global.name) catch |err|
                    fatal("failed to bind output: {}", .{err});
            }
        },
        .global_remove => |ev| {
            var it = context.outputs.first;
            while (it) |node| : (it = node.next) {
                const output = &node.data;
                if (output.name == ev.name) {
                    context.outputs.remove(node);
                    output.deinit();
                    gpa.destroy(node);
                    break;
                }
            }
        },
    }
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    std.os.exit(1);
}

fn fatalPrintUsage(comptime format: []const u8, args: anytype) noreturn {
    log.err(format, args);
    std.io.getStdErr().writeAll(usage) catch {};
    std.os.exit(1);
}
