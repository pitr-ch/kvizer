class Virtual
  module Jobs
    class Job
      include Shortcuts
      attr_reader :virtual, :vm, :logger, :name, :offline_job, :online_job, :options

      def initialize(virtual, name, &definition)
        @virtual, @name           = virtual, name
        @logger                   = virtual.logging["job-#{name}"]
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

      def run(vm, options = { })
        running vm, options do
          if offline_job
            vm.stop_and_wait
            logger.info "running offline job".color(:yellow).bright
            instance_eval &offline_job
          end
          if online_job
            vm.run_and_wait
            logger.info "running online job".color(:yellow).bright
            instance_eval &online_job
          end
        end
      end

      def clone(new_name)
        template = self
        self.class.new virtual, new_name do
          online &template.online_job
          offline &template.offline_job
        end
      end

      # helpers
      def yum_install(*packages)
        vm.shell! 'root', "yum -y install #{packages.join(' ')}"
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

      private

      def running(vm, options = { }, &block)
        raise ArgumentError unless Hash === options
        default_options = config.job_options.has_key?(name.to_sym) ? config.job_options[name.to_sym].to_hash : { }
        @vm, @options   = vm, default_options.merge(options) { |_, o, n| n ? n : o }
        block.call
      ensure
        @vm = @options = nil
      end
    end

    class DSL
      include Shortcuts
      attr_reader :virtual, :jobs

      def initialize(virtual, &definition)
        @virtual = virtual
        @jobs    = { }
        instance_eval &definition
      end

      def job(name, template = nil, &definition)
        raise ArgumentError, "name '#{name}' already taken".color(:red) if @jobs[name]
        @jobs[name] = if template
                        @jobs[template].clone(name)
                      else
                        Job.new virtual, name, &definition
                      end
      end
    end

    class Collection
      attr_reader :jobs, :virtual

      def self.new_by_names(virtual, *job_names)
        new virtual, *job_names.map { |name| virtual.job_definitions[name] or
            raise "unknown job '#{name}'".color(:red) }
      end

      def initialize(virtual, *jobs)
        @virtual = virtual
        @jobs    = jobs
        @map     = self.jobs.inject({ }) { |hash, job| hash.update job.name => job }
      end

      def [](name)
        @map[name] or
            raise ArgumentError, "job with name '#{name}' was not found, available: #{@map.keys.join(', ')}".color(:red)
      end

      def job_index(job)
        jobs.index(job)
      end

      def job_first?(job)
        jobs[0] == job
      end

      def previous_job(job)
        return nil if job_first? job
        jobs[job_index(job)-1]
      end

      def job_last?(job)
        jobs[-1] == job
      end

      def next_job(job)
        return nil if job_last? job
        jobs[job_index(job)+1]
      end
    end
  end
end
