spec_version=1
display_name=DocuSeal
image=docker.io/docuseal/docuseal:latest
doc_url=https://github.com/docusealco/docuseal
menu_order=152

base_port=3114

instance_subdirs=data
record_subdirs=data

var=secret_key_base|source=random_hex|len=128

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=ℹ️ 首次啟動後請前往 ${http_url} 建立第一個管理員帳號。
success_warn=若之後改成域名 / HTTPS / 反向代理，請同步調整 ${instance_dir}/.env 的 `HOST` 與 `FORCE_SSL`。
success_warn=若要啟用郵件寄送或雲端附件儲存，請依官方文件補上 SMTP / S3 / GCS / Azure 相關環境變數。

quadlet_type=single
quadlet_template=quadlet/default.container
