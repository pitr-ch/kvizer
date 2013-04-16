class Kvizer
  module Jobs
    class Job < Abstract
      attr_reader :logger, :name, :offline_job, :online_job, :options

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
        Execution.new(self, vm, options).run
      end

      def clone(new_name)
        template = self
        self.class.new kvizer, new_name do
          online &template.online_job
          offline &template.offline_job
        end
      end
    end

  end
end


