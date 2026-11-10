---
name: "docker-stack"
description: "一键部署和管理 26+ 开发测试基础设施组件（Redis/MySQL/Kafka/Nacos/ES 等，单机或集群）。当用户要搭建、部署、扩容或排查 Docker 中间件时使用。"
---

# Docker 基础设施部署

本 skill 提供 Docker 安装 + 26+ 基础设施组件一键部署（自包含于 `scripts/` 目录），支持单机与集群/高可用模式。

## 何时使用

- 用户要装 Docker、部署 Redis / MySQL / Kafka / Nacos / ES 等中间件
- 用户要集群/高可用模式（哨兵、主从、KRaft...）
- 用户要查看部署状态/凭据、清理 Docker 资源

## 脚本清单

| 脚本 | 功能 |
|------|------|
| docker_install.sh | 自动安装 Docker Engine + Compose（CentOS/Ubuntu，支持中国镜像源） |
| docker_compose_deploy.sh | 一键部署 26+ 组件，单机/集群 |
| docker_cleaner.sh | 清理容器/镜像/卷/网络 |

## 核心用法

```bash
# 安装 Docker（中国镜像源）
sudo ./docker_install.sh -y --mirror china

# 单机部署
./docker_compose_deploy.sh deploy redis,mysql,minio

# 集群/高可用（组件:模式）
./docker_compose_deploy.sh deploy kafka:cluster,nacos:cluster,redis:sentinel

# 状态 / 凭据 / 清理
./docker_compose_deploy.sh status
./docker_compose_deploy.sh info
./docker_cleaner.sh -a
```

## 26 组件速查

- 数据库：Redis / MySQL / PostgreSQL / MongoDB
- 搜索：Elasticsearch / OpenSearch
- 存储：MinIO / RustFS
- 消息队列：RabbitMQ / Kafka / RocketMQ / Pulsar
- 协调：ZooKeeper；网关：OpenResty / Kong
- 监控：Prometheus / Grafana / Loki / SkyWalking
- 日志：Logstash / Kibana；安全：Keycloak / Sentinel
- 调度：XXL-Job / PowerJob；注册中心：Nacos

## 预设方案

dev-minimal / dev-full / monitoring / elk / all-databases / all-mq / storage / cluster-mq

## 集群模式（`组件:模式` 触发）

redis:sentinel|cluster、mysql:master-slave|dual-master、postgresql:ha、mongodb:rs、rabbitmq:cluster、kafka:cluster、rocketmq:cluster、zookeeper:cluster、elasticsearch:cluster、opensearch:cluster、nacos:cluster、minio:distributed、keycloak:cluster

## 注意事项

- 需 root；数据卷统一在 `~/docker-stack/data/`
- 先 `list` 看可用组件，再 `deploy`
- 完整操作手册见 `scripts/DEPLOYMENT_GUIDE.md`
