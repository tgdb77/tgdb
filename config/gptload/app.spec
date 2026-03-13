spec_version=1
display_name=GPT Load
image=ghcr.io/tbphp/gpt-load:latest
doc_url=https://github.com/tbphp/gpt-load
menu_order=52

base_port=3061

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env

var=AUTH_KEY|source=random_hex|len=32|prefix=sk-
var=ENCRYPTION_KEY|source=random_hex|len=32

success_extra=🔑 web訪問金鑰：${AUTH_KEY}

quadlet_type=single
quadlet_template=quadlet/default.container
