# راهنمای استفاده از اسکریپت نصب Matrix

این سند نحوه استفاده از اسکریپت `install-dev.sh` را برای نصب خودکار Matrix Synapse توضیح می‌دهد.

---

## فهرست مطالب

1. [پیش‌نیازها](#پیش‌نیازها)
2. [حالت‌های نصب](#حالت‌های-نصب)
3. [نصب روی سرور محلی (Local)](#نصب-روی-سرور-محلی-local)
4. [نصب روی سرور از راه دور (Remote VPS)](#نصب-روی-سرور-از-راه-دور-remote-vps)
5. [تولید Root CA جداگانه](#تولید-root-ca-جدایانه)
6. [تنظیمات نصب](#تنظیمات-نصب)
7. [مراحل نصب](#مراحل-نصب)
8. [بعد از نصب](#بعد-از-نصب)
9. [عیب‌یابی](#عیب‌یابی)

---

## پیش‌نیازها

### سیستم عامل‌های پشتیبانی شده:
- **Arch Linux** / **Manjaro**
- **Debian** 11+
- **Ubuntu** 20.04+

### پیش‌نیازهای نرم‌افزاری:

#### روی Local (سرور خودتان):
```bash
# Arch Linux / Manjaro
sudo pacman -S ansible python python-pip git

# Debian / Ubuntu
sudo apt update
sudo apt install -y ansible python3 python3-pip git
```

#### روی Remote (از سیستم لوکال به VPS):
```bash
# روی سیستم لوکال شما
sudo pacman -S ansible python python-pip git  # Arch/Manjaro
# یا
sudo apt install -y ansible python3 python3-pip git  # Debian/Ubuntu
```

### دسترسی‌های لازم:
- **Local**: دسترسی sudo با رمز عبور
- **Remote**: دسترسی SSH + sudo با رمز عبور روی سرور هدف

---

## حالت‌های نصب

اسکریپت **سه حالت نصب** دارد:

| حالت | گزینه | توضیحات |
|------|-------|---------|
| **Local** | 1 | نصب روی همان سیستم که اسکریپت را اجرا می‌کنید |
| **Remote VPS** | 2 | نصب روی سرور از راه دور via SSH |
| **Generate Root CA** | 3 | فقط تولید Root CA برای استفاده در چندین سرور |

---

## نصب روی سرور محلی (Local)

این حالت وقتی استفاده می‌شود که می‌خواهید Matrix را روی همان سیستمی که اسکریپت را اجرا می‌کنید، نصب کنید.

### مراحل:

1. **اجرای اسکریپت:**
```bash
chmod +x install-dev.sh
./install-dev.sh
```

2. **انتخاب حالت نصب:**
```
Enter your choice (1, 2 or 3): 1
```

3. **تأیید آدرس سرور:**
اسکریپت به صورت خودکار IP شما را تشخیص می‌دهد:
```
Detected IP addresses:
eth0             192.168.1.100/24 metric 100

Use '192.168.1.100' as server address? [y/n/IP/Domain]: y
```

4. **وارد کردن رمز sudo:**
```
Sudo password: [رمز sudo خود را وارد کنید]
```

5. **تنظیمات Admin:**
```
Username [admin]: admin
Password [generated_password]: [رمز دلخواه یا Enter برای رمز خودکار]
```

6. **انتخاب گزینه SSL:**
```
Select SSL certificate option:

  1) Create new Root CA
     - Generate a new Root CA and server certificate
     - Best for: First installation or isolated server

  2) Use existing Root CA
     - Use an existing Root CA for federation
     - Best for: Adding server to existing federation

Your choice [1]: 1
```

7. **تأیید نهایی و شروع نصب:**
```
=== Installation Summary ===

  Server IP:         192.168.1.100
  Installation Mode: local
  IPv6:              true
  Element Web:       true
  Admin Username:    admin
  SSL Option:        Create new Root CA

Proceed with installation? [Y/n]: y
```

---

## نصب روی سرور از راه دور (Remote VPS)

این حالت برای نصب Matrix روی یک VPS از راه دور استفاده می‌شود.

### مراحل:

1. **در سیستم لوکال خود، اسکریپت را اجرا کنید:**
```bash
chmod +x install-dev.sh
./install-dev.sh
```

2. **انتخاب حالت Remote:**
```
Enter your choice (1, 2 or 3): 2
```

3. **وارد کردن اطلاعات سرور:**
```
Enter server IP address or domain: 45.148.31.170
SSH username [root]: root
SSH host [45.148.31.170]: [Enter]
SSH port [22]: [Enter]
```

4. **انتخاب احراز هویت SSH:**
```
SSH Authentication:
Use custom SSH key? [y/N]: n
Use password authentication? [y/N]: y
SSH password: [رمز SSH را وارد کنید]
```

5. **رمز sudo سرور:**
```
Sudo password: [رمز sudo سرور را وارد کنید]
```

6. **بقیه مراحل مثل حالت Local است.**

---

## تولید Root CA جداگانه

اگر می‌خواهید چندین سرور Matrix را به هم Federation دهید، بهتر است یک Root CA مشترک داشته باشید.

### مراحل:

1. **اجرای اسکریپت:**
```bash
./install-dev.sh
```

2. **انتخاب گزینه 3:**
```
Enter your choice (1, 2 or 3): 3
```

3. **Root CA تولید می‌شود:**
```
=== Root CA Generation ===

=== Root CA Summary ===

  Mode:              Generate Root CA
  Root CA Key:       /opt/matrix-ca/rootCA.key
  Root CA Cert:      /opt/matrix-ca/rootCA.crt

✓ Root CA generation completed!
```

4. **استفاده از Root CA در نصب بعدی:**
هنگام نصب سرورهای دیگر، گزینه **"Use existing Root CA"** را انتخاب کنید و مسیر Root CA تولید شده را مشخص کنید.

---

## تنظیمات نصب

### تنظیمات خودکار (بدون سوال):

| تنظیم | مقدار | توضیحات |
|-------|-------|---------|
| **IPv6** | فعال (true) | پشتیبانی از IPv6 به صورت پیش‌فرض فعال است |
| **Element Web** | فعال (true) | رابط کاربری Element به صورت پیش‌فرض نصب می‌شود |

### تنظیمات قابل تغییر:

1. **IPv6 Support**: همیشه فعال است (برای غیرفعال کردن، باید اسکریپت را ویرایش کنید)
2. **Element Web**: همیشه فعال است (برای غیرفعال کردن، باید اسکریپت را ویرایش کنید)

---

## مراحل نصب

### Phase 1: Environment Detection
اسکریپت سیستم عامل و پیش‌نیازها را بررسی می‌کند.

### Phase 2: User Inputs
اطلاعات لازم از کاربر دریافت می‌شود.

### Phase 3: Install Prerequisites
نصب Ansible (در صورت نیاز).

### Phase 4: Ensure Playbook
دانلود یا به‌روزرسانی playbook از GitHub.

### Phase 5: SSL Certificates
تولید گواهی‌نامه‌های SSL خودامضا.

### Phase 6: Configure Playbook
پیکربندی inventory و vars.yml.

### Phase 7: Install Ansible Roles
نصب نقش‌های Ansible مورد نیاز.

### Phase 8: Pre-flight Check
بررسی نهایی قبل از نصب.

### Phase 8.5: Final Confirmation
تأیید نهایی قبل از شروع نصب اصلی.

### Phase 8.6, 8.7, 8.8: Cleanup (Auto-confirmed)
پاکسازی خودکار داده‌ها و سرویس‌های قبلی (در صورت وجود).

### Phase 9: Installation
نصب اصلی Matrix Synapse و سرویس‌ها.

### Phase 10: Create Admin User
ایجاد کاربر admin.

### Phase 11: Summary
نمایش خلاصه نصب.

---

## بعد از نصب

### خروجی موفقیت‌آمیز:

```
========================================
MATRIX INSTALLATION COMPLETE
========================================

Server Information:
  - IP/Domain: 45.148.31.170
  - Installation Mode: local

Admin User:
  - Username: admin
  - Password: [your-password]

Access URLs:
  - Matrix API: https://45.148.31.170/_matrix/client/versions
  - Element Web: https://45.148.31.170/

Important Files:
  - Vars YAML: inventory/host_vars/45.148.31.170/vars.yml
  - Inventory: inventory/hosts
  - SSL Cert: /matrix-ssl/45.148.31.170.crt
  - Root CA: /opt/matrix-ca/rootCA.crt

========================================
✓ Installation completed successfully!
```

### دسترسی به Element Web:

1. **از مرورگر به آدرس سرور بروید:**
```
https://[YOUR-SERVER-IP]/
```

2. **اولین بار:** مرورگر هشدار SSL می‌دهد چون گواهی‌نامه خودامضا است.

3. **اعتماد به گواهی‌نامه (یک بار):**
   - Chrome/Edge: `Advanced` → `Proceed to...`
   - Firefox: `Advanced` → `Accept the Risk and Continue`

4. **برای اعتماد دائمی، Root CA را به مرورگر اضافه کنید:**
   - Chrome/Edge:
     1. باز کردن: `chrome://settings/certificates`
     2. تب **Authorities**
     3. کلیک **Import** و انتخاب `/opt/matrix-ca/rootCA.crt`
     4. تیک **Trust this certificate for identifying websites**

   - Firefox:
     1. باز کردن: `Settings` → `Privacy & Security` → `Certificates`
     2. کلیک **View Certificates** → **Authorities**
     3. کلیک **Import** و انتخاب `/opt/matrix-ca/rootCA.crt`
     4. تیک **Trust this CA to identify websites**

5. **ورود به Element:**
   - با نام کاربری و رمز admin خود وارد شوید

### نصب Root CA روی سیستم (برای Federation):

برای Federation بین سرورها، Root CA باید روی هر سرور نصب شود:

```bash
# روی هر سرور
sudo mkdir -p /usr/local/share/ca-certificates/matrix
sudo cp /opt/matrix-ca/rootCA.crt /usr/local/share/ca-certificates/matrix/
sudo update-ca-certificates
```

---

## عیب‌یابی

### خطا: "Permission denied" هنگام اجرای اسکریپت

**راه حل:**
```bash
chmod +x install-dev.sh
```

### خطا: "Ansible not found"

**راه حل:**
```bash
# Arch/Manjaro
sudo pacman -S ansible python python-pip

# Debian/Ubuntu
sudo apt install -y ansible python3 python3-pip
```

### خطا: "SSH connection failed"

**راه حل:**
```bash
# تست دسترسی SSH
ssh -v root@your-server-ip

# اگر key ssh دارید:
ssh -i ~/.ssh/id_rsa root@your-server-ip
```

### خطای SSL در مرورگر: "ERR_SSL_KEY_USAGE_INCOMPATIBLE"

این خطا نباید رخ دهد (در نسخه اصلاح‌شده اسکریپت رفع شده است). اگر رخ داد:

**راه حل:**
گواهی‌نامه‌ها را دوباره بسازید:
```bash
# پاک کردن SSL قدیمی
sudo rm -rf /matrix-ssl/*

# اجرای مجدد اسکریپت
./install-dev.sh
```

### خطای Synapse: "accept_keys_insecurely"

این خطا در نسخه اصلاح‌شده اسکریپت رفع شده است. اگر رخ داد، مطمئن شوید که در `vars.yml`:

```yaml
matrix_synapse_configuration_extension_yaml: |
  key_server:
    accept_keys_insecurely: true
  trusted_key_servers: []
```

### سرویس‌های Matrix کار نمی‌کنند

**بررسی وضعیت:**
```bash
# روی سرور
sudo systemctl status matrix-synapse
sudo docker ps | grep matrix-
```

**بررسی لاگ:**
```bash
sudo journalctl -u matrix-synapse -f
sudo docker logs matrix-synapse
```

---

## نکات مهم

1. **حفظ Root CA:** فایل `/opt/matrix-ca/rootCA.crt` را امن نگه دارید. برای Federation به آن نیاز دارید.

2. **فایل vars.yml:** فایل پیکربندی در `inventory/host_vars/[IP]/vars.yml` است. تغییرات بعدی را می‌توانید در این فایل اعمال کنید.

3. **نصب مجدد:** اسکریپت به صورت خودکار داده‌های قبلی را پاک می‌کند. برای حفظ داده‌ها، قبل از نصب مجدد از `/matrix/postgres` backup بگیرید.

4. **Firewall:** مطمئن شوید پورت‌های زیر باز باشند:
   - **443/tcp** - برای Element Web و Client API
   - **8448/tcp** - برای Federation

5. **زمان نصب:** نصب کامل 10-20 دقیقه طول می‌کشد (بسته به سرعت اینترنت).

---

## دستورات مفید

### بررسی وضعیت سرویس‌ها:
```bash
sudo systemctl status matrix-synapse
sudo systemctl list-units | grep matrix
```

### مشاهده لاگ‌ها:
```bash
sudo journalctl -u matrix-synapse -n 100 -f
sudo docker logs -f matrix-synapse
```

### راه‌اندازی مجدد سرویس‌ها:
```bash
sudo systemctl restart matrix-synapse
sudo systemctl restart matrix-*
```

### ایجاد کاربر جدید:
```bash
cd /opt/matrix-docker-ansible-deploy
ansible-playbook -i inventory/hosts setup.yml \
  --extra-vars="username=newuser password=newpass admin=no" \
  --tags=register-user
```

---

## پشتیبانی

اگر به مشکلی برخوردید که در این راهنما راه حل ندارد:

1. لاگ نصب را بررسی کنید: `install.log`
2. لاگ‌های Synapse را بررسی کنید
3. به پروژه [matrix-docker-ansible-deploy](https://github.com/spantaleev/matrix-docker-ansible-deploy) مراجعه کنید
