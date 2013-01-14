class Kvizer
  class Logging # TODO command and pid
    class Formatter < Log4r::Formatter
      def initialize(options = { })
        @time_format = options[:date_pattern] || '%H:%M:%S'
        @pattern     = options[:pattern] || "%s %s %20s: %s\n"
      end

      def format(event)
        sprintf @pattern, level(event), time, event.name, message(event)
      end

      def time
        Time.now.strftime @time_format
      end

      def level(event)
        Log4r::LNAMES[event.level].rjust 5
      end

      def message(event)
        event.data
      end
    end

    class ColoredFormatter < Formatter
      def level(event)
        colorize super, event.level
      end

      def message(event)
        colorize super, event.level
      end

      # later we'll probably add .bright or something, that's reason for case
      def colorize(string, level)
        case level
        when 1
          string
        when 2
          string.color(:green)
        when 3
          string.color(:yellow)
        when 4
          string.color(:red)
        end
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
      (colored ? ColoredFormatter : Formatter).new
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
                            path = File.expand_path(
                                "#{kvizer.config.logger.output}/#{Time.now.strftime '%y.%m.%d %H.%M.%S'} #{ARGV.first}.log", kvizer.root)

                            outputter           = Log4r::FileOutputter.new(kvizer.config.logger.output, :filename => path)
                            outputter.formatter = @standard_formatter
                            outputter.level     = kvizer.config.logger.level
                            outputter
                          end
    end
  end
end