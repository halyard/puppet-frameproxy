# @summary Configure mitmproxy instance for frame
#
# @param datadir sets location to store cached photos and TLS cert
# @param hostname sets hostname of frame API endpoint for certificate generation
# @param aws_access_key_id sets the AWS key to use for Route53 challenge
# @param aws_secret_access_key sets the AWS secret key to use for the Route53 challenge
# @param email sets the contact address for the certificate
# @param ip sets the IP to use for mitmproxy docker container
class frameproxy (
  String $datadir,
  String $hostname,
  String $aws_access_key_id,
  String $aws_secret_access_key,
  String $email,
  String $ip = '172.17.0.4',
) {
  $hook_script =  "#!/usr/bin/env bash
cat \$LEGO_CERT_KEY_PATH \$LEGO_CERT_KEY_PATH > ${datadir}/tls/cert
/usr/bin/systemctl restart container@frameproxy"

  firewall { '100 dnat for mitmproxy':
    chain  => 'DOCKER_EXPOSE',
    jump   => 'DNAT',
    proto  => 'tcp',
    dport  => 8080,
    todest => "${ip}:8080",
    table  => 'nat',
  }

  file { [
      $datadir,
      "${datadir}/cache",
      "${datadir}/tls",
      "${datadir}/scripts",
    ]:
      ensure => directory,
  }

  -> acme::certificate { $hostname:
    hook_script           => $hook_script,
    aws_access_key_id     => $aws_access_key_id,
    aws_secret_access_key => $aws_secret_access_key,
    email                 => $email,
  }

  file { "${datadir}/scripts/cache.py":
    ensure => file,
    source => 'puppet:///modules/frameproxy/cache.py',
  }

  docker::container { 'frameproxy':
    image   => 'mitmproxy/mitmproxy',
    args    => [
      "--ip ${ip}",
      "-v ${datadir}/cache:/opt/cache",
      "-v ${datadir}/tls:/opt/tls",
      "-v ${datadir}/scripts:/opt/scripts",
    ],
    cmd     => "mitmproxy --allow-hosts ${hostname} --certs ${hostname}=/opt/tls/cert -s /opt/scrits/cache.py",
    require => [
    ],
  }
}
