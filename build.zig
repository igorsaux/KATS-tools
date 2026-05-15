// Copyright (C) 2026 Igor Spichkin
// SPDX-License-Identifier: MPL-2.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("kats_tools", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .strip = .optimize != .Debug,
    });

    const mod_static = b.addLibrary(.{
        .name = "kats_tools",
        .linkage = .static,
        .root_module = mod,
    });

    b.installArtifact(mod_static);

    const mod_dynamic = b.addLibrary(.{
        .name = "kats_tools",
        .linkage = .dynamic,
        .root_module = mod,
    });

    b.installArtifact(mod_dynamic);

    const exe = b.addExecutable(.{
        .name = "kats_tools",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .strip = .optimize != .Debug,
            .imports = &.{
                .{ .name = "kats_tools", .module = mod },
            },
        }),
    });

    b.installArtifact(exe);

    const run_step = b.step("run", "Run the app");

    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const header_gen_exe = b.addExecutable(.{
        .name = "header_gen",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/header_gen.zig"),
            .target = target,
            .optimize = optimize,
            .strip = .optimize != .Debug,
            .imports = &.{
                .{ .name = "kats_tools", .module = mod },
            },
        }),
    });

    const header_gen_run = b.addRunArtifact(header_gen_exe);

    header_gen_run.addFileArg(b.path("src/kats_tools.h"));
    const header_path = header_gen_run.addOutputFileArg("kats_tools.h");

    const header_install = b.addInstallHeaderFile(header_path, "kats_tools.h");

    b.getInstallStep().dependOn(&header_install.step);
}
