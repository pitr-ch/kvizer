class Kvizer
  module Jobs
    class Report < Abstract

      attr_reader :execution

      def initialize(execution)
        @execution = execution
        super kvizer
      end

      def kvizer
        execution.kvizer
      end


    end
  end
end