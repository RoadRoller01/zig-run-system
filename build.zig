const std = @import("std");
const Cpio = @import("cpio.zig");
const Step = std.Build.Step;

pub fn addRunSystem(hisB: *std.Build) *std.Build.Step.Run {
    const build_root_path = hisB.build_root.path orelse std.fs.cwd().realpathAlloc(hisB.allocator, ".") catch unreachable;
    const dir_name = std.fs.path.basename(build_root_path);

    const b =
        if (std.mem.eql(u8, dir_name, "zig-run-system"))
            hisB
        else
            hisB.dependency("zig_run_system", .{}).builder;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const init_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const init = b.addExecutable(.{
        .name = "init",
        .root_module = init_mod,
    });
    // b.installArtifact(init);

    var initramfs_step = Step.init(.{
        .name = "GenerateInitramfs",
        .id = .custom,
        .owner = b,
        .makeFn = make,
    });
    initramfs_step.dependOn(&init.step);

    const initramfs_file = init.getEmittedBinDirectory().path(b, "initramfs.cpio");

    const call_qemu = b.addSystemCommand(switch (target.result.cpu.arch) {
        .aarch64 => &.{"qemu-system-aarch644"},
        .x86_64 => &.{"qemu-system-x86_64"},
        else => @panic("arch is not added"),
    });

    call_qemu.addArgs(if (target.result.os.tag == .linux) switch (target.result.cpu.arch) {
        .aarch64 => &.{ "-kernel", b.path("images/Image.gz").src_path.sub_path, "-M", "virt", "-cpu", "cortex-a53", "-append", "console=ttyAMA0 init=\\init" },
        .x86_64 => &.{ "-kernel", b.path("images/bzImage").src_path.sub_path, "-append", "console=ttyS0 init=\\init" },
        else => @panic("linux arch is not added"),
    } else @panic("os is not added"));

    call_qemu.addArg("-display");
    call_qemu.addArg("none");
    call_qemu.addArg("-serial");
    call_qemu.addArg("mon:stdio");
    call_qemu.addArg("-initrd");
    call_qemu.addFileArg(initramfs_file);

    call_qemu.step.dependOn(&initramfs_step);

    return call_qemu;
}

fn make(step: *Step, options: Step.MakeOptions) anyerror!void {
    // step.dump(.{ .handle = 0 });
    _ = options;
    const b = step.owner;
    const init: *Step.Compile = @fieldParentPtr("step", step.dependencies.getLast());

    const init_file = try init.getEmittedBin().getPath3(b, step).openFile("", .{});
    var init_stream = std.io.StreamSource{ .file = init_file };

    const initramfs_file = try init.getEmittedBinDirectory().getPath3(b, step).openFile("initramfs.cpio", .{ .mode = .write_only });
    var initramfs_stream = std.io.StreamSource{ .file = initramfs_file };

    var cpio = try Cpio.init(&initramfs_stream);
    try cpio.addFile("init", &init_stream, 0o755);
    try cpio.finalize();
}

pub fn build(b: *std.Build) void {
    // TODO: tests(:
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&addRunSystem(b).step);
    return;
}
