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

## Screenshots — captured

Produced by the **Screenshots** workflow (Actions → Screenshots → Run workflow),
which drives the real app on an emulator and a simulator, seeded with six months
of demo data. Download the `screenshots-ios` / `screenshots-android` artifacts.

Regenerate them whenever the UI changes materially — never hand-crop or resize,
because both stores validate exact pixel dimensions.

| Store | Captured | Where it goes |
|---|---|---|
| Apple | 1320×2868 (iPhone 17 Pro Max) | App Store Connect → **View All Sizes in Media Manager** → **iPhone 6.9" Display**. Apple reuses these for the smaller display sizes, so this is the only slot to fill. The default 6.5" box on the version page wants 1242×2688 and will reject them. |
| Play | 1440×2952 (Pixel 6 Pro) | Play Console → Main store listing → Phone screenshots. |

Order matters: upload `01`…`05` in filename order. Apple shows only the first
three on the install sheet, and home → statistics → savings is the story.

1. **Home** — gradient header, balance + savings, the monthly split, the
   income-day savings prompt, and the day-grouped expense list.
2. **Statistics** — spend-to-date, suggested weekly budget, savings rate,
   essentials vs. luxuries.
3. **Savings** — goals with their auto-computed monthly deposits, plus the
   deposit ledger.
4. **Income** — the recurring salary rule and recent income.
5. **Categories** — the sub-category tree, to show the depth.
