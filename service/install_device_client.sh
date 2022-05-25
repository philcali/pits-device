#! /bin/bash

CONFIG_LOC="/etc/aws-iot-device-client"
mkdir -p $CONFIG_LOC

echo "Installing Dependencies"
sudo apt-get update -q
sudo apt-get install -yq \
    git \
    cmake \
    g++ \
    cpp \
    libssl-dev

echo "Building AWS IoT Device Client"
git clone https://github.com/awslabs/aws-iot-device-client
cd aws-iot-device-client
mkdir build
cd build
cmake ../
cmake --build . --target aws-iot-device-client

mv aws-iot-device-client /sbin/aws-iot-device-client

cd ../../
rm -rf aws-iot-device-client

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

echo "Configuring AWS IoT Device Client"
. /etc/pinthesky/pinthesky.env
for replacement in THING_CERT THING_KEY THING_NAME CA_CERT DATA_ENDPOINT EVENT_INPUT EVENT_OUTPUT CONFIURE_INPUT CONFIGURE_OUTPUT; do
    if [ -f "${!replacement}" ] && [ $replacement = 'CONFIGURE_INPUT' ] || [ $replacement = 'CONFIGURE_OUTPUT' ] then;
        chmod 600 "${!replacement}"
    fi
    if [ -f "${!replacement}" ] && [ $replacement = 'EVENT_INPUT' ] || [ $replacement = 'EVENT_OUTPUT' ] then;
        chmod 745 $(dirname "${!replacement}")
        chmod 600 "${!replacement}"
    fi
    if [ $replacement = 'THING_CERT' ]; then
        chmod 644 "${!replacement}"
    fi
    sed -i "s|$replacement|${!replacement}|" aws-iot-device-client.json
done
mv aws-iot-device-client.json $CONFIG_LOC/aws-iot-device-client.conf

chmod 700 /etc/pinthesky/certs
chmod 745 $CONFIG_LOC

systemctl enable aws-iot-device-client
systemctl start aws-iot-device-client