# إصدار Android (APK)

هذا المجلد يحتوي مشروع Android Studio جاهز لتغليف اللعبة داخل تطبيق Android.

1. افتح مجلد `android` في Android Studio.
2. اسمح له بتنزيل Android Gradle Plugin/SDK إذا طلب ذلك.
3. Build > Generate App Bundle(s) / APK(s) > Generate APK(s).
4. ملف APK سيظهر عادةً تحت `android/app/build/outputs/apk/debug/`.

ملاحظة: لم يتم تضمين APK ثنائي في هذه النسخة لأن بيئة التنفيذ الحالية لا تحتوي على Android SDK/Gradle اللازمة لبناء ملف APK هنا. المشروع جاهز للبناء على جهازك أو GitHub Actions.
