class Virtual
  class Logging
    attr_reader :virtual, :outputter, :formatter

    def initialize(virtual, options = { })
      @virtual   = virtual
      @formatter = options[:formatter] || ColorFormatter.new(
          :pattern => options[:pattern] || '%5l %d %22c: %m',
          :date_pattern => '%H:%M:%S')
      @outputter = options[:outputter] || default_outputter
    end

    def [](logger_name)
      Log4r::Logger[logger_name] || begin
        logger = Log4r::Logger.new(logger_name)
        logger.add @outputter
        logger
      end
    end

    private

    def default_outputter
      outputter = if virtual.config.logger.output == 'stdout'
                    Log4r::Outputter.stdout
                  else
                    Log4r::RollingFileOutputter.new :filename => virtual.config.logger.output
                  end

      outputter.formatter = formatter
      outputter.level = virtual.config.logger.level
      outputter
    end

  end

  class ColorFormatter < Log4r::PatternFormatter
    def initialize(options = { })
      super

      def self.format(event)
        string = super
        colorize(string[0..(level_size-1)], event.level) + string[level_size..-1]
      end

    end

    # later we'll probably add .bright or something, that's reason for case
    def colorize(string, level)
      case level
        when 1
          string.color(:yellow)
        when 2
          string.color(:magenta)
        when 3
          string.color(:cyan)
        when 4
          string.color(:white)
      end
    end

    def level_size
      pattern =~ /(%(\d+)l)/ ? $2.to_i : 0
    end
  end
end