const std = @import("std");
const Cpio = @import("./cpio.zig");
const Step = std.Build.Step;

pub fn addRunSystem(hisB: *std.Build, argv: []const []const u8) *std.Build.Step.Run {
    const hisBDir = hisB.build_root.path orelse std.fs.cwd().realpathAlloc(hisB.allocator, ".") catch unreachable;
    const dir_name = std.fs.path.basename(hisBDir);

    const b =
        if (std.mem.startsWith(u8, dir_name, "zig-run-system"))
            hisB
        else
            hisB.dependency("zig_run_system", .{}).builder;

    const bDir =
        if (b == hisB)
            null
        else
            b.build_root.path orelse std.fs.cwd().realpathAlloc(b.allocator, ".") catch unreachable;

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const init_mod = hisB.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const init = b.addExecutable(.{
        .name = "init",
        .root_module = init_mod,
    });

    // b.installArtifact(init);

    const builders = .{ hisB, b };

    std.debug.print("{any}", .{@TypeOf(builders)});

    const initramfs_step = b.allocator.create(Step) catch @panic("OOM");
    initramfs_step.* = Step.init(.{
        .name = "GenerateInitramfs",
        .id = .custom,
        .owner = builders[1],
        .makeFn = make,
    });
    initramfs_step.dependOn(&init.step);

    const initramfs_file = init.getEmittedBinDirectory().path(b, "initramfs.cpio");

    var call_qemu = b.addSystemCommand(switch (target.result.cpu.arch) {
        .aarch64 => &.{"qemu-system-aarch64"},
        .x86_64 => &.{"qemu-system-x86_64"},
        else => @panic("arch is not added"),
    });

    call_qemu.addArgs(if (target.result.os.tag == .linux) switch (target.result.cpu.arch) {
        .aarch64 => &.{
            "-kernel",
            b.path("images/Image.gz").src_path.sub_path,
            "-M",
            "virt",
            "-cpu",
            "cortex-a53",
            "-append",
            b.fmt("console=ttyAMA0 init=\\init {s} {s} {s} {s} ", .{ hisBDir, b.graph.zig_lib_directory.path.?, bDir orelse "none", std.mem.join(b.allocator, " ", argv) catch unreachable }),
        },
        .x86_64 => &.{
            "-kernel",
            b.path("images/bzImage").src_path.sub_path,
            "-append",
            b.fmt("console=ttyS0 init=\\init {s} {s} {s} {s}", .{ hisBDir, b.graph.zig_lib_directory.path.?, bDir orelse "none", std.mem.join(b.allocator, " ", argv) catch unreachable }),
        },
        else => @panic("linux arch is not added"),
    } else @panic("os is not added"));

    call_qemu.addArgs(&.{
        "-display",
        "none",
        "-serial",
        "mon:stdio",
        "-initrd",
    });
    call_qemu.addFileArg(initramfs_file);

    // mount parnet project dir
    call_qemu.addArgs(&.{
        "-virtfs",
        b.fmt("local,path={s},mount_tag=host0,security_model=mapped,id=host0", .{hisBDir}),
    });

    // mount zig lib dir
    call_qemu.addArgs(&.{
        "-virtfs",
        b.fmt("local,path={s},mount_tag=host1,security_model=mapped,id=host1", .{b.graph.zig_lib_directory.path.?}),
    });

    if (bDir) |dir| {
        // mount our project dir
        call_qemu.addArgs(&.{
            "-virtfs",
            b.fmt("local,path={s},mount_tag=host2,security_model=mapped,id=host2", .{dir}),
        });
    }
    call_qemu.step.dependOn(initramfs_step);

    return call_qemu;
}

fn make(step: *Step, options: Step.MakeOptions) anyerror!void {
    // step.dump(.{ .handle = 0 });
    _ = options;
    const b = step.owner;
    const init: *Step.Compile = @fieldParentPtr("step", step.dependencies.getLast());

    const _bin_dir = init.getEmittedBinDirectory().getPath3(b, step);
    var bin_dir = _bin_dir.openDir(".", .{}) catch @panic("Failed to open bin dir");
    defer bin_dir.close();

    const init_file = bin_dir.openFile("init", .{}) catch @panic("init not found");
    defer init_file.close();
    var init_stream = std.io.StreamSource{ .file = init_file };

    const initramfs_file = bin_dir.createFile("initramfs.cpio", .{}) catch @panic("Create initramfs file failed");
    defer initramfs_file.close();
    var initramfs_stream = std.io.StreamSource{ .file = initramfs_file };

    var cpio = try Cpio.init(&initramfs_stream);
    try cpio.addFile("init", &init_stream, 0o755);

    try cpio.finalize();
}

pub fn build(b: *std.Build) void {
    if (b.pkg_hash.len == 0) {
        var test_step = b.step("test", "Run tests");
        test_step.dependOn(&addRunSystem(b, &.{ "tajreba", "jamela" }).step);
    }
    return;
}
