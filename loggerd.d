import core.sys.posix.syslog;
import core.sys.posix.unistd : getlogin, getpid;
import core.stdc.time;
import core.stdc.string;
import std.c.stdlib : exit;
import std.conv;
import std.datetime;
import std.getopt;
import std.path;
import std.socket;
import std.stdio;
import std.string;
import core.memory;

enum VERSION = "1.0.0";

void main(string[] args) {
  bool use_udp;
  int priority = LOG_NOTICE;
  ushort udp_port = 514;
  string tag = getlogin().to!(string),
         unix_addr, udp_addr;
  int log_flags;
  size_t max_line_size = 65536;

  // TODO: the next release of D updates std.getopt to auto-generate this
  // help text, so I bailed on doing it manually
  auto print_help = {
    writefln("
Usage:
%s [options] [message]
", args[0].baseName);
    exit(0);
  };

  getopt(args,
      std.getopt.config.bundling,
      "id|i", { log_flags |= LOG_PID; },
      "stderr|s", { log_flags |= LOG_PERROR; },
      "file|f", (string _, string fname) { freopen(fname.toStringz, "r", stdin.getFP); },
      "priority|p", (string _, string p) { priority = parse_priority(p); },
      "tag|t", &tag,
      "socket|u", &unix_addr,
      "udp|d", &use_udp,
      "server|n", &udp_addr,
      "port|P", &udp_port,
      "version|v|V", { writefln("%s version %s", args[0].baseName, VERSION); exit(0); },
      "help|h", print_help,
      "max|m", &max_line_size,
  );

  Socket socket;
  if (udp_addr) {
    socket = new Socket(AddressFamily.INET, SocketType.DGRAM);
    socket.connect(new InternetAddress(udp_addr, udp_port));
  } else if (unix_addr) {
    socket = new Socket(AddressFamily.UNIX, use_udp ? SocketType.DGRAM : SocketType.STREAM);
    socket.connect(new UnixAddress(unix_addr));
  } else { // write directly to syslog() C function
    openlog(tag.toStringz, log_flags, 0);
  }

  stdout.close();

  char[25] pid_buffer;
  char[] socket_message_buffer;
  time_t now;

  // line is assumed to be null-terminated already
  void log_line(const char[] line) {
    if (socket) {
      const char[] pid = (log_flags & LOG_PID) ? sformat(pid_buffer, "[%d]", getpid()) : "";
      // this odd timestamp format is what syslog requires, it's from the ctime() C function,
      // truncated to the first 15 chars
      // http://www.ietf.org/rfc/rfc3164.txt
      time(&now);
      char[] tp = (ctime(&now)+4)[0..15];

      size_t needed_size = 25 /* priority fudge */ + tp.length + tag.length + pid.length + line.length + 7;
      if (socket_message_buffer.length < needed_size) {
        socket_message_buffer.length = needed_size;
      }

      // using C snprintf here instead of std.string.sformat, since I saw GC
      // allocations with sformat
      snprintf(socket_message_buffer.ptr, socket_message_buffer.length,
          "<%d>%.15s %.*s%.*s: %s\n",
          priority, tp.ptr, tag.length, tag.ptr, pid.length, pid.ptr, line.ptr);
      auto message = socket_message_buffer[0..strlen(socket_message_buffer.ptr)];
      socket.send(message);
      if (log_flags & LOG_PERROR)
        stderr.write(message);
    } else {
      syslog(priority, "%s", line.ptr);
    }
  }

  // remove the program name from args, then see if a message was passed on the
  // command line
  auto message_args = args[1..$];
  if (message_args.length > 0) {
    log_line(message_args.join(" ") ~ '\0');
  } else {
    char[] buffer = new char[max_line_size];
    while (fgets(buffer.ptr, cast(int)buffer.length, stdin.getFP) != null) {
      // comment from logger.c:
      // glibc is buggy and adds an additional newline,
      // so we have to remove it here until glibc is fixed
      size_t len = strlen(buffer.ptr);
      if (len > 0  && buffer[len-1] == '\n')
        buffer[len-1] = '\0';

      log_line(buffer[0..len]);
    }
  }

  if(!socket)
    closelog();
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

int parse_priority(string priority) {
  int result;
  foreach (part; priority.split(".")) {
    int *p = part in PRIORITY_NAMES;
    if (p) result |= *p;
    else {
      throw new Exception(format("Unknown priority %s", part));
    }
  }
  return result;
}
