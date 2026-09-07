# SquadIQ Setup Guide

## 1. تطبيق Database Schema على Supabase

### الطريقة الأولى: من خلال Dashboard (الأسهل)

1. افتح مشروع Supabase من: https://supabase.com/dashboard
2. اختار مشروعك
3. من القائمة الجانبية، اضغط على **SQL Editor**
4. اضغط **New Query**
5. انسخ محتويات ملف `supabase/schema.sql` بالكامل
6. الصقه في المحرر
7. اضغط **Run** أو اضغط `Ctrl+Enter`

إذا نجح التنفيذ، سترى رسالة "Success. No rows returned"

### الطريقة التانية: باستخدام Supabase CLI

إذا كان عندك Supabase CLI مثبت:

```bash
# Link your project
supabase link --project-ref your-project-ref

# Push the schema
supabase db push
```

---

## 2. إعداد Environment Variables

### الخطوات:

1. **انسخ ملف `.env.example` إلى `.env`:**
   ```powershell
   Copy-Item .env.example .env
   ```

2. **احصل على Supabase Credentials:**
   - افتح مشروعك من: https://supabase.com/dashboard
   - اذهب إلى: **Settings** → **API**
   - انسخ:
     - **Project URL** → ضعه في `SUPABASE_URL`
     - **anon public** key → ضعه في `SUPABASE_ANON_KEY`

3. **افتح ملف `.env` وعدّل القيم:**
   ```
   SUPABASE_URL=https://xyzabcdef.supabase.co
   SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
   ```

4. **(اختياري) للـ AI Assistant - احصل على Anthropic API Key:**
   - اذهب إلى: https://console.anthropic.com/
   - أنشئ API key
   - ضعه في `ANTHROPIC_API_KEY`

---

## 3. تشغيل التطبيق

### ⚠️ مهم: CORS Fix للـ Web

إذا كنت ستشغل التطبيق على **Chrome/Web**، ستحتاج نشر FPL Proxy أولاً:

```powershell
# ثبت Supabase CLI
winget install --id Supabase.CLI

# سجل دخول
supabase login

# اربط المشروع
supabase link --project-ref psgqhiqcxnupzbbunydx

# انشر الـ proxy
.\deploy-functions.ps1
```

**البديل:** شغل على Windows Desktop بدلاً من Web (لا يحتاج proxy)

للتفاصيل الكاملة، راجع: **`CORS-FIX.md`**

---

### الطريقة الأولى: باستخدام PowerShell Script

```powershell
.\run.ps1
```

هذا الـ script سيقرأ الـ `.env` تلقائياً ويمرر المتغيرات للتطبيق.

### الطريقة التانية: يدوياً

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

---

## 4. نشر AI Assistant Edge Function (اختياري)

إذا كنت تريد استخدام AI Assistant:

1. **ثبت Supabase CLI** (إذا لم يكن مثبتاً):
   ```powershell
   winget install --id Supabase.CLI
   ```

2. **سجل دخول:**
   ```bash
   supabase login
   ```

3. **اربط المشروع:**
   ```bash
   supabase link --project-ref your-project-ref
   ```

4. **انشر الـ function:**
   ```bash
   supabase functions deploy ai-assistant
   ```

5. **أضف الـ API key كـ secret:**
   ```bash
   supabase secrets set ANTHROPIC_API_KEY=sk-ant-your-key-here
   ```

---

## 5. التحقق من الإعداد

بعد تشغيل التطبيق:

1. يجب أن ترى شاشة Sign In/Sign Up
2. أنشئ حساب جديد
3. سجل دخول
4. اربط FPL Manager ID الخاص بك (الرقم من URL ملفك الشخصي في FPL)
5. يجب أن ترى الـ Dashboard مع:
   - Deadline countdown
   - Manager summary
   - Squad list

---

## ⚠️ ملاحظات مهمة

### Security (من README):

- ❌ **لا تضع `.env` في Git** - الملف مضاف في `.gitignore` بالفعل
- ✅ **استخدم anon key** للـ Flutter app (مش service_role key)
- ✅ **Service role key** يبقى في الـ Edge Functions بس (server-side)

### Known Stubs (من README):

- **Shop/Purchase flow** - الـ button موجود بس مش شغال (محتاج in_app_purchase integration)
- **`validate-purchase` function** - موجودة بس الـ receipt validation stub
- **Push Notifications** - مش مفعلة (local notifications بس)

---

## Troubleshooting

### "Missing config" screen

إذا رأيت شاشة "Missing Supabase configuration":
- تأكد أن ملف `.env` موجود
- تأكد أن القيم فيه صحيحة (مش `your-project-ref` أو `your-anon-key`)
- جرب تشغل باستخدام `.\run.ps1`

### Database errors

إذا واجهت أخطاء في Database:
- تأكد أنك طبقت `schema.sql` كامل
- تحقق من الـ SQL Editor في Supabase Dashboard للتأكد من وجود الجداول
- شوف الـ logs في: **Database** → **Logs**

### Auth errors

إذا واجهت مشاكل في Auth:
- تأكد أن Email Auth مفعل في Supabase
- اذهب إلى: **Authentication** → **Providers** → تأكد أن Email مفعل

---

## Next Steps

بعد ما تخلص Setup:

1. ✅ `flutter analyze` - تأكد مفيش errors
2. ✅ `flutter test` - شغل الـ tests
3. 📱 جرب الـ features الأساسية
4. 🔧 اقرأ README.md للتعرف على الـ architecture والـ stubs

