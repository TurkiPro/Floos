# Store listing — فلوس (Floos)

Everything you'll be asked to paste into Play Console and App Store Connect.
Copy-paste ready; character limits noted.

- **Privacy policy URL:** <https://floos.turkisecurity.com/privacy.html>
- **Support / marketing URL:** <https://floos.turkisecurity.com/>
- **Support email:** privacy@turkisecurity.com → routes to turki.security@gmail.com
- **Category:** Finance
- **Price:** Free, no in-app purchases, no ads

---

## Google Play

### App name (30 chars)

```
فلوس — تتبّع المصاريف
```

### Short description (80 chars)

```
تتبّع مصاريفك ودخلك وأهدافك. يعمل بدون إنترنت — بياناتك لا تغادر جهازك أبدًا.
```

### Full description (4000 chars)

```
فلوس تطبيق بسيط وسريع لتتبّع مصاريفك ودخلك، مصمّم بالعربية أولًا.

كل بياناتك تبقى على جهازك. لا حسابات، ولا تسجيل دخول، ولا خوادم، ولا إعلانات، ولا تتبّع. التطبيق يعمل بالكامل بدون إنترنت.

■ المصاريف والدخل
• سجّل مصروفًا أو دخلًا في ثوانٍ.
• فئات جاهزة مع تصنيفات فرعية مفصّلة (فطور، غداء، قهوة، وقود، فواتير…) ويمكنك إنشاء وتعديل ما تشاء.
• مكتبة أيقونات واسعة وألوان قابلة للتخصيص.

■ الالتزامات الشهرية
• سجّل الإيجار والاشتراكات والفواتير مرة واحدة، وسيضيفها التطبيق تلقائيًا كل شهر.
• الدخل المتكرر (الراتب) يُضاف تلقائيًا في موعده.

■ أهداف الادخار
• حدّد هدفًا ومبلغًا وتاريخًا، ويحسب لك التطبيق الإيداع الشهري المطلوب.
• عند استلام راتبك يذكّرك بتخصيص المبلغ: أودِع كاملًا، أو جزءًا، أو تخطَّ هذا الشهر — ويُعاد حساب الإيداع الشهري تلقائيًا.

■ إحصائيات تفهمها
• إنفاق الشهر، المعدل اليومي، والمتوقع لنهاية الشهر.
• ميزانية أسبوعية مقترحة مبنية على عاداتك الفعلية.
• صنّف فئاتك إلى «أساسيات» و«كماليات» وشاهد النسبة بينهما.
• معدل الادخار، أكبر مصروف، أعلى أيام الإنفاق، ومقارنة بالشهر الماضي.
• سلوك كل شهر وكل سنة: الدخل مقابل المصروف مقابل الادخار مقابل المتبقي.
• تصدير الحركات والإحصائيات إلى CSV.

■ خصوصية حقيقية
• لا يجمع التطبيق أي بيانات عنك، ولا يرسل شيئًا لأي جهة.
• اقفل التطبيق ببصمتك أو بصمة وجهك أو رمز جهازك.
• يمكنك حذف كل بياناتك من الإعدادات في أي وقت.

■ تفاصيل تهمّك
• التقويم الميلادي والهجري.
• الوضع الفاتح والداكن، وستة ألوان للتمييز.
• تذكيرات اختيارية بالوقت الذي تختاره.

فلوس مجاني بالكامل، بدون إعلانات وبدون اشتراكات.
```

### Content rating (IARC questionnaire)

Answer **No** to everything — no violence, no sexuality, no profanity, no
gambling (the app tracks personal spending; it does not simulate gambling), no
user-generated content, no user interaction, no location sharing, no purchases.
Expected outcome: **Everyone / 3+**.

### Data safety form

| Question | Answer |
|---|---|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | N/A (nothing is transmitted) |
| Do you provide a way for users to request that their data is deleted? | **Yes** — deleted in-app via Settings → حذف كل البيانات, and by uninstalling |

This is accurate: the database is a local SQLite file, and the app contains no
networking code. Nothing to declare.

### Permissions declaration

The app declares only `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `VIBRATE`
and `USE_BIOMETRIC`. **No sensitive or restricted permissions** — no exact
alarms, no location, no contacts, no storage — so no permissions declaration
form is required.

---

## Apple App Store

### App name (30 chars)

```
فلوس — تتبّع المصاريف
```

### Subtitle (30 chars)

```
مصاريفك وأهدافك على جهازك
```

### Promotional text (170 chars)

```
تتبّع مصاريفك ودخلك وأهداف ادخارك بالعربية. إحصائيات تفهمها، تذكيرات ذكية، وقفل بالبصمة. بدون إنترنت وبدون إعلانات — بياناتك لا تغادر جهازك.
```

### Keywords (100 chars, comma-separated, no spaces)

```
مصاريف,ميزانية,ادخار,مصروف,محفظة,مالية,راتب,فواتير,توفير,حسابات,مصروفات,budget
```

### Description

Reuse the Play full description above (Apple has the same 4000-char limit).

### App privacy (nutrition labels)

Select **"Data Not Collected"**. Do not tick any data type — the app has no
networking, no analytics SDK and no third-party services.

### Age rating

Answer **None** to every content question → **4+**.

### Export compliance

When prompted "Does your app use encryption?": the app uses no custom
encryption, only the OS-standard HTTPS/keychain primitives it never actually
calls. Answer **No** to the "non-exempt encryption" question.

---

## Screenshots (still to capture)

Neither store accepts a submission without them.

| Store | Requirement |
|---|---|
| Play | Min 2 phone screenshots. 16:9–9:16, each side 320–3840 px. |
| Apple | 6.7" iPhone (1290×2796) **and** 6.5" (1284×2778). Min 3 each. |

Good screens to shoot, in order — they tell the product's story:

1. **Home** — the gradient header, balance + savings cards, the monthly split,
   and the day-grouped expense list.
2. **Statistics** — the savings-rate and essentials-vs-luxuries cards.
3. **Savings** — a goal with its auto-computed monthly deposit.
4. **Income-day prompt** — "استلمت دخلك — خصّص لأهدافك" with the deposit buttons.
5. **Categories** — the sub-category tree, to show the depth.

Seed realistic-looking numbers first (debug builds have Settings → أدوات تجريبية
→ تعبئة ببيانات تجريبية, which fills six months of plausible data).

**You need a device or emulator for this** — screenshots must come from real
phone hardware/simulator at those exact pixel sizes; a resized desktop window
won't pass Apple's dimension check.
