# راهنمای نصب Matrix Synapse با Self-signed SSL

این راهنما برای نصب Matrix Synapse با استفاده از playbook `matrix-docker-ansible-deploy` با استفاده از **self-signed certificates** و **بدون دامنه** (فقط IP) تهیه شده است. این تنظیمات برای federation بین چند سرور در شبکه خصوصی یا محیط تست مناسب است.

## پیش‌نیازها

### روی سیستم لوکال (Manjaro/Linux)

```bash
# نصب Ansible
sudo pacman -S ansible

# کلون کردن playbook
git clone https://github.com/spantaleev/matrix-docker-ansible-deploy.git
cd matrix-docker-ansible-deploy

# نصب Ansible roles
just update
# یا
just roles
# یا
ansible-galaxy install -r requirements.yml -p roles/galaxy/ --force
```

**کار با Nix (پیش‌فرض):**

این playbook از Nix استفاده می‌کند. وقتی وارد دایرکتوری playbook می‌شوید، Nix به صورت خودکار از طریق فایل `.envrc` لود می‌شود:

```bash
cd /home/amir/Works/Startup/Matrix/matrix-second/matrix-docker-ansible-deploy

# Nix به صورت خودکار فعال می‌شود (direnv)
# اگر direnv نصب نیست، به صورت دستی فعال کنید:
# برای بار اول بهتره بعد از وارد شدن به این مسیر، دستور
# زیر را یک بار اجرا شود:
direnv allow
```

اگر Nix روی سیستم شما نصب نیست، می‌توانید Ansible را به صورت معمولی از package manager سیستم خود نصب کنید.

---

### روی سیستم لوکال (Ubuntu/Debian)

```bash
# نصب Ansible
sudo apt update
sudo apt install ansible -y

# کلون کردن playbook
git clone https://github.com/spantaleev/matrix-docker-ansible-deploy.git
cd matrix-docker-ansible-deploy

# نصب Ansible roles
just update
# یا
just roles
# یا
ansible-galaxy install -r requirements.yml -p roles/galaxy/ --force
```

### روی سرور (Ubuntu/Debian)

- Docker باید نصب باشد
- Python 3 باید نصب باشد
- دسترسی SSH با کاربری که دسترسی `sudo` داشته باشد

**Ansible چطور کار می‌کند:**

Ansible یک ابزار مدیریت پیکربندی است که از طریق SSH به سرورها متصل می‌شود و دستورات را اجرا می‌کند. برخلاف Puppet یا Chef، نیازی به نصب agent روی سرورها ندارد - فقط Python و SSH کافی است.

---

## مرحله ۱: ایجاد Certificate Authority (CA) و Certificates

چون Let's Encrypt در دسترس نیست، باید Self-signed certificate بسازید.

### ساخت CA و Certificate

```bash
# در فولدر مخصوص certificates
mkdir -p ~/Works/Startup/Matrix/matrix-second/matrix-ca
cd ~/Works/Startup/Matrix/matrix-second/matrix-ca

# 1. ساخت Root CA private key
openssl genrsa -out rootCA.key 4096

# 2. ساخت Root CA certificate (10 سال اعتبار)
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 3650 \
  -subj "/C=IR/ST=State/L=City/O=MatrixCA/OU=IT/CN=Matrix Root CA" \
  -out rootCA.crt

# 3. ساخت Server private key
openssl genrsa -out server-217.78.237.15.key 4096

# 4. ساخت CSR
openssl req -new -key server-217.78.237.15.key -out server-217.78.237.15.csr \
  -subj "/C=IR/ST=State/L=City/O=Matrix/OU=Server/CN=217.78.237.15"

# 5. ساخت فایل config برای Subject Alternative Names (SAN)
cat > server-217.78.237.15.cnf <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = matrix.local
IP.1 = 217.78.237.15
EOF

# 6. امضای certificate با Root CA
openssl x509 -req -in server-217.78.237.15.csr -CA rootCA.crt -CAkey rootCA.key \
  -CAcreateserial -out server-217.78.237.15.crt -days 365 -sha256 \
  -extfile server-217.78.237.15.cnf

# 7. ساخت full-chain certificate (server cert + Root CA)
cat server-217.78.237.15.crt rootCA.crt > cert-full-chain.pem
```

**⚠️ نکته مهم:** فایل `rootCA.crt` را روی تمام سرورهایی که می‌خواهید با هم federation کنند نصب کنید.

---

## مرحله ۲: تنظیم Inventory

### ویرایش `inventory/hosts`

```bash
nano inventory/hosts
```

```ini
[matrix_servers]
217.78.237.15 ansible_host=217.78.237.15 ansible_ssh_user=admin ansible_become=true ansible_become_user=root
```

---

## مرحله ۳: تنظیم متغیرهای Host

### ساخت فایل vars.yml

**💡 نکته مفید:** می‌توانید از فایل نمونه استفاده کنید:
```bash
mkdir -p inventory/host_vars/217.78.237.15
cp examples/vars.yml inventory/host_vars/217.78.237.15/vars.yml
nano inventory/host_vars/217.78.237.15/vars.yml
```

**💡 نکته مفید:** برای دیدن تمام متغیرهای قابل تنظیم، می‌توانید فایل‌های defaults/main.yml را در roles بررسی کنید:
```bash
find roles -name "main.yml" -path "*/defaults/*" | head -5
```

```yaml
# ===========================================
# تنظیمات اصلی
# ===========================================

# Domain و Server FQN - چون دامین نداریم از IP استفاده می‌کنیم
matrix_domain: "217.78.237.15"
matrix_server_fqn_matrix: "217.78.237.15"

# Homeserver implementation
matrix_homeserver_implementation: synapse

# Secret key - یک کلید قوی تولید کنید
matrix_homeserver_generic_secret_key: 'YOUR_STRONG_SECRET_KEY_HERE'

# Reverse proxy type
matrix_playbook_reverse_proxy_type: playbook-managed-traefik

# IPv6 support - اگر سرور IPv6 ندارد روی false تنظیم کنید. اگه بعدا احتمال پشتیبانی از IPv6 اضافه شود، بهتر است true باشه
devture_systemd_docker_base_ipv6_enabled: true

# Postgres password
postgres_connection_password: 'YOUR_POSTGRES_PASSWORD'

# ===========================================
# Element Web
# ===========================================

matrix_client_element_enabled: true
matrix_server_fqn_element: "217.78.237.15"

# ⚠️ نکته مهم در مورد redirect:
# - با IP: حتماً باید false باشد چون Synapse و Element روی یک Host هستند
# - با Domain: بستگی به تنظیمات دارد. اگر Element روی subdomain جداگانه (مثل element.example.com)
#   و Synapse روی domain اصلی (matrix.example.com) هستند، می‌توانید true باشد.
#   در غیر این صورت اگر هر دو روی یک domain باشند، باید false باشد.
matrix_synapse_container_labels_public_client_root_enabled: false

# ===========================================
# تنظیمات SSL/TLS برای Self-signed Certificates
# ===========================================

# غیرفعال کردن ACME / Let's Encrypt
traefik_config_certificatesResolvers_acme_enabled: false

# فعال کردن SSL directory (چون ACME را غیرفعال کردیم)
traefik_ssl_dir_enabled: true

# اضافه کردن TLS self-signed به provider.yml
# این تنظیم certificateها را به Traefik معرفی می‌کند
# مسیر ها به همین شکل باید بمانند، این فایل ها در داکر traefik به همین آدرس کپی می شوند.
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
# کپی کردن فایل‌های SSL به سرور
# ===========================================

**⚠️ نکته مهم درباره امنیت:**
به جای استفاده از `src:` که مسیر فایل روی سیستم لوکال رو ذخیره می‌کنه، می‌تونید از `content:` استفاده کنید تا محتوای certificate مستقیماً در vars.yml ذخیره بشه. این روش امن‌تر است چون فایل‌های sensitive روی سیستم لوکال ذخیره نمی‌شوند.

**روش اول: استفاده از `src:` (ساده‌تر اما فایل روی لوکال ذخیره می‌شود)**
```yaml
aux_file_definitions:
  # Private key
  - dest: "{{ traefik_ssl_dir_path }}/privkey.pem"
    src: /home/amir/Works/Startup/Matrix/matrix-second/matrix-ca/server-217.78.237.15.key
    mode: "0600"

  # Full chain certificate (server cert + root CA)
  - dest: "{{ traefik_ssl_dir_path }}/cert.pem"
    src: /home/amir/Works/Startup/Matrix/matrix-second/matrix-ca/cert-full-chain.pem
    mode: "0644"
```

**روش دوم: استفاده از `content:` (امن‌تر - فایل روی لوکال ذخیره نمی‌شود)**
```yaml
aux_file_definitions:
  # Private key
  - dest: "{{ traefik_ssl_dir_path }}/privkey.pem"
    content: |
      -----BEGIN PRIVATE KEY-----
      YOUR_PRIVATE_KEY_CONTENT_HERE
      -----END PRIVATE KEY-----
    mode: "0600"

  # Full chain certificate
  - dest: "{{ traefik_ssl_dir_path }}/cert.pem"
    content: |
      -----BEGIN CERTIFICATE-----
      YOUR_CERTIFICATE_CONTENT_HERE
      -----END CERTIFICATE-----
      -----BEGIN CERTIFICATE-----
      YOUR_ROOT_CA_CONTENT_HERE
      -----END CERTIFICATE-----
    mode: "0644"
```

**⚠️ نکته مهم درباره مسیر `/ssl/…`:**
مسیر `/ssl/cert.pem` و `/ssl/privkey.pem` در این تنظیمات، **مسیر داخل کانتینر Traefik** است، نه مسیر روی host سرور.
- روی host: `/matrix/traefik/ssl/cert.pem`
- در کانتینر: `/ssl/cert.pem`

Playbook به صورت خودکار `/matrix/traefik/ssl/` رو به `/ssl/` در کانتینر mount می‌کند.

---

## مرحله ۴: بررسی تنظیمات (Pre-flight Check)

قبل از نصب، از صحت تنظیمات اطمینان حاصل کنید:

```bash
# بررسی تنظیمات - این دستور خطای locale را هم برطرف می‌کند
LC_ALL=C.UTF-8 LANG=C.UTF-8 ansible-playbook -i inventory/hosts setup.yml --tags=check-all
```

اگر خطایی دریافت کردید، قبل از ادامه آن را برطرف کنید.

---

## ⚠️ Trick: ساخت دستی فولدرها

به دلیل یک باگ در playbook، فولدرهای Traefik به صورت خودکار ساخته نمی‌شوند. قبل از اجرای نصب، باید این فولدرها را روی سرور بسازید:

```bash
# اتصال SSH به سرور
ssh admin@217.78.237.15

# ساخت فولدرها
sudo mkdir -p /matrix/traefik/ssl
sudo mkdir -p /matrix/traefik/config

# تنظیم مالکیت
sudo chown -R matrix:matrix /matrix/

# خروج از SSH
exit
```

---

## مرحله ۵: نصب

```bash
# اجرای playbook
LC_ALL=C.UTF-8 LANG=C.UTF-8 ansible-playbook -i inventory/hosts setup.yml --tags=install-all,ensure-matrix-users-created,start
```

اگر بدون SSH key هستید، ممکنه نیاز به `--ask-pass` و `-K` (برای sudo password) باشد.

---

## مرحله ۶: ساخت کاربر ادمین

```bash
LC_ALL=C.UTF-8 LANG=C.UTF-8 ansible-playbook -i inventory/hosts setup.yml \
  --extra-vars='username=YOUR_USERNAME password=YOUR_PASSWORD admin=yes' \
  --tags=register-user
```

---

## نکات مهم و رفع مشکلات

### 1. نصب Root CA روی سیستم‌ها برای Federation

برای federation بین سرورها، باید Root CA را روی تمام سرورها نصب کنید:

```bash
# On VPS Server
sudo cp rootCA.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates
```

### 2. اعتماد مرورگر به Self-signed Cert برای کلاینت

برای استفاده از Element Web در مرورگر:
- Chrome/Edge: به `chrome://settings/certificates` بروید، تب "Authorities" را انتخاب کنید و `rootCA.crt` را import کنید.
- Firefox: به `Settings > Privacy & Security > Certificates` بروید و `rootCA.crt` را import کنید.

### 3. خطای ERR_TOO_MANY_REDIRECTS

اگر با این خطا مواجه شدید، مطمئن شوید که:
```yaml
matrix_synapse_container_labels_public_client_root_enabled: false
```

این متغیر در vars.yml تنظیم شده باشد. چون Element و Synapse روی یک Host هستند، نباید Synapse روی root path redirect انجام دهد.

### 4. صحت‌سنجی نصب

بعد از اتمام نصب، وضعیت سرویس‌ها را بررسی کنید:

```bash
# روی سرور
ssh admin@217.78.237.15

# بررسی وضعیت سرویس‌ها
sudo systemctl status matrix-traefik
sudo systemctl status matrix-synapse
sudo docker ps

# اگر سرویس‌ها running نیستند، ریستارت کنید
sudo systemctl restart matrix-traefik
sudo systemctl restart matrix-synapse

exit

# تست Matrix API
curl -k https://217.78.237.15/_matrix/client/versions

# تست Element Web در مرورگر: https://217.78.237.15/
```

---

## 💡 نکات تکمیلی

### نگهداری تنظیمات با Git

دایرکتوری `inventory/` در playbook توسط `.gitignore` نادیده گرفته می‌شود، بنابراین می‌توانید تنظیمات خود را در یک git repository جداگانه نگهداری کنید:

```bash
cd /home/amir/Works/Startup/Matrix/matrix-second/matrix-docker-ansible-deploy/inventory
git init
git add .
git commit -m "Initial Matrix configuration for 217.78.237.15"
```

### هشدار: پایان سرویس اعلان انقضای Let's Encrypt

** جهت اطلاعات بیشتر:** چون از self-signed certificate استفاده می‌کنید، باید خودتان expiration certificates را بررسی کنید. می‌توانید از ابزارهایی مثل [Uptime Kuma](https://github.com/louislam/uptime-kuma) برای این کار استفاده کنید.

### 5. رفع مشکل SSL

اگر certificate درست کار نمی‌کند:

**الف) بررسی فولدرها:**
```bash
# بررسی وجود فولدرها (اگر وجود ندارند، باگ رخ داده)
sudo ls -la /matrix/traefik/ssl/
sudo ls -la /matrix/traefik/config/

# اگر فولدرها وجود ندارند، آن‌ها را دستی بسازید
sudo mkdir -p /matrix/traefik/ssl
sudo mkdir -p /matrix/traefik/config
sudo chown -R matrix:matrix /matrix/
```

**ب) بررسی فایل‌های SSL:**
```bash
# بررسی فایل‌های SSL روی سرور
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

---

## ساخت سرور دوم برای Federation

برای ساخت سرور دوم که با سرور اول federation کند:

1. مراحل ۱ تا ۵ را برای سرور دوم تکرار کنید
2. IP سرور دوم را در inventory اضافه کنید
3. Certificate جدید با IP سرور دوم بسازید
4. **نکته مهم:** همان Root CA (`rootCA.crt`) را برای سرور دوم هم استفاده کنید
5. روی هر دو سرور، Root CA را نصب کنید

### مثال vars.yml برای سرور دوم

```yaml
matrix_domain: "10.0.2.15"  # IP سرور دوم
matrix_server_fqn_matrix: "10.0.2.15"
matrix_client_element_enabled: true
matrix_server_fqn_element: "10.0.2.15"
matrix_synapse_container_labels_public_client_root_enabled: false
# ... بقیه تنظیمات مشابه سرور اول
```

### نصب Root CA روی سرور دوم

```bash
# روی سرور دوم
sudo mkdir -p /usr/local/share/ca-certificates/
sudo scp rootCA.crt admin@10.0.2.15:/tmp/
ssh admin@10.0.2.15 "sudo mv /tmp/rootCA.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates"
```

---

## دستورات

### شروع مجدد سرویس‌ها

```bash
# ریستارت Traefik
ansible -i inventory/hosts all -m shell -a "systemctl restart matrix-traefik" --become

# ریستارت Synapse
ansible -i inventory/hosts all -m shell -a "systemctl restart matrix-synapse" --become
```

### مشاهده لاگ‌ها

```bash
# روی سرور
sudo journalctl -u matrix-traefik -f
sudo journalctl -u matrix-synapse -f
```

### بررسی کانتینرها

```bash
sudo docker ps
sudo docker logs matrix-traefik --tail 50
sudo docker logs matrix-synapse --tail 50
```

---

## فایل‌های مهم

| فایل | توضیحات |
|------|---------|
| `inventory/hosts` | لیست سرورها |
| `inventory/host_vars/SERVER_IP/vars.yml` | تنظیمات هر سرور |
| `/matrix/traefik/config/provider.yml` | Traefik provider configuration |
| `/matrix/traefik/config/traefik.yml` | Traefik main configuration |
| `/matrix/traefik/ssl/` | فایل‌های SSL |

---

## منابع

- [Matrix Docker Ansible Deploy](https://github.com/spantaleev/matrix-docker-ansible-deploy)
- [Configuring SSL Certificates](https://github.com/spantaleev/matrix-docker-ansible-deploy/blob/master/docs/configuring-playbook-ssl-certificates.md)
- [Playbook Tags](https://github.com/spantaleev/matrix-docker-ansible-deploy/blob/master/docs/playbook-tags.md)
