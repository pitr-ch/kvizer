class Kvizer
  class Logging
    attr_reader :kvizer, :outputter, :formatter

    def initialize(kvizer, options = { })
      @kvizer    = kvizer
      @formatter = options[:formatter] || ColorFormatter.new(
          :pattern      => options[:pattern] || '%5l %d %22c: %m',
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
      outputter = if kvizer.config.logger.output == 'stdout'
                    Log4r::Outputter.stdout
                  else
                    Log4r::RollingFileOutputter.new :filename => kvizer.config.logger.output
                  end

      outputter.formatter = formatter
      outputter.level     = kvizer.config.logger.level
      outputter
    end
  end

  class ColorFormatter < Log4r::PatternFormatter
    def initialize(options = { })
      super

      original_method = self.method(:format)
      singleton_class.send :define_method, :format do |event|
        string = original_method.call(event)
        colorize(string[0..(level_size-1)], event.level) + string[level_size..-1]
      end
    end

    # later we'll probably add .bright or something, that's reason for case
    def colorize(string, level)
      case level
      when 1
        string.color(:yellow)
      when 2
        string.color(:cyan)
      when 3
        string.color(:magenta)
      when 4
        string.color(:red)
      end
    end

    def level_size
      pattern =~ /(%(\d+)l)/ ? $2.to_i : 0
    end
  end
end