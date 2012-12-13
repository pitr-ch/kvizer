class Virtual
  module Jobs2
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
        self.class.new virtual, new_name do
          online &template.online_job
          offline &template.offline_job
        end
      end

      # helpers
      def yum_install(*packages)
        vm.shell! 'root', "yum -y install #{packages.join(' ')}"
      end

      private

      def running(vm, options = { }, &block)
        default_options = config.job_options.has_key?(name.to_sym) ? config.job_options[name.to_sym].to_hash : { }
        @vm, @options   = vm, default_options.merge(options.delete_if { |_, v| !v })
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
        raise ArgumentError, "name '#{name}' already taken" if @jobs[name]
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
        new virtual, *job_names.map { |name| virtual.job_definitions[name] or raise "unknown job '#{name}'" }
      end

      def initialize(virtual, *jobs)
        @virtual = virtual
        @jobs    = jobs
        @map     = self.jobs.inject({ }) { |hash, job| hash.update job.name => job }
      end

      def [](name)
        @map[name] or
            raise ArgumentError, "job with name '#{name}' was not found, available: #{@map.keys.join(', ')}"
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
