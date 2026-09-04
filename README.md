# رحلة اسم الفاعل — Web + Android

هذه النسخة تضبط الواجهة للهاتف والتابلت وتمنع مشكلة الأعمدة المتداخلة في الشاشات الصغيرة. على الهاتف تصبح اللعبة عمودًا واحدًا، وتختفي رسومات الخلفية الكبيرة التي كانت تغطي المحتوى.

## Android
المجلد `android` يحتوي مشروعًا لتغليف الموقع كتطبيق Android. التطبيق يفتح نسخة الموقع الأونلاين مباشرة، لذلك تبقى حسابات الطلاب وSupabase ولوحة المدير على نفس النظام المركزي.

لإنشاء APK استخدم Android Studio، أو شغّل GitHub Actions إن تم رفع مجلد `android` كمستودع.


## v6 additions
- Manager entry is available directly from the registration/login screen.
- Paid/manager-granted stages use a single server-authoritative attempt.
- Manager reports show per-stage attempts, score, selected answers, correct answers, wrong answers, timeouts and response time.
- Run `one_time_reports.sql` in Supabase SQL Editor before deploying this version.
