#!/bin/bash
set -e


ANSIBLE_USER="ansible"
SSH_PUBKEY=""


echo "=== 🔧 Aktualizacja systemu ==="
sudo apt update -y && sudo apt upgrade -y


echo "=== 📦 Instalacja podstawowych pakietów ==="
sudo apt install -y ca-certificates curl gnupg lsb-release ufw software-properties-common python3 python3-pip


echo "=== 🐳 Instalacja Dockera ==="
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update -y
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

sudo systemctl enable docker
sudo systemctl start docker


echo "=== 🐍 Instalacja Docker SDK dla Pythona ==="
sudo apt install -y python3-docker python3-venv python3-setuptools


echo "=== ⚙️ Instalacja Ansible ==="
sudo add-apt-repository --yes --update ppa:ansible/ansible
sudo apt install -y ansible


echo "=== 👤 Tworzenie użytkownika ansible ==="
if id "$ANSIBLE_USER" &>/dev/null; then
  echo "Użytkownik $ANSIBLE_USER już istnieje, pomijam..."
else
  sudo adduser --disabled-password --gecos "" "$ANSIBLE_USER"
  sudo usermod -aG sudo "$ANSIBLE_USER"
  sudo mkdir -p /home/$ANSIBLE_USER/.ssh
  echo "$SSH_PUBKEY" | sudo tee /home/$ANSIBLE_USER/.ssh/authorized_keys > /dev/null
  sudo chmod 700 /home/$ANSIBLE_USER/.ssh
  sudo chmod 600 /home/$ANSIBLE_USER/.ssh/authorized_keys
  sudo chown -R $ANSIBLE_USER:$ANSIBLE_USER /home/$ANSIBLE_USER/.ssh
  echo "$ANSIBLE_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$ANSIBLE_USER > /dev/null
  sudo chmod 0440 /etc/sudoers.d/$ANSIBLE_USER
fi


echo "=== 🔥 Konfiguracja UFW ==="
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 11434/tcp
sudo ufw --force enable


echo "=== 👥 Dodawanie użytkownika ansible do grupy docker ==="
sudo usermod -aG docker "$ANSIBLE_USER"


echo "=== 📦 Instalacja kolekcji community.docker ==="
sudo -u "$ANSIBLE_USER" ansible-galaxy collection install community.docker || true


echo ""
echo "✅ Instalacja zakończona!"
echo "Docker: $(docker --version)"
echo "Ansible: $(ansible --version | head -n 1)"
echo ""
echo "🔑 Użytkownik: $ANSIBLE_USER"
echo "UFW porty: 22, 80, 443, 11434"
echo ""
echo "Teraz możesz zalogować się z Maca:"
echo "ssh $ANSIBLE_USER@<IP_SERWERA> -i ~/.ssh/id_ed25519"
