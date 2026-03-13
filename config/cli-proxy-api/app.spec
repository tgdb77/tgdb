spec_version=1
display_name=CLIProxyAPI
image=docker.io/eceasy/cli-proxy-api:latest
doc_url=https://github.com/router-for-me/CLIProxyAPI
menu_order=42

base_port=8377
instance_subdirs=auths logs static
record_subdirs=auths logs static

var=api_key|source=random_hex|len=64
var=management_key|source=random_hex|len=64

config=config.yaml|template=configs/config.yaml.example|mode=600|label=config.yaml
config=secrets.env|template=configs/secrets.env.example|mode=600|label=secrets.env

success_extra=🛠️ 管理介面：${http_url}/management.html
success_extra=🔑 訪問 API Key：${api_key}
success_extra=🔑 管理金鑰：${management_key}

success_warn=注意：CLIProxyAPI 會在首次啟動後把 ${instance_dir}/config.yaml 的 remote-management.secret-key 自動轉成 bcrypt 雜湊並覆寫檔案；明文金鑰請以 ${instance_dir}/secrets.env 為準。
success_warn=OAuth 回呼埠固定：8085(Gemini)/1455(Codex)/54545(Claude)/51121(Antigravity)/11451(iFlow)。若其中任一埠已被占用，容器可能啟動失敗；請編輯 Quadlet 註解掉不需要的 PublishPort。

quadlet_type=single
quadlet_template=quadlet/default.container
