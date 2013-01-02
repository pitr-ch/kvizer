class Kvizer
  class Logging
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

    attr_reader :kvizer

    def initialize(kvizer, options = { })
      @kvizer             = kvizer
      @colored_formatter  = new_formatter true
      @standard_formatter = new_formatter false
    end

    def [](logger_name)
      Log4r::Logger[logger_name] || begin
        logger = Log4r::Logger.new(logger_name)
        logger.add stdout_outputter if stdout_outputter
        logger.add file_outputter if file_outputter
        logger
      end
    end

    private

    def new_formatter(colored = false)
      (colored ? ColorFormatter : Log4r::PatternFormatter).new(
          :pattern      => '%5l %d %22c: %m',
          :date_pattern => '%H:%M:%S')
    end

    def stdout_outputter
      @stdout_outputter ||= if kvizer.config.logger.print_to_stdout
                              outputter           = Log4r::Outputter.stdout
                              outputter.formatter = @colored_formatter
                              outputter.level     = kvizer.config.logger.level
                              outputter
                            end
    end

    def file_outputter
      @file_outputter ||= if kvizer.config.logger.output
                            outputter           = Log4r::FileOutputter.new(
                                kvizer.config.logger.output,
                                :filename => File.expand_path(kvizer.config.logger.output, kvizer.root))
                            outputter.formatter = @standard_formatter
                            outputter.level     = kvizer.config.logger.level
                            outputter
                          end
    end
  end
end