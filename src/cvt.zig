//!
//! VESA CVT standard timing modelines generator
//!

// This file is a port from libxcvt.c

const std = @import("std");

pub const Parameters = struct {
    width: u32,
    height: u32,
    /// CVT default is 60.0Hz
    refresh_rate: f32 = 60.0,
    reduced: bool = false,
    interlaced: bool = false,
    margins: bool = false,
};

pub const Mode = struct {
    hdisplay: u32,
    vdisplay: u32,
    vrefresh_hz: f32,
    hsync_khz: f32,
    dot_clock_khz: u64,
    hsync_start: u32,
    hsync_end: u32,
    htotal: u32,
    vsync_start: u32,
    vsync_end: u32,
    vtotal: u32,

    vsync: SyncPulse,
    hsync: SyncPulse,
    interlaced: bool,

    pub fn hfrontporch(mode: Mode) u32 {
        return mode.hsync_start - mode.hdisplay;
    }

    pub fn hsyncwidth(mode: Mode) u32 {
        return mode.hsync_end - mode.hsync_start;
    }

    pub fn hbackporch(mode: Mode) u32 {
        return mode.htotal - mode.hsync_end;
    }

    pub fn vfrontporch(mode: Mode) u32 {
        return mode.vsync_start - mode.vdisplay;
    }

    pub fn vsyncwidth(mode: Mode) u32 {
        return mode.vsync_end - mode.vsync_start;
    }

    pub fn vbackporch(mode: Mode) u32 {
        return mode.vtotal - mode.vsync_end;
    }
};

pub const SyncPulse = enum { negative, positive };

/// top/bottom margin size (% of height) - default: 1.8
const CVT_MARGIN_PERCENTAGE = 1.8;

/// character cell horizontal granularity (pixels) - default 8
const CVT_H_GRANULARITY = 8;

/// Minimum vertical porch (lines) - default 3
const CVT_MIN_V_PORCH = 3;

/// Minimum number of vertical back porch lines - default 6
const CVT_MIN_V_BPORCH = 6;

/// Pixel Clock step (kHz)
const CVT_CLOCK_STEP = 250;

/// Minimum time of vertical sync + back porch interval (µs) default 550.0
const CVT_MIN_VSYNC_BP = 550.0;

/// Nominal HSync width (% of line period) - default 8
const CVT_HSYNC_PERCENTAGE = 8;

/// Definition of Horizontal blanking time limitation Gradient (%/kHz) - default 600
const CVT_M_FACTOR = 600;

/// Offset (%) - default 40
const CVT_C_FACTOR = 40;

/// Blanking time scaling factor - default 128
const CVT_K_FACTOR = 128;

/// Scaling factor weighting - default 20
const CVT_J_FACTOR = 20;

const CVT_M_PRIME = CVT_M_FACTOR * CVT_K_FACTOR / 256;
const CVT_C_PRIME = (CVT_C_FACTOR - CVT_J_FACTOR) * CVT_K_FACTOR / 256 + CVT_J_FACTOR;

// Minimum vertical blanking interval time (µs) - default 460
const CVT_RB_MIN_VBLANK = 460;

// Fixed number of clocks for horizontal sync
const CVT_RB_H_SYNC = 32;

// Fixed number of clocks for horizontal blanking
const CVT_RB_H_BLANK = 160;

// Fixed number of lines for vertical front porch - default 3
const CVT_RB_VFPORCH = 3;

fn apply_h_granularity(value: u32) u32 {
    return value - (value % CVT_H_GRANULARITY);
}

fn get_percentage(value: u32, perc: f32) u32 {
    const flt: f32 = @floatFromInt(value);
    const portion = flt * perc / 100.0;
    return @intFromFloat(portion);
}

fn is_aspect_ratio(mode: Mode, h: u32, v: u32) bool {
    return (mode.vdisplay % v) == 0 and ((mode.vdisplay * h / v) == mode.hdisplay);
}

fn float(value: u64) f32 {
    return @floatFromInt(value);
}

fn int(value: f32) u32 {
    return @intFromFloat(value);
}

pub fn compute(params: Parameters) Mode {
    // var vfield_rate: f32 = undefined;
    // var hperiod: f32 = undefined;
    // int hdisplay_rnd, hmargin;
    // int vdisplay_rnd, vmargin, vsync;
    // float interlace;            // Please rename this

    var mode: Mode = .{
        .hdisplay = params.width,
        .vdisplay = params.height,
        .vrefresh_hz = params.refresh_rate,
        .interlaced = params.interlaced,

        .hsync_khz = undefined,
        .dot_clock_khz = undefined,
        .hsync_start = undefined,
        .hsync_end = undefined,
        .htotal = undefined,
        .vsync_start = undefined,
        .vsync_end = undefined,
        .vtotal = undefined,
        .vsync = undefined,
        .hsync = undefined,
    };

    // Required field rate
    const vfield_rate: f32 = if (params.interlaced)
        params.refresh_rate * 2
    else
        params.refresh_rate;

    // Horizontal pixels
    const hdisplay_rnd = apply_h_granularity(mode.hdisplay);

    // Determine left and right borders
    const hmargin = if (params.margins)
        // right margin is actually exactly the same as left
        apply_h_granularity(get_percentage(hdisplay_rnd, CVT_MARGIN_PERCENTAGE))
    else
        0;

    // Find total active pixels
    mode.hdisplay = hdisplay_rnd + 2 * hmargin;

    // Find number of lines per field
    const vdisplay_rnd = if (params.interlaced)
        mode.vdisplay / 2
    else
        mode.vdisplay;

    // Find top and bottom margins nope.
    const vmargin: u32 = if (params.margins)
        // top and bottom margins are equal again.
        get_percentage(vdisplay_rnd, CVT_MARGIN_PERCENTAGE)
    else
        0;

    mode.vdisplay = mode.vdisplay + 2 * vmargin;

    // interlace
    const interlace: f32 = if (params.interlaced)
        0.5
    else
        0.0;

    // Determine vsync Width from aspect ratio
    const vsync: u32 = if (is_aspect_ratio(mode, 4, 3))
        4
    else if (is_aspect_ratio(mode, 16, 9))
        5
    else if (is_aspect_ratio(mode, 16, 10))
        6
    else if (is_aspect_ratio(mode, 5, 4))
        7
    else if (is_aspect_ratio(mode, 15, 9))
        7
    else // Custom
        10;

    var hperiod_khz: f32 = undefined;
    if (params.reduced == false) { // simplified GTF calculation

        // float hblank_percentage;
        // int vsync_and_back_porch, vback_porch;
        // int hblank;

        // Estimated Horizontal period
        hperiod_khz = ((1_000_000.0 / vfield_rate - CVT_MIN_VSYNC_BP)) / (float(vdisplay_rnd + 2 * vmargin + CVT_MIN_V_PORCH) + interlace);

        // Find number of lines in sync + backporch
        const vsync_and_back_porch: f32 = if (((CVT_MIN_VSYNC_BP / hperiod_khz) + 1) < (float(vsync) + CVT_MIN_V_PORCH))
            float(vsync) + CVT_MIN_V_PORCH
        else
            (CVT_MIN_VSYNC_BP / hperiod_khz) + 1;

        // 10. Find number of lines in back porch
        const vback_porch = vsync_and_back_porch - float(vsync);
        _ = vback_porch;

        // Find total number of lines in vertical field
        mode.vtotal = vdisplay_rnd + 2 * vmargin + int(vsync_and_back_porch + interlace + CVT_MIN_V_PORCH);

        // Find ideal blanking duty cycle from formula
        const hblank_percentage = @max(20, CVT_C_PRIME - CVT_M_PRIME * hperiod_khz / 1000.0);

        // Blanking time

        var hblank = int(float(mode.hdisplay) * hblank_percentage / (100.0 - hblank_percentage));
        hblank -= hblank % (2 * CVT_H_GRANULARITY);

        // Find total number of pixels in a line.
        mode.htotal = mode.hdisplay + hblank;

        // Fill in HSync values
        mode.hsync_end = mode.hdisplay + hblank / 2;

        mode.hsync_start = mode.hsync_end - (mode.htotal * CVT_HSYNC_PERCENTAGE) / 100;
        mode.hsync_start += CVT_H_GRANULARITY - mode.hsync_start % CVT_H_GRANULARITY;

        // Fill in vsync values
        mode.vsync_start = mode.vdisplay + CVT_MIN_V_PORCH;
        mode.vsync_end = mode.vsync_start + vsync;
    } else { // reduced blanking

        // Estimate Horizontal period.
        hperiod_khz = ((1000000.0 / vfield_rate - CVT_RB_MIN_VBLANK)) / float(vdisplay_rnd + 2 * vmargin);

        // Find number of lines in vertical blanking
        const vblank_interval_lines = @min(CVT_RB_VFPORCH + vsync + CVT_MIN_V_BPORCH, int(CVT_RB_MIN_VBLANK / hperiod_khz + 1));

        // Find total number of lines in vertical field
        mode.vtotal = vdisplay_rnd + 2 * vmargin + int(interlace) + vblank_interval_lines;

        // Find total number of pixels in a line
        mode.htotal = mode.hdisplay + CVT_RB_H_BLANK;

        // Fill in HSync values
        mode.hsync_end = mode.hdisplay + CVT_RB_H_BLANK / 2;
        mode.hsync_start = mode.hsync_end - CVT_RB_H_SYNC;

        // Fill in vsync values
        mode.vsync_start = mode.vdisplay + CVT_RB_VFPORCH;
        mode.vsync_end = mode.vsync_start + vsync;
    }

    // Find pixel clock frequency (kHz for xf86)
    mode.dot_clock_khz = int(float(mode.htotal * 1000) / hperiod_khz);
    mode.dot_clock_khz -= mode.dot_clock_khz % CVT_CLOCK_STEP;

    // Find actual Horizontal Frequency (kHz)
    mode.hsync_khz = float(mode.dot_clock_khz) / float(mode.htotal);

    // Find actual Field rate
    mode.vrefresh_hz = 1000.0 * float(mode.dot_clock_khz) / float(mode.htotal * mode.vtotal);

    // Find actual vertical frame frequency
    // ignore - just set the mode flag for interlaced
    if (params.interlaced) {
        mode.vtotal *= 2;
    }

    if (params.reduced) {
        mode.hsync = .positive;
        mode.vsync = .negative;
    } else {
        mode.hsync = .negative;
        mode.vsync = .positive;
    }

    // FWXGA hack adapted from hw/xfree86/modes/xf86EdidModes.c, because you can't say 1366
    if (mode.hdisplay == 1360 and mode.vdisplay == 768) {
        mode.hdisplay = 1366;
        mode.hsync_start -= 1;
        mode.hsync_end -= 1;
    }

    return mode;
}

pub fn parse_modeline(modeline: []const u8) !Mode {
    var iter = std.mem.tokenizeScalar(u8, modeline, ' ');

    const header = iter.next() orelse return error.MissingHeader;
    if (!std.mem.eql(u8, header, "Modeline"))
        return error.InvalidHeader;

    const name = iter.next() orelse return error.MissingName;
    _ = name;

    const pclk_str = iter.next() orelse return error.MissingPixelClock;

    const hdisplay_str = iter.next() orelse return error.MissingHDisplay;
    const hsync_start_str = iter.next() orelse return error.MissingHSyncStart;
    const hsync_end_str = iter.next() orelse return error.MissingHSyncEnd;
    const htotal_str = iter.next() orelse return error.MissingHTotal;

    const vdisplay_str = iter.next() orelse return error.MissingVDisplay;
    const vsync_start_str = iter.next() orelse return error.MissingVSyncStart;
    const vsync_end_str = iter.next() orelse return error.MissingVSyncEnd;
    const vtotal_str = iter.next() orelse return error.MissingVTotal;

    const hsync_flag = iter.next() orelse return error.MissingHSyncFlag;
    const vsync_flag = iter.next() orelse return error.MissingVSyncFlag;

    const hsync: SyncPulse = if (std.mem.eql(u8, hsync_flag, "+hsync"))
        .positive
    else if (std.mem.eql(u8, hsync_flag, "-hsync"))
        .negative
    else
        return error.InvalidHSyncFlag;

    const vsync: SyncPulse = if (std.mem.eql(u8, vsync_flag, "+vsync"))
        .positive
    else if (std.mem.eql(u8, vsync_flag, "-vsync"))
        .negative
    else
        return error.InvalidVSyncFlag;

    const pclk_mhz = try std.fmt.parseFloat(f32, pclk_str);
    const hdisplay = try std.fmt.parseInt(u32, hdisplay_str, 10);
    const hsync_start = try std.fmt.parseInt(u32, hsync_start_str, 10);
    const hsync_end = try std.fmt.parseInt(u32, hsync_end_str, 10);
    const htotal = try std.fmt.parseInt(u32, htotal_str, 10);
    const vdisplay = try std.fmt.parseInt(u32, vdisplay_str, 10);
    const vsync_start = try std.fmt.parseInt(u32, vsync_start_str, 10);
    const vsync_end = try std.fmt.parseInt(u32, vsync_end_str, 10);
    const vtotal = try std.fmt.parseInt(u32, vtotal_str, 10);

    const dot_clock_khz: u64 = @intFromFloat(1000 * pclk_mhz);

    const hsync_khz: f32 = float(dot_clock_khz) / float(htotal);
    const vrefresh_hz: f32 = 1000 * hsync_khz / float(vtotal);

    return .{
        .dot_clock_khz = dot_clock_khz,
        .hsync_khz = hsync_khz,
        .vrefresh_hz = vrefresh_hz,
        .hdisplay = hdisplay,
        .hsync_start = hsync_start,
        .hsync_end = hsync_end,
        .htotal = htotal,
        .vdisplay = vdisplay,
        .vsync_start = vsync_start,
        .vsync_end = vsync_end,
        .vtotal = vtotal,
        .hsync = hsync,
        .vsync = vsync,
        .interlaced = false,
    };
}

const ModeTest = struct {
    input: Parameters,
    modeline: []const u8,
    output: Mode,
};

const well_known = [_]ModeTest{
    .{
        .input = .{ .width = 640, .height = 480, .refresh_rate = 60.0 },
        .modeline = "Modeline \"640x480_60.00\"   23.75  640 664 720 800  480 483 487 500 -hsync +vsync",
        .output = .{
            .hdisplay = 640,
            .hsync_start = 664,
            .hsync_end = 720,
            .htotal = 800,
            //
            .vdisplay = 480,
            .vsync_start = 483,
            .vsync_end = 487,
            .vtotal = 500,
            //
            .vrefresh_hz = 59.38,
            .hsync_khz = 29.69,
            .dot_clock_khz = 23_750,
            //
            .hsync = .negative,
            .vsync = .positive,
            .interlaced = false,
        },
    },
    // .{
    //     .input = .{ .width = 640, .height = 480, .refresh_rate = 60.0, .reduced = true },
    //     .modeline = "Modeline \"640x480R\"   23.50  640 688 720 800  480 483 487 494 +hsync -vsync",
    //     .output = .{
    //         .hdisplay = 640,
    //         .hsync_start = 688,
    //         .hsync_end = 720,
    //         .htotal = 800,
    //         //
    //         .vdisplay = 480,
    //         .vsync_start = 483,
    //         .vsync_end = 487,
    //         .vtotal = 494,
    //         //
    //         .vrefresh_hz = 59.46,
    //         .hsync_khz = 29.38,
    //         .dot_clock_khz = 23_500,
    //         //
    //         .hsync = .positive,
    //         .vsync = .negative,
    //         .interlaced = false,
    //     },
    // },
    .{
        .input = .{ .width = 800, .height = 480, .refresh_rate = 60.0 },
        .modeline = "Modeline \"800x480_60.00\"   29.50  800 824 896 992  480 483 493 500 -hsync +vsync",
        .output = .{
            .hdisplay = 800,
            .hsync_start = 824,
            .hsync_end = 896,
            .htotal = 992,
            //
            .vdisplay = 480,
            .vsync_start = 483,
            .vsync_end = 493,
            .vtotal = 500,
            //
            .vrefresh_hz = 59.48,
            .hsync_khz = 29.74,
            .dot_clock_khz = 29_500,
            //
            .hsync = .negative,
            .vsync = .positive,
            .interlaced = false,
        },
    },
    .{
        .input = .{ .width = 1920, .height = 1080, .refresh_rate = 60.0 },
        .modeline = "Modeline \"1920x1080_60.00\"  173.00  1920 2048 2248 2576  1080 1083 1088 1120 -hsync +vsync",
        .output = .{
            .hdisplay = 1920,
            .hsync_start = 2048,
            .hsync_end = 2248,
            .htotal = 2576,
            //
            .vdisplay = 1080,
            .vsync_start = 1083,
            .vsync_end = 1088,
            .vtotal = 1120,
            //
            .vrefresh_hz = 59.96,
            .hsync_khz = 67.16,
            .dot_clock_khz = 173_000,
            //
            .hsync = .negative,
            .vsync = .positive,
            .interlaced = false,
        },
    },
};

fn test_mode_eql(expected: Mode, actual: Mode) !void {
    errdefer {
        std.debug.print("expected: {}\n", .{expected});
        std.debug.print("actual:   {}\n", .{actual});
    }

    try std.testing.expectEqual(expected.hdisplay, actual.hdisplay);
    try std.testing.expectEqual(expected.hsync_start, actual.hsync_start);
    try std.testing.expectEqual(expected.hsync_end, actual.hsync_end);
    try std.testing.expectEqual(expected.htotal, actual.htotal);

    try std.testing.expectEqual(expected.vdisplay, actual.vdisplay);
    try std.testing.expectEqual(expected.vsync_start, actual.vsync_start);
    try std.testing.expectEqual(expected.vsync_end, actual.vsync_end);
    try std.testing.expectEqual(expected.vtotal, actual.vtotal);

    try std.testing.expectApproxEqRel(expected.vrefresh_hz, actual.vrefresh_hz, 0.01);
    try std.testing.expectApproxEqRel(expected.hsync_khz, actual.hsync_khz, 0.01);
    try std.testing.expectEqual(expected.dot_clock_khz, actual.dot_clock_khz);

    try std.testing.expectEqual(expected.hsync, actual.hsync);
    try std.testing.expectEqual(expected.vsync, actual.vsync);
    try std.testing.expectEqual(expected.interlaced, actual.interlaced);
}

test parse_modeline {
    for (well_known) |spec| {
        const mode = try parse_modeline(spec.modeline);
        errdefer std.debug.print("modeline: {s}\n", .{spec.modeline});
        try test_mode_eql(spec.output, mode);
    }
}

test compute {
    for (well_known) |spec| {
        const mode = compute(spec.input);
        errdefer std.debug.print("params:   {}\n", .{spec.input});
        try test_mode_eql(spec.output, mode);
    }
}
