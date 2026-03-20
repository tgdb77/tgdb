spec_version=1
display_name=Remark42
image=ghcr.io/umputun/remark42:latest
doc_url=https://remark42.com/docs/getting-started/
menu_order=59

base_port=8090
instance_subdirs=var
record_subdirs=var

input=site_id|prompt=請輸入 Remark42 的 SITE 識別字（預設 remark）: |ask=1|default=remark|no_space=1|pattern=^[A-Za-z0-9_-]+$|pattern_msg=SITE 識別字僅可使用英數、底線與連字號。|env=SITE

var=secret|source=random_hex|len=64|env=SECRET

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_extra=站點識別字：${site_id}
success_extra=測試頁面：${http_url}/web
success_warn=目前預設為匿名登入（AUTH_ANON=true）以便快速測試；若要正式上線，建議編輯 ${instance_dir}/.env 改用 Email/OAuth 驗證或停用匿名登入。
success_warn=若要嵌入外部網站或經由反向代理對外提供，請先把 ${instance_dir}/.env 的 REMARK_URL 改成實際的 HTTPS 網址。

quadlet_type=single
quadlet_template=quadlet/default.container
