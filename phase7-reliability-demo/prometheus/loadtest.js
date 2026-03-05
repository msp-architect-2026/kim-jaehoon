import http from 'k6/http';
import { sleep, check } from 'k6';

// HPA 스케일 아웃을 유도하기 위한 점진적 부하 시나리오
export const options = {
  stages: [
    { duration: '30s', target: 50 },   // 워밍업
    { duration: '2m', target: 400 },   // 400명까지 빡세게 증가 (HPA 발동 구간)
    { duration: '1m', target: 400 },   // 400명 유지
    { duration: '30s', target: 0 },    // 쿨다운
  ],
};

export default function () {
  const baseUrl = 'http://192.168.x.x';

  // 1. 메인 페이지 로드 (frontend, adservice, recommendationservice 부하)
  let res = http.get(`${baseUrl}/`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.5);

  // 2. 특정 상품 상세 조회 (productcatalogservice 부하)
  res = http.get(`${baseUrl}/product/0PUK6V6EV0`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(0.5);

  // 3. 장바구니에 상품 담기 (cartservice 부하)
  res = http.post(`${baseUrl}/cart`, {
    product_id: '0PUK6V6EV0',
    quantity: 1
  });
  sleep(0.5);

  // 4. 통화 변경 (currencyservice 부하)
  res = http.post(`${baseUrl}/setCurrency`, { currency_code: 'KRW' });
  sleep(0.5);
  
  // 5. 장바구니 확인 (cartservice 최종 확인)
  res = http.get(`${baseUrl}/cart`);
  check(res, { 'status is 200': (r) => r.status === 200 });
  sleep(1);
}
