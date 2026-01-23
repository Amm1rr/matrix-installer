# راهنمای قدم به قدم نصب Matrix Synapse
## روی سرور VPS با IP 45.148.31.170

این راهنما برای نصب Matrix Synapse روی سرور خودتان (VPS) با استفاده از IP `45.148.31.170` تهیه شده است.

---

## پیش‌نیازها

- Docker نصب شده
- Python 3 نصب شده
- دسترسی sudo با کاربر `admin`

---

## مرحله ۱: نصب Ansible

روی سرور (که با SSH به آن وصل شده‌اید) Ansible را نصب کنید:

```bash
sudo apt update
sudo apt install ansible git -y
```

**Ansible چیست؟** ابزاری برای خودکارسازی نصب و تنظیم نرم‌افزار. با Ansible نیازی به اجرای ده‌ها دستور به صورت دستی نیست - همه چیز با یک فایل تنظیمات انجام می‌شود.

---

## مرحله ۲: کلون کردن Playbook

```bash
cd ~
git clone https://github.com/spantaleev/matrix-docker-ansible-deploy.git
cd matrix-docker-ansible-deploy

# نصب پیش‌نیازهای Ansible
ansible-galaxy install -r requirements.yml -p roles/galaxy/ --force
```

---

## مرحله ۳: ساخت Certificate Authority و SSL

چون دامنه ندارید و فقط IP دارید، باید self-signed certificate بسازید.

### ساخت CA و Certificate

```bash
# ساخت فولدر
mkdir -p ~/matrix-ca
cd ~/matrix-ca

# 1. ساخت Root CA private key
openssl genrsa -out rootCA.key 4096

# 2. ساخت Root CA certificate (10 سال اعتبار)
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 \
  -subj "/C=IR/ST=State/L=City/O=MatrixCA/OU=IT/CN=Matrix Root CA" \
  -out rootCA.crt

# 3. ساخت Server private key
openssl genrsa -out server-45.148.31.170.key 4096

# 4. ساخت CSR
openssl req -new -key server-45.148.31.170.key -out server-45.148.31.170.csr \
  -subj "/C=IR/ST=State/L=City/O=Matrix/OU=Server/CN=45.148.31.170"

# 5. ساخت فایل config برای Subject Alternative Names (SAN)
cat > server-45.148.31.170.cnf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = matrix.local
IP.1 = 45.148.31.170
EOF

# 6. امضای certificate با Root CA
openssl x509 -req -in server-45.148.31.170.csr -CA rootCA.crt -CAkey rootCA.key \
  -CAcreateserial -out server-45.148.31.170.crt -days 365 -sha256 \
  -extfile server-45.148.31.170.cnf

# 7. ساخت full-chain certificate (server cert + Root CA)
cat server-45.148.31.170.crt rootCA.crt > cert-full-chain.pem
```

---

## مرحله ۴: تنظیم Inventory

فایل `inventory/hosts` را ویرایش کنید:

```bash
nano ~/matrix-docker-ansible-deploy/inventory/hosts
```

محتوای زیر را در آن قرار دهید:

```ini
[matrix_servers]
45.148.31.170 ansible_connection=local
```

ذخیره کنید: `Ctrl+O`، `Enter`، سپس `Ctrl+X`

---

## مرحله ۵: تنظیم متغیرهای Host

### ساخت فولدر و کپی فایل نمونه

```bash
mkdir -p ~/matrix-docker-ansible-deploy/inventory/host_vars/45.148.31.170
cp ~/matrix-docker-ansible-deploy/examples/vars.yml \
   ~/matrix-docker-ansible-deploy/inventory/host_vars/45.148.31.170/vars.yml
nano ~/matrix-docker-ansible-deploy/inventory/host_vars/45.148.31.170/vars.yml
```

### ویرایش vars.yml

فایل را باز کنید و مقادیر زیر را تنظیم کنید:

```yaml
# ===========================================
# تنظیمات اصلی
# ===========================================

# Domain - از IP استفاده می‌کنیم چون دامنه نداریم
matrix_domain: "45.148.31.170"
matrix_server_fqn_matrix: "45.148.31.170"

# Homeserver implementation
matrix_homeserver_implementation: synapse

# Secret key - یک کلید قوی جایگزین کنید
matrix_homeserver_generic_secret_key: 'YOUR_STRONG_SECRET_KEY_HERE_CHANGE_THIS'

# Reverse proxy type
matrix_playbook_reverse_proxy_type: playbook-managed-traefik

# IPv6 support - اگر سرور IPv6 ندارد false کنید
devture_systemd_docker_base_ipv6_enabled: false

# Postgres password - یک پسورد قوی جایگزین کنید
postgres_connection_password: 'YOUR_POSTGRES_PASSWORD_HERE_CHANGE_THIS'

# ===========================================
# Element Web
# ===========================================

matrix_client_element_enabled: true
matrix_server_fqn_element: "45.148.31.170"

# مهم: چون Element و Synapse روی یک IP هستند، باید false باشد
matrix_synapse_container_labels_public_client_root_enabled: false

# ===========================================
# تنظیمات Federation (برای IP-based setup)
# ===========================================

matrix_synapse_federation_enabled: true
matrix_synapse_federation_ip_range_blacklist: []

# ===========================================
# تنظیمات Synapse Extension
# ===========================================

matrix_synapse_configuration_extension_yaml: |
  federation_verify_certificates: false
  suppress_key_server_warning: true
  report_stats: false
  key_server:
    accept_keys_insecurely: true
  trusted_key_servers: []

# ===========================================
# تنظیمات SSL/TLS برای Self-signed Certificates
# ===========================================

# غیرفعال کردن ACME / Let's Encrypt
traefik_config_certificatesResolvers_acme_enabled: false

# فعال کردن SSL directory
traefik_ssl_dir_enabled: true

# تنظیم certificateها برای Traefik
traefik_provider_configuration_extension_yaml: |
  tls:
    certificates:
      - certFile: /ssl/cert.pem
        keyFile: /ssl/privkey.pem
    stores:
      default:
        defaultCertificate:
          certFile: /ssl/cert.pem
          keyFile: /ssl/privkey.pem

# ===========================================
# کپی کردن فایل‌های SSL
# ===========================================

aux_file_definitions:
  # Private key
  - dest: "{{ traefik_ssl_dir_path }}/privkey.pem"
    src: /home/admin/matrix-ca/server-45.148.31.170.key
    mode: "0600"

  # Full chain certificate (server cert + root CA)
  - dest: "{{ traefik_ssl_dir_path }}/cert.pem"
    src: /home/admin/matrix-ca/cert-full-chain.pem
    mode: "0644"
```

**نکته مهم:** حتماً `YOUR_STRONG_SECRET_KEY_HERE_CHANGE_THIS` و `YOUR_POSTGRES_PASSWORD_HERE_CHANGE_THIS` را با پسوردهای قوی جایگزین کنید.

---

## مرحله ۶: ساخت دستی فولدرها

به دلیل یک باگ در playbook، باید فولدرها را دستی بسازید:

```bash
sudo mkdir -p /matrix/traefik/ssl
sudo mkdir -p /matrix/traefik/config
sudo chown -R matrix:matrix /matrix/
```

---

## مرحله ۷: بررسی تنظیمات (Pre-flight Check)

```bash
cd ~/matrix-docker-ansible-deploy
LC_ALL=C.UTF-8 LANG=C.UTF-8 ansible-playbook -i inventory/hosts setup.yml --tags=check-all
```

اگر خطایی دیدید، قبل از ادامه آن را برطرف کنید.

---

## مرحله ۸: نصب

```bash
LC_ALL=C.UTF-8 LANG=C.UTF-8 ansible-playbook -i inventory/hosts setup.yml --tags=install-all,ensure-matrix-users-created,start
```

این فرآیند ممکن است ۱۰-۲۰ دقیقه طول بکشد. صبور باشید.

---

## مرحله ۹: ساخت کاربر ادمین

```bash
LC_ALL=C.UTF-8 LANG=C.UTF-8 ansible-playbook -i inventory/hosts setup.yml \
  --extra-vars='username=YOUR_USERNAME password=YOUR_PASSWORD admin=yes' \
  --tags=register-user
```

جای `YOUR_USERNAME` و `YOUR_PASSWORD` را با نام کاربری و پسورد دلخواه جایگزین کنید.

---

## مرحله ۱۰: بررسی نصب

### بررسی وضعیت سرویس‌ها

```bash
sudo systemctl status matrix-traefik
sudo systemctl status matrix-synapse
sudo docker ps
```

### تست Matrix API

```bash
curl -k https://45.148.31.170/_matrix/client/versions
```

### تست Element Web

در مرورگر به آدرس زیر بروید:
```
https://45.148.31.170/
```

**نکته:** چون از self-signed certificate استفاده می‌کنید، مرورگر هشدار امنیتی نشان می‌دهد. باید روی "Advanced" و سپس "Proceed to 45.148.31.170" کلیک کنید.

---

## مرحله ۱۱: نصب Root CA در سیستم (برای Federation)

برای اینکه Federation بین سرورهای Matrix با گواهی‌نامه self-signed کار کند، باید Root CA را در سیستم عامل نصب کنید:

```bash
# ساخت فولدر
sudo mkdir -p /usr/local/share/ca-certificates/matrix

# کپی Root CA
sudo cp ~/matrix-ca/rootCA.crt /usr/local/share/ca-certificates/matrix/

# به‌روزرسانی certificate store
sudo update-ca-certificates
```

برای تأیید نصب:
```bash
# باید rootCA.crt را در لیست ببینید
ls -la /usr/local/share/ca-certificates/matrix/

# بررسی certificate store
sudo trust list | grep Matrix
```

---

## مرحله ۱۲: تست Federation (اختیاری)

اگر سرور دوم Matrix دارید، می‌توانید Federation را تست کنید:

### از سرور اول به سرور دوم:

```bash
# تست دسترسی federation
curl -k https://[SECOND-SERVER-IP]:8448/_matrix/federation/v1/version
```

### ساخت room directory (لوکال):

در Element Web روی سرور اول، یک room جدید بسازید و سپس از سرور دوم با همان کاربر وارد شوید و room را ببینید.

---

## رفع مشکلات رایج

### سرویس‌ها اجرا نمی‌شوند

```bash
# ریستارت سرویس‌ها
sudo systemctl restart matrix-traefik
sudo systemctl restart matrix-synapse

# مشاهده لاگ‌ها
sudo journalctl -u matrix-traefik -f
sudo journalctl -u matrix-synapse -f

# لاگ کانتینرها
sudo docker logs matrix-traefik --tail 50
sudo docker logs matrix-synapse --tail 50
```

### خطای ERR_TOO_MANY_REDIRECTS

مطمئن شوید در `vars.yml` این تنظیم وجود دارد:
```yaml
matrix_synapse_container_labels_public_client_root_enabled: false
```

### خطای Synapse: "accept_keys_insecurely"

اگر Synapse استارت نمی‌شود و این خطا را می‌دهید:

```
Error in configuration:
  Your server is configured to accept key server responses without signature
  validation or TLS certificate validation. If you are *sure* you want to do
  this, set 'accept_keys_insecurely' on the keyserver configuration.
```

**راه حل:** مطمئن شوید در `vars.yml` تنظیمات زیر وجود دارد:
```yaml
matrix_synapse_configuration_extension_yaml: |
  key_server:
    accept_keys_insecurely: true
  trusted_key_servers: []
```

دلیل: وقتی از self-signed certificate استفاده می‌کنید، باید `trusted_key_servers` را خالی کنید تا Synapse سعی نکند به matrix.org وصل شود.

### مشکل SSL

```bash
# بررسی فایل‌های SSL
sudo ls -la /matrix/traefik/ssl/

# بررسی provider.yml
sudo cat /matrix/traefik/config/provider.yml
```

باید شامل TLS configuration باشد:
```yaml
tls:
  certificates:
    - certFile: /ssl/cert.pem
      keyFile: /ssl/privkey.pem
  stores:
    default:
      defaultCertificate:
        certFile: /ssl/cert.pem
        keyFile: /ssl/privkey.pem
```

### خطای ERR_SSL_KEY_USAGE_INCOMPATIBLE در مرورگر

اگر مرورگر این خطا را می‌دهد، یعنی certificate با تنظیمات اشتباه ساخته شده است.

**راه حل:** certificate را دوباره با تنظیمات درست بسازید:
```bash
cd ~/matrix-ca

# فایل config را اصلاح کنید
cat > server-45.148.31.170.cnf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = matrix.local
IP.1 = 45.148.31.170
EOF

# دوباره certificate را بسازید
openssl x509 -req -in server-45.148.31.170.csr -CA rootCA.crt -CAkey rootCA.key \
  -CAcreateserial -out server-45.148.31.170.crt -days 365 -sha256 \
  -extfile server-45.148.31.170.cnf

# full-chain را دوباره بسازید
cat server-45.148.31.170.crt rootCA.crt > cert-full-chain.pem

# کپی در محل SSL
sudo cp cert-full-chain.pem /matrix/traefik/ssl/cert.pem
sudo cp server-45.148.31.170.key /matrix/traefik/ssl/privkey.pem

# ریستارت traefik
sudo systemctl restart matrix-traefik
```

دلیل: مرورگرهای مدرن به `digitalSignature` و `extendedKeyUsage = serverAuth` نیاز دارند.
        certFile: /ssl/cert.pem
        keyFile: /ssl/privkey.pem
```

---

## فایل‌های مهم

| فایل | توضیحات |
|------|---------|
| `~/matrix-docker-ansible-deploy/inventory/hosts` | لیست سرورها (localhost) |
| `~/matrix-docker-ansible-deploy/inventory/host_vars/45.148.31.170/vars.yml` | تنظیمات اصلی |
| `/matrix/traefik/config/provider.yml` | Traefik configuration |
| `/matrix/traefik/ssl/` | فایل‌های SSL |
| `~/matrix-ca/rootCA.crt` | Root CA certificate |

---

## دستورات مفید

### ریستارت سرویس‌ها

```bash
sudo systemctl restart matrix-traefik
sudo systemctl restart matrix-synapse
```

### مشاهده لاگ‌ها

```bash
sudo journalctl -u matrix-traefik -f
sudo journalctl -u matrix-synapse -f
```

### کانتینرهای در حال اجرا

```bash
sudo docker ps
```

---

## منابع

- [Matrix Docker Ansible Deploy](https://github.com/spantaleev/matrix-docker-ansible-deploy)
- [Ansible Documentation](https://docs.ansible.com/)
