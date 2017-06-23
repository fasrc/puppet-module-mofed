# See README.md for more details.
class mofed::srp (
  Enum['present', 'absent', 'disabled'] $ensure = 'present',
  Array $ports = [],
) inherits mofed::params {

  include mofed

  case $ensure {
    'present': {
      $package_ensure = 'present'
      $file_ensure    = 'file'
      $srp_load       = 'yes'
      $service_ensure = 'running'
      $service_enable = true
    }
    'absent': {
      $package_ensure = 'absent'
      $file_ensure    = 'absent'
      $srp_load       = 'no'
      $service_ensure = 'stopped'
      $service_enable = false
    }
    'disabled': {
      $package_ensure = 'present'
      $file_ensure    = 'file'
      $srp_load       = 'yes'
      $service_ensure = 'stopped'
      $service_enable = false
    }
    default: {
      # Do nothing
    }
  }

  package { 'srptools':
    ensure  => $package_ensure,
    require => Class['mofed::repo'],
  }

  if $mofed::manage_config {
    shellvar { 'SRP_LOAD':
      ensure  => 'present',
      target  => $mofed::openib_config_path,
      value   => $srp_load,
      notify  => $mofed::openib_shellvar_notify,
      require => Class['::mofed::install'],
    }
  }

  file { '/etc/rsyslog.d/srp_daemon.conf':
    ensure  => 'absent',
    require => Package['srptools'],
  }

  rsyslog::snippet { '60_srp_daemon.conf':
    ensure  => $file_ensure,
    content => template('mofed/srp/srp_daemon.rsyslog.conf.erb'),
    require => Package['srptools'],
  }

  # Template uses:
  # - $ports
  file { '/etc/sysconfig/srpd':
    ensure  => $file_ensure,
    owner   => 'root',
    group   => 'root',
    mode    => '0644',
    content => template('mofed/srp/srpd.sysconfig.erb'),
    require => Package['srptools'],
  }

  # opensmd can not be limited to specific ports
  # so only run if ports are not defined
  if empty($ports) {
    service { 'srpd':
      ensure     => $service_ensure,
      enable     => $service_enable,
      hasstatus  => true,
      hasrestart => true,
      #subscribe  => File[$mofed::openib_config_path],
      require    => Package['srptools'],
    }
  } else {
    service { 'srpd':
      ensure     => 'stopped',
      enable     => false,
      hasstatus  => true,
      hasrestart => true,
      require    => Package['srptools'],
    }

    if versioncmp($::operatingsystemrelease, '7.0') >= 0 {
      systemd::unit_file { 'srpd@.service':
        ensure => $file_ensure,
        source => 'puppet:///modules/mofed/srp/srpd@.service',
      }

      $ports.each |Integer $index, String $port| {
        $i = $index + 1
        service { "srpd@${i}":
          ensure     => $service_ensure,
          enable     => $service_enable,
          hasstatus  => true,
          hasrestart => true,
          require    => Exec['systemctl-daemon-reload'],
          subscribe  => [
            File['/etc/sysconfig/srpd'],
            Systemd::Unit_file['srpd@.service'],
          ]
        }
      }
    }
  }

}
