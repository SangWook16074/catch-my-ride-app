# google_mobile_ads가 끌어오는 androidx.work — R8이 Room 구현(WorkDatabase_Impl,
# Class.forName으로만 참조)을 최적화로 깨뜨려 릴리즈에서만 기동 크래시가 나던 문제
# (2026-09-16 릴리즈 실행 실측: "Failed to create an instance of androidx.work.impl.WorkDatabase")
-keep class androidx.work.** { *; }
