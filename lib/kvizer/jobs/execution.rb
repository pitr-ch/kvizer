require 'uuidtools'

class Kvizer
  module Jobs
    class Execution < Abstract
      attr_reader :vm, :logger, :job, :options, :report, :uuid

      def initialize(job, vm, options = {})
        @job = job
        super kvizer
        @uuid   = generate_uuid
        @vm     = vm
        #@report = Report.new self
        @logger = logging["#{job.name}"]

        job_options     = config.job_options
        job_name        = job.name.to_sym
        default_options = ConfigNode.new job_options.has_key?(job_name) ? job_options[job_name].to_hash : {}
        @options        = default_options.deep_merge!(options).to_hash
      end

      def kvizer
        job.kvizer
      end

      def run
        logger.info 'running'
        logger.info "options: #{options.inspect}"
        logger.info "uuid: #{uuid}"
        if job.offline_job
          vm.stop_and_wait
          logger.info 'offline part'
          instance_eval &job.offline_job
        end
        if job.online_job
          vm.run_and_wait
          logger.info 'online part'
          instance_eval &job.online_job
        end
        logger.info 'success'
        return true
      rescue => e
        logger.error 'execution failed'
        logger.error "#{e.message} (#{e.class})\n#{e.backtrace.join("\n")}"
        return false
      end

      # helpers
      def yum_install(*packages)
        vm.shell! 'root', "yum -y install #{packages.map { |p| %("#{p}") }.join(' ')}"
      end

      def wait_for(timeout = nil, sleep_interval = 5, &condition)
        start = Time.now
        loop do
          return true if condition.call

          if timeout && timeout < (Time.now - start)
            logger.error 'Timeout expired.'
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

      def generate_uuid
        UUIDTools::UUID.timestamp_create
      end

    end
  end
end
