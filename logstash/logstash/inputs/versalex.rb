require "logstash/inputs/base"
require "logstash/namespace"
require "versalex"
require "socket"

class LogStash::Inputs::VersaLex < LogStash::Inputs::Base
  config_name 'versalex'
  milestone 1

  default :codec, "plain"

  # The name of the upstart service to tail.
  config :service, :validate => :string, :default => 'cleo-harmony'

  # The name of the logfile to tail.
  # If both service and file are specified, file takes precedence.
  config :logfile, :validate => :path

  # The sleep interval when the tailer gets to
  # the end of the file.
  config :interval, :validate => :number, :default => 2

  # The buffer size to use when reading the log.
  config :buffer_size, :validate => :number, :default => 1048576 # 1 MB

  # Set rewind to true to start at the top of the current logfile.
  # By default, only new events are followed.
  config :rewind, :validate => :boolean, :default => false

  def initialize(*args)
    super(*args)
  end

  public
  def register
    @logger.info "Registering VersaLex event log: #{@logfile}"
    @hostname = Socket.gethostname
    @logfile ||= VersaLex::default_log(@service)
    if @logfile.nil?
      if @service.nil?
        raise ArgumentError.new("logfile or service must be specified")
      else
        raise ArgumentError.new("service not found: #{@service}")
      end
    end
  end

  public
  def run(queue)
    # Connect to the EventLog parser
    eventlog = VersaLex::EventLog.new @logfile, :follow=>true, :bufsize=>@buffer_size, :sleep=>@interval, :logger=>@logger

    # Save the queue for the update callback, observe, and follow
    @skip  = !@rewind
    @logger.warn "skipping to end of current logfile..." if @skip
    @skipped_events = 0
    @queue = queue
    eventlog.add_observer(self)
    eventlog.run
  end

  def update(event)
    if @skip
      if event==:eof
        @skip = false
        @logger.warn "...skipped #{@skipped_events} log events"
      elsif event.is_a? VersaLex::Event
        @skipped_events += 1
      end
    elsif event.is_a? VersaLex::Event
      e = LogStash::Event.new(
            "host"     => @hostname,
            "path"     => @logfile,
            "type"     => event.type,
            "thread"   => event.thread,
            "threadid" => event.threadid,
            "eventid"  => event.id,
            "message"  => event.message,
            LogStash::Event::TIMESTAMP => event.time.iso8601
          )

      # copy the VersaLex event attributes to the logstash event,
      # with the only wierdness being renaming 'host' to 'vlhost'
      # because 'host' already means something to logstash.
      event.attributes.each {|k,v| e[k=='host'?'vlhost':k]=v} if event.attributes

      decorate(e)
      @queue << e
    end
  end
end

if __FILE__ == $0
  puts "hello, world\n"
end
