#! /bin/bash

CONFIG_LOC="/etc/aws-iot-device-client"
mkdir -p $CONFIG_LOC

install_client() {
    echo "Installing Dependencies"
    sudo apt-get update -q
    sudo apt-get install -yq \
        git \
        cmake \
        g++ \
        cpp \
        libssl-dev

    echo "Building AWS IoT Device Client"
    # START HACK: temporary until this feature on mainline
    git clone https://github.com/philcali/aws-iot-device-client
    cd aws-iot-device-client
    git remote add awslabs https://github.com/awslabs/aws-iot-device-client
    git pull --tags awslabs
    # END HACK
    mkdir build
    cd build
    cmake ../
    cmake --build . --target aws-iot-device-client

    mv aws-iot-device-client /sbin/aws-iot-device-client

    cd ../../
    rm -rf aws-iot-device-client
}

install_service() {
    echo "Installing system service"
    cat > /etc/systemd/system/aws-iot-device-client.service << EOL
[Unit]
Description=AWS IoT Device Client
Wants=network-online.target
After=network.target network-online.target

[Service]
ExecStart=/sbin/aws-iot-device-client --config-file $CONFIG_LOC/aws-iot-device-client.conf

[Install]
WantedBy=multi-user.target
EOL
    systemctl enable aws-iot-device-client
    systemctl start aws-iot-device-client
}

configure_device_client() {
    echo "Configuring AWS IoT Device Client"
    . /etc/pinthesky/pinthesky.env
    git clone https://github.com/awslabs/aws-iot-device-client
    mkdir -p $JOBS_DIR
    cp -r aws-iot-device-client/sample-job-handlers/*.sh $JOBS_DIR/
    rm -rf aws-iot-device-client
    for replacement in THING_CERT THING_KEY THING_NAME CA_CERT DATA_ENDPOINT EVENT_INPUT EVENT_OUTPUT CONFIGURE_INPUT CONFIGURE_OUTPUT JOBS_DIR; do
        if [ -f "${!replacement}" ] && [ $replacement = 'CONFIGURE_INPUT' ] || [ $replacement = 'CONFIGURE_OUTPUT' ]; then
            chmod 600 "${!replacement}"
        fi
        if [ -f "${!replacement}" ] && [ $replacement = 'EVENT_INPUT' ] || [ $replacement = 'EVENT_OUTPUT' ]; then
            chmod 745 $(dirname "${!replacement}")
            chmod 600 "${!replacement}"
        fi
        if [ $replacement = 'THING_CERT' ]; then
            chmod 644 "${!replacement}"
        fi
        sed -i "s|$replacement|${!replacement}|" aws-iot-device-client.json
    done
    mv aws-iot-device-client.json $CONFIG_LOC/aws-iot-device-client.conf
    mv upgrade-pinthesky.sh $JOBS_DIR/

    chmod 700 /etc/pinthesky/certs
    chmod 745 $CONFIG_LOC
    chmod 640 $CONFIG_LOC/aws-iot-device-client.conf
}

usage() {
    echo "install_device_client.sh: Installs the aws-iot-device-client software"
    echo " -t: install_client, install_service, configure_device_client"
    echo " -h: prints this help"
}

while getopts "t:" flag
do
    case "${flag}" in
        t) TARGET="${OPTARG}";;
        *) usage;;
    esac
done

eval $TARGET