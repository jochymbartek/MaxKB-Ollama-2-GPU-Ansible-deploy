# MaxKB + Ollama (2×GPU) — Ansible deploy

**TL;DR:** This playbook brings up an **Ollama cluster (2 containers + Nginx LB)** on one VM and **MaxKB + Nginx** on a second VM. It adds HTTPS and protects `/admin` and `/doc_chat` with HTTP Basic Auth.

---

## Architecture

* **VM #1 – `ollama`**: `ollama0` (GPU 0) + `ollama1` (GPU 1) behind `nginx-ollama-lb` (port **7869**).
* **VM #2 – `maxkb`**: MaxKB (port 8080) served by Nginx (ports **80/443**), Basic Auth on `/admin` and `/doc_chat`.

## Requirements

* 2× Ubuntu 22.04+ VMs (NVIDIA drivers on the Ollama VM; CUDA runtime for Docker).
* SSH access; your workstation has Ansible and an SSH key (e.g., `~/.ssh/id_ed25519`).

---

## 1) Bootstrap both VMs

**Edit the script first** and paste your public key into the variable:

```bash
# in setup-linux-vm.sh
SSH_PUBKEY="ssh-ed25519 AAAA...your-public-key... user@host"
```

Run on **each** VM (script from your repo):

```bash
curl -fsSL -o setup-linux-vm.sh \
  https://raw.githubusercontent.com/jochymbartek/MaxKB-Ollama-2-GPU-Ansible-deploy/main/setup-linux-vm.sh
chmod +x setup-linux-vm.sh
sudo ./setup-linux-vm.sh
```

The script:

* updates the system; installs **Docker (+ compose plugin), Python**, and **Ansible**,
* creates user **`ansible`** with passwordless sudo,
* installs your public key to `/home/ansible/.ssh/authorized_keys`,
* opens UFW ports **22, 80, 443, 11434** and enables UFW,
* adds `ansible` to the `docker` group.

---

## 2) Inventory

`inventory.ini`

```ini
[ollama]
ollama ansible_host=<IP_VM_1> ansible_port=22 ansible_user=ansible ansible_ssh_private_key_file=~/.ssh/id_ed25519

[maxkb]
maxkb  ansible_host=<IP_VM_2> ansible_port=22 ansible_user=ansible ansible_ssh_private_key_file=~/.ssh/id_ed25519
```

---

## 3) Host variables

`host_vars/maxkb.yml`

```yaml
maxkb_domain: example.com         # public domain pointing to VM #2
nginx_auth_user: admin            # Basic Auth username
nginx_auth_password_hash: ""      # bcrypt/crypt hash (see below)
```

**Generate password hash** (choose one):

```bash
# bcrypt (preferred)
htpasswd -nbB admin 'Str0ngP@ss' | cut -d: -f2

# or SHA-512 crypt
openssl passwd -6 'Str0ngP@ss'
```

Paste the result into `nginx_auth_password_hash`.

---

## 4) SSL certificates (named exactly like `maxkb_domain`)

Place certs in `files/ssl/` and **name them with the exact value of `maxkb_domain`**:

```
files/ssl/{{ maxkb_domain }}.pem   # full chain cert
files/ssl/{{ maxkb_domain }}.key   # private key
```

**Examples**

* If `maxkb_domain: example.com` → `files/ssl/example.com.pem` and `files/ssl/example.com.key`.
* If `maxkb_domain: chat.mycorp.io` → `files/ssl/chat.mycorp.io.pem` and `files/ssl/chat.mycorp.io.key`.

Nginx config references them as:

```
ssl_certificate     /etc/ssl/certs/{{ maxkb_domain }}.pem;
ssl_certificate_key /etc/ssl/private/{{ maxkb_domain }}.key;
```

---

## 5) What gets deployed

### On VM #1 (`ollama`)

* `docker-compose` with:

  * `ollama0` (GPU 0) and `ollama1` (GPU 1) – `ollama/ollama:0.11.10`,
  * `nginx-ollama-lb` on **7869** using `least_conn` to both backends,
  * shared models volume `/opt/ollama/models:/models`,
  * healthchecks on `/api/tags`.

### On VM #2 (`maxkb`)

* MaxKB behind Nginx on **443**, with:

  * 80 → 443 redirect,
  * TLS from `files/ssl/`,
  * **Basic Auth** on `^/admin/` and `^/doc_chat/`,
  * `/chat/api/` proxied with `no-store`.

---

## 6) Run

Test connectivity:

```bash
ansible all -i inventory.ini -m ping
```

Deploy:

```bash
ansible-playbook -i inventory.ini main.yml
```

---

## 7) Verify

* **Ollama LB**: `curl -s http://<IP_VM_1>:7869/api/tags`
* **MaxKB UI**: `https://<maxkb_domain>/`
* **Admin (Basic Auth)**: `https://<maxkb_domain>/admin/`
* **Doc chat (Basic Auth)**: `https://<maxkb_domain>/doc_chat/`
* **Health**: `https://<maxkb_domain>/healthz`

---

## 8) Variables quick reference

| Variable                         | Where                 | Meaning                                   |
| -------------------------------- | --------------------- | ----------------------------------------- |
| `ansible_host`                   | `inventory.ini`       | VM IP                                     |
| `ansible_port`                   | `inventory.ini`       | SSH port (default 22)                     |
| `ansible_user`                   | `inventory.ini`       | `ansible`                                 |
| `ansible_ssh_private_key_file`   | `inventory.ini`       | path to your private key                  |
| `SSH_PUBKEY`                     | `setup-linux-vm.sh`   | **paste your public key string here**     |
| `maxkb_domain`                   | `host_vars/maxkb.yml` | public FQDN for MaxKB                     |
| `nginx_auth_user`                | `host_vars/maxkb.yml` | Basic Auth user                           |
| `nginx_auth_password_hash`       | `host_vars/maxkb.yml` | password hash                             |
| `files/ssl/{{ maxkb_domain }}.*` | `files/ssl/`          | TLS cert & key named after `maxkb_domain` |

---

## 9) Troubleshooting

* **401 on `/admin` or `/doc_chat`** → check `nginx_auth_user` and the hash value.
* **502 from LB** → `docker logs` for `ollama0/ollama1`; ensure GPU visibility and healthchecks OK.
* **TLS error** → ensure filenames **exactly** match `maxkb_domain` and the chain is complete in `.pem`.
