spec_version=1
display_name=RedisInsight
image=docker.io/redis/redisinsight:latest
doc_url=https://redis.io/docs/latest/develop/tools/redisinsight/
menu_order=9001

hidden=1

base_port=5540
instance_subdirs=data
record_subdirs=data

config_template=configs/.env.example
config_dest=.env
config_mode=600
config_label=.env（環境變數）

full_remove_purge_record=1

quadlet_type=single
quadlet_template=quadlet/default.container
