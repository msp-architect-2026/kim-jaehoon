# config/ - 중앙 설정

## 역할
모든 Phase에서 사용하는 **공통 변수**를 한 곳에서 관리

## 파일
- `lab.env.example` - 설정 템플릿 (IP, 도메인, 버전 등)
- `lab.env` - 실제 사용 설정 (`.gitignore`에 포함)

## 사용법
```bash
cp lab.env.example lab.env
vim lab.env  # 본인 환경에 맞게 수정
source lab.env  # 스크립트에서 불러오기
```

## 관리하는 항목
- 네트워크 IP (Mini PC, K8s 노드들)
- 도메인 (GitLab, Argo CD, Grafana)
- 버전 (K8s, Helm, CNI)
- Registry 주소
- Slack Webhook
