job 'clean installation'

job 'base' do
  offline do
    host.setup_private_network
    vm.setup_private_network
  end
  online do
    shell! 'root', 'mkdir -p .ssh', :password => config.root_password
    shell! 'root', %(printf "#{config.authorized_keys}" > .ssh/authorized_keys),
           :password => config.root_password
  end
end

job 'install-htop' do
  online { yum_install "htop" }
end

job 'install-katello-nightly' do
  online do
    shell! 'root',
           "rpm -Uvh http://fedorapeople.org/groups/katello/releases/yum/nightly/Fedora/16/x86_64/katello-repos-latest.rpm"
    yum_install "katello-repos-testing"
    yum_install "katello-all"
  end
end

job 'install-katello' do
  online do
    shell! 'root',
           "rpm -Uvh http://fedorapeople.org/groups/katello/releases/yum/1.1/Fedora/16/x86_64/katello-repos-1.1.3-1.fc16.noarch.rpm"
    yum_install "katello-all"
  end
end

job 'configure-katello' do
  online { shell! 'root', "katello-configure --no-bars" }
end

job 'turnoff-services' do
  online do
    shell! 'root', 'setenforce 0'
    shell! 'root', 'service iptables stop'
    shell! 'root', 'service katello stop'
    shell! 'root', 'service katello-jobs stop'
    shell! 'root', 'chkconfig iptables off'
    shell! 'root', 'chkconfig katello off'
    shell! 'root', 'chkconfig katello-jobs off'
    # TODO stop foreman
  end
end

job 'add-user' do
  online do
    shell! 'root', 'useradd user -G wheel'
    shell! 'root', 'passwd user -f -u'
    shell! 'root', "echo #{config.user_password} | passwd user --stdin"
    shell! 'root', 'su user -c "mkdir /home/user/.ssh"'
    shell! 'root', 'su user -c "touch /home/user/.ssh/authorized_keys"'
    shell! 'root', 'cat /root/.ssh/authorized_keys > /home/user/.ssh/authorized_keys'

    shell! 'root', 'chmod u+w /etc/sudoers'
    shell! 'root',
           'sed -i -E "s/# %wheel\s+ALL=\(ALL\)\s+NOPASSWD: ALL/%wheel\tALL=\(ALL\)\tNOPASSWD: ALL/" ' +
               '/etc/sudoers'
    shell! 'root',
           'sed -i -E "s/%wheel\s+ALL=\(ALL\)\s+ALL/# %wheel\tALL=\(ALL\)\tALL/" /etc/sudoers'
    shell! 'root',
           'sed -i -E "s/Defaults\s+requiretty/# Defaults\trequiretty/" /etc/sudoers'
    shell! 'root', 'chmod u-w /etc/sudoers'
    shell! 'user', 'sudo echo a' # test
  end
end

job 'install-guest-additions' do
  online do
    version = config.virtual_box_version
    yum_install %w(dkms kernel-devel @development-tools)
    shell! 'root',
           "wget http://download.virtualbox.org/virtualbox/#{version}/VBoxGuestAdditions_#{version}.iso"
    shell! 'root', 'mkdir additions'
    shell! 'root', "mount -o loop VBoxGuestAdditions_#{version}.iso ./additions"
    shell! 'root', 'additions/VBoxLinuxAdditions.run'
    shell! 'root', 'usermod -a -G vboxsf root'
    shell! 'root', 'usermod -a -G vboxsf user'
  end
end

job 'setup-shared-folders' do
  offline { vm.setup_shared_folders }
  online do
    config.shared_folders.each do |name, path|
      shell! 'user', "ln -s /media/sf_#{name}/ #{name}"
    end
    shell! 'user', 'rm .bash_profile'
    shell! 'user', 'ln -s /home/user/support/.bash_profile .bash_profile'
  end
end

#class Bundle < Job
#  def online_job
#    shell! 'root', 'yum install -y git tito ruby-devel postgresql-devel sqlite-devel libxml2 libxml2-devel libxslt ' +
#        'libxslt-devel'
#    #shell! 'user', 'cd katello/src; sudo bundle install'
#  end
#end

job 'setup-development' do
  online do
    shell! 'root', 'rm /etc/katello/katello.yml'
    shell! 'root', "ln -s #{config.katello_path}/src/config/katello.yml /etc/katello/katello.yml"

    # reset oauth
    shell! 'user', "sudo #{config.katello_path}/src/script/reset-oauth shhhh"
    shell! 'root', 'service tomcat6 restart'
    shell! 'root', 'service pulp-server restart'

    # create katello db
    waiting = 0
    wait_for(60) { shell('root', 'service postgresql status').success } ||
        raise('db is not running even after 60s')
    shell! 'root', 'su - postgres -c \'createuser -dls katello  --no-password\''
  end
end

job 'install-packaging' do
  online do
    yum_install %w(tito ruby-devel postgresql-devel sqlite-devel libxml2 libxml2-devel libxslt libxslt-devel)

    # koji setup
    shell! 'user', 'mkdir $HOME/.koji'
    shell! 'user', 'ln -s $HOME/support/koji/katello-config $HOME/.koji/katello-config'
    shell! 'user', %(echo 'KOJI_OPTIONS=-c ~/.koji/katello-config build --nowait' | tee $HOME/.titorc)
    # patch koji-cli to be able to download scratch built rpms, see https://fedorahosted.org/koji/ticket/237
    shell! 'user', 'cat support/0001-koji-cli-add-download-scratch-build-command.patch | sudo patch -p0 /usr/bin/koji'
  end
end

job 'package2' do # TODO rename to package
  online do
    shell! 'user', "git clone #{options[:source]} katello-build-source"
    shell! 'user', "cd katello-build-source; git checkout #{options[:branch]}"

    shell! 'root',
           #"rpm -Uvh http://fedorapeople.org/groups/katello/releases/yum/nightly/Fedora/16/x86_64/katello-repos-1.3.1-1.fc16.noarch.rpm"
           # latest links to 1.2, use above variant when you encounter problems
           "rpm -Uvh http://fedorapeople.org/groups/katello/releases/yum/nightly/Fedora/16/x86_64/katello-repos-latest.rpm"
    yum_install "katello-repos-testing"
    yum_install "puppet" # workaround for missing puppet user when puppet is installed by yum-builddep

    spec_dirs = %w(src cli katello-configure katello-utils repos selinux/katello-selinux scripts/system-test)
    rpms      = spec_dirs.map { |dir| build_rpms dir }.flatten

    logger.info "All packaged rpms:\n  #{rpms.join("\n  ")}"

    install_rpms rpms
  end

  # @return [Array(String)] of successfully built rpms
  def self.build_rpms(dir)
    logger.info "building '#{dir}'"
    result = shell! 'user', "cd katello-build-source/#{dir}; tito build --test --srpm --dist=.fc16"
    result.out =~ /^Wrote: (.*src\.rpm)$/
    srpm_file = $1

    if options[:use_koji]
      result  = shell!('user', "koji -c ~/.koji/katello-config build --scratch katello-nightly-fedora16 #{srpm_file}")
      task_id = /^Created task: (\d+)$/.match(result.out)[1]

      shell! 'user', "koji -c ~/.koji/katello-config watch-task #{task_id}"

      shell! 'user', 'mkdir -p /tmp/koji'
      result = shell! 'user', "cd /tmp/koji; koji -c ~/.koji/katello-config download-scratch-build #{task_id}"
      result.out.split("\n").map { |line| '/tmp/koji/' + /^Downloading \[\d+\/\d+\]: (.+)$/.match(line)[1] }
      # parse Created task: 15874
      # download built rpms to /tmp/koji/
      # cd /tmp/koji; koji -c ~/.koji/katello-config download-scratch-build 15854
      # parse rpms from
      #   Downloading [1/2]: katello-configure-1.3.1-1.git.167.a0bb275.fc16.src.rpm
      #   Downloading [2/2]: katello-configure-1.3.1-1.git.167.a0bb275.fc16.noarch.rpm
    else
      shell! 'root', "yum-builddep -y #{srpm_file}"
      result = shell! 'user', "cd katello-build-source/#{dir}; tito build --test --rpm --dist=.fc16"
      result.out =~ /Successfully built: (.*)\Z/
      $1.split(/\s/).tap { |rpms| logger.info "rpms: #{rpms.join(' ')}" }
    end
  end

  def self.install_rpms(rpms)
    to_install = rpms.select { |rpm| rpm !~ /headpin|devel|src\.rpm/ }
    result     = shell 'root', "yum localinstall -y --nogpgcheck #{to_install.join ' '}"
    unless result.success
      shell 'root', "rpm -Uvh --oldpackage --force #{to_install.join ' '}"
    end
  end
end

job 'reconfigure-katello', 'configure-katello'

job 'system-test' do
  online do
    wait_for(600, 20) { shell('user', 'katello -u admin -p admin ping').success } ||
        raise('Katello is not healthy')
    result = shell 'user', "/usr/share/katello/script/cli-tests/cli-system-test all #{options[:extra]}"
    logger.error "system tests FAILED" unless result.success
  end
end

job 'update' do
  online { shell! 'root', 'yum update -y' }
end

job 'relax-security' do
  online do
    # allow incoming connections to postgresql
    unless shell('root', 'cat /var/lib/pgsql/data/pg_hba.conf | grep "192.168.25.0/24"').success
      shell! 'root',
             'echo "host all all 192.168.25.0/24 trust" | tee -a /var/lib/pgsql/data/pg_hba.conf'
    end
    shell! 'root',
           "sed -i 's/^#.*listen_addresses =.*/listen_addresses = '\\'*\\'/ " +
               '/var/lib/pgsql/data/postgresql.conf'

    # allow incoming connections to elasticsearch
    el_config = '/etc/elasticsearch/elasticsearch.yml'
    shell! 'root', "sed -i 's/^.*network.bind_host.*/network.bind_host: 0.0.0.0/' #{el_config}"
    shell! 'root', "sed -i 's/^.*network.publish_host.*/network.publish_host: 0.0.0.0/' #{el_config}"
    shell! 'root', "sed -i 's/^.*network.host.*/network.host: 0.0.0.0/' #{el_config}"

    # reset katello secret to "katello"
    shell! 'root', "sed -i 's/^.*oauth_secret: .*/oauth_secret: shhhh/' /etc/pulp/pulp.conf"
    shell! 'root', "sed -i 's/^.*candlepin.auth.oauth.consumer.katello.secret =.*/" +
        "candlepin.auth.oauth.consumer.katello.secret = shhhh/' /etc/candlepin/candlepin.conf"
    shell! 'root', "sed -i 's/^.*oauth_secret: .*/    oauth_secret: shhhh/' /etc/katello/katello.yml"

    shell! 'root', 'service pulp-server restart'
    shell! 'root', 'service tomcat6 restart'
    #       /home/use r/support/start-elastic.sh
    shell! 'root', 'service elasticsearch restart'
    shell! 'root', 'service postgresql restart'
  end
end
