# 📅 [Project Name: LeaveSync]
### **Google Calendar API 기반 실시간 연차 관리 솔루션**

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Riverpod](https://img.shields.io/badge/Riverpod-764BA2?style=for-the-badge&logo=dart&logoColor=white)

사용자가 **구글 캘린더**에 기록한 휴가 일정을 API로 분석하여, 복잡한 계산 없이 실시간으로 잔여 연차를 관리해 주는 Flutter 애플리케이션입니다.

---

## 🚀 Key Features

* **Google Calendar 실시간 동기화**
    * `googleapis`를 활용하여 캘린더 내 특정 키워드(`연차`, `반차`, `반반차`) 자동 감지 및 파싱.
* **스마트 연차 주기 계산**
    * 사용자가 설정한 연차 초기화 날짜(회계 연도 등)를 기준으로 **'현재 유효한 1년 주기'**를 동적으로 계산.
* **상세 사용 내역 리스트**
    * 단순 총량 표시를 넘어, 개별 일정의 차감 수치와 날짜를 리스트 형태로 제공하여 투명성 확보.
* **사용자 중심 가이드 시스템**
    * 인터랙티브 오버레이를 통해 입력 규칙 안내. 로그아웃 후 재로그인 시 UX를 고려하여 가이드 재노출 로직 설계.

---

## 🛠 Tech Stack

| 분류 | 기술 스택 |
| :--- | :--- |
| **Framework** | `Flutter` (Dart) |
| **State Management** | `Riverpod` (StateNotifier) |
| **Authentication** | `Google Sign-In` (OAuth 2.0) |
| **API** | `Google Calendar API v3` |
| **Local Storage** | `Shared Preferences` |

---

## 🏗 Architecture
> **Clean Architecture & MVVM 패턴을 지향하여 관심사 분리(SoC)를 구현하였습니다.**

### **Layered Architecture**
1. **Presentation Layer**
    * **View**: `HomeScreen`, `SettingsScreen` (UI 렌더링 및 사용자 인터랙션)
    * **ViewModel**: `LeaveViewModel` (Provider를 통한 상태 관리 및 비즈니스 로직 연동)
2. **Domain Layer**
    * **Entity/Model**: `LeaveResult`, `LeaveSettings` (핵심 데이터 구조)
    * **Logic**: 연차 주기 계산 및 키워드 매칭 규칙
3. **Data Layer**
    * **Service**: `GoogleCalendarService` (외부 Google API 통신 및 `status` 기반 데이터 필터링)

---

## 💡 Troubleshooting & Challenges

### 1️⃣ API 데이터 누락 및 검색 범위 최적화
* **Issue**: 설정된 초기화 날짜가 미래일 경우 검색 범위(`timeMin`) 설정 오류로 데이터 누락 발생.
* **Solution**: 현재 날짜와 비교하여 **'회계 주기'를 자동 보정**하는 알고리즘 적용. `maxResults: 2500` 확보를 통해 대규모 데이터 누락 방지.

### 2️⃣ 데이터 정합성 유지 (삭제 일정 처리)
* **Issue**: 캘린더에서 삭제된 일정이 API 응답(`cancelled`)에 포함되어 잔여량이 오계산됨.
* **Solution**: `event.status` 검증 로직을 추가하여 `confirmed` 상태인 일정만 계산에 포함하도록 필터링 강화.

### 3️⃣ 세션 기반 가이드 노출 로직
* **Issue**: 최초 1회만 노출되는 가이드가 계정 전환(로그아웃 후 재로그인) 시에는 나타나지 않아 신규 계정 사용자가 규칙을 알 수 없음.
* **Solution**: `SharedPreferences` 상태를 로그아웃 시점에 초기화하여 **로그인 세션 단위로 가이드를 제어**하도록 UX 개선.

---

## 📖 How to Use

1. **구글 로그인**: 앱 실행 후 관리할 캘린더 계정으로 로그인합니다.
2. **초기화 날짜 설정**: 설정 메뉴에서 매년 연차가 초기화되는 날짜를 선택합니다.
3. **캘린더 작성 규칙**: 제목에 아래 키워드를 포함하면 자동 반영됩니다.
    * `연차` : **1.0개** 차감
    * `반차` : **0.5개** 차감
    * `반반차` : **0.25개** 차감
4. **실시간 동기화**: '지금 동기화' 버튼을 눌러 데이터를 업데이트합니다.

---

## 👨‍💻 Developer
**김영석** | *Professional Android / Flutter Developer*
* **Core Skills**: Android Native (Kotlin/Java), Flutter, Clean Architecture, MVVM