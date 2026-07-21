spec_version=1
cli_quick_args=none
display_name=AnythingLLM
description=AI 知識庫與對話工作區，可連接模型、匯入文件並建立具上下文的聊天助理。
image=docker.io/mintplexlabs/anythingllm:latest
doc_url=https://github.com/Mintplex-Labs/anything-llm
menu_order=204

access_policy=local_only

base_port=3117
instance_subdirs=storage
record_subdirs=storage

var=sig_key|source=random_hex|len=64|env=SIG_KEY
var=sig_salt|source=random_hex|len=64|env=SIG_SALT
var=jwt_secret|source=random_hex|len=32|env=JWT_SECRET

config=.env|template=configs/.env.example|mode=600|label=.env

success_warn=若你要連線宿主機上的 Ollama / LM Studio / LocalAI 等服務，請把 AnythingLLM 內的連線位址改成宿主機可達位址，不要直接填 `localhost`；必要時可再搭配反向代理或內網位址。

quadlet_type=single
quadlet_template=quadlet/default.container
