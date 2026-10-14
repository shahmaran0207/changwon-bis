# API 상세 스펙

`scripts/schema.sql` 기준. 전부 Swagger(springdoc-openapi)로 자동 문서화 대상.
공통 응답 포맷은 쓰지 않고(불필요한 래핑 지양), 성공 시 데이터 자체를 반환하고 실패 시 `ErrorResponse`로 통일한다.

## 공통

### 에러 응답

```json
{
  "code": "STOP_NOT_FOUND",
  "message": "정류소를 찾을 수 없습니다.",
  "timestamp": "2026-10-14T09:00:00+09:00"
}
```

| 코드 | HTTP Status | 상황 |
|---|---|---|
| `STOP_NOT_FOUND` | 404 | stopId에 해당하는 정류소 없음 |
| `ROUTE_NOT_FOUND` | 404 | routeId에 해당하는 노선 없음 |
| `INVALID_UPDOWN_CD` | 400 | updownCd가 0/1이 아님 |
| `VALIDATION_ERROR` | 400 | 요청 파라미터 형식 오류 |
| `UNAUTHORIZED` | 401 | 관제 API, JWT 없음/만료 |

창원시 자체 API 대비 차별점: **JSON 기본 지원, 모든 엔드포인트에 요청/응답 예제 명시, 에러코드 표로 정리** (창원 OpenAPI는 이 세 가지가 전부 빠져 있었음).

---

## 1. 정류소 검색

```
GET /api/v1/stops?keyword={keyword}&cityCode={cityCode}&page={page}&size={size}
```

| 파라미터 | 타입 | 필수 | 설명 |
|---|---|---|---|
| keyword | string | Y | 정류소명 일부 또는 초성(예: "ㅈㅇㅁㅇㅈ" → "자유무역지역") |
| cityCode | int | N | 38010=창원, 38030=진주. 생략 시 전체 |
| page | int | N | 기본 0 |
| size | int | N | 기본 20, 최대 100 |

**응답 200**
```json
{
  "content": [
    {
      "stopId": 123,
      "externalStopId": "CWB379001114",
      "cityCode": 38010,
      "stopNo": "321916",
      "stopName": "자유무역지역정문",
      "lat": 35.20939656,
      "lng": 128.5830333
    }
  ],
  "page": 0,
  "size": 20,
  "totalElements": 1
}
```

**초성검색 설계 메모**: `stop.stop_name`에 함수 기반 인덱스로 초성 추출 컬럼(`stop_name_choseong`)을 별도로 두고, 검색 시 `keyword`가 초성 패턴이면 그 컬럼을, 아니면 `stop_name ILIKE`를 사용하도록 쿼리 분기. (초성 추출은 애플리케이션 레이어에서 자바로 구현 — 한글 유니코드 완성형 블록 연산)

---

## 2. 정류소 도착예정 목록

```
GET /api/v1/stops/{stopId}/arrivals
```

**응답 200** — `arrival_status` 테이블을 그대로 반영, status별 필드 유무가 다름

```json
{
  "stopId": 123,
  "stopName": "자유무역지역정문",
  "arrivals": [
    {
      "routeId": 45,
      "routeNo": "21",
      "status": "NORMAL",
      "predictedSec": 180,
      "vehicleNo": "경남71자5215",
      "remainingStops": 3
    },
    {
      "routeId": 46,
      "routeNo": "22",
      "status": "WAITING_DISPATCH",
      "predictedSec": null,
      "nextDepartureTime": "14:30"
    },
    {
      "routeId": 47,
      "routeNo": "23",
      "status": "SERVICE_ENDED",
      "predictedSec": null
    },
    {
      "routeId": 48,
      "routeNo": "24",
      "status": "NO_SIGNAL",
      "predictedSec": null,
      "lastCollectedAt": "2026-10-14T08:45:00+09:00"
    }
  ]
}
```

| status | 의미 | 추가 필드 |
|---|---|---|
| `NORMAL` | 정상 운행 중, 도착예정 계산됨 | `predictedSec`, `vehicleNo`, `remainingStops` |
| `SERVICE_ENDED` | 금일 운행 종료(막차 지남) | 없음 |
| `BEFORE_FIRST_BUS` | 첫차 전 | `firstDepartureTime` |
| `WAITING_DISPATCH` | 운행 중이나 배차 대기 | `nextDepartureTime`(배차간격 기반 추정) |
| `NO_SIGNAL` | 위치 데이터 수신 실패 | `lastCollectedAt` (collection_status 테이블과 연동) |

창원 BIS가 전부 "조회 결과가 없습니다"로만 뭉뚱그렸던 걸 4+1가지로 명확히 분리한 게 핵심 차별점.

---

## 3. 노선 검색

```
GET /api/v1/routes?keyword={keyword}&cityCode={cityCode}
```

**응답 200**
```json
{
  "content": [
    {
      "routeId": 45,
      "externalRouteId": "CWB379000210",
      "routeNo": "21",
      "routeType": "지선버스",
      "startNodeNm": "경남대,서중학교",
      "endNodeNm": "초소",
      "firstVehicleTime": "06:10",
      "lastVehicleTime": "22:00"
    }
  ]
}
```

---

## 4. 노선 상세 — 정류소 순서

```
GET /api/v1/routes/{routeId}/stops?updownCd={updownCd}
```

| 파라미터 | 필수 | 설명 |
|---|---|---|
| updownCd | N | 0(정방향)/1(역방향). **생략 시 0을 기본값으로 반환** (방향 미선택 상태에서 양방향을 한번에 안 보여주기로 한 결정 반영) |

**응답 200**
```json
{
  "routeId": 45,
  "updownCd": 0,
  "stops": [
    { "nodeOrd": 1, "stopId": 501, "stopName": "경남대,서중학교" },
    { "nodeOrd": 2, "stopId": 502, "stopName": "문화동" }
  ]
}
```

---

## 5. 노선 형상(지도 표출)

```
GET /api/v1/routes/{routeId}/line?updownCd={updownCd}
```

**응답 200** — GeoJSON LineString (`route_line_view` 그대로 직렬화)
```json
{
  "type": "Feature",
  "geometry": {
    "type": "LineString",
    "coordinates": [[128.5584661, 35.17916686], [128.5602673, 35.18424623]]
  },
  "properties": { "routeId": 45, "updownCd": 0 }
}
```

지도 표출 시 프론트에서 일정 구간마다 방향 화살표 심볼을 올리는 로직(줌레벨 연동)은 이 좌표 배열을 기반으로 클라이언트에서 처리 (서버는 순수 좌표만 제공).

---

## 6. 노선 실시간 버스 위치

```
GET /api/v1/routes/{routeId}/vehicles
```

**응답 200**
```json
{
  "routeId": 45,
  "vehicles": [
    {
      "vehicleNo": "경남71자5215",
      "lat": 35.210497,
      "lng": 128.584105,
      "nodeOrd": 12,
      "updownCd": 0,
      "collectedAt": "2026-10-14T08:59:40+09:00"
    }
  ]
}
```

차량이 없으면 `"vehicles": []` (빈 배열, 404 아님 — 노선 자체는 존재하므로 404는 routeId가 틀렸을 때만).

---

## 7. 관제 — 로그인 (JWT + TOTP)

```
POST /api/v1/admin/auth/login
```

**요청**
```json
{
  "username": "admin",
  "password": "비밀번호",
  "totpCode": "482913"
}
```

**응답 200**
```json
{
  "accessToken": "eyJhbGciOiJIUzI1NiJ9...",
  "tokenType": "Bearer",
  "expiresInSec": 3600
}
```

| 코드 | HTTP Status | 상황 |
|---|---|---|
| `INVALID_CREDENTIAL` | 401 | username/password 불일치 |
| `INVALID_TOTP_CODE` | 401 | password는 맞으나 totpCode 불일치 (password 단계 통과 여부는 알려주지 않음 — 둘 다 같은 메시지로 뭉뚱그려서 계정 존재 여부 추측 방지) |
| `TOTP_NOT_ENROLLED` | 409 | `admin_user.totp_enabled_at`이 NULL — 최초 로그인, OTP 앱 등록 플로우로 리다이렉트 |

**최초 등록 플로우**: `totp_enabled_at`이 NULL인 계정이 로그인 시도하면 `TOTP_NOT_ENROLLED`를 반환하고, 별도 엔드포인트(`POST /api/v1/admin/auth/totp-setup`)에서 QR코드(otpauth:// URI)를 발급 → OTP 앱에 등록 → 첫 코드 검증 성공 시 `totp_enabled_at` 기록.

이후 모든 관제 API는 `Authorization: Bearer {accessToken}` 헤더 필수. 없거나 만료되면 전부 `401 UNAUTHORIZED`.

---

## 8. 관제 — 수집 상태

```
GET /api/v1/admin/collection-status
```

**응답 200**
```json
{
  "sources": [
    {
      "source": "TAGO_BUS",
      "targetId": null,
      "lastCollectedAt": "2026-10-14T09:00:05+09:00",
      "successCount": 128934,
      "failCount": 12,
      "lastErrorMsg": null
    },
    {
      "source": "ITS_TRAFFIC",
      "targetId": null,
      "lastCollectedAt": "2026-10-14T08:55:00+09:00",
      "successCount": 4032,
      "failCount": 0,
      "lastErrorMsg": null
    }
  ]
}
```

`arrival_status.status = NO_SIGNAL`이 떴을 때 관제 화면에서 "왜"를 바로 이 데이터로 설명할 수 있어야 한다 (대시민 빈 상태와 관제 수집 상태가 같은 근거 데이터를 보는 구조).

---

## 9. 관제 — 배차 이상 / 노선 이탈

```
GET /api/v1/admin/dispatch-anomalies?routeId={routeId}&from={ISO8601}&to={ISO8601}
GET /api/v1/admin/route-deviations?routeId={routeId}&from={ISO8601}&to={ISO8601}
```

routeId 생략 시 전체 노선 대상. from/to 생략 시 최근 24시간.

**dispatch-anomalies 응답 200**
```json
{
  "anomalies": [
    {
      "id": 1001,
      "routeId": 45,
      "updownCd": 0,
      "type": "BUNCHING",
      "detectedAt": "2026-10-14T08:40:00+09:00",
      "detail": "동일 방면 버스 2대가 2분 간격 이내로 연속 접근"
    }
  ]
}
```

**route-deviations 응답 200**
```json
{
  "deviations": [
    {
      "id": 501,
      "vehicleNo": "경남71자5215",
      "routeId": 45,
      "detectedAt": "2026-10-14T08:50:00+09:00",
      "deviationM": 320.5,
      "lat": 35.21300,
      "lng": 128.58700
    }
  ]
}
```

---

## 10. 디지털 트윈 시뮬레이션

```
GET /api/v1/digital-twin/routes/{routeId}/simulate?updownCd={updownCd}&dayType={dayType}&timeBucket={timeBucket}
```

| 파라미터 | 필수 | 값 |
|---|---|---|
| dayType | Y | `WEEKDAY`/`SATURDAY`/`SUNDAY`/`HOLIDAY` |
| timeBucket | Y | `COMMUTE_AM`/`DAYTIME`/`COMMUTE_PM`/`NIGHT` |

요청 시 `route_link_map`으로 노선→링크 시퀀스를 가져오고, 각 링크의 `road_link_speed_stat`(해당 dayType×timeBucket) 평균속도로 구간 통행시간을 즉시 계산한다. 캐싱 없이 매 요청 계산(데이터는 정적이라 계산량이 가볍고, 집계 테이블 갱신 시 바로 반영됨).

**응답 200**
```json
{
  "routeId": 45,
  "updownCd": 0,
  "dayType": "WEEKDAY",
  "timeBucket": "COMMUTE_AM",
  "totalDistanceM": 18400,
  "estimatedTotalSec": 2140,
  "segments": [
    {
      "seq": 1,
      "linkId": 4150000300,
      "lengthM": 85.0,
      "avgSpeedKmh": 52.69,
      "estimatedSec": 5.8
    }
  ]
}
```

| 코드 | HTTP Status | 상황 |
|---|---|---|
| `ROUTE_LINK_MAP_NOT_FOUND` | 404 | 해당 노선이 아직 도로 링크에 맵매칭되지 않음 (맵매칭 배치 전 상태) |
| `SPEED_STAT_MISSING` | 206(Partial Content) | 일부 링크의 해당 dayType×timeBucket 집계값이 없음 → 그 구간은 `max_speed_kmh`(법정속도)로 대체 계산하고 `estimated: true` 플래그 표시 |

---

## 11. 안심귀가서비스

```
POST /api/v1/safety/guardians
```

**요청**
```json
{
  "arrivalStopId": 501,
  "guardianPhone": "010-1234-5678",
  "password": "비밀번호",
  "childTagId": "1234567890123456",
  "privacyConsent": true
}
```

`privacyConsent`가 `true`가 아니면 등록 자체를 막는다 — 진주 BIS 등록폼에 동의 체크박스가 없었던 걸 직접 겨냥한 설계.

| 코드 | HTTP Status | 상황 |
|---|---|---|
| `CONSENT_REQUIRED` | 400 | privacyConsent가 false/누락 |
| `INVALID_PHONE_FORMAT` | 400 | 전화번호 형식 오류 |
| `VALIDATION_ERROR` | 400 | 그 외 필수값 누락 (전부 필수 처리 — 창원/진주 폼의 "필수값 표시 없음" 문제 해결) |

```
POST /api/v1/safety/events
```

BIT 시뮬레이터에서 "자녀안심귀가" 버튼 태그 시 호출. 요청: `{ "childTagId": "...", "routeId": 45, "boardStopId": 501 }` → 서버가 guardian 조회 후 SMS 발송(연동은 추후 구현 단계에서 실제 발신 서비스 선택).

---

## 남은 작업
- [x] 관제 API (로그인+수집상태+배차이상+노선이탈)
- [x] 디지털 트윈 시뮬레이션 API
- [x] 안심귀가서비스 API
- [ ] 각 엔드포인트 Swagger 어노테이션 작성은 실제 구현 단계에서
