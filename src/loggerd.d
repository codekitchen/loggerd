import core.stdc.string;
import core.stdc.time;
import core.sys.posix.syslog;
import core.sys.posix.unistd : getlogin, getpid;
import std.algorithm;
import std.c.stdlib : exit;
import std.conv;
import std.exception;
import std.getopt;
import std.path;
import std.socket;
import std.stdio;
import std.string;
import std.range;

enum VERSION = "1.0.0";

alias InputRange!(char[]) InputStream;
alias OutputRange!(const char[]) OutputStream;
alias outputRangeObject!(const char[]) outputStream;

void main(string[] args) {
  bool use_udp = true;
  int priority = LOG_NOTICE;
  ushort server_port = 514;
  string tag = getlogin().to!(string),
         unix_addr, server_addr;
  int log_flags;

  getopt(args,
      std.getopt.config.bundling,
      "id|i",        { log_flags |= LOG_PID; },
      "stderr|s",    { log_flags |= LOG_PERROR; },
      "file|f",      (string _, string fname) { freopen(fname.toStringz, "r", stdin.getFP); },
      "priority|p",  (string _, string p) { priority = parse_priority(p); },
      "tag|t",       &tag,
      "socket|u",    &unix_addr,
      "udp|d",       &use_udp,
      "server|n",    &server_addr,
      "port|P",      &server_port,
      "version|v|V", { writefln("%s version %s", args[0].baseName, VERSION); exit(0); },
      // TODO: the next release of D updates std.getopt to auto-generate
      // help text, so I punted on doing it manually
  );

  stdout.close();
  InputStream input;
  OutputStream output;

  // remove the program name from args, then see if a message was passed on the
  // command line
  auto message_args = args[1..$];
  if (message_args.length > 0) {
    input = [(message_args.join(" ") ~ '\0').dup].inputRangeObject;
  } else {
    // byLine keeps an internal buffer, which can reallocate when we read a
    // bigger line than we've seen before, and doesn't ever shrink
    // this should result in very few allocations overall, which my testing confirms
    input = stdin.byLine(KeepTerminator.yes)
                 // skip blank lines -- length 1 not 0, because it includes the newline
                 .filter!("a.length > 1")
                 // turn the trailing newline into a null byte to make this a C string
                 .map!((s) { if(s.length>0) s[$-1] = '\0'; return s; })
                 .inputRangeObject;
  }

  Socket socket;
  if (server_addr) {
    socket = new Socket(AddressFamily.INET, use_udp ? SocketType.DGRAM : SocketType.STREAM);
    socket.connect(new InternetAddress(server_addr, server_port));
  } else if (unix_addr) {
    socket = new Socket(AddressFamily.UNIX, SocketType.STREAM);
    socket.connect(new UnixAddress(unix_addr));
  }

  if (socket) {
    output = outputStream(SocketSink(socket));
    // when sending over a socket we have to do our own syslog-compliant message formatting
    input = input.syslog_formatter(tag, log_flags, priority).inputRangeObject;
  } else {
    output = outputStream(new SyslogSink(tag, log_flags, priority));
  }

  copy(input, output);
}

struct SocketSink {
  Socket socket;
  void put(const char[] message) {
    socket.send(message);
  }
}

class SyslogSink {
  this(string tag, int log_flags, int priority) {
    openlog(tag.toStringz, log_flags, 0);
    this.priority = priority;
  }

  ~this() {
    closelog();
  }

  void put(const char[] message)
  in { assert(strlen(message.ptr) <= message.length); }
  body {
    syslog(priority, "%s", message.ptr);
  }

  int priority;
}

// since syslog doesn't have a function to just format a message without
// sending it, the formatting logic is duplicated here (just as it is in
// logger.c)
auto syslog_formatter(R)(R source, string tag, int log_flags, int priority) {
  char[] buffer;
  string pid = (log_flags & LOG_PID) ? format("[%d]", getpid()) : "";

  char[] format_message(const char[] message) {
    time_t now = void;
    time(&now);
    auto tp = (ctime(&now)+4)[0..15];

    size_t needed_size = 25 /* priority fudge */ + tp.length + tag.length + pid.length + message.length + 7;
    if (buffer.length < needed_size) {
      buffer.length = needed_size;
    }

    // using C snprintf here instead of std.string.sformat, since I saw GC
    // allocations with sformat (DMD v2.064.2)
    snprintf(buffer.ptr, buffer.length, "<%d>%.15s %.*s%.*s: %s\n",
        priority, tp.ptr, tag.length, tag.ptr, pid.length, pid.ptr, message.ptr);
    return buffer[0..strlen(buffer.ptr)];
  }

  return map!(format_message)(source);
}

enum PRIORITY_NAMES = [
  "alert":    LOG_ALERT,
  "crit" :    LOG_CRIT,
  "debug":    LOG_DEBUG,
  "emerg":    LOG_EMERG,
  "err":      LOG_ERR,
  "error":    LOG_ERR,        /* DEPRECATED */
  "info":     LOG_INFO,
  "notice":   LOG_NOTICE,
  "panic":    LOG_EMERG,      /* DEPRECATED */
  "warn":     LOG_WARNING,    /* DEPRECATED */
  "warning":  LOG_WARNING,

  "auth":     LOG_AUTH,
  "daemon":   LOG_DAEMON,
  "kern":     LOG_KERN,
  "lpr":      LOG_LPR,
  "mail":     LOG_MAIL,
  "news":     LOG_NEWS,
  "security": LOG_AUTH,       /* DEPRECATED */
  "syslog":   LOG_SYSLOG,
  "user":     LOG_USER,
  "uucp":     LOG_UUCP,
  "local0":   LOG_LOCAL0,
  "local1":   LOG_LOCAL1,
  "local2":   LOG_LOCAL2,
  "local3":   LOG_LOCAL3,
  "local4":   LOG_LOCAL4,
  "local5":   LOG_LOCAL5,
  "local6":   LOG_LOCAL6,
  "local7":   LOG_LOCAL7,
];

int parse_priority(string priorities) {
  auto lookup = (string part) =>
    *enforce(part in PRIORITY_NAMES,
             format("Unknown priority %s", part));
  return priorities.split(".").map!(lookup).reduce!("a | b");
}

unittest {
  assert(parse_priority("uucp") == LOG_UUCP);
  assert(parse_priority("news.warn.info") == (LOG_NEWS | LOG_WARNING | LOG_INFO));
  assertThrown(parse_priority("news.wut"));
  assertThrown(parse_priority("wut"));
}
