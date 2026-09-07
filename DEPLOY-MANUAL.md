# 🚀 نشر FPL Proxy يدوياً (من Dashboard)

## الطريقة السريعة بدون CLI

### 1️⃣ افتح Supabase Dashboard

اذهب إلى: https://psgqhiqcxnupzbbunydx.supabase.co/functions

أو:
1. افتح: https://supabase.com/dashboard
2. اختار مشروعك
3. من القائمة الجانبية: **Edge Functions**

---

### 2️⃣ أنشئ Function جديدة

1. اضغط **Create a new function**
2. في حقل **Function name** اكتب: `fpl-proxy`
3. في حقل **Code** امسح كل حاجة والصق الكود ده:

```typescript
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';

const FPL_BASE_URL = 'https://fantasy.premierleague.com/api';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // Extract the FPL endpoint path from query parameter
    const url = new URL(req.url);
    const path = url.searchParams.get('path');

    if (!path) {
      return new Response(
        JSON.stringify({ error: 'Missing path parameter' }),
        {
          status: 400,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        }
      );
    }

    // Build the full FPL URL
    const fplUrl = `${FPL_BASE_URL}${path}`;

    // Forward the request to FPL
    const response = await fetch(fplUrl, {
      headers: {
        'User-Agent': 'SquadIQ/0.1 (+read-only)',
      },
    });

    // Get the response data
    const data = await response.text();

    // Return the response with CORS headers
    return new Response(data, {
      status: response.status,
      headers: {
        ...corsHeaders,
        'Content-Type': response.headers.get('Content-Type') || 'application/json',
      },
    });
  } catch (error) {
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      }
    );
  }
});
```

4. اضغط **Deploy**

---

### 3️⃣ اختبر الـ Function

افتح الرابط ده في متصفح جديد:

```
https://psgqhiqcxnupzbbunydx.supabase.co/functions/v1/fpl-proxy?path=/bootstrap-static/
```

**المفروض تشوف:**
- بيانات JSON من FPL
- مفيش errors

---

### 4️⃣ أعد تشغيل التطبيق

```powershell
# أوقف التطبيق الحالي (اضغط 'q' في terminal)

# شغل من جديد
.\run.ps1
```

**⚠️ مهم:** لازم restart كامل، مش hot reload!

---

### 5️⃣ جرب ربط FPL Manager ID تاني

الآن المفروض يشتغل بدون CORS errors! ✓

---

## 🔍 Troubleshooting

### لو Function مش شغالة

1. تأكد من اسم الـ function بالظبط: `fpl-proxy` (بدون مسافات)
2. تأكد من الكود اتنسخ كامل بدون errors
3. شوف الـ Logs في Dashboard → Edge Functions → fpl-proxy → Logs

### لو لسه CORS errors

1. امسح cache المتصفح: `Ctrl+Shift+Delete`
2. أعد تشغيل التطبيق (مش hot reload)
3. افتح Developer Tools → Network tab وشوف الـ requests

---

## ✅ بعد الـ Deployment

الكود هيكتشف تلقائياً إن الـ function موجودة ويستخدمها!

جرب دلوقتي! 🚀
