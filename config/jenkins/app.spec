spec_version=1
display_name=Jenkins
image=docker.io/jenkins/jenkins:lts-jdk21
doc_url=https://github.com/jenkinsci/docker
menu_order=155

base_port=8221
instance_subdirs=jenkins_home
record_subdirs=jenkins_home

cli_quick_args=agent_port

input=agent_port|prompt=請輸入 Jenkins Agent TCP 對外埠（預設 55288；輸入 0 取消）: |ask=1|type=port|default_source=next_available_port|start=55288|avoid=host_port|check_available=1|env=JENKINS_SLAVE_AGENT_PORT|allow_cancel=1|cli_zero_as_default=1

config=.env|template=configs/.env.example|mode=600|label=.env（環境變數）

post_deploy=scripts/post_deploy_show_initial_admin_password.sh|runner=bash|allow_fail=1

success_warn=預設不開agent_port。若之後真的要開，請自行取消註解即可。
success_warn=若之後改成域名 / HTTPS / 子路徑反向代理，請編輯 ${instance_dir}/.env 的 `JENKINS_OPTS`（例如 `--prefix=/jenkins`）並同步調整反代設定。

quadlet_type=single
quadlet_template=quadlet/default.container

update_pull_images=docker.io/jenkins/jenkins:lts-jdk21
