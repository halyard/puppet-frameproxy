# @summary Configure mitmproxy instance for frame
#
# @param datadir sets location to store cached photos and TLS cert
# @param proxy_hostname sets hostname of proxy endpoint for certificate generation
# @param proxy_aws_access_key_id sets the aws key to use for route53 challenge
# @param proxy_aws_secret_access_key sets the aws secret key to use for the route53 challenge
# @param intercept_hostname sets hostname of frame api endpoint for certificate generation
# @param intercept_aws_access_key_id sets the aws key to use for route53 challenge
# @param intercept_aws_secret_access_key sets the aws secret key to use for the route53 challenge
# @param email sets the contact address for the certificate
# @param ip sets the IP to use for mitmproxy docker container
class frameproxy (
  String $datadir,
  String $proxy_hostname,
  String $proxy_aws_access_key_id,
  String $proxy_aws_secret_access_key,
  String $intercept_hostname,
  String $intercept_aws_access_key_id,
  String $intercept_aws_secret_access_key,
  String $email,
  String $ip = '172.17.0.4',
) {
  $proxy_hook_script =  "#!/usr/bin/env bash
cat \$LEGO_CERT_KEY_PATH \$LEGO_CERT_PATH > ${datadir}/tls/proxy_cert
/usr/bin/systemctl restart container@frameproxy"

  $intercept_hook_script =  "#!/usr/bin/env bash
cat \$LEGO_CERT_KEY_PATH \$LEGO_CERT_PATH > ${datadir}/tls/intercept_cert
/usr/bin/systemctl restart container@frameproxy"

  $command = [
    'mitmdump',
    "--allow-hosts ${intercept_hostname}",
    "--certs ${intercept_hostname}=/opt/tls/intercept_cert",
    "--certs ${proxy_hostname}=/opt/tls/proxy_cert",
    '-s /opt/scripts/cache.py',
  ]

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

  file { "${datadir}/scripts/cache.py":
    ensure => file,
    source => 'puppet:///modules/frameproxy/cache.py',
  }

  acme::certificate { $proxy_hostname:
    hook_script           => $proxy_hook_script,
    aws_access_key_id     => $proxy_aws_access_key_id,
    aws_secret_access_key => $proxy_aws_secret_access_key,
    email                 => $email,
  }

  acme::certificate { $intercept_hostname:
    hook_script           => $intercept_hook_script,
    aws_access_key_id     => $intercept_aws_access_key_id,
    aws_secret_access_key => $intercept_aws_secret_access_key,
    email                 => $email,
  }

  docker::container { 'frameproxy':
    image     => 'ghcr.io/mitmproxy/mitmproxy:latest',
    args      => [
      "--ip ${ip}",
      "-v ${datadir}/cache:/opt/cache",
      "-v ${datadir}/tls:/opt/tls",
      "-v ${datadir}/scripts:/opt/scripts",
    ],
    cmd       => join($command, ' '),
    subscribe => [
      File["${datadir}/scripts/cache.py"],
      Acme::Certificate[$proxy_hostname],
      Acme::Certificate[$intercept_hostname],
    ],
  }
}
