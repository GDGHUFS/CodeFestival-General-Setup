#!/bin/bash
sudo tee -a /etc/yum.repos.d/vscodium.repo << 'EOF'
[gitlab.com_paulcarroty_vscodium_repo]
name=gitlab.com_paulcarroty_vscodium_repo
baseurl=https://paulcarroty.gitlab.io/vscodium-deb-rpm-repo/rpms/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg
metadata_expire=1h
EOF

echo "VSCodium 설치를 시작합니다."
sudo dnf install codium -y
echo "이제 확장 프로그램을 설치하겠습니다."
codium --install-extension GitHub.github-vscode-theme
codium --install-extension redhat.java
codium --install-extension MS-CEINTL.vscode-language-pack-ko
codium --install-extension ms-python.python
echo "VSCodium 설치를 완료했습니다."
