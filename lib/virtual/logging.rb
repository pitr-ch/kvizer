class Virtual
  class Logging
    attr_reader :virtual, :outputter, :formatter

    def initialize(virtual, options = { })
      @virtual   = virtual
      @formatter = options[:formatter] || Log4r::PatternFormatter.new(
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
end