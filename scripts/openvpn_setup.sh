#!/bin/zsh

LBLUE='\033[1;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# The working directory
wdir="$(pwd)"

# Lets create a proper directory structure first

echo "${GREEN}Creating directory Sturcture...${NC}"
mkdir ${wdir}/output
mkdir ${wdir}/output/ca
mkdir ${wdir}/output/openvpn
mkdir ${wdir}/output/openvpn/server
mkdir ${wdir}/output/openvpn/clients

# We need so set some variables first

echo "${LBLUE}How do you want to name your certification agency?${NC}"
echo "This will be the master CA which is used to sign the clients and sevrers certificates"
read ca_name

echo "${LBLUE}How do you want to name your VPN-Server?${NC}"
read server_name

echo "${LBLUE}What's the server's remote address (URL or IP)?${NC}"
read remote_address
echo "${remote_address}" > ${wdir}/output/openvpn/server/remote_address.txt

echo "${LBLUE}How many client certificate-key-pairs do you want to create?${NC}"
read num_clients

# Get the easyrsa files and extract them
echo "${GREEN} ${NC}"
echo "${GREEN}Downloading EasyRSA...${NC}"
wget https://github.com/OpenVPN/easy-rsa/releases/download/v3.1.7/EasyRSA-3.1.7.tgz

echo "${GREEN}Extracting...${NC}"
tar xvf EasyRSA-3.1.7.tgz
mv EasyRSA-3.1.7.tgz EasyRSA.tgz
mv EasyRSA-3.1.7 EasyRSA

echo "${GREEN}Creating CA and and OpenVPN EasyRSA-Instacne${NC}"
cp -R EasyRSA/ ${wdir}/output/ca/
cp -R EasyRSA/ ${wdir}/output/openvpn/

echo "${GREEN}Cleaning up...${NC}"
rm -r EasyRSA/
rm EasyRSA.tgz

###############################
### Certification Authority ###
###############################

echo "${GREEN}Creating Master CA...${NC}"

cd ${wdir}/output/ca/EasyRSA/
cp vars.example vars

echo "${LBLUE}You will now have to edit the CAs variables. Press Enter to continue.${NC}"
## Wait for the user to react
read
editor vars || $EDITOR vars || nano vars || vi vars || vim vars || nvim vars

## Create the authority
echo "${GREEN}Creating the certification authority...${NC}"
./easyrsa init-pki

# echo "${RED}You can leave the 'Common Name' empty${NC}"
cat <<-EOF | ./easyrsa build-ca nopass
${ca_name}
EOF

##################################
### Server Certificate and Key ###
##################################

echo "${GREEN}Creating Server Certificate and Key...${NC}"

cd ${wdir}/output/openvpn/EasyRSA/

./easyrsa init-pki
cat <<-EOF | ./easyrsa gen-req server nopass
${server_name}
EOF

cp pki/private/server.key ../server/
cp pki/reqs/server.req ${wdir}/output/ca/

## Sign the server.req on the CA
echo "${GREEN}Signing the server certificate with the CA...${NC}"

cd ${wdir}/output/ca/EasyRSA/

./easyrsa import-req ../server.req server
cat <<-EOF | ./easyrsa sign-req server server
yes
EOF

## Copy the signed server certificate and the ca.crt back to the server directoy
cp pki/issued/server.crt ${wdir}/output/openvpn/server/ 
cp pki/ca.crt ${wdir}/output/openvpn/server/

cd ${wdir}/output/openvpn/EasyRSA/

echo "${GREEN}Generating Diffie-Hellman key...${NC}"
./easyrsa gen-dh
cp pki/dh.pem ${wdir}/output/openvpn/server/

echo "${GREEN}Generating HMAC-Signatur...${NC}"
sudo openvpn --genkey secret ta.key
sudo chown ${USER} ta.key
cp ta.key ${wdir}/output/openvpn/server/

cp ${wdir}/conf/server.conf ${wdir}/output/openvpn/server/server.conf

## Create client config directory
mkdir ${wdir}/output/openvpn/server/ccd

####################################
### Client Certificates and Keys ###
####################################

echo "${GREEN}Generating client certificates and keys..."

### Create 'num_clients' client certificates
for i in $(seq 1 ${num_clients})
do
   echo "${GREEN}Client ${i}:${NC}"
   mkdir ${wdir}/output/openvpn/clients/client${i}
   echo "${GREEN}Creating certificate and key...${NC}"
   cd ${wdir}/output/openvpn/EasyRSA/
   cp ta.key ${wdir}/output/openvpn/clients/client${i}
   cat <<-EOF | ./easyrsa gen-req client${i} nopass
client${i}
EOF
   echo "${GREEN}Signing certificate...${NC}"
   cp pki/private/client${i}.key ${wdir}/output/openvpn/clients/client${i}/
   cp pki/reqs/client${i}.req ${wdir}/output/ca/
   cd ${wdir}/output/ca/EasyRSA/
   ./easyrsa import-req ../client${i}.req client${i}
   cat <<-EOF | ./easyrsa sign-req client client${i}
yes
EOF
   cp pki/issued/client${i}.crt ${wdir}/output/openvpn/clients/client${i}/
   cp pki/ca.crt ${wdir}/output/openvpn/clients/client${i}/
   # Place in the specified remote address and set proper client name
   echo "${GREEN}Creating config file...${NC}"
   cat ${wdir}/conf/client.conf | sed "s/my-server-1/${remote_address}/g" | sed "s/c_name/client${i}/g" > ${wdir}/output/openvpn/clients/client${i}/client${i}.conf
   cd ${wdir}/output/openvpn/clients/client${i}
   # Remove txqueuelen parameter for windows configuration
   cat client${i}.conf | sed 's/txqueuelen 1000//g' > client${i}.ovpn
   # Zip compress the client's directory
   echo "${GREEN}Creating .zip archive...${NC}"
   cd ../
   zip client${i}.zip -r client${i}
   echo "${GREEN}Cleaning up...${NC}"
   rm -r client${i}
   # Push route settings to server.conf and ccd
   ip=$(expr 100 + ${i})
   echo "ifconfig-push 10.8.0.${ip} 255.255.255.0" >${wdir}/output/openvpn/server/ccd/client${i}
   echo "route 10.8.0.${ip} 255.255.255.0" >> ${wdir}/output/openvpn/server/server.conf
done

echo "${GREEN}DONE!${NC}"
