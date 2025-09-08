#!/bin/sh

# Credits to the following for inspiration:
# - https://gist.github.com/gmassawe/b29643dc98e9905303a43c5affa0e278
# - https://stackoverflow.com/questions/10175812/how-can-i-generate-a-self-signed-ssl-certificate-using-openssl/41366949#41366949

usage() {
cat <<EOF
Usage: selfsigned.sh [SUBJECT_ALT_NAMES]...

Example: DN_COMMON_NAME=example.com ./selfsigned.sh DNS:example.com IP:123.123.123.123 email:my@example.com RID:1.2.3.4


Use the following environment variables to specify the subject set.
DN_COUNTRY DN_STATE DN_LOCALITY DN_ORGANIZATION DN_ORGANIZATION_UNIT DN_COMMON_NAME DN_ALT_NAMES

NOTE: DN_COMMON_NAME and at least one SUBJECT_ALT_NAME must be specified.

KEY_ALGO supports "rsa" or "ed25519". Default is "ed25519".
"
EOF
}

LBLUE='\033[1;34m'
LRED='\033[1;31m'
NC='\033[0m'

fatal() {
	printf "${LRED}[ERR]: $*${NC}\n"
	exit 1
}

info() {
	printf "${LBLUE}[INF]: $*${NC}\n"
}

# Defaults
openssl_cnf="openssl.cnf"

root_key="root.key"
root_crt="root.crt"

ca_key="ca.key"
ca_crt="ca.crt"
ca_csr="ca.csr"
ca_ext="v3_intermediate_ca.ext"
ca_chain="ca_chain.crt"

srv_key="server.key"
srv_crt="server.crt"
srv_csr="server.csr"
srv_ext="v3_server_cert.ext"

cli_key="client.key"
cli_crt="client.crt"
cli_csr="client.csr"
cli_ext="v3_client_cert.ext"

ca_duration=3650
cert_duration=730

# Handle args
if [ "$1" = "-h" ] || [ "$1" = "help" ] || [ "$1" = "--help" ]; then
	usage
fi

algo="${KEY_ALGO:-ed25519}"
if [ "$algo" = "rsa" ]; then
	algo="rsa:4096 -sha512"
else
	algo="ed25519"
fi


# Construct subject
subj=""
append_subj() {
	key="$1"
	val="$2"
	if [ -n "$val" ]; then
		subj="${subj}/${key}=${val}"
	fi
}

append_subj "C" "$DN_COUNTRY"
append_subj "ST" "$DN_STATE"
append_subj "L" "$DN_LOCALITY"
append_subj "O" "$DN_ORGANIZATION"
append_subj "OU" "$DN_ORGANIZATION_UNIT"
if [ -z "$DN_COMMON_NAME" ]; then
	fatal "Unspecified DN_COMMON_NAME!"
fi
append_subj "CN" "$DN_COMMON_NAME"

echo "SUBJ: $subj"


# Concatenate subjectAltNames
alt_names="subjectAltName="
for name in "$@"; do
	alt_names="${alt_names}${name},"
done
alt_names="${alt_names%?}"

echo "ALT NAMES: $alt_names"

#info "create openssl config"
#cat <<EOF > "./$openssl_cnf"
#[req]
#distinguished_name = req_distinguished_name
#x509_extensions = v3_ca
#req_extensions = v3_req
#default_md = sha256
#prompt = no
#
#[req_distinguished_name]
#C = ${dn_country}
#ST = ${dn_state}
#L = ${dn_locality}
#O = ${dn_organization}
#OU = ${dn_organization_unit}
#CN = ${dn_common_name}
#
#[v3_ca]
#basicConstraints = CA:TRUE
#keyUsage = keyCertSign, cRLSign
#subjectKeyIdentifier = hash
#authorityKeyIdentifier = keyid:always,issuer:always
#
#[v3_req]
#basicConstraints = CA:FALSE
#keyUsage = digitalSignature, keyEncipherment
#subjectAltName = @alt_names
#
#[alt_names]
#DNS.1 = example.com
#DNS.2 = *.example.com
#EOF

info "create root certificate"
#openssl genpkey -algorithm RSA -out "$root_key" -aes256 -pkeyopt rsa_keygen_bits:4096
#openssl req -new -x509 -sha256 -days 3650 -key "$root_key" -extensions v3_ca -out "$root_crt"

openssl req -x509 \
	-newkey "$algo" \
	-keyout "$root_key" \
	-out "$root_crt" \
	-days "$ca_duration" \
	-noenc \
	-subj "$subj" \
	-addext "basicConstraints=CA:TRUE" \
	-addext "keyUsage=keyCertSign,cRLSign" \
	-addext "subjectKeyIdentifier=hash" \
	-addext "authorityKeyIdentifier=keyid:always,issuer:always"

#info "create intermediate CA"
#cat <<EOF > "./$ca_ext"
#basicConstraints = CA:TRUE, pathlen:0
#keyUsage = keyCertSign, cRLSign
#authorityKeyIdentifier = keyid:always,issuer:always
#subjectKeyIdentifier = hash
#EOF
#openssl genpkey -algorithm RSA -out "$ca_key" -aes256 -pkeyopt rsa_keygen_bits:4096
#openssl req -new -key "$ca_key" -out "$ca_csr"
#openssl x509 -req -in "$ca_csr" -CA "$root_crt" -CAkey "$root_key" -CAcreateserial -extfile "$ca_ext" -days 3650 -sha256 -out "$ca_crt"

openssl req -x509 \
	-newkey "$algo" \
	-CA "$root_crt" \
	-CAkey "$root_key" \
	-keyout "$ca_key" \
	-out "$ca_crt" \
	-days "$ca_duration" \
	-noenc \
	-subj "$subj" \
	-addext "basicConstraints = CA:TRUE, pathlen:0" \
	-addext "keyUsage = keyCertSign, cRLSign" \
	-addext "authorityKeyIdentifier = keyid:always,issuer:always" \
	-addext "subjectKeyIdentifier = hash"


info "create CA chain"
cat "$ca_crt" "$root_crt" > "$ca_chain"

#info "create server certificate"
#cat <<EOF > "./$srv_ext"
#basicConstraints = CA:FALSE
#keyUsage = digitalSignature, keyEncipherment
#extendedKeyUsage = serverAuth
#subjectAltName = @alt_names
#
#[alt_names]
#DNS.1 = example.com
#DNS.2 = *.example.com
#EOF
#openssl genpkey -algorithm RSA -out "$srv_key" -aes256 -pkeyopt rsa_keygen_bits:4096
#openssl genpkey -algorithm $algo -out "$srv_key"
#openssl req -new -key "$srv_key" -out "$srv_csr" -config "$openssl_cnf"
#openssl req -new -key "$srv_key" -out "$srv_csr" -config "$openssl_cnf"
#openssl x509 -req -in "$srv_csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial -extfile "$srv_ext" -days 730 -sha256 -out "$srv_crt"

openssl req -x509 \
	-newkey "$algo" \
	-CA "$ca_crt" \
	-CAkey "$ca_key" \
	-days "$ca_duration" \
	-keyout "$srv_key" \
	-out "$srv_crt" \
	-noenc \
	-subj "$subj" \
	-addext "basicConstraints=CA:FALSE" \
	-addext "keyUsage=digitalSignature,keyEncipherment" \
	-addext "extendedKeyUsage=serverAuth" \
	-addext "$alt_names"

#info "create client certificate"
#cat <<EOF > "./$cli_ext"
#basicConstraints = CA:FALSE
#keyUsage = digitalSignature
#extendedKeyUsage = clientAuth
#EOF
#openssl genpkey -algorithm RSA -out "$cli_key" -aes256 -pkeyopt rsa_keygen_bits:4096
#openssl req -new -key "$cli_key" -out "$cli_csr" -config "$openssl_cnf"
#openssl x509 -req -in "$cli_csr" -CA "$ca_crt" -CAkey "$ca_key" -CAcreateserial -extfile "$cli_ext" -days 730 -sha256 -out "$cli_crt"

openssl req -x509 \
	-newkey "$algo" \
	-CA "$ca_crt" \
	-CAkey "$ca_key" \
	-days "$ca_duration" \
	-keyout "$cli_key" \
	-out "$cli_crt" \
	-noenc \
	-subj "$subj" \
	-addext "basicConstraints=CA:FALSE" \
	-addext "keyUsage=digitalSignature" \
	-addext "extendedKeyUsage=clientAuth" \
	-addext "$alt_names"

info "verify server certificate against CA chain"
openssl verify -verbose -CAfile ca_chain.crt "$srv_crt"

info "verify client certificate against CA chain"
openssl verify -verbose -CAfile ca_chain.crt "$cli_crt"


# References:
# `-subj` is documented in `man openssl-x509`
# `subjectAltName` is documented in `man x509v3_config`
# Terminal colors: https://stackoverflow.com/a/5947802
