mv docker.au-team.irpo.* /etc/nginx/ssl
mv web.au-team.irpo.* /etc/nginx/ssl

apt-get install -y openssl-gost-engine
control openssl-gost enabled
