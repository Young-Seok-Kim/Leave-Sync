# 📅 [Project Name: LeaveSync]
### **Google Calendar API 기반 실시간 연차 관리 솔루션**

![Flutter](https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white)
![Riverpod](https://img.shields.io/badge/Riverpod-764BA2?style=for-the-badge&logo=dart&logoColor=white)
![Hive](https://img.shields.io/badge/Hive-FFAB40?style=for-the-badge&logo=sqlite&logoColor=white)

사용자가 **구글 캘린더**에 기록한 휴가 일정을 API로 분석하고, **근로기준법 기반 자동 계산**을 통해 실시간으로 잔여 연차를 관리해 주는 Flutter 애플리케이션입니다.

---

## 🚀 Key Features

* **근로기준법 기반 자동 연차 산출 (Smart Onboarding)**
    * **입사일 입력만으로 모든 설정 완료**: 입사일을 기준으로 만 근속 연수를 계산하여 법정 가산 연차(2년마다 1개 추가)를 자동으로 산정.
    * **지능형 초기화일 세팅**: 다음 입사 기념일의 '하루 전'을 연차 소멸일로 자동 제안하여 사용자 설정 편의성 극대화.
* **시점 기반 스마트 정렬 (Time-aware Sorting)**
    * 현재 시간을 기준으로 **'다가올 휴가'**를 상단에 배치하고, **'지난 휴가'**는 하단으로 자동 정렬하여 사용자 편의성 극대화.
* **상태별 시각적 차등화 (Visual Differentiation)**
    * 지난 일정은 Grayscale 처리 및 투명도 조절을 통해 '완료된 데이터'임을 직관적으로 표현하고, 예정된 일정은 Brand Color를 적용하여 강조.
* **Google Calendar 실시간 동기화**
    * `googleapis`를 활용하여 캘린더 내 특정 키워드(`연차`, `반차`, `반반차`) 자동 감지 및 실시간 데이터 파싱.
* **하이브리드 데이터 관리 (Hive & SharedPreferences)**
    * `Hive`를 이용한 객체 단위 설정값 저장과 `SharedPreferences`를 이용한 세션 상태 관리를 병행하여 데이터 무결성 확보.

---

## 🛠 Tech Stack

| 분류 | 기술 스택 |
| :--- | :--- |
| **Framework** | `Flutter` (Dart) |
| **State Management** | `Riverpod` (StateNotifier) |
| **Authentication** | `Google Sign-In` (OAuth 2.0) |
| **API** | `Google Calendar API v3` |
| **Local Storage** | `Hive` (NoSQL), `Shared Preferences` |

---

## 🏗 Architecture
> **Clean Architecture & MVVM 패턴을 지향하여 관심사 분리(SoC)를 구현하였습니다.**

### **Layered Architecture**
1. **Presentation Layer**
    * **View**: `OnboardingScreen`, `HomeScreen`, `SettingsScreen`
    * **ViewModel**: `LeaveNotifier` (Provider를 통한 상태 관리 및 비즈니스 로직 연동)
2. **Domain Layer**
    * **Entity/Model**: `UserSetting` (Hive TypeAdapter 적용)
    * **Logic**: 근로기준법 가산 연차 계산 및 차기 초기화 시점 산출 알고리즘
3. **Data Layer**
    * **Service**: `GoogleCalendarService` (외부 API 통신 및 `status` 기반 데이터 필터링)

---

## 💡 Troubleshooting & Challenges

### 1️⃣ 근속 연수에 따른 가산 연차 계산 로직 최적화
* **Issue**: 단순 연도 차이 계산 시, 입사 기념일 도래 여부에 따라 만 근속 연수가 오계산되어 법정 연차 개수가 부정확하게 산출됨.
* **Solution**: `DateTime` 비교를 통해 **기념일 경과 여부를 판별**하고, `(근속연수 - 1) / 2` 공식을 적용하여 가산 연차를 정확히 산정하는 로직 구현. (예: 21년 5월 입사자 기준 현재 16개 산출 검증 완료)

### 2️⃣ 사용자 주도적 설정(UI/UX)과 자동화의 균형
* **Issue**: 자동 계산 결과가 사용자의 실제 회사 규정과 다를 경우 수정이 불가능하여 발생하는 UX 저해 요소 발견.
* **Solution**: 입사일 선택 시 **자동 계산 로직이 트리거**되도록 설계하되, 결과값은 **TextEditingController를 통해 직접 수정** 가능하도록 하이브리드 입력 방식 채택.

### 3️⃣ 연차 초기화 시점 자동화 알고리즘
* **Issue**: 사용자가 연차 소멸 시점(초기화 날짜)을 매번 수동으로 계산해야 하는 번거로움.
* **Solution**: 입사일을 기준으로 **'차기 입사 기념일 - 1일'**을 계산하는 알고리즘을 추가하여 온보딩 과정에서 원클릭으로 설정이 완료되도록 개선.

### 4️⃣ API 데이터 누락 및 정합성 유지 (삭제 일정 처리)
* **Issue**: 캘린더에서 삭제된 일정(`cancelled`)이 계산에 포함되거나 미래 주기 데이터가 누락되는 문제.
* **Solution**: `event.status` 필터링 강화 및 현재 날짜와 비교하여 **'회계 주기'를 자동 보정**하는 검색 범위(`timeMin`) 알고리즘 적용.

---

## 📖 How to Use

1. **초기 설정 (Onboarding)**: 앱 실행 후 본인의 **입사일**을 선택합니다.
    * 입사일 기준 **총 연차**와 **초기화 날짜**가 자동으로 계산됩니다. (필요 시 수동 수정 가능)
2. **구글 로그인**: 관리할 캘린더 계정으로 로그인합니다.
3. **캘린더 작성 규칙**: 제목에 아래 키워드를 포함하면 실시간으로 반영됩니다.
    * `연차` : **1.0개** / `반차` : **0.5개** / `반반차` : **0.25개**
4. **실시간 확인**: 대시보드에서 잔여 연차와 다가올 휴가 일정을 확인합니다.

---

## 👨‍💻 Developer
**김영석** | *Professional Android / Flutter Developer*
* **Core Skills**: Android Native (Kotlin/Java), Flutter, Clean Architecture, MVVM