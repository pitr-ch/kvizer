class Kvizer
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
    attr_reader :kvizer, :name, :logger

    def initialize(kvizer, name)
      @kvizer, @name   = kvizer, name
      @logger          = kvizer.logging[name]
      @ssh_connections = { }
    end

    def ip
      kvizer.info.attributes[name][:ip]
    end

    def mac
      kvizer.info.attributes[name][:mac]
    end

    def shell(user, cmd, options = { })
      logger.info "sh@#{user}$ #{cmd}"

      stdout_data = ""
      stderr_data = ""
      exit_code   = nil
      exit_signal = nil
      ssh         = ssh_connection user, options[:password]

      ssh.open_channel do |channel|
        channel.exec(cmd) do |ch, success|
          abort "FAILED: couldn't execute command (ssh.channel.exec)" unless success

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
      raise CommandFailed, "cmd failed: #{cmd}\nerr:\n#{result.err}" unless result.success
      result
    end

    def ssh_connection(user, password = nil)
      @ssh_connections[user] ||= session = begin
        logger.debug "SSH connecting #{user}"
        Net::SSH.start(ip, user, :password => password, :paranoid => false)
      end
    end

    def ssh_close # TODO collect and close all ssh connections
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
        kvizer.info.reload_attributes
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
      kvizer.info.reload
      kvizer.vms(true)
      cloned_vm = kvizer.vm name
      cloned_vm.take_snapshot snapshot
    end

    def delete
      host.shell! "VBoxManage unregistervm \"#{name}\" --delete"
      kvizer.info.reload
      kvizer.vms(true)
    end

    def set_hostname
      raise unless running?
      shell 'root', "hostname #{name.gsub(/[^-a-zA-Z0-9.]/, '-')}"
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
      sleep 5 # other commands fail after this when called immidietly
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

    def run_and_wait(headless = config.headless)
      run headless
      wait_for :running
      set_hostname
    end

    def stop_and_wait
      stop
      wait_for(:stopped, 5*60) || power_off!
    end

    def power_off!
      ssh_close
      host.shell! "VBoxManage controlvm \"#{name}\" poweroff"
      sleep 1
    end

    def connect(user)
      run_and_wait
      cmd = "ssh #{user}@#{ip} -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
      logger.info "connecting: #{cmd}"
      exec cmd
    end

    def to_s
      "#<Kvizer::VM #{name} ip:#{ip.inspect} mac:#{mac.inspect}>"
    end

    def setup_private_network
      raise if running?
      unless mac
        logger.info "Setting up network"
        host.shell! "VBoxManage modifyvm \"#{name}\" --nic2 hostonly --hostonlyadapter2 #{config.hostonly.name}"
        kvizer.info.reload
      else
        true
      end
    end

    def setup_resources(ram_megabytes, cpus)
      raise if running?
      host.shell! "VBoxManage modifyvm \"#{name}\" --cpus #{cpus} --memory #{ram_megabytes}"
    end

    def setup_shared_folders
      raise if running?
      config.shared_folders.each do |name, path|
        path = File.expand_path path, kvizer.root
        host.shell "VBoxManage sharedfolder remove \"#{self.name}\" --name \"#{name}\""
        host.shell! "VBoxManage sharedfolder add \"#{self.name}\" --name \"#{name}\" --hostpath \"#{path}\" " +
                        "--automount"
      end
    end

    def run_job(job, options = { })
      raise ArgumentError, "not a job #{job.inspect}" unless job.kind_of? Kvizer::Jobs::Job
      job.run self, options
    end

    private

    def run(headless = config.headless)
      unless running?
        setup_shared_folders
        host.shell! "VBoxManage startvm \"#{name}\" --type #{headless ? 'headless' : 'gui' }"
      end
    end

    def stop
      unless status == :stopped
        shell 'root', 'service pulp-server stop'
        sleep 5
        ssh_close
        host.shell! "VBoxManage controlvm \"#{name}\" acpipowerbutton"
      end
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
