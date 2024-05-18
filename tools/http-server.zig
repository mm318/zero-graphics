const std = @import("std");
const http = std.http;
const log = std.log.scoped(.server);

const server_addr = "127.0.0.1";
const server_port = 8000;

const linger = extern struct { l_onoff: i32, l_linger: i32 }; // where is this defined in std?
const zero_linger_val = linger{ .l_onoff = 1, .l_linger = 0 };

var stop = std.atomic.Value(bool).init(false);

var server: ?std.net.Server = null;
var server_lock: std.Thread.Mutex = .{};

// forcibly close listening socket
fn closeServer() void {
    log.info("closing server!", .{});

    server_lock.lock();
    defer server_lock.unlock();

    if (server) |*s| {
        const result = std.c.setsockopt(
            s.stream.handle,
            std.posix.SOL.SOCKET,
            std.posix.SO.LINGER,
            &zero_linger_val,
            @sizeOf(@TypeOf(zero_linger_val)),
        );
        log.info("set server no linger result: {}", .{result});

        s.deinit();
    }

    server = null;
}

const Connection = struct {
    connection: ?std.net.Server.Connection = null,
    lock: std.Thread.Mutex = .{},

    // force close any open connection
    fn close(self: *Connection) void {
        self.lock.lock();
        defer self.lock.unlock();

        if (self.connection) |c| {
            const result = std.c.setsockopt(
                c.stream.handle,
                std.posix.SOL.SOCKET,
                std.posix.SO.LINGER,
                &zero_linger_val,
                @sizeOf(@TypeOf(zero_linger_val)),
            );
            log.info("set connection no linger result: {}", .{result});

            c.stream.close();
        }

        self.connection = null;
    }
};

var connections: std.ArrayList(Connection) = undefined;

fn getNextConnectionIdx() !usize {
    for (0.., connections.items) |i, c| {
        if (c.connection == null) {
            return i;
        }
    }
    try connections.append(.{});
    return connections.items.len - 1;
}

var workers: std.Thread.Pool = undefined;

fn handleInterrupt(signal: i32) callconv(.C) void {
    std.log.info("caught signal {}", .{signal});

    // mark loops can be exited
    stop.store(true, .monotonic);

    for (0.., connections.items) |idx, *c| {
        log.info("closing connection {}!", .{idx});
        c.close();
    }

    closeServer();
}

// Run the server and handle incoming requests.
fn runServer(allocator: std.mem.Allocator) !void {
    const dir = try std.fs.cwd().openDir(".", .{});
    while (!stop.load(.monotonic)) {
        const connection = server.?.accept() catch |err| {
            log.err("server error: {}\n", .{err});
            continue;
        };
        const idx = getNextConnectionIdx() catch |err| {
            log.err("server error: {}\n", .{err});
            continue;
        };
        connections.items[idx].connection = connection;
        try workers.spawn(handleConnection, .{ idx, dir, allocator });
    }
}

pub fn getMimeType(file_ext: []const u8) []const u8 {
    const eq = struct {
        pub fn eq(a: []const u8, b: []const u8) bool {
            return std.mem.eql(u8, a, b);
        }
    }.eq;

    var buf: [8]u8 = undefined;
    const file_type = std.ascii.lowerString(&buf, file_ext);

    return if (eq(".jpg", file_type) or eq(".jpeg", file_type))
        "image/jpeg"
    else if (eq(".png", file_type))
        "image/png"
    else if (eq(".gif", file_type))
        "image/gif"
    else if (eq(".webp", file_type))
        "image/webp"
    else if (eq(".bmp", file_type))
        "image/bmp"
    else if (eq(".svg", file_type))
        "image/svg+xml"
    else if (eq(".mp4", file_type))
        "video/mp4"
    else if (eq(".h264", file_type))
        "video/H264"
    else if (eq(".h265", file_type))
        "video/H265"
    else if (eq(".mov", file_type))
        "video/quicktime"
    else if (eq(".webm", file_type))
        "video/webm"
    else if (eq(".mkv", file_type))
        "video/x-matroska"
    else if (eq(".3gp", file_type))
        "video/3gpp"
    else if (eq(".mpeg", file_type) or eq(".m4v", file_type))
        "video/mpeg"
    else if (eq(".avi", file_type))
        "video/x-msvideo"
    else if (eq(".wmv", file_type))
        "video/x-ms-wmv"
    else if (eq(".flv", file_type))
        "video/x-flv"
    else if (eq(".pdf", file_type))
        "application/pdf"
    else if (eq(".js", file_type))
        "application/javascript"
    else if (eq(".json", file_type))
        "application/json"
    else if (eq(".md", file_type))
        "text/markdown"
    else if (eq(".html", file_type) or eq(".htm", file_type))
        "text/html"
    else if (eq(".css", file_type))
        "text/css"
    else
        "text/plain";
}

fn handleConnection(connection_idx: usize, dir: std.fs.Dir, allocator: std.mem.Allocator) void {
    log.info("opening connection {}", .{connection_idx});
    defer {
        log.info("closing connection {}!", .{connection_idx});
        connections.items[connection_idx].close();
    }

    var read_buffer: [8000]u8 = undefined;
    var http_server = http.Server.init(connections.items[connection_idx].connection.?, &read_buffer);
    while (!stop.load(.monotonic) and http_server.state == .ready) {
        var request = http_server.receiveHead() catch |err| {
            log.err("connection error: {s}\n", .{@errorName(err)});
            return;
        };

        // Log the request details.
        log.info("{s} {s} {s}", .{ @tagName(request.head.method), @tagName(request.head.version), request.head.target });

        // Read the request body.
        const request_reader = request.reader() catch |err| {
            log.err("connection error: {}\n", .{err});
            return;
        };
        const request_body = request_reader.readAllAlloc(allocator, 8192) catch |err| {
            log.err("connection error: {}\n", .{err});
            return;
        };
        defer allocator.free(request_body);

        const file = dir.openFile(request.head.target[1..], .{});
        if (file) |f| {
            defer f.close();

            const file_size = (f.stat() catch |err| {
                log.err("file error: {}\n", .{err});
                return;
            }).size;
            log.info("estimated file size: {} bytes", .{file_size});

            const content = f.readToEndAllocOptions(allocator, 16777216, file_size, @alignOf(u8), null) catch |err| {
                log.err("file error: {}\n", .{err});
                return;
            };
            defer allocator.free(content);

            const idx = std.mem.lastIndexOfScalar(u8, request.head.target, '.') orelse 0;
            const mime_type = getMimeType(request.head.target[idx..]);
            log.info("file size: {} bytes. file type: {s}", .{ content.len, mime_type });

            // Write the response body.
            request.respond(content, .{
                .extra_headers = &.{
                    .{ .name = "content-type", .value = mime_type },
                },
            }) catch |err| {
                log.err("connection error: {}\n", .{err});
                return;
            };
        } else |_| {
            // Set the response status to 404 (not found).
            log.info("file not found!", .{});
            request.respond(&.{}, .{ .status = .not_found }) catch |err| {
                log.err("connection error: {}\n", .{err});
                return;
            };
        }
    }
}

pub fn main() !void {
    // Create an allocator.
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer std.debug.assert(gpa.deinit() == .ok);
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 2) {
        std.log.err("Missing argument: Application name!", .{});
        std.process.exit(1);
    }
    const application_name = args[1];

    connections = std.ArrayList(Connection).init(allocator);
    defer {
        log.info("freeing connections!", .{});
        connections.deinit();
    }

    try workers.init(.{ .allocator = allocator, .n_jobs = 4 });
    defer {
        log.info("freeing workers!", .{});
        workers.deinit();
    }

    var block_sigset: std.c.sigset_t = undefined;
    std.c.sigfillset(&block_sigset);
    const act = std.c.Sigaction{
        .handler = .{ .handler = handleInterrupt },
        .mask = block_sigset,
        .flags = 0,
    };
    _ = std.c.sigaction(std.c.SIG.INT, &act, null);

    // Initialize the server.
    const address = try std.net.Address.parseIp(server_addr, server_port);
    server = try address.listen(.{});
    defer closeServer();

    // Log the server address and port.
    log.info(
        "Application is being served at http://{s}:{d}/{s}.htm",
        .{ server_addr, server_port, application_name },
    );

    // Run the server.
    runServer(allocator) catch |err| {
        // Handle server errors.
        log.err("server error: {}\n", .{err});
        if (@errorReturnTrace()) |trace| {
            std.debug.dumpStackTrace(trace.*);
        }
    };
}
