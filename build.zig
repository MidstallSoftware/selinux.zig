const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const linkage = b.option(std.Build.Step.Compile.Linkage, "linkage", "whether to statically or dynamically link the library") orelse .static;

    const libsepolSource = b.dependency("libsepol", .{});
    const libselinuxSource = b.dependency("libselinux", .{});

    const pcre2 = b.dependency("pcre2", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });

    const fts = b.dependency("musl-fts", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });

    const python = b.dependency("python", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });

    const libsepol = std.Build.Step.Compile.create(b, .{
        .name = "sepol",
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        },
        .kind = .lib,
        .linkage = linkage,
    });

    libsepol.addIncludePath(libsepolSource.path("include"));

    try libsepol.root_module.c_macros.append(b.allocator, "-DHAVE_REALLOCARRAY");

    {
        var dir = try std.fs.openDirAbsolute(libsepolSource.path("src").getPath(libsepolSource.builder), .{
            .iterate = true,
        });
        defer dir.close();

        var walk = try dir.walk(b.allocator);
        defer walk.deinit();

        while (try walk.next()) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".c")) continue;

            libsepol.addCSourceFile(.{
                .file = libsepolSource.path(b.pathJoin(&.{ "src", entry.path })),
            });
        }
    }

    libsepol.installHeadersDirectoryOptions(.{
        .source_dir = libsepolSource.path("include/sepol"),
        .install_dir = .header,
        .install_subdir = "sepol",
    });

    b.installArtifact(libsepol);

    const libselinux = std.Build.Step.Compile.create(b, .{
        .name = "selinux",
        .root_module = .{
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        },
        .kind = .lib,
        .linkage = linkage,
    });

    libselinux.addIncludePath(libselinuxSource.path("include"));
    libselinux.linkLibrary(libsepol);
    libselinux.linkLibrary(pcre2.artifact("pcre2-8"));
    libselinux.linkLibrary(python.artifact("python3"));

    if (target.result.isMusl()) {
        libselinux.linkLibrary(fts.artifact("fts"));
        libselinux.root_module.addCMacro("stat64", "stat");
        libselinux.root_module.addCMacro("fstat64", "fstat");
        libselinux.root_module.addCMacro("lstat64", "lstat");
        libselinux.root_module.addCMacro("fstatat64", "fstatat");
        libselinux.root_module.addCMacro("blksize64_t", "blksize_t");
        libselinux.root_module.addCMacro("blkcnt64_t", "blkcnt_t");
        libselinux.root_module.addCMacro("ino64_t", "ino_t");
        libselinux.root_module.addCMacro("off64_t", "off_t");
        try libselinux.root_module.c_macros.append(b.allocator, "-DHAVE_STRLCPY");
    }

    libselinux.root_module.addCMacro("PCRE2_CODE_UNIT_WIDTH", "8");

    try libselinux.root_module.c_macros.append(b.allocator, "-DHAVE_REALLOCARRAY");
    try libselinux.root_module.c_macros.append(b.allocator, "-D_GNU_SOURCE");
    try libselinux.root_module.c_macros.append(b.allocator, "-D__USE_GNU");
    try libselinux.root_module.c_macros.append(b.allocator, "-DUSE_PCRE2");

    {
        var dir = try std.fs.openDirAbsolute(libselinuxSource.path("src").getPath(libselinuxSource.builder), .{
            .iterate = true,
        });
        defer dir.close();

        var walk = try dir.walk(b.allocator);
        defer walk.deinit();

        while (try walk.next()) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.basename, ".c")) continue;

            libselinux.addCSourceFile(.{
                .file = libselinuxSource.path(b.pathJoin(&.{ "src", entry.path })),
            });
        }
    }

    libselinux.installHeadersDirectoryOptions(.{
        .source_dir = libselinuxSource.path("include/selinux"),
        .install_dir = .header,
        .install_subdir = "selinux",
    });

    b.installArtifact(libselinux);
}
