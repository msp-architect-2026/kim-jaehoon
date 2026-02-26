# 🏗️ On-Prem GitOps Microservices Platform

> Google Online Boutique 기반 MSA K8s 운영 자동화 및 관측성(Observability) 통합 플랫폼

## 🎯 Project Overview & Impact
본 프로젝트는 퍼블릭 클라우드의 매니지드 K8s 서비스에 의존하지 않고, **순수 온프레미스(kubeadm) 환경에서 Control Plane부터 Network, Storage, CI/CD 파이프라인까지 전 과정을 직접 설계하고 구축한 GitOps 기반 플랫폼**입니다.

* **Impact:** 선언적 상태 관리(SSoT)를 통해 인프라 구성의 멱등성을 보장하고, 어플리케이션 배포부터 모니터링 경고(Alert)까지의 라이프사이클을 100% 자동화하여 운영 개입을 최소화했습니다.

## 🛠️ Tech Stack
단순 툴킷의 나열이 아닌, 목적에 따른 계층별(Layer) 인프라 스택 구성입니다.

* **Orchestration & Compute:** `Kubernetes (kubeadm)`, `Docker`
* **CI/CD & GitOps:** `GitLab CI`, `Argo CD`
* **Traffic & Networking:** `MetalLB (L4)`, `Ingress-NGINX (L7)`, `Calico/Flannel (CNI)`
* **Observability:** `Prometheus`, `Grafana`, `Loki`, `Promtail`
* **Storage:** `NFS Dynamic Provisioner` (상태 저장형 데이터 관리)

<div align="left">
  <img src="https://img.shields.io/badge/kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white">
  <img src="https://img.shields.io/badge/gitlab-FC6D26?style=for-the-badge&logo=gitlab&logoColor=white">
  <img src="https://img.shields.io/badge/argo%20cd-EF7B4D?style=for-the-badge&logo=argo&logoColor=white">
  <img src="https://img.shields.io/badge/prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white">
</div>

## 💻 Live Action
![Demo](./docs/images/online-boutique-home.png)

---

## 🗺️ Master Architecture Blueprint

> 플랫폼 제어 서버(CI/CD Hub)와 런타임 클러스터(1 Master, 2 Worker Nodes)를 분리하여 설계한 통합 데이터 흐름 및 네트워크 아키텍처입니다.

[![Master Architecture](./docs/images/mainarchitecture.png)](./docs/images/mainarchitecture.png)

### 📌 Key Engineering Decisions
인프라 엔지니어로서 다음과 같은 기술적 의사결정을 통해 시스템의 안정성과 확장성을 확보했습니다.

* **The "Hard Way" via kubeadm:** 클라우드 벤더 종속성(Lock-in)을 탈피하고 K8s 컴포넌트(API Server, etcd, Scheduler)의 내부 동작 원리와 CNI 플러그인(Calico/Flannel) 통신 구조를 딥다이브하기 위해 kubeadm으로 클러스터를 직접 프로비저닝했습니다.
* **GitOps 기반 Continuous Delivery:** Argo CD를 도입하여 Git Repository를 유일한 진실의 원천(Single Source of Truth)으로 삼았습니다. 이를 통해 코드 기반의 인프라 상태 동기화를 달성하고, 배포 롤백 및 시각적 추적성을 확보했습니다.
* **On-Premise Traffic Routing:** 온프레미스 환경의 한계인 외부 Load Balancer 부재를 해결하기 위해 `MetalLB`를 L2 모드로 구성하고, `Ingress-NGINX`를 통해 마이크로서비스 간의 L7 라우팅 최적화 경로를 설계했습니다.
* **Full-stack Observability:** Metric(Prometheus)과 Log(Loki) 데이터를 Grafana로 통합 대시보드화하여 관측성을 극대화했습니다. 

---

## 📚 Documentation & Deep Dive

아키텍처 설계 배경, 컴포넌트별 세부 구성 및 **인프라 구축 중 발생한 트러블슈팅(Troubleshooting) 기록** 등 상세한 엔지니어링 문서는 Wiki에서 제공합니다.

* [🏠 Wiki Home](https://github.com/msp-architect-2026/kim-jaehoon/wiki)
* [🖥️ Infrastructure Architecture](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Infrastructure-Architecture)
* [📦 Application Architecture](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Application-Architecture)
* [🔥 Troubleshooting Log (추가 권장)](#)
