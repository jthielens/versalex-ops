versalex-logstash
=================

Log tailer for Cleo Harmony and Cleo VLTrader (collectively "VersaLex") including a LogStash input plugin.

## Tailing the XML log

Harmony and VLTrader produce an XML log file in `logs/Harmony.xml` or `log/VLTrader.xml`, depending on the product.  This log file is maintained as a complete valid XML file, so each time it is updated, the proper closing tags (usually `</Run></Session></Log>`) are appended.  The next time an event is written to the log, the closing tags are overwritten, new `<Event>...</Event>`(s) are written to the log, and the XML elements are again properly closed.  This makes the log file impossible to `tail` using traditional tools.

### Command Line

```
usage: ruby versalex.rb [options] [file]
    -f, --follow           follow until killed
    -n, --lines N          show last N lines (or skip +N lines)
    -s, --service name     use logs for named upstart service
    -h, --help             Show this message
```

_The source of the log events_ is determined explitly by the `file` name supplied at the end of the command line, or implicitly by the `--service name` argument.  If both the filename and service name are supplied, the filename takes precedence.  If neither is supplied, the default `cleo-service` is used.  If using a service name, the service must be registered as an upstart service with an `/etc/init/service.conf` file containing an `env CLEOHOME=path` directive, which is used to locate the XML log file.

_The log events to display_ are controlled by `--lines` (`-n`) and `--follow` (`-f`).  If a line count is supplied, the last `n` events are display (if the line count starts with `+`, then the first `n` events are skipped instead).  If `-follow` is requested, the display does not stop at the end of the log file, but instead the program monitors and waits for ongoing updates to be posted to the file.  Note that the follow continues at the top of the file if the log file is rotated.

### Use as a Ruby module

The `VersaLex` module supplies a `VersaLex::EventLog` class that uses Ruby's `observer` mixin.  The constructor takes the log filename as a mandatory argument, followed by the following options, all optional:

| Option => Default     | Description                                |
|-----------------------|--------------------------------------------|
| `:follow  => false`   | Set to `true` to enable log file following |
| `:bufsize => 1048576` | Read buffer size (default is 1 MB)         |
| `:sleep   => 2`       | Sleep interval when following, in seconds  |

The EventLog passes events to registered observers through their `update` methods.  The events may be one of:

- the `:eof` symbol, when the parser gets to the end of a file (but before it sleeps, if following)
- the `:next` symbol, when the follower detects a file switch (between the last event of the old file and the first event of the new file)
- a `VersaLex::Event` object, which has the following attributes
  - `event.type` &mdash; the type (the enclosing XML element for the event)
  - `event.time` &mdash; the event timestamp as a Ruby time
  - `event.threadid` &mdash; the internal event thread ID `TN` number
  - `event.thread` &mdash; the thread name for `TN`
  - `event.command` &mdash; the internal event command ID `CN` number
  - `event.id` &mdash; the internal event ID `EN` number (1, 2, ...)
  - `event.attributes` &mdash;
  - `event.message` &mdash; formats a single line message "thread[threadid] type text", formatting the text from the attributes
  - `event.inspect` &mdash; formats an extended message "id/time message", using an ISO-8601 time format

Example:

```
require 'versalex'

eventlog = VersaLex::EventLog.new "Harmony.xml"
reporter = Object.new
def reporter.update(event)
	case event
	when :eof     # got to the end of the (current) log file
	when :next    # log file archived, starting at the top of the new file
	else          # it's an Event, print it
	    p event
	end
end
eventlog.add_observer(reporter)
eventlog.run

```

## Input plugin for LogStash

As interesting as it is to be able to tail the XML log as if it were a typical flat file log, the real goal of the project is to create a LogStash input plugin that preserves the richness of the XML detail within the LogStash filter/output framework.  The `versalex` LogStash input plugin extends the `VersaLex` module into the LogStash environment.

Note that both `logstash/inputs/versalex.rb` and `versalex.rb` must be on the plugin classpath, e.g.:

```
logstash -e 'input { versalex {} } output { stdout {} }' --pluginpath .
```

### Synopsis

```
input {
  versalex {
    service => ... # string (optional), default "cleo-harmony"
    logfile => ... # path (optional), default derived from "service =>"
    interval => ... # number (optional), default 2
    buffer_size => ... # number (optional), default 1048576 (1MB)
    rewind => ... # boolean (optional), default false
  }
}
```

### Details

#### service
If a logfile is not identified explicitly, it will be located from the service name.  The service must be registered as an upstart service with an `/etc/init/service.conf` file containing an `env CLEOHOME=path` directive, which is used to locate the XML log file.  The default service name is `cleo-harmony`.

#### logfile
Identifies the logfile to parse for events.  If the file does not exist, input will wait until it appears.  The input processes events from the logfile, monitoring and waiting for ongoing updates to be posted to the end of the file.  Note that the monitoring continues at the top of the file if the log file is rotated.  By default, the logfile is determined from the service name.

#### interval
The number of seconds to sleep when reaching the end of the logfile, in seconds.  2 seconds by default.

#### buffer_size
The size in bytes of the logfile read buffer.  Defaults to 1MB.

#### rewind
If `true`, starts reporting events from the start of the existing log file.  By default, the input spools to the end of the file and does not start emitting events until it reaches the end of the file for the first time.  Because of the way the logfile is structured, the file must be processed silently to parse the existing events, so a delay of a few seconds for a large logfile is expected.