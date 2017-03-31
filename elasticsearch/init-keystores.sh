#! /bin/sh

set -e

ES_CONFIG_FILE=${ES_CONFIG_FILE:-/usr/share/java/elasticsearch/config/elasticsearch.yml}

SECRETS_DIR=/etc/elasticsearch/secrets
CLIENT_CERTS_DIR=$SECRETS_DIR/client-certs
CLIENT_CA_DIR=$SECRETS_DIR/client-ca
KEYSTORE_DIR=/tmp/elasticsearch/keystores
KEYSTORE_FILE=$KEYSTORE_DIR/keystore.jks
KEYSTORE_PWD=kspass #$(head /dev/urandom -c 512 | tr -dc A-Z-a-z-0-9 | head -c 17)
TRUSTSTORE_PWD=tspass #$(head /dev/urandom -c 512 | tr -dc A-Z-a-z-0-9 | head -c 17)
TRUSTSTORE_FILE=$KEYSTORE_DIR/truststore.jks
WORK_DIR=`mktemp -d`

if [ ! -w $ES_CONFIG_FILE ] ; then
  echo "[INFO] $ES_CONFIG_FILE is not writeable.  Skipping JKS generation on container start"
  exit 0
fi

if  [ -d $CLIENT_CERTS_DIR ] && [ "$(ls -A $CLIENT_CERTS_DIR | wc -l)" -gt 0 ] ; then

    mkdir -p $KEYSTORE_DIR

    pushd $CLIENT_CERTS_DIR
    for client_dir in *
    do
        client_alias=$(basename $client_dir)
        client_ca="$CLIENT_CA_DIR/$client_alias/ca.crt"
        if [ -f "$client_dir/tls.crt" ] && [ -f "$client_dir/tls.key" ] && [ -f $client_ca ] ; then
            echo "[INFO] found $client_alias in client-certs with tls.crt, tls.key, and associated ca. Generating pkcs12 keystore"
            openssl pkcs12 \
                -export \
                -name $client_alias \
                -in $client_dir/tls.crt \
                -inkey $client_dir/tls.key \
                -passout pass:$KEYSTORE_PWD \
                -out $WORK_DIR/$client_alias.pkcs12

            echo "[INFO] importing $client_alias pkcs12 keystore into $KEYSTORE_FILE"
            keytool -importkeystore \
                -srckeystore $WORK_DIR/$client_alias.pkcs12 \
                -srcstoretype pkcs12 \
                -srcstorepass $KEYSTORE_PWD \
                -alias $client_alias \
                -destkeystore $KEYSTORE_FILE \
                -deststoretype jks \
                -deststorepass $KEYSTORE_PWD

            echo "[INFO] importing $client_ca into $KEYSTORE_FILE"
            keytool -import \
                -file $client_ca \
                -noprompt \
                -keystore $KEYSTORE_FILE \
                -alias "${client_alias}-ca" \
                -trustcacerts \
                -storepass $KEYSTORE_PWD

            echo "[INFO] importing $client_ca into $TRUSTSTORE_FILE"
            keytool -import \
                -file $client_ca \
                -noprompt \
                -keystore $TRUSTSTORE_FILE \
                -alias "${client_alias}-ca" \
                -trustcacerts \
                -storepass $TRUSTSTORE_PWD

        else
            echo "[WARN] found $client_alias in $client_dir directory but missing on or more of: tls.crt, tls.key, or associated ca in $CLIENT_CA_DIR/$client_alias."
        fi

    done
    popd
else
  echo "[INFO] $CLIENT_CERTS_DIR does not exist or has no keys. Skipping JKS generation on container start"
  exit 0
fi

if [ -f $KEYSTORE_FILE ] && [ -f $TRUSTSTORE_FILE ] ; then
    echo "[INFO] Modifying the Elasticsearch config to use the generated $KEYSTORE_FILE"
    for entry in "/etc/elasticsearch/keystore/searchguard.key" "/etc/elasticsearch/keystore/admin.jks" "/etc/elasticsearch/keystore/key"
    do
      sed -i "s#$entry#"$KEYSTORE_FILE"#g" $ES_CONFIG_FILE
    done

    echo "[INFO] Modifying the Elasticsearch config to use the generated $TRUSTSTORE_FILE"
    for entry in "/etc/elasticsearch/keystore/searchguard.truststore" "/etc/elasticsearch/keystore/truststore"
    do
      sed -i "s#$entry#"$TRUSTSTORE_FILE"#g" $ES_CONFIG_FILE
    done

#    echo "[INFO] Modifying the Elasticsearch config to use the generated passwords..."
#    sed -i 's#keystore_password: kspass#keystore_password: '$KEYSTORE_PWD'#g' $ES_CONFIG_FILE
#    sed -i 's#truststore_password: tspass#truststore_password: '$TRUSTSTORE_PWD'#g' $ES_CONFIG_FILE

fi
