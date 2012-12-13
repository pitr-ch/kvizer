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

  #module Jobs
  #  class Job
  #    include Shortcuts
  #    attr_reader :virtual, :vm, :logger
  #
  #    def initialize(virtual)
  #      @virtual = virtual
  #      @logger  = virtual.logging["job-#{name}"]
  #    end
  #
  #    def run(vm)
  #      @vm = vm
  #      if respond_to? :offline_job
  #        vm.stop_and_wait
  #        logger.info "running offline job"
  #        offline_job
  #      end
  #      if respond_to? :online_job
  #        vm.run_and_wait
  #        logger.info "running online job"
  #        online_job
  #      end
  #    ensure
  #      @vm = nil
  #    end
  #
  #    def name
  #      self.class.to_s.split('::').last
  #    end
  #
  #    def yum_install(*packages)
  #      vm.shell! 'root', "yum -y install #{packages.join(' ')}"
  #    end
  #  end
  #
  #  class Base < Job
  #  end
  #
  #  class NetworkSetup < Job
  #    def offline_job
  #      host.setup_private_network
  #      vm.setup_private_network
  #    end
  #  end
  #
  #  class Htop < Job
  #    def online_job
  #      yum_install "htop"
  #    end
  #  end
  #
  #  class KatelloInstallation < Job
  #    def online_job
  #      # stable repo
  #      vm.shell! 'root',
  #                "rpm -Uvh http://fedorapeople.org/groups/katello/releases/yum/nightly/Fedora/16/x86_64/katello-repos-latest.rpm"
  #      # for nightly builds
  #      yum_install "katello-repos-testing"
  #      yum_install "katello-all"
  #    end
  #  end
  #
  #  class KatelloConfiguration < Job
  #    def online_job
  #      vm.shell! 'root', "katello-configure"
  #    end
  #  end
  #
  #  class TurnOff < Job
  #    def online_job
  #      vm.shell! 'root', 'setenforce 0'
  #      vm.shell! 'root', 'service iptables stop'
  #      vm.shell! 'root', 'service katello stop'
  #      vm.shell! 'root', 'service katello-jobs stop'
  #      vm.shell! 'root', 'chkconfig iptables off'
  #      vm.shell! 'root', 'chkconfig katello off'
  #      vm.shell! 'root', 'chkconfig katello-jobs off'
  #    end
  #  end
  #
  #  class AddUser < Job
  #    def online_job
  #      vm.shell! 'root', 'useradd user -G wheel'
  #      vm.shell! 'root', 'passwd user -f -u'
  #      vm.shell! 'root', 'echo katello | passwd user --stdin'
  #      vm.shell! 'root', 'su user -c "mkdir /home/user/.ssh"'
  #      vm.shell! 'root', 'su user -c "touch /home/user/.ssh/authorized_keys"'
  #      vm.shell! 'root', 'cat /root/.ssh/authorized_keys > /home/user/.ssh/authorized_keys'
  #
  #      vm.shell! 'root', 'chmod u+w /etc/sudoers'
  #      vm.shell! 'root',
  #                'sed -i -E "s/# %wheel\s+ALL=\(ALL\)\s+NOPASSWD: ALL/%wheel\tALL=\(ALL\)\tNOPASSWD: ALL/" ' +
  #                    '/etc/sudoers'
  #      vm.shell! 'root',
  #                'sed -i -E "s/%wheel\s+ALL=\(ALL\)\s+ALL/# %wheel\tALL=\(ALL\)\tALL/" /etc/sudoers'
  #      vm.shell! 'root',
  #                'sed -i -E "s/Defaults\s+requiretty/# Defaults\trequiretty/" /etc/sudoers'
  #      vm.shell! 'root', 'chmod u-w /etc/sudoers'
  #      vm.shell! 'user', 'sudo echo a' # test
  #    end
  #  end
  #
  #  class GuestAdditions < Job
  #    def online_job
  #      v = config.virtual_box_version
  #      yum_install %w(dkms kernel-devel @development-tools)
  #      vm.shell! 'root',
  #                "wget http://download.virtualbox.org/virtualbox/#{v}/VBoxGuestAdditions_#{v}.iso"
  #      vm.shell! 'root', 'mkdir additions'
  #      vm.shell! 'root', "mount -o loop VBoxGuestAdditions_#{v}.iso ./additions"
  #      vm.shell! 'root', 'additions/VBoxLinuxAdditions.run'
  #      vm.shell! 'root', 'usermod -a -G vboxsf root'
  #      vm.shell! 'root', 'usermod -a -G vboxsf user'
  #    end
  #  end
  #
  #  class SharedFolders < Job
  #    def offline_job
  #      vm.setup_shared_folders
  #    end
  #
  #    def online_job
  #      config.shared_folders.each do |name, path|
  #        vm.shell! 'user', "ln -s /media/sf_#{name}/ #{name}"
  #      end
  #      vm.shell! 'user', 'rm .bash_profile'
  #      vm.shell! 'user', 'ln -s /home/user/support/.bash_profile .bash_profile'
  #    end
  #  end
  #
  #  #class Bundle < Job
  #  #  def online_job
  #  #    vm.shell! 'root', 'yum install -y git tito ruby-devel postgresql-devel sqlite-devel libxml2 libxml2-devel libxslt ' +
  #  #        'libxslt-devel'
  #  #    #vm.shell! 'user', 'cd katello/src; sudo bundle install'
  #  #  end
  #  #end
  #
  #  class Development < Job
  #    def online_job
  #      vm.shell! 'root', 'rm /etc/katello/katello.yml'
  #      vm.shell! 'root', 'ln -s /home/user/katello/src/config/katello.yml /etc/katello/katello.yml'
  #
  #      # reset oauth
  #      vm.shell! 'user', 'sudo katello/src/script/reset-oauth shhhh'
  #      vm.shell! 'root', 'service tomcat6 restart'
  #      vm.shell! 'root', 'service pulp-server restart'
  #
  #      # create katello db
  #      waiting = 0
  #      loop do
  #        break if vm.shell('root', 'service postgresql status').success
  #        waiting += 1
  #        sleep 1
  #        raise 'db is not running even after 30s' if waiting > 30
  #      end
  #      vm.shell! 'root', "su - postgres -c 'createuser -dls katello  --no-password'"
  #    end
  #  end
  #
  #  class ForPackaging < Job
  #    def require # TODO call the method in the job
  #      File.exist?("#{config.root}/support/koji")
  #    end
  #
  #    def online_job
  #      yum_install %w(tito ruby-devel postgresql-devel sqlite-devel libxml2 libxml2-devel libxslt libxslt-devel)
  #
  #      vm.shell! 'user', 'mkdir $HOME/.koji'
  #      vm.shell! 'user', 'ln -s $HOME/support/koji/katello-config $HOME/.koji/katello-config'
  #      vm.shell! 'user', %(echo 'KOJI_OPTIONS=-c ~/.koji/katello-config build --nowait' | tee $HOME/.titorc)
  #    end
  #  end
  #
  #  class Package < Job
  #    def online_job
  #      # TODO parametrize to build from any git repo and any branch
  #      dirs = %w(src cli katello-configure katello-utils repos selinux/katello-selinux scripts/system-test)
  #
  #      rpms = dirs.map do |dir|
  #        logger.info "building dir '#{dir}'"
  #        result = vm.shell! 'user', "cd katello/#{dir}; tito build --test --srpm --dist=.fc16"
  #        result.out =~ /^Wrote: (.*src\.rpm)$/
  #        vm.shell! 'root', "echo y | yum-builddep #{$1}"
  #        result = vm.shell! 'user', "cd katello/#{dir}; tito build --test --rpm --dist=.fc16"
  #        result.out =~ /Successfully built: (.*)\Z/
  #        $1.split(/\s/).tap { |rpms| logger.info "rpms: #{rpms.join(' ')}" }
  #      end.flatten
  #
  #      logger.info "All packaged rpms:\n  #{rpms.join("\n  ")}"
  #
  #      to_install = rpms.select { |rpm| rpm !~ /headpin|devel|src\.rpm/ }
  #      vm.shell! 'root', "yum localinstall -y --nogpgcheck #{to_install.join ' '}"
  #      #rpm -Uvh --oldpackage --force $RPMBUILD/*/*/*rpm
  #    end
  #  end
  #
  #  class KatelloConfiguration2 < KatelloConfiguration
  #  end
  #
  #  class Update < Job
  #    def online_job
  #      vm.shell! 'root', 'yum update -y'
  #    end
  #  end
  #
  #  class RelaxSecurity < Job
  #    def online_job
  #      # allow incoming connections to postgresql
  #      unless vm.shell('root', 'cat /var/lib/pgsql/data/pg_hba.conf | grep "192.168.25.0/24"').success
  #        vm.shell! 'root',
  #                  'echo "host all all 192.168.25.0/24 trust" | tee -a /var/lib/pgsql/data/pg_hba.conf'
  #      end
  #      vm.shell! 'root',
  #                "sed -i 's/^#.*listen_addresses =.*/listen_addresses = '\\'*\\'/ " +
  #                    '/var/lib/pgsql/data/postgresql.conf'
  #
  #      # allow incoming connections to elasticsearch
  #      el_config = '/etc/elasticsearch/elasticsearch.yml'
  #      vm.shell! 'root', "sed -i 's/^.*network.bind_host.*/network.bind_host: 0.0.0.0/' #{el_config}"
  #      vm.shell! 'root', "sed -i 's/^.*network.publish_host.*/network.publish_host: 0.0.0.0/' #{el_config}"
  #      vm.shell! 'root', "sed -i 's/^.*network.host.*/network.host: 0.0.0.0/' #{el_config}"
  #
  #      # reset katello secret to "katello"
  #      vm.shell! 'root', "sed -i 's/^.*oauth_secret: .*/oauth_secret: shhhh/' /etc/pulp/pulp.conf"
  #      vm.shell! 'root', "sed -i 's/^.*candlepin.auth.oauth.consumer.katello.secret =.*/" +
  #          "candlepin.auth.oauth.consumer.katello.secret = shhhh/' /etc/candlepin/candlepin.conf"
  #      vm.shell! 'root', "sed -i 's/^.*oauth_secret: .*/    oauth_secret: shhhh/' /etc/katello/katello.yml"
  #
  #      vm.shell! 'root', 'service pulp-server restart'
  #      vm.shell! 'root', 'service tomcat6 restart'
  #      #       /home/use r/support/start-elastic.sh
  #      vm.shell! 'root', 'service elasticsearch restart'
  #      vm.shell! 'root', 'service postgresql restart'
  #    end
  #  end
  #
  #  class Collection
  #    attr_reader :jobs, :virtual
  #
  #    def self.new_from_names(virtual, *job_names)
  #      new virtual, *job_names.map { |name| Jobs.const_get name }
  #    end
  #
  #    def initialize(virtual, *job_classes)
  #      @virtual = virtual
  #      @jobs    = job_classes.map { |klass| klass.new(virtual) }
  #      @map     = self.jobs.inject({ }) { |hash, job| hash.update job.name => job }
  #    end
  #
  #    def [](name)
  #      @map[name] or
  #          raise ArgumentError, "job with name '#{name}' was not found, available: #{@map.keys.join(', ')}"
  #    end
  #
  #    def job_index(job)
  #      jobs.index(job)
  #    end
  #
  #    def job_first?(job)
  #      jobs[0] == job
  #    end
  #
  #    def previous_job(job)
  #      return nil if job_first? job
  #      jobs[job_index(job)-1]
  #    end
  #
  #    def job_last?(job)
  #      jobs[-1] == job
  #    end
  #
  #    def next_job(job)
  #      return nil if job_last? job
  #      jobs[job_index(job)+1]
  #    end
  #
  #    #def jobs_since(job)
  #    #  jobs[job_index(job)..-1]
  #    #end
  #  end
  #end
end
