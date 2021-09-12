const std = @import("std");
const Builder = @import("std").build.Builder;

const ScanProtocolsStep = @import("deps/zig-wayland/build.zig").ScanProtocolsStep;

pub fn build(b: *Builder) !void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const scanner = ScanProtocolsStep.create(b);

    const protocol_path = std.mem.trim(u8, try b.exec(
        &[_][]const u8{ "pkg-config", "--variable=pkgdatadir", "river-protocols" },
    ), &std.ascii.spaces);
    const layout_protocol = try std.fs.path.join(b.allocator, &[_][]const u8{protocol_path, "river-layout-v3.xml"});
    scanner.addProtocolPath(layout_protocol);

    const exe = b.addExecutable("rivercarro", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.step.dependOn(&scanner.step);
    exe.addPackage(scanner.getPkg());
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");

    scanner.addCSource(exe);

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
