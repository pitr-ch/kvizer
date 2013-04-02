class Kvizer
  module Jobs
    class Job < Abstract
      attr_reader :vm, :logger, :name, :offline_job, :online_job, :options

      def initialize(kvizer, name, &definition)
        super kvizer
        @name                     = name
        @logger                   = logging["job(#{name})"]
        @online_job, @offline_job = nil
        instance_eval &definition if definition
      end

      def online(&definition)
        @online_job = definition
        self
      end

      def offline(&definition)
        @offline_job = definition
        self
      end

      def run(vm, options = {})
        running vm, options do
          if offline_job
            vm.stop_and_wait
            logger.info "running offline job"
            instance_eval &offline_job
          end
          if online_job
            vm.run_and_wait
            logger.info "running online job"
            instance_eval &online_job
          end
        end
      end

      def clone(new_name)
        template = self
        self.class.new kvizer, new_name do
          online &template.online_job
          offline &template.offline_job
        end
      end

      # helpers
      def yum_install(*packages)
        vm.shell! 'root', "yum -y install #{packages.flatten.map {|p| "\"#{p}\""}.join(' ')}"
      end

      def wait_for(timeout = nil, sleep_interval = 5, &condition)
        start = Time.now
        loop do
          return true if condition.call

          if timeout && timeout < (Time.now - start)
            logger.warn 'Timeout expired.'
            return false
          end

          sleep sleep_interval
        end
      end

      def shell(*args)
        vm.shell(*args)
      end

      def shell!(*args)
        vm.shell!(*args)
      end

      private

      def running(vm, options = {}, &block)
        raise ArgumentError unless Hash === options
        default_options = config.job_options.has_key?(name.to_sym) ? config.job_options[name.to_sym].to_hash : {}
        @vm, @options   = vm, default_options.merge(options) { |_, o, n| n ? n : o }
        logger.info "running with options #{self.options.inspect}"
        block.call
      ensure
        @vm = @options = nil
      end
    end

  end
end


