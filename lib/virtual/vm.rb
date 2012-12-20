class Virtual
  class VM
    class LinePrinter
      def initialize(&printer)
        @printer = printer
        @rest    = ""
      end

      def <<(data)
        @rest << data
        while (line = @rest[/\A.*\n/])
          @printer.call line.chomp
          @rest[/\A.*\n/] = ''
        end
      end
    end

    include Shortcuts
    attr_reader :virtual, :name, :logger

    def initialize(virtual, name)
      @virtual, @name  = virtual, name
      @logger          = virtual.logging[name]
      @ssh_connections = { }
    end

    def ip
      virtual.info.attributes[name][:ip]
    end

    def mac
      virtual.info.attributes[name][:mac]
    end

    def shell(user, cmd, options = { })
      logger.debug "shell@#{user}$ #{cmd}".color(:green)

      stdout_data = ""
      stderr_data = ""
      exit_code   = nil
      exit_signal = nil
      ssh         = ssh_connection user, options[:password]

      ssh.open_channel do |channel|
        channel.exec(cmd) do |ch, success|
          abort "FAILED: couldn't execute command (ssh.channel.exec)".color(:red) unless success

          debug = LinePrinter.new { |line| logger.debug line }
          warn  = LinePrinter.new { |line| logger.warn line }

          channel.on_data do |ch, data|
            stdout_data << data
            debug << data
            #$stdout << data
          end
          channel.on_extended_data do |ch, type, data|
            stderr_data << data
            warn << data
            #$stderr << data
          end
          channel.on_request("exit-status") { |ch, data| exit_code = data.read_long }
          channel.on_request("exit-signal") { |ch, data| exit_signal = data.read_long }
        end
      end
      ssh.loop

      return ShellOutResult.new(exit_code == 0, stdout_data, stderr_data)
    end

    def shell!(user, cmd, options = { })
      result = shell user, cmd, options
      raise CommandFailed, "cmd failed: #{cmd}\nerr:\n#{result.err}".color(:red) unless result.success
      result
    end

    def ssh_connection(user, password = nil) # FIXME do better
                                             # TODO ignore known hosts
                                             # ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no petr@host
      @ssh_connections[user] ||= session = begin
        logger.debug "SSH connecting #{user}"
        Net::SSH.start(ip, user, :password => password, :paranoid => false)
      end
    end

    def ssh_close # TODO do better
      @ssh_connections.keys.each do |user|
        ssh = @ssh_connections.delete user
        ssh.close unless ssh.closed?
      end
    end

    def running?
      status == :running
    end

    def wait_for(status, timeout = nil)
      start = Time.now
      loop do
        virtual.info.reload_attributes
        current = self.status
        return true if current == status
        logger.info "Waiting for: #{status}, now is: #{current}"

        if timeout && timeout < (Time.now - start)
          logger.warn 'Timeout expired.'
          return false
        end

        sleep 5
      end
    end

    def clone_vm(name, snapshot)
      host.shell! "VBoxManage clonevm \"#{self.name}\" --snapshot \"#{snapshot}\" --mode machine " +
                      "--options link --name \"#{name}\" --register"
      virtual.info.reload
      virtual.vms(true)
      cloned_vm = virtual.vm name
      cloned_vm.take_snapshot snapshot
    end

    def delete
      host.shell! "VBoxManage unregistervm \"#{name}\" --delete"
      virtual.info.reload
      virtual.vms(true)
    end

    def status
      result      = host.shell!('VBoxManage list runningvms').out
      box_status  = !!(result =~ /"#{name}"/)
      ping_status = host.shell("ping -c 1 -W 500 #{ip}").success
      case [box_status, ping_status]
      when [false, false]
        :stopped
      when [true, false]
        :no_connection
      when [true, true]
        :running
      else
        :unknown
      end
    end

    # TODO add class for snapshot, fix broken deletion of snapshots with manual
    # hdd deletion
    # VBoxManage list hdds to find child disks and delete them
    # add methods for restore, delete, take
    def snapshots
      out = host.shell!("VBoxManage snapshot \"#{name}\" list").out
      out.each_line.map do |line|
        line =~ /Name: ([^(]+) \(/
        $1
      end
    end

    def take_snapshot(snapshot_name)
      stop_and_wait
      cmd    = "VBoxManage snapshot \"#{name}\" take \"#{snapshot_name}\""
      result = host.shell cmd
      if result.success
        return
      else
        sleep 1
        host.shell! cmd
      end
      sleep 5 # FIXME other commands fail after this when called immidietly
    end

    def restore_snapshot(snapshot_name)
      raise ArgumentError, "No snapshot named #{snapshot_name}" unless snapshots.include? snapshot_name
      stop_and_wait
      # restore state form previous job
      host.shell! "VBoxManage snapshot \"#{name}\" restore \"#{snapshot_name}\""
      # delete child snapshots
      snapshots.reverse.each do |snapshot|
        break if snapshot == snapshot_name
        delete_snapshot snapshot
      end
    end

    def delete_snapshot(snapshot_name)
      sleep 1
      host.shell! "VBoxManage snapshot \"#{name}\" delete \"#{snapshot_name}\""
    end

    def run(gui = config.use_gui)
      unless running?
        setup_shared_folders
        host.shell! "VBoxManage startvm \"#{name}\" --type #{gui ? 'gui' : 'headless' }"
      end
    end

    def run_and_wait(gui = config.use_gui)
      run gui
      wait_for :running
    end

    def stop
      unless status == :stopped
        shell 'root', 'service pulp-server stop'
        sleep 5
        ssh_close
        host.shell! "VBoxManage controlvm \"#{name}\" acpipowerbutton"
      end
    end

    def stop_and_wait
      stop
      wait_for(:stopped, 5*60) || power_off!
    end

    def power_off!
      ssh_close
      host.shell! "VBoxManage controlvm \"#{name}\" poweroff"
    end

    def connect(user)
      run_and_wait
      cmd = "ssh #{user}@#{ip} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
      logger.info "connecting: #{cmd}"
      exec cmd
    end

    def to_s
      "#<Virtual::VM #{name} ip:#{ip.inspect} mac:#{mac.inspect}>"
    end

    def setup_private_network
      raise if running?
      unless mac
        logger.info "Setting up network"
        host.shell! "VBoxManage modifyvm \"#{name}\" --nic2 hostonly --hostonlyadapter2 #{config.hostonly.name}"
        virtual.info.reload
      else
        true
      end
    end

    def setup_shared_folders
      raise if running?
      config.shared_folders.each do |name, path|
        host.shell "VBoxManage sharedfolder remove \"#{self.name}\" --name \"#{name}\""
        host.shell! "VBoxManage sharedfolder add \"#{self.name}\" --name \"#{name}\" --hostpath \"#{path}\" " +
                        "--automount"
      end
    end

    def run_job(job, options = { })
      raise ArgumentError, "not a job #{job.inspect}" unless job.kind_of? Virtual::Jobs2::Job
      job.run self, options
    end


    #def mount_point_path
    #  @mount_point_path ||= File.join(config.vbox.mount_dir, name)
    #end

    #def mount
    #  Dir.mkdir mount_point_path unless File.exist? mount_point_path
    #  unless mounted?
    #    result = host.shell! "sshfs #{user}@#{ip}:/ #{mount_point_path}"
    #    raise result.err unless result.success
    #    File.symlink mount_point_path, link_path unless File.exist?(link_path)
    #  else
    #    logger.error "already mounted"
    #  end
    #  self
    #end
    #
    #def unmount
    #  if mounted?
    #    result = host.shell! "umount #{mount_point_path}"
    #    raise result.err unless result.success
    #    File.delete link_path if File.exist?(link_path)
    #  else
    #    logger.error "not mounted"
    #  end
    #  self
    #end
    #
    #def mounted?
    #  Dir.glob(File.join(mount_point_path, '**')).size > 2
    #end

    #def user
    #  if name =~ /fedora/
    #    config.users.fedore
    #  elsif name =~ /rhel/
    #    config.users.rhel
    #  else
    #    raise
    #  end
    #end
    #

    #def link_path
    #  "/Users/pitr/#{name}"
    #end
  end
end
