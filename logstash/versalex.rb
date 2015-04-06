#!/usr/bin/env ruby

require 'observer'
require 'rexml/document'
require 'time'

module VersaLex
  #----------------------------------------------------------------------------#
  # VersaLex XML Event Log parser/tailer.  Use it like this:                   #
  #   eventlog = VersaLex::EventLog.new "file", :follow=>true                  #
  #   eventlog.add_observer(Class.new{ def update(event) p(event) end}.new)    #
  # or if that's too concise try:                                              #
  #   observer = Object.new                                                    #
  #   def observer.update(event)                                               #
  #     case event                                                             #
  #     when :eof   # got to the end of the (current) log file                 #
  #     when :next  # log file archived, starting at the top of the new file   #
  #     else        # it's an Event                                            #
  #       p event                                                              #
  #     end                                                                    #
  #   end                                                                      #
  #   eventlog.add_observer(observer)                                          #
  # The following options are supported:                                       #
  #   :follow  - whether to stop at :eof or keep going forever (default false) #
  #   :bufsize - the file read buffer size (default 1MB)                       #
  #   :sleep   - the sleep interval in seconds at eof (default 2)              #
  #----------------------------------------------------------------------------#
  class EventLog
    include Observable

    DELIMS   = [['<Event>','</Event>',''], ['<Run ','>','</Run>']]
    BUFSIZE  = 1048576 # 1 MB
    SLEEP    = 2

    def initialize(log, args)
      @log      = log
      @follow  = args[:follow]  || false
      @bufsize = args[:bufsize] || BUFSIZE
      @sleep   = args[:sleep]   || SLEEP
      $logger  = args[:logger]
    end

    private
    def quick_match(buf,index,delimiters,&block)
      # search through delimiter tuples looking for first start token
      begin_index = begin_token = end_token = suffix = nil
      delimiters.each do |tuple|
        if test=buf.index(tuple[0],index)
          if !begin_index || test<begin_index
            begin_index=test
            begin_token=tuple[0]
            end_token  =tuple[1]
            suffix     =tuple[2]
          end
        end
      end
      # now if we can find the matching end_token, yield it out
      if begin_index && (end_index = buf.index(end_token,begin_index+begin_token.length))
        yield begin_index, end_index+end_token.length, suffix
        true
      else
        nil
      end
    end

    public
    def run
      f = File.open(@log, 'rb')
      follow = @follow
      begin
        buf = ''
        while s=f.read(@bufsize)
          buf += s
          start=0
          1 while quick_match(buf,start,DELIMS) do
            |a,z,suffix| changed && notify_observers(Event.new(buf[a...(start=z)]+suffix))
          end
          buf = buf[start..-1]
        end
        changed && notify_observers(:eof)  # or done, if not following
        while follow do
          # here's the following part
          size = f.stat.size
          sleep @sleep
          newsize = f.stat.size
          g = File.open(@log, 'rb')
          reopensize = g.stat.size
          # puts "at end size=#{size} newsize=#{newsize} reopensize=#{reopensize}"+
          #      " position=#{f.pos} slop=#{buf.length} [#{buf}]\n"
          if newsize > size
            # file grew, so go back before the slop (which gets overwritten anyway)
            # make sure to check this before the reopensize to not abandon the tail!
            f.seek size-buf.length, IO::SEEK_SET
            g.close # we'll get back to it next time
            break
          elsif reopensize < size
            # file archived, so chuck the slop and start at the top of the new file
            changed && notify_observers(:next)
            f.close
            f = g
            break
          end
          g.close
        end
      rescue Interrupt
        follow = false
      end while follow
    ensure
      f.close if f && !f.closed?
    end
  end

  #----------------------------------------------------------------------------#
  # Represents a LexiComLogEvent parsed from the XML event log file.           #
  #----------------------------------------------------------------------------#
  class Event
    @@threads = {}
    attr_reader   :type
    attr_reader   :time
    attr_reader   :threadid
    attr_reader   :thread
    attr_reader   :command
    attr_reader   :id
    attr_reader   :attributes

    COLOR = {"black"=>30, "red"    =>31, "green"=>32, "orange"=>"38;5;166",
             "blue" =>34, "magenta"=>35, "cyan" =>36, "white" =>37}

    def initialize(string)
      event = REXML::Document.new string
      case event.elements[1].name
      when 'Run'
        # <Run TNnnnn='Local Listener"...> should populate @@threads['nnnn']='Local Listener'
        @type = 'Run'
        attrs = event.elements[1].attributes
        tn    = attrs.select{|k,v|k=~/^TN\d+/}.to_a  # works with 1.8-2.x
        if !tn.empty?
          key = tn[0][0]
          @@threads[key[2..-1]] = attrs[key];
        end
        # <Run date="%Y/%m/%d %H:%M:%S"...>
        # the trick here is to split into digit strings, map to int, splat into args to Time.local
        @time = Time.local *attrs['date'].split(/\D/).map!{|i|i.to_i}
      when 'Event'
        # <Event>
        #   <Mark date="%Y/%m/%d %H:%M:%S" TN="task#" CN="command#" EN="event#"/>
        #   one of (this list is from the JavaDocs, but seems inaccurate):
        #   <Thread   action [type]   />
        #   <Command  text type [line]/>
        #   <Detail   level [type]     >content</Content>
        #   <Hint                      >content</Hint>
        #   <Request  text type       />
        #   <Incoming [transferID messageID source folder host mailbox transport]/>
        #   <File     [transferID messageID source direction destination number fileSize fileTimeStamp host mailbox]/>
        #   <Transfer bytes seconds [active percentage mode blocks errors]/>
        #   <Response host             >content</Response>
        #   <Result   text
        #             command line (if Command)
        #             transferID messageID source direction destination number fileSize fileTimeStamp (if File)
        #             bytes seconds (from Transfer)
        #             origMessageID mdn asyncMDN>content</Result>
        #   <End/>
        # </Event>
        event.elements[1].elements.each do |element|
          case element.name
          when 'Mark'
            @time       = Time.local *element.attributes['date'].split(/\D/).map!{|i|i.to_i}
            @threadid   = element.attributes['TN']
            @command    = element.attributes['CN']
            @id         = element.attributes['EN']
            @thread     = @@threads[@threadid]
          else
            @type       = element.name
            @attributes = {}
            element.attributes.each {|a,v| @attributes[a]=v unless a=='text'&&v=='-'}
            @attributes['text'] = (@attributes['text']||'') + element.text if element.text
          end
        end
        case @type
        when 'Thread'
          @thread = @@threads[@threadid] = @attributes['action']
        when 'Response'
          # merge 'host' with 'text' and delete 'host'
          @attributes['text'] = (@attributes['host']||'') + (@attributes['text']||'')
          @attributes.delete 'host'
        when 'End'
          @@threads.delete(@threadid)
        end
      end
    end

    #--------------------------------------------------------------------------#
    # Renders the event as a single string message.                            #
    #--------------------------------------------------------------------------#
    def message
      if @attributes
        msg = @attributes.select{|k,v|k!='text'}.to_a.map{|kv|%Q[#{kv[0]}='#{kv[1]}']}.join(' ')
        msg = (msg && msg.length>0?msg+': ':'')+@attributes['text'] if @attributes['text']
      end
      msg = ': '+msg if msg && msg.length>0
      "#{@thread}[#{@command||@threadid}] #{@type}#{msg}"
    end

    #--------------------------------------------------------------------------#
    # Approximates the VersaLex UI, adding id and time to message.             #
    #--------------------------------------------------------------------------#
    def inspect
      "#{@id}/#{@time.iso8601} #{message}"
    end

    #--------------------------------------------------------------------------#
    # Approximates the VersaLex UI, adding id and time to message, with color. #
    #--------------------------------------------------------------------------#
    def inspect_colorfully
      color = COLOR[@attributes['color']] if @attributes
      color = COLOR["blue"] if @type=='Transfer'
      if color
        "\e[#{color}m#{@id}/#{@time.iso8601} #{message}\e[0m"
      else
        "#{@id}/#{@time.iso8601} #{message}"
      end
    end
  end

  #----------------------------------------------------------------------------#
  # Default log file locator:                                                  #
  #   if the cleo-harmony.conf upstart script is found and points to env       #
  #   CLEOHOME use this to automatically locate the Harmony.xml file.          #
  #----------------------------------------------------------------------------#
  def self.default_log(service)
    begin
      service ||= 'cleo-harmony'
      File.new("/etc/init/#{service}.conf").readlines.each do |line|
        return "#{$1}/logs/Harmony.xml" if line =~ /^env\s+CLEOHOME\s*=\s*(.*)/
      end
    rescue # throw away IO errors
    end
    nil
  end
end

if __FILE__ == $0
  #----------------------------------------------------------------------------#
  # Laster observer calls &block for the last max_events events before the     #
  # first :eof (the Laster ignores following, so you may get less than the     #
  # requested max if the file is currently short).                             #
  #----------------------------------------------------------------------------#
  class Laster
    attr_reader   :events

    def initialize(eventlog, max_events, &block)
      @max_events = max_events
      @events     = []
      @callback   = block
      @eventlog   = eventlog
      eventlog.add_observer(self)
    end

    def update(event)
      if event==:eof
        @events.each {|event| @callback.call event}
        @eventlog.delete_observer(self)
      elsif event.is_a? VersaLex::Event
        @events.push event
        @events.shift if @events.length > @max_events
      end
    end

    def last_event_number
      @events[-1]::id if @events.length>0
    end
  end

  #----------------------------------------------------------------------------#
  # Dumper observer calls &block for each event after:                         #
  # - skipping skip events for skip >= 0, or                                   #
  # - skipping until the first :eof, if skip < 0                               #
  #----------------------------------------------------------------------------#
  class Dumper
    def initialize(eventlog, skip, &block)
      @skip = skip
      @callback = block
      eventlog.add_observer(self)
    end

    def update(event)
      if event.is_a? VersaLex::Event
        if @skip > 0
          @skip -= 1
        elsif @skip == 0
          @callback.call event
        end
      elsif @skip < 0 && event==:eof
        @skip = 0
      end
    end
  end

  #----------------------------------------------------------------------------#
  # Option Parser:                                                             #
  #   vltail   [options]                                                       #
  #   options: [-f|--follow]                                                   #
  #            [-n|--lines [+]lines]                                           #
  #            [-h|--help]                                                     #
  #            [-s|--service name]                                             #
  #            [file]                                                          #
  #----------------------------------------------------------------------------#
  require 'optparse'
  options = {}
  parser = OptionParser.new do |opts|
    opts.banner = "usage: #{__FILE__} [options] [file]"

    opts.on("-f", "--follow", "follow until killed") do |f|
      options[:follow] = f
    end
    opts.on("-n N", "--lines N",  "show last N lines (or skip +N lines)") do |n|
      options[:lines] = n
    end
    opts.on("-s name", "--service name",  "use logs for named upstart service") do |name|
      options[:service] = name
    end
    opts.on_tail("-h", "--help", "Show this message") do
      puts opts
      exit
    end
  end

  #----------------------------------------------------------------------------#
  # Final option validation and set :skip and :last from :line:                #
  #   :skip is how many lines to skip in the Dumper (-n lines option)          #
  #   :last is how many lines to buffer before the first :eof (-n +lines), but #
  #   then we pass :skip -1 to Dumper to tell it to stay mute until :eof       #
  #----------------------------------------------------------------------------#
  begin
    parser.parse!
    options[:file] = ARGV.shift || VersaLex::default_log(options[:service])
    if ARGV.length>0
      raise OptionParser::ParseError.new 'only one filename may be specified'
    elsif !options[:file]
      if options[:service]
        raise OptionParser::ParseError.new "service #{options[:service]} not found"
      else
        raise OptionParser::ParseError.new 'log filename must be specified'
      end
    end
    if !options[:lines]
    elsif options[:lines] =~ /^\d+$/
      options[:last] = options[:lines].to_i
      options[:skip] = -1
    elsif options[:lines] =~ /^\+\d+$/
      options[:skip] = options[:lines].to_i
    else
      raise OptionParser::ParseError.new "lines must be a number or +number: #{options[:lines]}"
    end
  rescue OptionParser::ParseError => e
    puts e.to_s
    parser.parse %w[--help]
    exit
  end

  #----------------------------------------------------------------------------#
  # Setup and run the EventLog and wait for Interrupt (^C) if :follow.         #
  #----------------------------------------------------------------------------#
  eventlog = VersaLex::EventLog.new options[:file], :follow=>options[:follow]
  laster   = Laster.new(eventlog, options[:last])    {|e| puts e.inspect_colorfully} if options[:last]
  dumper   = Dumper.new(eventlog, options[:skip]||0) {|e| puts e.inspect_colorfully}
  begin
    eventlog.run
  rescue Exception => e
    puts "Error: #{e.message}\n"
  end
end
