#! /bin/sh

set -e

ES_CONFIG_FILE=/usr/share/java/elasticsearch/config/elasticsearch.yaml

SECRETS_DIR=/etc/elasticsearch/secrets
CLIENT_CERTS_DIR=$SECRETS_DIR/client-certs
CLIENT_CA_DIR=$SECRETS_DIR/client-ca
KEYSTORE_DIR=/etc/elasticsearch/keystores
KEYSTORE_FILE=$KEYSTORE_DIR/keystore
KEYSTORE_PWD=$(head /dev/urandom -c 512 | tr -dc A-Z-a-z-0-9 | head -c 17)
TRUSTSTORE_PWD=$(head /dev/urandom -c 512 | tr -dc A-Z-a-z-0-9 | head -c 17)
TRUSTSTORE_FILE=$KEYSTORE_DIR/truststore
WORK_DIR=`mktemp -d`

if [ ! -w $ES_CONFIG_FILE ] ; then
  echo "[INFO] $ES_CONFIG_FILE is not writeable.  Skipping JKS generation on container start"
  exit 0
fi

if  [ -f $CLIENT_CERTS_DIR ] && [ ! -z "$(ls -A $CLIENT_CERTS_DIR | wc -l)" -gt 0 ] ; then
    pushd $CLIENT_CERTS_DIR

    shopt -s nullglob
    client_dirs=(*/)
    shopt -u nullglob

    for client_dir in $(client_dirs[*])
    do
        client_alias=basename(client_dir)
        client_ca="$CLIENT_CA_DIR/$client_alias/ca.cert"
        if [ -f "$client_dir/tls.cert" ] && [ -f "$client_dir/tls.key" ] && [ -f $client_ca ] ; then
            echo "[INFO] found $client_alias in client-certs with tls.cert, tls.key, and associated ca. Generating pkcs12 keystore"
            openssl pkcs12 \
                -export \
                -name $client_alias \
                -in $client_dir/tls.cert \
                -inkey $client_dir/tls.key \
                -out $WORK_DIR/$client_alias.pkcs12

            echo "[INFO] importing $client_alias pkcs12 keystore into $KEYSTORE_FILE"
            keytool -importkeystore \
                -destkeystore $KEYSTORE_FILE \
                -srckeystore $WORK_DIR/$client_alias.pkcs12 \
                -srcstoretype pkcs12 \
                -alias $client_alias \
                -storepass $KEYSTORE_PASSWORD

            echo "[INFO] importing $client_ca into $TRUSTSTORE_FILE"
            keytool -noprompt -import \
                -alias $client_alias
                -file $client_ca
                -keystore $TRUSTSTORE_FILE \
                -trustcacerts \
                -storepass $TRUSTSTORE_PWD

        else
            echo "[WARN] found $client_alias in client-certs directory but are missing the tls.cert, tls.key, or associated ca."
        fi

    done
    popd
else
  echo "[INFO] $CLIENT_CERTS_DIR does not exist or has no keys. Skipping JKS generation on container start"
  exit 0
fi

if [ -f $KEYSTORE_FILE ] && [ -f $TRUSTSTORE_FILE ] ; then
    echo "[INFO] Modifying the Elasticsearch config to use the generated $KEYSTORE_FILE"
    for entry in "/etc/elasticsearch/secret/searchguard.key" "/etc/elasticsearch/secret/key" "/etc/elasticsearch/secret/admin.jks"
    do
      sed -i 's#$entry#'$KEYSTORE_FILE'#g' $ES_CONFIG_FILE
    done

    echo "[INFO] Modifying the Elasticsearch config to use the generated $TRUSTSTORE_FILE"
    for entry in "/etc/elasticsearch/secret/searchguard.truststore" "/etc/elasticsearch/secret/truststore"
    do
      sed -i 's#/etc/elasticsearch/secret/searchguard.truststore#'$TRUSTSTORE_FILE'#g' $ES_CONFIG_FILE
    done

    echo "[INFO] Modifying the Elasticsearch config to use the generated passwords..."
    sed -i 's#keystore_password: kspass#keystore_password: '$KEYSTORE_PASSWORD'#g' $ES_CONFIG_FILE
    sed -i 's#truststore_password: tspass#keystore_password: '$TRUSTSTORE_PWD'#g' $ES_CONFIG_FILE

fi
