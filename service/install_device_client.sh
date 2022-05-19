#! /bin/bash

CONFIG_LOC="/etc/aws-iot-device-client"
mkdir -p $CONFIG_LOC

echo "Installing Dependencies"
sudo apt-get update -q
sudo apt-get install -y \
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

cd ../
mv aws-iot-device-client /sbin/aws-iot-device-client

cd ../
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
for replacement in THING_CERT THING_KEY THING_NAME CA_CERT CREDENTIALS_ENDPOINT EVENT_INPUT EVENT_OUTPUT; do
    sed -i "s|$replacement|${!replacement}|" aws-iot-device-client.json
done
mv aws-iot-device-client.json $CONFIG_LOC/

systemctl enable aws-iot-device-client
systemctl start aws-iot-device-client