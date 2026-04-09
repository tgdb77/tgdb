spec_version=1
display_name=oauth2-proxy
image=quay.io/oauth2-proxy/oauth2-proxy:v7.13.0
doc_url=https://oauth2-proxy.github.io/oauth2-proxy/configuration/integration/
menu_order=138

access_policy=local_only

base_port=4184

cli_quick_args=cookie_parent_domain issuer_url client_id client_secret
input=cookie_parent_domain|prompt=請輸入要共用登入 Cookie 的主網域（例：example.com，輸入 0 取消）: |required=1|ask=1|no_space=1|pattern=^[^[:space:]]+[.][^[:space:]]+$|pattern_msg=請輸入有效的主網域（例：example.com）。|env=OAUTH2_PROXY_COOKIE_PARENT_DOMAIN|allow_cancel=1
input=issuer_url|prompt=請輸入 Pocket ID Issuer URL（例：https://id.example.com，輸入 0 取消）: |required=1|ask=1|no_space=1|pattern=^https?://[^[:space:]]+$|pattern_msg=請輸入有效的 http(s):// URL。|env=OAUTH2_PROXY_ISSUER_URL|allow_cancel=1
input=client_id|prompt=請輸入 Pocket ID Client ID（不得為空，輸入 0 取消）: |required=1|ask=1|no_space=1|env=OAUTH2_PROXY_CLIENT_ID|allow_cancel=1
input=client_secret|prompt=請輸入 Pocket ID Client Secret（不得為空，輸入 0 取消）: |required=1|type=password|no_space=1|env=OAUTH2_PROXY_CLIENT_SECRET|allow_cancel=1

var=cookie_secret|source=random_hex|len=32|env=OAUTH2_PROXY_COOKIE_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

success_warn= 本範本預設走 Nginx `auth_request` 模式；oauth2-proxy 只處理登入與驗證，真正業務流量仍由各站點自己的 Nginx `proxy_pass` 反向代理。`OAUTH2_PROXY_UPSTREAMS` 因此預設為 `static://202`（依官方 auth-only/ForwardAuth 用法推定）。
success_warn= 這個範本適合保護「同一主網域底下的多個子網域」（例：app1.example.com、app2.example.com）。若是不同主網域，請改用每個主網域各部署一個 oauth2-proxy。
success_warn= 請在 Pocket ID 同一個 OIDC Client 中加入所有子網域 Callback URL（例：https://app1.${cookie_parent_domain}/oauth2/callback、https://app2.${cookie_parent_domain}/oauth2/callback），並建議勾選 PKCE（S256）。
success_warn= 部署完成後，請在你自己的 Nginx 反向代理站點中填入「實際受保護網域」與「實際上游 URL」；可直接參考 ${instance_dir}/nginx/shared-auth-site.conf 與 ${instance_dir}/nginx/shared-auth-locations.conf 範本。
success_warn= 若要保護同機 TGDB 應用，Nginx 站點內真正業務流量的上游請優先使用 host.containers.internal，不要填 127.0.0.1。

quadlet_type=single
quadlet_template=quadlet/default.container
