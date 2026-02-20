# profiles/ - 환경별 설정 프로필

## 역할
집/학원에서 **IP 주소나 네트워크 대역**이 다를 때 빠르게 전환

## 구조
- `home/` - 집 환경 설정
- `academy/` - 학원 환경 설정

## 사용법
```bash
# 학원으로 전환
bash profiles/switch-env.sh academy

# 집으로 전환
bash profiles/switch-env.sh home
```

## 각 프로필에 포함될 것
- `lab.env` - 해당 환경의 IP/도메인 설정
