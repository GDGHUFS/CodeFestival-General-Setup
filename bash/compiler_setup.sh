#!/bin/bash
echo "Java 설치를 시작합니다."
cd /tmp
wget https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.12%2B7/OpenJDK17U-jdk_x64_linux_hotspot_17.0.12_7.tar.gz
tar xf OpenJDK17U-jdk_x64_linux_hotspot_17.0.12_7.tar.gz
mv jdk-17.0.12+7 /opt/cf-env/java17
ln -s /opt/cf-env/java17/bin/javac /opt/cf-env/bin/cf-javac
ln -s /opt/cf-env/java17/bin/java  /opt/cf-env/bin/cf-java
cf-javac --version
cf-java --version
echo "Java 설치를 완료했습니다."

echo "Python 설치를 시작합니다."
cd /tmp
wget https://www.python.org/ftp/python/3.9.17/Python-3.9.17.tgz
tar xf Python-3.9.17.tgz
cd Python-3.9.17
./configure --prefix=/opt/cf-env/python39 --enable-optimizations
make -j$(nproc)
make install
ln -s /opt/cf-env/python39/bin/python3 /opt/cf-env/bin/cf-python
cf-python --version
echo "Python 설치를 완료했습니다."

echo "C/C++ 설치를 시작합니다."
# 미안
echo "alias cf-gcc=\"gcc\"" >> ~/.bashrc
echo "alias cf-g++=\"g++\"" >> ~/.bashrc
echo "C/C++ 설치를 완료했습니다."
