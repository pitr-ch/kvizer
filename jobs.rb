job 'clean installation'

job 'base' do
  offline do
    host.setup_private_network
    vm.setup_private_network
  end
  online do
    vm.shell! 'root', 'mkdir -p .ssh', :password => config.root_password
    vm.shell! 'root', %(printf "#{config.authorized_keys}" > .ssh/authorized_keys),
              :password => config.root_password
  end
end

job 'install-htop' do
  online { yum_install "htop" }
end

job 'install-katello' do
  online do
    vm.shell! 'root',
              "rpm -Uvh http://fedorapeople.org/groups/katello/releases/yum/nightly/Fedora/16/x86_64/katello-repos-latest.rpm"
    yum_install "katello-repos-testing"
    yum_install "katello-all"
  end
end

job 'configure-katello' do
  online { vm.shell! 'root', "katello-configure" }
end

job 'turnoff-services' do
  online do
    vm.shell! 'root', 'setenforce 0'
    vm.shell! 'root', 'service iptables stop'
    vm.shell! 'root', 'service katello stop'
    vm.shell! 'root', 'service katello-jobs stop'
    vm.shell! 'root', 'chkconfig iptables off'
    vm.shell! 'root', 'chkconfig katello off'
    vm.shell! 'root', 'chkconfig katello-jobs off'
    # TODO stop foreman
  end
end

job 'add-user' do
  online do
    vm.shell! 'root', 'useradd user -G wheel'
    vm.shell! 'root', 'passwd user -f -u'
    vm.shell! 'root', "echo #{config.user_password} | passwd user --stdin"
    vm.shell! 'root', 'su user -c "mkdir /home/user/.ssh"'
    vm.shell! 'root', 'su user -c "touch /home/user/.ssh/authorized_keys"'
    vm.shell! 'root', 'cat /root/.ssh/authorized_keys > /home/user/.ssh/authorized_keys'

    vm.shell! 'root', 'chmod u+w /etc/sudoers'
    vm.shell! 'root',
              'sed -i -E "s/# %wheel\s+ALL=\(ALL\)\s+NOPASSWD: ALL/%wheel\tALL=\(ALL\)\tNOPASSWD: ALL/" ' +
                  '/etc/sudoers'
    vm.shell! 'root',
              'sed -i -E "s/%wheel\s+ALL=\(ALL\)\s+ALL/# %wheel\tALL=\(ALL\)\tALL/" /etc/sudoers'
    vm.shell! 'root',
              'sed -i -E "s/Defaults\s+requiretty/# Defaults\trequiretty/" /etc/sudoers'
    vm.shell! 'root', 'chmod u-w /etc/sudoers'
    vm.shell! 'user', 'sudo echo a' # test
  end
end

job 'install-guest-additions' do
  online do
    version = config.virtual_box_version
    yum_install %w(dkms kernel-devel @development-tools)
    vm.shell! 'root',
              "wget http://download.virtualbox.org/virtualbox/#{version}/VBoxGuestAdditions_#{version}.iso"
    vm.shell! 'root', 'mkdir additions'
    vm.shell! 'root', "mount -o loop VBoxGuestAdditions_#{version}.iso ./additions"
    vm.shell! 'root', 'additions/VBoxLinuxAdditions.run'
    vm.shell! 'root', 'usermod -a -G vboxsf root'
    vm.shell! 'root', 'usermod -a -G vboxsf user'
  end
end

job 'setup-shared-folders' do
  offline { vm.setup_shared_folders }
  online do
    config.shared_folders.each do |name, path|
      vm.shell! 'user', "ln -s /media/sf_#{name}/ #{name}"
    end
    vm.shell! 'user', 'rm .bash_profile'
    vm.shell! 'user', 'ln -s /home/user/support/.bash_profile .bash_profile'
  end
end

#class Bundle < Job
#  def online_job
#    vm.shell! 'root', 'yum install -y git tito ruby-devel postgresql-devel sqlite-devel libxml2 libxml2-devel libxslt ' +
#        'libxslt-devel'
#    #vm.shell! 'user', 'cd katello/src; sudo bundle install'
#  end
#end

job 'setup-development' do
  online do
    vm.shell! 'root', 'rm /etc/katello/katello.yml'
    vm.shell! 'root', "ln -s #{config.katello_path}/src/config/katello.yml /etc/katello/katello.yml"

    # reset oauth
    vm.shell! 'user', "sudo #{config.katello_path}/src/script/reset-oauth shhhh"
    vm.shell! 'root', 'service tomcat6 restart'
    vm.shell! 'root', 'service pulp-server restart'

    # create katello db
    waiting = 0
    loop do
      break if vm.shell('root', 'service postgresql status').success
      waiting += 1
      sleep 1
      raise 'db is not running even after 30s' if waiting > 30
    end
    vm.shell! 'root', "su - postgres -c 'createuser -dls katello  --no-password'"
  end
end

job 'install-packaging' do
  online do
    yum_install %w(tito ruby-devel postgresql-devel sqlite-devel libxml2 libxml2-devel libxslt libxslt-devel)
  end
end

job 'package' do
  online do
    dirs = %w(src katello-configure katello-utils cli repos selinux/katello-selinux)

    rpms = dirs.map do |dir|
      logger.info "building '#{dir}'"
      result = vm.shell! 'user', "cd #{config.katello_path}/#{dir}; tito build --test --srpm --dist=.fc16"
      result.out =~ /^Wrote: (.*src\.rpm)$/
      vm.shell! 'root', "echo y | yum-builddep #{$1}"
      result = vm.shell! 'user', "cd #{config.katello_path}/#{dir}; tito build --test --rpm --dist=.fc16"
      result.out =~ /Successfully built: (.*)\Z/
      $1.split(/\s/).tap { |rpms| logger.info "rpms: #{rpms.join(' ')}" }
    end.flatten

    logger.info "All packaged rpms:\n  #{rpms.join("\n  ")}"

    to_install = rpms.select { |rpm| rpm !~ /headpin|devel|src\.rpm/ }
    vm.shell 'root', "yum localinstall -y --nogpgcheck #{to_install.join ' '}"
  end
end

job 'package2' do
  online do
    vm.shell! 'user', "git clone #{options[:source]} katello-build-source"
    vm.shell! 'user', "cd katello-build-source; git checkout #{options[:branch]}"

    vm.shell! 'root',
              "rpm -Uvh http://fedorapeople.org/groups/katello/releases/yum/nightly/Fedora/16/x86_64/katello-repos-latest.rpm"
    yum_install "katello-repos-testing"

    yum_install "puppet" # FIXME workaround for missing puppet user when puppet is installed by yum-builddep

    spec_dirs = %w(src cli katello-configure katello-utils repos selinux/katello-selinux scripts/system-test)

    rpms = spec_dirs.map do |dir|
      logger.info "building '#{dir}'"
      result = vm.shell! 'user', "cd katello-build-source/#{dir}; tito build --test --srpm --dist=.fc16"
      result.out =~ /^Wrote: (.*src\.rpm)$/
      vm.shell! 'root', "echo y | yum-builddep #{$1}"
      result = vm.shell! 'user', "cd katello-build-source/#{dir}; tito build --test --rpm --dist=.fc16"
      result.out =~ /Successfully built: (.*)\Z/
      $1.split(/\s/).tap { |rpms| logger.info "rpms: #{rpms.join(' ')}" }
    end.flatten

    logger.info "All packaged rpms:\n  #{rpms.join("\n  ")}"

    to_install = rpms.select { |rpm| rpm !~ /headpin|devel|src\.rpm/ }
    result     = vm.shell 'root', "yum localinstall -y --nogpgcheck #{to_install.join ' '}"
    unless result.success
      vm.shell 'root', "rpm -Uvh --oldpackage --force #{to_install.join ' '}"
    end
    #rpm -Uvh --oldpackage --force $RPMBUILD/*/*/*rpm
  end
end

job 'reconfigure-katello', 'configure-katello'

job 'system-test' do
  online do
    binding.pry
    result = vm.shell 'user', '/usr/share/katello/script/cli-tests/cli-system-test all'
    logger.error "system tests FAILED" unless result.success
  end
end

job 'update' do
  online { vm.shell! 'root', 'yum update -y' }
end

job 'relax-security' do
  online do
    # allow incoming connections to postgresql
    unless vm.shell('root', 'cat /var/lib/pgsql/data/pg_hba.conf | grep "192.168.25.0/24"').success
      vm.shell! 'root',
                'echo "host all all 192.168.25.0/24 trust" | tee -a /var/lib/pgsql/data/pg_hba.conf'
    end
    vm.shell! 'root',
              "sed -i 's/^#.*listen_addresses =.*/listen_addresses = '\\'*\\'/ " +
                  '/var/lib/pgsql/data/postgresql.conf'

    # allow incoming connections to elasticsearch
    el_config = '/etc/elasticsearch/elasticsearch.yml'
    vm.shell! 'root', "sed -i 's/^.*network.bind_host.*/network.bind_host: 0.0.0.0/' #{el_config}"
    vm.shell! 'root', "sed -i 's/^.*network.publish_host.*/network.publish_host: 0.0.0.0/' #{el_config}"
    vm.shell! 'root', "sed -i 's/^.*network.host.*/network.host: 0.0.0.0/' #{el_config}"

    # reset katello secret to "katello"
    vm.shell! 'root', "sed -i 's/^.*oauth_secret: .*/oauth_secret: shhhh/' /etc/pulp/pulp.conf"
    vm.shell! 'root', "sed -i 's/^.*candlepin.auth.oauth.consumer.katello.secret =.*/" +
        "candlepin.auth.oauth.consumer.katello.secret = shhhh/' /etc/candlepin/candlepin.conf"
    vm.shell! 'root', "sed -i 's/^.*oauth_secret: .*/    oauth_secret: shhhh/' /etc/katello/katello.yml"

    vm.shell! 'root', 'service pulp-server restart'
    vm.shell! 'root', 'service tomcat6 restart'
    #       /home/use r/support/start-elastic.sh
    vm.shell! 'root', 'service elasticsearch restart'
    vm.shell! 'root', 'service postgresql restart'
  end
end
