class Kvizer
  module Jobs
    class Collection < Abstract
      attr_reader :jobs

      def self.new_by_names(kvizer, *job_names)
        new kvizer, *job_names.map { |name| kvizer.job_definitions[name] or
            raise ArgumentError, "unknown job '#{name}'" }
      end

      def initialize(kvizer, *jobs)
        super kvizer
        @jobs = jobs
        @map  = self.jobs.inject({}) { |hash, job| hash.update job.name => job }
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
