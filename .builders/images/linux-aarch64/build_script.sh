#!/usr/bin/env bash

set -exu

build_wheels() {
    /py${DD_BUILD_PYTHON_VERSION}/bin/python -m pip wheel "$@"
}

# We don't support pymqi on ARM for now
sed -i '/pymqi==/d' /home/requirements.in

# Packages which must be built from source
always_build=()

if [[ "${DD_BUILD_PYTHON_VERSION}" == "3" ]]; then
    # confluent-kafka and librdkafka need to be compiled from source to get kerberos support
    # The librdkafka version needs to stay in sync with the confluent-kafka version,
    # thus we extract the version from the requirements file.
    kafka_version=$(grep 'confluent-kafka==' /home/requirements.in | sed -E 's/^.*([[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+).*$/\1/')
    # Libraries need to be explicitly specified for static linking to work properly
    LDFLAGS="${LDFLAGS} -L/usr/local/lib -lkrb5 -lgssapi_krb5 -llmdb" \
    DOWNLOAD_URL="https://github.com/confluentinc/librdkafka/archive/refs/tags/v{{version}}.tar.gz" \
        VERSION="${kafka_version}" \
        SHA256="2d49c35c77eeb3d42fa61c43757fcbb6a206daa560247154e60642bcdcc14d12" \
        RELATIVE_PATH="librdkafka-{{version}}" \
        bash install-from-source.sh --enable-sasl --enable-curl
    always_build+=("confluent-kafka")
else
    echo "CFLAGS=\"-I/usr/local/ssl/include ${CFLAGS}\"" >> $DD_ENV_FILE
    echo "LDFLAGS=\"-L/usr/local/ssl/lib ${LDFLAGS}\"" >> $DD_ENV_FILE

    # Not working on Python 2
    sed -i '/aerospike==/d' /home/requirements.in
fi

# Empty arrays are flagged as unset when using the `-u` flag. This is the safest way to work around that
# (see https://stackoverflow.com/a/61551944)
pip_no_binary=${always_build[@]+"${always_build[@]}"}
if [[ "$pip_no_binary" ]]; then
    # If there are any packages that must always be built, inform pip
    echo "PIP_NO_BINARY=\"${pip_no_binary}\"" >> $DD_ENV_FILE
fi
