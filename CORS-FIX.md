# 🔧 CORS Fix for FPL API

## المشكلة
عند محاولة ربط FPL Manager ID على الـ web، تظهر رسالة خطأ:
```
Network error calling /entry/1844507/
```

السبب: FPL API لا يسمح بـ CORS من المتصفح.

---

## ✅ الحل (طريقتان)

### الطريقة 1: استخدام Supabase Edge Function كـ Proxy (الأفضل)

**الخطوات:**

1. **ثبت Supabase CLI** (لو مش مثبت):
   ```powershell
   winget install --id Supabase.CLI
   ```

2. **سجل دخول**:
   ```bash
   supabase login
   ```

3. **اربط المشروع**:
   ```bash
   supabase link --project-ref psgqhiqcxnupzbbunydx
   ```

4. **انشر الـ FPL Proxy**:
   ```powershell
   .\deploy-functions.ps1
   ```
   أو يدوياً:
   ```bash
   supabase functions deploy fpl-proxy
   ```

5. **أعد تشغيل التطبيق** (Hot reload مش كفاية):
   - اضغط `q` في terminal الـ Flutter
   - شغل من جديد: `.\run.ps1`

6. **جرب ربط FPL Manager ID تاني** ✓

---

### الطريقة 2: استخدام Desktop/Mobile بدلاً من Web

على Windows/Android/iOS، مفيش مشكلة CORS لأن التطبيق بيتصل مباشرة.

**للتشغيل على Windows:**
1. فعّل Developer Mode:
   ```powershell
   start ms-settings:developers
   ```
2. شغل على Windows:
   ```powershell
   flutter run -d windows --dart-define=SUPABASE_URL=https://psgqhiqcxnupzbbunydx.supabase.co --dart-define=SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBzZ3FoaXFjeG51cHpiYnVueWR4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg0OTA3NjUsImV4cCI6MjEwNDA2Njc2NX0.DFjI1ou3kJgbgGB5gZmq4lrgyE_46XsfR8wUcuYZxKQ
   ```

---

## 🧪 اختبر أن الـ Proxy شغال

افتح الرابط ده في المتصفح:
```
https://psgqhiqcxnupzbbunydx.supabase.co/functions/v1/fpl-proxy?path=/bootstrap-static/
```

**لو شغال صح:**
- هتشوف JSON data من FPL
- مفيش CORS errors

**لو مش شغال:**
- رسالة "Function not found" → محتاج تنشر الـ function
- رسالة "401" → شوف الـ authentication settings

---

## 📐 كيف بيشتغل؟

```
Before (CORS Error):
Browser → ❌ FPL API (blocked by CORS)

After (Using Proxy):
Browser → ✓ Supabase Edge Function → ✓ FPL API → ✓ Response
```

الـ Edge Function بيعمل request من السيرفر (مش من المتصفح)، فالـ CORS مبيأثرش.

---

## 🔒 ملاحظات أمان

- ✅ الـ Edge Function **read-only** - مبيعملش transfers أو تغييرات
- ✅ بيستخدم نفس الـ User-Agent الـ FplProvider بيستخدمه
- ✅ مفيش credentials بتتخزن - بس بيعمل proxy للـ public API

---

## ❓ Troubleshooting

### "Function not found" بعد الـ deployment

```bash
# تأكد من الـ deployment
supabase functions list

# لو مش موجود، انشره تاني
supabase functions deploy fpl-proxy
```

### CORS errors لسه موجودة

1. تأكد إن الـ function اتنشر فعلاً
2. امسح الـ cache: `Ctrl+Shift+R` في المتصفح
3. أعد تشغيل الـ Flutter app (مش hot reload)

### "Timeout" أو "Network error"

- ممكن FPL API نفسه بطيء أو down
- جرب تفتح `https://fantasy.premierleague.com/api/bootstrap-static/` في tab جديد
- لو مش شغال، يبقى المشكلة من FPL نفسه

---

## 📚 ملفات ذات صلة

- `supabase/functions/fpl-proxy/index.ts` - كود الـ proxy
- `lib/data_providers/fpl_provider.dart` - استخدام الـ proxy
- `deploy-functions.ps1` - script النشر
- `supabase/functions/README.md` - دليل الـ Edge Functions

---

## ✅ بعد الحل

لما الـ proxy يشتغل:
1. ✓ تقدر تربط FPL Manager ID
2. ✓ الـ Dashboard يحمل بياناتك
3. ✓ كل الـ features تشتغل عادي
4. ✓ مفيش CORS errors في الـ console

جرب دلوقتي! 🚀
