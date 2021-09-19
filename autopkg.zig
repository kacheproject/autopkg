// Copyright 2021 Rubicon Rowe.
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const Allocator = std.mem.Allocator;
const _p = std.fs.path;

fn PackedSlice (comptime T: type, constant: bool) type {
    const Type = if (constant) [*]const T else [*] T;
    return packed struct {
        ptr: Type,
        len: usize,

        const Self = @This();

        pub fn init(s: if (constant) []const T else []T) Self {
            return Self {
                .ptr = s.ptr,
                .len = s.len,
            };
        }

        pub fn slice(self: *Self) if (constant) []const T else []T {
            return self.ptr[0..self.len];
        }
    };
}

/// This is a travsal structure for your package.
/// The structure is used to transfer infomation between different autopkg in different import container.
pub const AutoPkgI = packed struct {
    name: PackedSlice(u8, true) = undefined,
    path: PackedSlice(u8, true) = undefined,
    rootSrc: PackedSlice(u8, true) = undefined, // Releative to .path
    dependencies: PackedSlice(AutoPkg, false) = undefined,
    includeDirs: PackedSlice([]const u8, true) = undefined,
    cSrcFiles: PackedSlice([]const u8, true) = undefined,
    ccflags: PackedSlice([]const u8, true) = undefined,
    linkSystemLibs: PackedSlice([]const u8, true) = undefined,
    linkLibNames: PackedSlice([]const u8, true) = undefined,
    libraryPaths: PackedSlice([]const u8, true) = undefined,
    linkLibC: bool = false,
    alloc: usize = 0,
    doNotTest: bool = false,

    const Self = @This();

    pub fn fromNormal(val: AutoPkg) Self {
        return AutoPkgI {
            .name = PackedSlice(u8, true).init(val.name),
            .path = PackedSlice(u8, true).init(val.path),
            .rootSrc = PackedSlice(u8, true).init(val.rootSrc),
            .dependencies = PackedSlice(AutoPkg, false).init(val.dependencies),
            .includeDirs = PackedSlice([]const u8, true).init(val.includeDirs),
            .cSrcFiles = PackedSlice([]const u8, true).init(val.cSrcFiles),
            .ccflags = PackedSlice([]const u8, true).init(val.ccflags),
            .linkLibC = val.linkLibC,
            .alloc = if (val.alloc) |alloc| @ptrToInt(alloc) else 0,
            .linkSystemLibs = PackedSlice([]const u8, true).init(val.linkSystemLibs),
            .linkLibNames = PackedSlice([]const u8, true).init(val.linkLibNames),
            .libraryPaths = PackedSlice([]const u8, true).init(val.libraryPaths),
            .doNotTest = val.doNotTest,
        };
    }

    pub fn toNormal(self: *Self) AutoPkg {
        return AutoPkg {
            .name = self.name.slice(),
            .path = self.path.slice(),
            .rootSrc = self.rootSrc.slice(),
            .dependencies = self.dependencies.slice(),
            .includeDirs = self.includeDirs.slice(),
            .cSrcFiles = self.cSrcFiles.slice(),
            .ccflags = self.ccflags.slice(),
            .linkLibC = self.linkLibC,
            .alloc = if (self.alloc != 0) @intToPtr(*Allocator, self.alloc) else null,
            .linkSystemLibs = self.linkSystemLibs.slice(),
            .linkLibNames = self.linkLibNames.slice(),
            .libraryPaths = self.libraryPaths.slice(),
            .doNotTest = self.doNotTest,
        };
    }

    fn advCast(obj: anytype) Self {
        const T = @TypeOf(obj);
        var newObj = Self {};
        comptime const requiredFieldList = .{
            "name", "path", "rootSrc", "dependencies",
            "includeDirs", "cSrcFiles", "ccflags",
            "linkLibC", "linkSystemLibs", "linkLibNames", "libraryPaths",
        };
        inline for (requiredFieldList) |name| {
            if (@hasField(T, name)) {
                @field(newObj, name) = @bitCast(@TypeOf(@field(newObj, name)), @field(obj, name));
            } else {
                @compileError("AutoPkgI field '" ++ name ++ "' not found.");
            }
        }
        newObj.alloc = @field(obj, "alloc");
        // Optional fields:
        if (@hasField(T, "doNotTest")){
            @field(newObj, "doNotTest") = @as(bool, @field(obj, "doNotTest"));
        } else {
            @field(newObj, "doNotTest") = true;
        }
        return newObj;
    }
};

pub fn accept(pkg: anytype) AutoPkg {
    var casted = AutoPkgI.advCast(pkg);
    return casted.toNormal();
}

var generalAllocator = std.heap.GeneralPurposeAllocator(.{}){};

pub fn genExport(pkg: AutoPkg) AutoPkgI {
    var newPkg = pkg.dupe(pkg.alloc orelse &generalAllocator.allocator) catch unreachable;
    return AutoPkgI.fromNormal(newPkg);
}

/// Declare your package.
/// `name` is the name.
/// `path` is relative path to this library from parent AutoPkg declaration or the file where call .addBuild().
/// `rootSrc` could be "" to tell zig build system building without zig file.
/// `dependencies` is dependencies of this package.
pub const AutoPkg = struct {
    name: []const u8,
    path: []const u8,
    rootSrc: []const u8 = &.{}, // Releative to .path
    dependencies: []AutoPkg = &.{},
    includeDirs: []const []const u8 = &.{},
    cSrcFiles: []const []const u8 = &.{},
    ccflags: []const []const u8 = &.{},
    linkSystemLibs: []const []const u8 = &.{},
    linkLibNames: []const []const u8 = &.{},
    libraryPaths: []const []const u8 = &.{},
    linkLibC: bool = false,
    alloc: ?*Allocator = null,
    doNotTest: bool = false,
    // To developers: Once you add new field here, make sure they will be copied in
    // `.resolve()` and `.dupe()`. Don't forget deinitlise it in `.deinit()` when needed.
    // And don't forget add them in `AutoPkgI`.

    const Self = @This();

    /// Add to builder as a static library.
    pub fn addBuild(self: *const Self, b: *std.build.Builder) *std.build.LibExeObjStep {
        var me = b.addStaticLibrary(self.name, if (self.rootSrc.len != 0) self.rootSrc else null);
        self.setupBuild(me, b);
        return me;
    }

    fn setupBuild(self: *const Self, me: *std.build.LibExeObjStep, b: *std.build.Builder) void {
        var dependedSteps = b.allocator.alloc(*std.build.LibExeObjStep, self.dependencies.len) catch unreachable;
        defer b.allocator.free(dependedSteps);
        for (self.dependencies) |d, i| {
            dependedSteps[i] = d.addBuild(b);
            if (d.rootSrc.len > 0) {
                me.addPackagePath(d.name, d.rootSrc);
            }
        }
        for (dependedSteps) |step| {
            me.linkLibrary(step);
        }
        for (self.includeDirs) |dir| {
            me.addIncludeDir(dir);
        }
        for (self.cSrcFiles) |file| {
            me.addCSourceFile(file, self.ccflags);
        }
        if (self.linkLibC) {
            me.linkLibC();
        }
        for (self.linkSystemLibs) |l| {
            me.linkSystemLibrary(l);
        }
        for (self.linkLibNames) |l| {
            me.linkSystemLibraryName(l);
        }
        for (self.libraryPaths) |p| {
            me.addLibPath(p);
        }
    }

    pub fn dependedBy(self: *const Self, step: *std.build.LibExeObjStep) void {
        var buildStep = self.addBuild(step.builder);
        step.linkLibrary(buildStep);
    }

    pub fn addTest(self: *const Self, b: *std.build.Builder, mode: std.builtin.Mode, target: *const std.zig.CrossTarget) *std.build.Step {
        var dependedTestSteps = b.allocator.alloc(?*std.build.Step, self.dependencies.len) catch unreachable;
        defer b.allocator.free(dependedTestSteps);
        for (self.dependencies) |d, i| {
            dependedTestSteps[i] = d.addTest(b, mode, target);
        }
        if (self.rootSrc.len > 0 and !self.doNotTest) {
            var me = b.addTest(self.rootSrc);
            self.setupBuild(me, b);
            me.setBuildMode(mode);
            me.setTarget(target.*);
            for (dependedTestSteps) |step| {
                if (step) |stepnn| {
                    me.step.dependOn(stepnn);
                }
            }
            return &me.step;
        } else {
            var me = b.allocator.create(std.build.Step) catch unreachable;
            me.* = std.build.Step.initNoOp(std.build.Step.Id.Custom, "autopkgTestPlaceHolder", b.allocator);
            for (dependedTestSteps) |step| {
                if (step) |stepnn| {
                    me.dependOn(stepnn);
                }
            }
            return me;
        }
    }

    /// Resolve all pathes, this method should not be called twice or more.
    pub fn resolve(self: *const Self, basePath: []const u8, alloc: *Allocator) Allocator.Error!AutoPkg {
        const rootPathVec = &.{basePath, self.path};
        var rootPath = try _p.join(alloc, rootPathVec);
        // (Rubicon:) above line was "var rootPath = try _p.join(alloc, &.{basePath, self.path});"
        // , but I got a segfault in zig 0.8.0-600 (Fedora 34 built) without compiling error.
        // Add std.debug.printf("{s}/{s}", .{basePath, self.path}); before the line then works fine.
        // Could it caused by the missing data doesn't be stored in stack and be refered
        // when directly used as &.{} in function argument? Might be a compiler bug, IDK.
        // Use the original version (it's more clear) if that were fixed.
        errdefer alloc.free(rootPath);

        var newDependencies = try alloc.alloc(AutoPkg, self.dependencies.len);
        errdefer alloc.free(newDependencies);
        for (self.dependencies) |d, i| {
            newDependencies[i] = try d.resolve(rootPath, alloc);
            errdefer d.deinit();
        }

        var newIncludeDirs = try alloc.alloc([]const u8, self.includeDirs.len);
        errdefer alloc.free(newIncludeDirs);
        for (self.includeDirs) |dir, i| {
            newIncludeDirs[i] = try _p.join(alloc, &.{rootPath, dir});
            errdefer alloc.free(newIncludeDirs[i]);
        }

        var newCSrcFiles = try alloc.alloc([]const u8, self.cSrcFiles.len);
        errdefer alloc.free(newCSrcFiles);
        for (self.cSrcFiles) |f, i| {
            newCSrcFiles[i] = try _p.join(alloc, &.{rootPath, f});
            errdefer alloc.free(newCSrcFiles[i]);
        }
        
        var newRootSrc = if (self.rootSrc.len != 0) try _p.join(alloc, &.{rootPath, self.rootSrc}) else try alloc.dupe(u8, self.rootSrc);
        errdefer alloc.free(newRootSrc);

        var newSystemLibs = try alloc.alloc([]const u8, self.linkSystemLibs.len);
        errdefer alloc.free(newSystemLibs);
        for (self.linkSystemLibs) |l, i| {
            newSystemLibs[i] = try alloc.dupe(u8, l);
            errdefer alloc.free(newSystemLibs[i]);
        }

        var newLibNames = try alloc.alloc([]const u8, self.linkLibNames.len);
        errdefer alloc.free(newLibNames);
        for (self.linkLibNames) |l, i| {
            newLibNames[i] = try alloc.dupe(u8, l);
            errdefer alloc.free(newLibNames[i]);
        }

        var newLibPaths = try alloc.alloc([]const u8, self.libraryPaths.len);
        errdefer alloc.free(newLibPaths);
        for (self.libraryPaths) |l, i| {
            newLibPaths[i] = try _p.join(alloc, &.{rootPath, l});
            errdefer alloc.free(newLibPaths[i]);
        }

        return AutoPkg {
            .name = try alloc.dupe(u8, self.name),
            .path = rootPath,
            .rootSrc = newRootSrc,
            .dependencies = newDependencies,
            .includeDirs = newIncludeDirs,
            .cSrcFiles = newCSrcFiles,
            .ccflags = self.ccflags,
            .linkLibC = self.linkLibC,
            .alloc = alloc,
            .linkSystemLibs = newSystemLibs,
            .linkLibNames = newLibNames,
            .libraryPaths = newLibPaths,
            .doNotTest = self.doNotTest,
        };
    }

    pub fn dupe(self: *const Self, alloc: *Allocator) Allocator.Error!Self {
        var result = Self {
            .name = &.{},
            .path = &.{},
        };
        inline for (.{"name", "path", "rootSrc", "dependencies"}) |name| {
            @field(result, name) = try alloc.dupe(@typeInfo(@TypeOf(@field(self, name))).Pointer.child, @field(self, name));
            errdefer alloc.free(@field(result, name));
        }
        inline for (.{"includeDirs", "cSrcFiles", "ccflags", "linkSystemLibs", "linkLibNames", "libraryPaths"}) |name| {
            @field(result, name) = try alloc.dupe(@typeInfo(@TypeOf(@field(self, name))).Pointer.child, @field(self, name));
            errdefer alloc.free(@field(result, name));
        }
        inline for (.{"linkLibC", "doNotTest"}) |name| {
            @field(result, name) = @field(self, name);
        }
        result.alloc = alloc;
        return result;
    }

    pub fn deinit(self: *Self) void {
        for (self.dependencies) |*d| {
            d.deinit();
        }
        if (self.alloc) |alloc| {
            alloc.free(self.name);
            alloc.free(self.path);
            alloc.free(self.rootSrc);
            alloc.free(self.dependencies);
            const arrToBeFreed = [_][]const []const u8{
                self.includeDirs,
                self.cSrcFiles, self.linkSystemLibs,
                self.linkLibNames, self.libraryPaths
            };
            inline for (.{"includeDirs", "cSrcFiles", "linkSystemLibs", "linkLibNames", "libraryPaths"}) |name| {
                alloc.free(@field(self, name));
            }
            self.alloc = null;
        }
    }
};